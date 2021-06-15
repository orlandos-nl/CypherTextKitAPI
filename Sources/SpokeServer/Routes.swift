import APNS
import MongoKitten
import JWT
import BSON
import Vapor
import Meow
import JWTKit

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
    let deviceId: String
    let password: String
}

struct PlainSignUpRequest: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let username: String
    let config: UserConfig
}

struct SIWARequest: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let username: String
    let appleToken: String
    let config: UserConfig
}

struct SetupAccount: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let identity: PublicSigningKey
    let initiaiDeviceId: String
    let initialDevice: UserDeviceConfig
}

struct UpdateProfilePictureData: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let profilePicture: Data
}

struct AuthResponse: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let profile: UserProfile
    let token: String
}

struct UpdateDeviceConfigRequest: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let signedConfig: Signed<UserDeviceConfig>
}

struct UserKeysResponse: Content {
    enum CodingKeys: String, CodingKey {
        case user = "a"
        case devices = "b"
    }
    
    static let defaultContentType = HTTPMediaType.bson
    
    let user: UserProfile
    let devices: [UserDeviceId]
}

public enum PushType: String, Codable {
    case none, call, message, contactRequest = "contactrequest", cancelCall = "cancelcall"
}

public struct SendMessage<Body: Codable>: Content {
    let message: Body
    let pushType: PushType?
    let messageId: String
}

struct CreateReadReceiptRequest: Content {
    let messageIds: [String]
    let state: ReadReceipt.State
    let messageSender: UserDeviceId
}

enum MessageType: String, Codable {
    case message = "a"
    case multiRecipientMessage = "b"
    case readReceipt = "c"
}

struct SendMessageRequest: Codable {
    let messageId: String
    let pushType: String
    let recipient: String
    let devices: [String]?
    let message: Document
}

struct UserInfoRequest: Content {
    static let defaultContentType = HTTPMediaType.bson
    
    let username: Reference<UserProfile>
}

struct SignUpResponse: Content {
    let existingUser: String?
}

struct SetToken: Content {
    let token: String
}

func registerRoutes(to routes: RoutesBuilder) {
    routes.post("auth", "apple", "sign-up") { req -> EventLoopFuture<SignUpResponse> in
        let body = try req.content.decode(SIWARequest.self)
        
        // TODO: Proof signed by config.identity
        
        return req.jwt.apple.verify(
            body.appleToken,
            applicationIdentifier: "nl.orlandos.Workspaces"
        ).flatMap { appleIdentityToken in
            req.meow(User.self).findOne(
                where: "appleIdentifier" == appleIdentityToken.subject.value
            ).flatMap { user in
                if let user = user {
                    return req.eventLoop.future(SignUpResponse(existingUser: user._id))
                } else {
                    let user = User(
                        username: body.username,
                        appleIdentifier: appleIdentityToken.subject.value,
                        config: body.config
                    )
                    
                    return user.save(in: req.meow).transform(to: SignUpResponse(existingUser: nil))
                }
            }
        }
    }
    
    routes.post("auth", "plain", "sign-up") { req -> EventLoopFuture<SignUpResponse> in
        let body = try req.content.decode(PlainSignUpRequest.self)
        
        let user = User(
            username: body.username,
            appleIdentifier: nil,
            config: body.config
        )
        
        return user.save(in: req.meow).transform(to: SignUpResponse(existingUser: nil))
    }
    
    // TODO: Use $set instead of `save`
    let protectedRoutes = routes.grouped(TokenAuthenticationMiddleware())
    
    protectedRoutes.post("current-device", "token") { req -> EventLoopFuture<Response> in
        guard var user = req.user, let deviceId = req.deviceId else {
            throw Abort(.notFound)
        }
        let body = try req.content.decode(SetToken.self)
        
        user.deviceTokens[deviceId] = body.token
        
        return user.save(in: req.meow).transform(to: Response(status: .ok))
    }
    
    protectedRoutes.post("current-user", "config") { req -> EventLoopFuture<UserProfile> in
        let config = try req.content.decode(UserConfig.self)
        
        guard var user = req.user, req.isMasterDevice else {
            throw Abort(.badRequest)
        }
        
        user.config = config
        
        return user.save(in: req.meow)
            .transform(to: UserProfile(representing: user))
    }
    
    protectedRoutes.get("users", ":userId") { req -> EventLoopFuture<UserProfile> in
        guard let user = req.parameters.get("userId", as: Reference<UserProfile>.self) else {
            throw Abort(.notFound)
        }
        
        return user.resolve(in: req.meow)
    }
    
    // TODO: Use update op with $push
//    protectedRoutes.post("users", ":userId", "block") { req -> EventLoopFuture<UserProfile> in
//        guard let currentUser = req.userId, let otherUser = req.parameters.get("userId", as: Reference<User>.self) else {
//            throw Abort(.unauthorized)
//        }
//
//        return currentUser.resolve(in: req.meow).flatMap { currentUser in
//            var currentUser = currentUser
//            currentUser.blockedUsers.insert(otherUser)
//
//            return currentUser.save(in: req.meow)
//                .transform(to: UserProfile(representing: currentUser))
//        }
//    }
//
//    // TODO: Use update op with $pull
//    protectedRoutes.post("users", ":userId", "unblock") { req -> EventLoopFuture<UserProfile> in
//        guard let currentUser = req.userId, let otherUser = req.parameters.get("userId", as: Reference<User>.self) else {
//            throw Abort(.unauthorized)
//        }
//
//        return currentUser.resolve(in: req.meow).flatMap { currentUser in
//            var currentUser = currentUser
//            currentUser.blockedUsers.remove(otherUser)
//
//            return currentUser.save(in: req.meow)
//                .transform(to: UserProfile(representing: currentUser))
//        }
//    }
    
    protectedRoutes.on(.POST, "users", ":userId", "devices", ":deviceId", "send-message", body: .collect(maxSize: 512_000)) { req throws -> EventLoopFuture<Response> in
        // TODO: Prevent receiving the same mesasgeID twice, so that a device can safely assume it being sent in the job queue
        guard let currentUserDevice = req.device else {
            throw Abort(.unauthorized)
        }
        
        guard
            let recipient = req.parameters.get("userId", as: Reference<User>.self),
            let deviceId = req.parameters.get("deviceId")
        else {
            throw Abort(.notFound)
        }
        
        let recipientDevice = UserDeviceId(user: recipient, device: deviceId)
        let body = try req.content.decode(SendMessage<RatchetedSpokeMessage>.self)
        let message = body.message
//        let pushType = body.pushType ?? .none
        
        let chatMessage = ChatMessage(
            messageId: body.messageId,
            message: message,
            from: currentUserDevice,
            to: recipientDevice
        )
        let encoded = try BSONEncoder().encode(chatMessage)
        
        return req.application.webSocketManager.websocket(forDevice: recipientDevice).flatMap { webSocket -> EventLoopFuture<Void> in
            if let webSocket = webSocket {
                let body: Document = [
                    "type": MessageType.message.rawValue,
                    "body": encoded
                ]
                
                let promise = req.eventLoop.makePromise(of: Void.self)
                webSocket.send(raw: body.makeData(), opcode: .binary, promise: promise)
                return promise.futureResult
                // TODO: Client ack
            } else {
                return recipient.resolve(in: req.meow).flatMap { recipient in
                    if recipient.blockedUsers.contains(currentUserDevice.user) {
                        req.logger.info("User is blocked")
                        return req.eventLoop.future()
                    }
                    
                    guard let token = recipient.deviceTokens[recipientDevice.device] else {
                        req.logger.info("Recipient device has no registered token")
                        return chatMessage.save(in: req.meow).transform(to: ())
                    }
                    
                    req.logger.info("Sending push to \(recipient._id)")
                    return req.apns.send(
                        rawBytes: encoded.makeByteBuffer(),
                        pushType: .alert,
                        to: token
                    ).flatMap {
                        chatMessage.save(in: req.meow).transform(to: ())
                    }
                }.recover { _ in }
            }
        }.transform(to: Response(status: .ok))
    }
    
    protectedRoutes.on(.POST, "actions", "send-message", body: .collect(maxSize: 512_000)) { req throws -> EventLoopFuture<Response> in
        // TODO: Prevent receiving the same mesasgeID twice, so that a device can safely assume it being sent in the job queue
        guard let currentUserDevice = req.device else {
            throw Abort(.unauthorized)
        }
        
        let body = try req.content.decode(SendMessage<MultiRecipientSpokeMessage>.self)
        let message = body.message
//        let pushType = body.pushType ?? .none
        
        let saved = try message.keys.map { keypair -> EventLoopFuture<Void> in
            let message = MultiRecipientSpokeMessage(
                tag: .multiRecipientMessage,
                container: message.container,
                keys: [keypair]
            )
            
            let recipient = Reference<User>(unsafeTo: keypair.user)
            
            if req.isAppleAuthenticated && recipient != currentUserDevice.user {
                throw Abort(.badRequest)
            }
            
            let recpientDevice = UserDeviceId(
                user: recipient,
                device: keypair.deviceId
            )
            
            let chatMessage = ChatMessage(
                messageId: body.messageId,
                message: message,
                from: currentUserDevice,
                to: recpientDevice
            )
            let body = try BSONEncoder().encode(chatMessage)
            
            return req.application.webSocketManager.websocket(forDevice: recpientDevice).flatMap { webSocket -> EventLoopFuture<Void> in
                if let webSocket = webSocket {
                    let body: Document = [
                        "type": MessageType.multiRecipientMessage.rawValue,
                        "body": body
                    ]
                    
                    let promise = req.eventLoop.makePromise(of: Void.self)
                    webSocket.send(raw: body.makeData(), opcode: .binary, promise: promise)
                    return promise.futureResult
                    // TODO: Client ack
                } else {
                    return recipient.resolve(in: req.meow).flatMap { recipient in
                        if recipient.blockedUsers.contains(currentUserDevice.user) {
                            req.logger.info("User is blocked")
                            return req.eventLoop.future()
                        }
                        
                        guard let token = recipient.deviceTokens[keypair.deviceId] else {
                            req.logger.info("Recipient device has no registered token")
                            return chatMessage.save(in: req.meow).transform(to: ())
                        }
                        
                        req.logger.info("Sending push to \(recipient._id)")
                        return req.apns.send(
                            rawBytes: body.makeByteBuffer(),
                            pushType: .alert,
                            to: token
                        ).flatMap {
                            chatMessage.save(in: req.meow).transform(to: ())
                        }
                    }
                }
            }
        }
        
        return EventLoopFuture.andAllSucceed(saved, on: req.eventLoop).transform(to: Response(status: .ok))
    }
    
    protectedRoutes.webSocket("websocket") { req, websocket in
        guard
            let user = req.userId,
            let device = req.device,
            let deviceId = req.deviceId
        else {
            _ = websocket.close(code: .unexpectedServerError)
            return
        }
        
        let chatMessages = req.meow(ChatMessage.self)
        
        let emittingOldMessages = chatMessages
            .find(where: "recipient.user" == user.reference && "recipient.device" == deviceId)
            .sequentialForEach { message in
                let type: MessageType
                let body: Document
                
                do {
                    if let message = message.message {
                        type = .message
                        body = try BSONEncoder().encode(message)
                    } else if let message = message.multiRecipientMessage {
                        type = .multiRecipientMessage
                        body = try BSONEncoder().encode(message)
                    } else {
                        return req.eventLoop.makeSucceededVoidFuture()
                    }
                } catch {
                    return req.eventLoop.makeSucceededVoidFuture()
                }
                
                let bson: Document = [
                    "type": type.rawValue,
                    "body": body
                ]
                
                let promise = req.eventLoop.makePromise(of: Void.self)
                
                guard message.recipient == device else {
                    // Skip this one, not intended for this device
                    promise.succeed(())
                    return promise.futureResult
                }
                
                websocket.send(raw: bson.makeData(), opcode: .binary, promise: promise)
                
                    // TODO: Multi-Device Support?
                    // TODO: What is a message never arrives at the client? Do we use acknowledgements (which become a receive-receipt)?
                return chatMessages.deleteOne(where: "_id" == message._id).transform(to: ())
            }
        
        emittingOldMessages.whenSuccess {
            req.application.webSocketManager.addSocket(websocket, forDevice: device)
        }
    }
    
    // TODO: Create and manage group chat configs
    // TODO: Read receipts and acknowledge receiving a message on the client (receive receipt), so the server can remove it and the other user also gets a heads up
}
