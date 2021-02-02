import BSON
import Vapor
import Meow
import JWTKit

// TODO: Ideally we'd have SCRAM-SHA-256 authentication in the client & server
// SCRAM-SHA-256 doesn't require the password to leave the client's device
// It's also more secure, since the server is being verified as well
// TODO: Use $set queries to prevent simultanious updates to the same model, overwriting one another
struct Credentials: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let username: String
    let password: String
    let publicKeys: Document
}

struct FirstLoginRequest: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let user: Reference<User>
    let deviceId: ObjectId
    let password: String
}

struct FirstLoginResponse: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let token: String
}

struct SetupAccount: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let identity: PublicSigningKey
}

struct AuthResponse: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let profile: UserProfile
    let token: String
}

struct UpdateDeviceConfigRequest: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let config: UserDeviceConfig
}

struct UserKeysResponse: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let user: UserProfile
    let devices: [UserDevice]
}

func registerRoutes(to routes: RoutesBuilder) {
    #if Xcode
    routes.get("reset") { req in
        return app.meow.raw.drop().flatMapThrowing { () -> Response in 
            for i in 0..<10 {
                let user = try User(username: "test\(i)", password: "test\(i)", identity: nil)
                _ = user.save(in: app.meow)
            }
            
            return Response(status: .ok)
        }
    }
    #endif
    
    routes.post("auth", "first-login") { req -> EventLoopFuture<FirstLoginResponse> in
        let login = try req.content.decode(FirstLoginRequest.self, using: BSONDecoder())
        
        return login.user.resolve(in: req.meow).flatMap { user in
            do {
                try user.authenticate(login.password)
                
                let device = try UserDevice(_id: .init(UserDeviceId(user: login.user, device: login.deviceId)))
                
                let token = Token(
                    device: device.$_id,
                    exp: ExpirationClaim(value: .init(timeIntervalSinceNow: 3600))
                )
                
                let signedToken = try Application.signer.sign(token)
                
                return device.save(in: req.meow).transform(to: FirstLoginResponse(token: signedToken))
            } catch {
                return req.eventLoop.makeFailedFuture(error)
            }
        }
    }
    
    // TODO: Use $set instead of `save`
    let protectedRoutes = routes.grouped(TokenAuthenticationMiddleware())
    
    protectedRoutes.post("auth", "setup") { req -> EventLoopFuture<UserProfile> in
        guard let currentUser = req.userId else {
            throw Abort(.unauthorized)
        }
        
        let setup = try req.content.decode(SetupAccount.self, using: BSONDecoder())
        
        return currentUser.resolve(in: req.meow).flatMapThrowing { user -> User in
            var user = user
            try user.changeIdentity(to: setup.identity)
            return user
        }.flatMap { user in
            user.save(in: req.meow).transform(to: UserProfile(representing: user))
        }
    }
    
    protectedRoutes.get("users", ":userId") { req -> EventLoopFuture<UserProfile> in
        guard let user = req.parameters.get("userId", as: Reference<UserProfile>.self) else {
            throw Abort(.notFound)
        }
        
        return user.resolve(in: req.meow)
    }
    
    // TODO: Use update op with $push
    protectedRoutes.post("users", ":userId", "block") { req -> EventLoopFuture<UserProfile> in
        guard let currentUser = req.userId, let otherUser = req.parameters.get("userId", as: Reference<User>.self) else {
            throw Abort(.unauthorized)
        }
        
        return currentUser.resolve(in: req.meow).flatMap { currentUser in
            var currentUser = currentUser
            currentUser.blockedUsers.insert(otherUser)
            
            return currentUser.save(in: req.meow)
                .transform(to: UserProfile(representing: currentUser))
        }
    }
    
    // TODO: Use update op with $pull
    protectedRoutes.post("users", ":userId", "unblock") { req -> EventLoopFuture<UserProfile> in
        guard let currentUser = req.userId, let otherUser = req.parameters.get("userId", as: Reference<User>.self) else {
            throw Abort(.unauthorized)
        }
        
        return currentUser.resolve(in: req.meow).flatMap { currentUser in
            var currentUser = currentUser
            currentUser.blockedUsers.remove(otherUser)
            
            return currentUser.save(in: req.meow)
                .transform(to: UserProfile(representing: currentUser))
        }
    }
    
    protectedRoutes.get("users", ":userId", "keys") { req -> EventLoopFuture<UserKeysResponse> in
        guard let user = req.parameters.get("userId", as: Reference<UserProfile>.self) else {
            throw Abort(.notFound)
        }
        
        return user.resolve(in: req.meow).flatMap { user in
            return req.meow(UserDevice.self).find(where: "_id.user" == user._id && "config" != nil)
                .allResults(failable: true)
                .map { devices in
                    UserKeysResponse(user: user, devices: devices)
                }
        }
    }
    
    protectedRoutes.post("current-user", "devices", ":deviceId") { req -> EventLoopFuture<UserDevice> in
        guard
            var currentUserDevice = req.device,
            let userIdentity = req.user?.identity
        else {
            throw Abort(.unauthorized)
        }
        
        let update = try req.content.decode(UpdateDeviceConfigRequest.self, using: BSONDecoder())
        currentUserDevice.config = update.config
        
        try update.config.publicKey.verifySignature(signedBy: userIdentity)
        
        return currentUserDevice.save(in: req.meow)
            .transform(to: currentUserDevice)
    }
    
    protectedRoutes.post("users", ":userId", "send-message") { req -> EventLoopFuture<ChatMessage> in
        guard
            let currentUserDevice = req.device,
            let otherUser = req.parameters.get("userId", as: Reference<User>.self)
        else {
            throw Abort(.unauthorized)
        }
        
        let messageId = req.headers["X-Message-Id"].first
        // TODO: Push type
        
        return otherUser.resolve(in: req.meow).flatMap { otherUser in
            if otherUser.blockedUsers.contains(currentUserDevice.$_id.user) {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden))
            }
            
            return req.body.collect()
                .unwrap(or: Abort(.badRequest))
                .flatMap { buffer in
                    return req.meow(UserDevice.self)
                        .find(where: "_id.user" == otherUser._id)
                        .allResults(failable: true)
                        .flatMap { devices in
                            let devices = devices.map(\.$_id.device)
                            let message = ChatMessage(
                                _id: messageId,
                                message: Document(buffer: buffer),
                                from: currentUserDevice*,
                                to: otherUser*,
                                devices: Set(devices)
                            )
                            
                            return message.save(in: req.meow).transform(to: message)
                    }
                }
        }
    }
    
    protectedRoutes.post("users", ":userId", "devices", ":deviceId", "send-message") { req -> EventLoopFuture<ChatMessage> in
        guard
            let currentUserDevice = req.device,
            let otherUser = req.parameters.get("userId", as: Reference<User>.self),
            let otherUserDeviceId = req.parameters.get("deviceId", as: ObjectId.self)
        else {
            throw Abort(.unauthorized)
        }
        
        let messageId = req.headers["X-Message-Id"].first
        // TODO: Push type
        
        let otherUserDevice = try Reference<UserDevice>(
            unsafeToEncoded: UserDeviceId(
                user: otherUser,
                device: otherUserDeviceId
            )
        )
        
        return otherUser.resolve(in: req.meow).flatMap { otherUser in
            if otherUser.blockedUsers.contains(currentUserDevice.$_id.user) {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden))
            }
            
            return otherUserDevice.exists(in: req.meow).flatMapThrowing { exists in
                if !exists {
                    throw Abort(.notFound)
                }
            }
        }.flatMap {
            return req.body.collect()
                .unwrap(or: Abort(.badRequest))
                .flatMap { buffer in
                    let message = ChatMessage(
                        _id: messageId,
                        message: Document(buffer: buffer),
                        from: currentUserDevice*,
                        to: otherUser,
                        devices: [otherUserDeviceId]
                    )
                    
                    return message.save(in: req.meow).transform(to: message)
                }
        }
    }
    
    protectedRoutes.webSocket("websocket") { req, websocket in
        guard let user = req.userId, let device = req.device else {
            _ = websocket.close(code: .unexpectedServerError)
            return
        }
        
        let chatMessages = req.meow(ChatMessage.self)
        
        let emittingOldMessages = chatMessages
            .find(where: "recipient" == user.reference)
            .sequentialForEach { message in
                let bson = try BSONEncoder().encode(message)
                let promise = req.eventLoop.makePromise(of: Void.self)
                
                guard message.devices.contains(where: { $0 == device.$_id.device }) else {
                    // Skip this one, not intended for this device
                    promise.succeed(())
                    return promise.futureResult
                }
                
                // Emit to all devices, this is just one
                // TODO: $push
                var message = message
                message.devicesReceived.insert(device.$_id.device)
                
                websocket.send(raw: bson.makeData(), opcode: .binary, promise: promise)
                
                return message.save(in: req.meow).flatMap { _ in
                    promise.futureResult
                }.flatMap {
                    // TODO: Multi-Device Support?
                    // TODO: What is a message never arrives at the client? Do we use acknowledgements (which become a receive-receipt)?
                    chatMessages.deleteOne(where: "_id" == message._id).transform(to: ())
                }
            }
        
        emittingOldMessages.flatMap {
            chatMessages.buildChangeStream {
                match("fullDocument.recipient" == user.reference)
            }
        }.map { changeStream in
            changeStream.forEach { notification in
                guard notification.operationType == .insert, let message = notification.fullDocument else {
                    return true
                }
                
                guard message.devices.contains(where: { $0 == device.$_id.device }) else {
                    // Skip this one, not intended for this device
                    return true
                }
                
                do {
                    var message = message
                    message.devicesReceived.insert(device.$_id.device)
                    let promise = req.eventLoop.makePromise(of: Void.self)
                    let bson = try BSONEncoder().encode(message)
                    
                    websocket.send(raw: bson.makeData(), opcode: .binary, promise: promise)
                    
                    _ = message.save(in: req.meow).flatMap { _ in
                        promise.futureResult
                    }.flatMap {
                        // TODO: Multi-Device Support?
                        // TODO: What is a message never arrives at the client? Do we use acknowledgements (which become a receive-receipt)?
                        chatMessages.deleteOne(where: "_id" == message._id).transform(to: ())
                    }
                    
                    return true
                } catch {
                    _ = websocket.close(code: .unexpectedServerError)
                    return false
                }
            }
        }.whenFailure { error in
            _ = websocket.close(code: .unexpectedServerError)
        }
        
//        websocket.onBinary { websocket, buffer in
//            let message = Document(buffer: buffer, isArray: false)
//        }
    }
    
    // TODO: Create and manage group chat configs
    // TODO: Read receipts and acknowledge receiving a message on the client (receive receipt), so the server can remove it and the other user also gets a heads up
}
