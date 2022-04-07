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

extension Document: ResponseEncodable {
    public func encodeResponse(for request: Request) -> EventLoopFuture<Response> {
        let response = Response(status: .ok, headers: [
            "Content-Type": "application/bson"
        ], body: .init(buffer: makeByteBuffer()))
        
        return request.eventLoop.makeSucceededFuture(response)
    }
}

public enum PushType: String, Codable {
    case none, call, message, contactRequest = "contactrequest", cancelCall = "cancelcall"
    
    func sendNotification(_ message: ChatMessage, for request: Request, to token: String) -> EventLoopFuture<Void> {
        switch self {
        case .none:
            return request.eventLoop.future()
        case .call, .cancelCall:
            request.logger.info("(Cancel) Call notifications not supported yet")
            return request.eventLoop.future()
        case .message:
            do {
                let notification = ChatNotification(
                    username: message.sender.user.reference,
                    deviceId: message.sender.device,
                    multiRecipientMessage: message.multiRecipientMessage,
                    message: message.message
                )
                
                let payload = try BSONEncoder().encode(notification).makeData()
                
                if payload.count > 1_500 {
                    request.logger.info("Message size \(payload.coun)")
                    return request.apns.send(
                        APNSwiftPayload(
                            alert: APNSwiftAlert(
                                title: "New Message",
                                body: "Open the app to view"
                            ),
                            badge: 1,
                            sound: .normal("default"),
                            hasContentAvailable: false,
                            hasMutableContent: true,
                            threadID: message.sender.user.reference,
                            targetContentId: message.sender.user.reference,
                            interruptionLevel: "active"
                        ),
                        to: token
                    ).recover { error in
                        request.logger.report(error: error)
                    }
                }
                
                return request.apns.send(
                    APNSwiftPayload(
                        alert: APNSwiftAlert(
                            title: "New Message",
                            subtitle: payload.base64EncodedString(),
                            body: "Open the app to view"
                        ),
                        badge: 1,
                        sound: .normal("default"),
                        hasContentAvailable: false,
                        hasMutableContent: true,
                        threadID: message.sender.user.reference,
                        targetContentId: message.sender.user.reference,
                        interruptionLevel: "active"
                    ),
                    to: token
                ).recover { error in
                    request.logger.report(error: error)
                }
            } catch {
                request.logger.report(error: error)
                return request.eventLoop.future()
            }
        case .contactRequest:
            return request.apns.send(
                APNSwiftPayload(
                    alert: APNSwiftAlert(
                        title: "Contact Request",
                        body: "Open the app to view"
                    ),
                    badge: 1,
                    sound: .normal("default"),
                    hasContentAvailable: false,
                    hasMutableContent: true,
                    threadID: message.sender.user.reference,
                    targetContentId: message.sender.user.reference,
                    interruptionLevel: "active"
                ),
                to: token
            ).recover { error in
                request.logger.report(error: error)
            }
        }
    }
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
    case ack = "d"
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
        
        let reference = Reference<User>(unsafeTo: body.username)
        
        return reference.exists(in: req.meow).flatMap { exists in
            if exists {
                return req.eventLoop.future(error: Abort(.badRequest))
            }
            
            let user = User(
                username: body.username,
                appleIdentifier: nil,
                config: body.config
            )
            
            return user.save(in: req.meow).transform(to: SignUpResponse(existingUser: nil))
        }
    }
    
    routes.get("users", ":userId") { req -> EventLoopFuture<UserProfile> in
        guard let user = req.parameters.get("userId", as: Reference<UserProfile>.self) else {
            throw Abort(.notFound)
        }
        
        return user.resolve(in: req.meow)
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
        
        let devices = try config.readAndValidateDevices()
        if devices.count > 3 {
            // Disallowed
            throw Abort(.badRequest)
        }
        
        user.config = config
        
        return user.save(in: req.meow)
            .transform(to: UserProfile(representing: user))
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
    
    protectedRoutes.post("blobs") { req -> EventLoopFuture<Blob> in
        guard let user = req.user else {
            throw Abort(.internalServerError)
        }
        
        return req.body.collect().unwrap(or: Abort(.badRequest)).flatMapThrowing { buffer -> Document in
            let document = Document(buffer: buffer)
            
            guard document.validate().isValid else {
                throw Abort(.badRequest)
            }
            
            return document
        }.flatMap { document in
            let blob = Blob(creator: user*, document: document)
            return blob.create(in: req.meow).transform(to: blob)
        }
    }
    
    protectedRoutes.get("blobs", ":blobId") { req -> EventLoopFuture<Blob> in
        let id = try req.parameters.require("blobId")
        
        return req.meow[Blob.self].findOne(where: "_id" == id).unwrap(or: Abort(.notFound))
    }
    
    protectedRoutes.post("users", ":userId", "devices", ":deviceId", "send-message") { req throws -> EventLoopFuture<Response> in
        // TODO: Prevent receiving the same mesasgeID twice, so that a device can safely assume it being sent in the job queue
        guard let currentUserDevice = req.device else {
            throw Abort(.unauthorized)
        }
        
        guard
            let sender = req.user,
            let recipient = req.parameters.get("userId", as: Reference<User>.self),
            let deviceId = req.parameters.get("deviceId")
        else {
            throw Abort(.notFound)
        }
        
        let recipientDevice = UserDeviceId(user: recipient, device: deviceId)
        let body = try req.content.decode(SendMessage<RatchetedMessage>.self)
        let message = body.message
        let pushType = body.pushType ?? .none
        
        let chatMessage = ChatMessage(
            messageId: body.messageId,
            message: message,
            from: currentUserDevice,
            to: recipientDevice
        )
        let encoded = try BSONEncoder().encode(chatMessage)
        
        func onWebSocketFailure() -> EventLoopFuture<Void> {
            let isRecipientConnected = req.application.webSocketManager.hasWebsocket(forUser: recipient)
            let recipient = recipient.resolve(in: req.meow)
            
            return recipient.and(isRecipientConnected).flatMap { (recipient, isRecipientConnected) in
                if recipient.blockedUsers.contains(currentUserDevice.user) {
                    req.logger.info("User is blocked")
                    return req.eventLoop.future()
                }
                
                guard
                    !isRecipientConnected,
                    recipient* != sender*,
                    let token = recipient.deviceTokens[recipientDevice.device]
                else {
                    req.logger.info("Recipient device has no registered token")
                    return chatMessage.save(in: req.meow).transform(to: ())
                }
                
                req.logger.info("Sending push to \(recipient._id)")
                return pushType.sendNotification(chatMessage, for: req, to: token).flatMap {
                    chatMessage.save(in: req.meow).transform(to: ())
                }
            }.recover { _ in }
        }
        
        return req.application.webSocketManager.websocket(forDevice: recipientDevice).flatMap { webSocket -> EventLoopFuture<Void> in
            if let webSocket = webSocket {
                let id = ObjectId()
                let body: Document = [
                    "id": id,
                    "type": MessageType.message.rawValue,
                    "body": encoded
                ]
                
                let promise = req.eventLoop.makePromise(of: Void.self)
                webSocket.send(raw: body.makeData(), opcode: .binary, promise: promise)
                return promise.futureResult.flatMap {
                    req.expectWebSocketAck(forId: id, forDevice: recipientDevice)
                }.flatMapError { _ in
                    onWebSocketFailure()
                }
            } else {
                return onWebSocketFailure()
            }
        }.transform(to: Response(status: .ok))
    }
    
    protectedRoutes.post("actions", "send-message") { req throws -> EventLoopFuture<Response> in
        // TODO: Prevent receiving the same messageID twice, so that a device can safely assume it being sent in the job queue
        guard let currentUserDevice = req.device else {
            throw Abort(.unauthorized)
        }
        
        let body = try req.content.decode(SendMessage<MultiRecipientMessage>.self)
        let message = body.message
        let pushType = body.pushType ?? .none
        
        let saved = try message.keys.map { keypair -> EventLoopFuture<Void> in
            let message = MultiRecipientMessage(
                tag: .multiRecipientMessage,
                container: message.container,
                keys: [keypair]
            )
            
            let recipient = Reference<User>(unsafeTo: keypair.user)
            
            if req.isAppleAuthenticated && recipient != currentUserDevice.user {
                throw Abort(.badRequest)
            }
            
            let recipientDevice = UserDeviceId(
                user: recipient,
                device: keypair.deviceId
            )
            
            let chatMessage = ChatMessage(
                messageId: body.messageId,
                message: message,
                from: currentUserDevice,
                to: recipientDevice
            )
            let body = try BSONEncoder().encode(chatMessage)
            
            func onWebSocketFailure() -> EventLoopFuture<Void> {
                let isRecipientConnected = req.application.webSocketManager.hasWebsocket(forUser: recipient)
                let recipient = recipient.resolve(in: req.meow)
                
                return recipient.and(isRecipientConnected).flatMap { (recipient, isRecipientConnected) in
                    if recipient.blockedUsers.contains(currentUserDevice.user) {
                        req.logger.info("User is blocked")
                        return req.eventLoop.future()
                    }
                    
                    guard
                        !isRecipientConnected,
                        recipient* != currentUserDevice.user,
                        let token = recipient.deviceTokens[keypair.deviceId]
                    else {
                        req.logger.info("Recipient device has no registered token")
                        return chatMessage.save(in: req.meow).transform(to: ())
                    }
                    
                    req.logger.info("Sending push to \(recipient._id)")
                    return pushType.sendNotification(chatMessage, for: req, to: token).flatMap {
                        chatMessage.save(in: req.meow).transform(to: ())
                    }
                }
            }
            
            return req.application.webSocketManager.websocket(forDevice: recipientDevice).flatMap { webSocket -> EventLoopFuture<Void> in
                if let webSocket = webSocket {
                    let id = ObjectId()
                    let body: Document = [
                        "id": id,
                        "type": MessageType.multiRecipientMessage.rawValue,
                        "body": body
                    ]
                    
                    let promise = req.eventLoop.makePromise(of: Void.self)
                    webSocket.send(raw: body.makeData(), opcode: .binary, promise: promise)
                    return promise.futureResult.flatMap {
                        req.expectWebSocketAck(forId: id, forDevice: recipientDevice)
                    }.flatMapError { error in
                        req.logger.report(error: error)
                        return onWebSocketFailure()
                    }
                } else {
                    return onWebSocketFailure()
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
        let manager = req.application.webSocketManager
        
        websocket.onBinary { websocket, buffer in
            let document = Document(buffer: buffer)
            
            guard
                document["type"] as? String == MessageType.ack.rawValue,
                let ackId = document["id"] as? ObjectId
            else {
                // Ignore
                return
            }
            
            manager.acknowledge(id: ackId, forDevice: device)
        }
        
        websocket.onClose.whenComplete { _ in
            req.logger.info("WebSocket Client disconnected")
        }
        
        let emittingOldMessages = chatMessages
            .find(where: "recipient.user" == user.reference && "recipient.device" == deviceId)
            .sort(["createdAt": .ascending])
            .sequentialForEach { message -> EventLoopFuture<Void> in
                guard message.recipient == device else {
                    // Skip this one, not intended for this device
                    req.logger.error("Invalid message for recipient")
                    return req.eventLoop.future()
                }
                
                let type: MessageType
                let body: Document
                
                do {
                    type = message.multiRecipientMessage != nil ? .multiRecipientMessage : .message
                    body = try BSONEncoder().encode(message)
                } catch {
                    req.logger.report(error: error)
                    return req.eventLoop.future(error: error)
                }
                
                let id = ObjectId()
                let bson: Document = [
                    "id": id,
                    "type": type.rawValue,
                    "body": body
                ]
                
                websocket.send(raw: bson.makeData(), opcode: .binary)
                
                return req.expectWebSocketAck(forId: id, forDevice: device).flatMap {
                    chatMessages.deleteOne(where: "_id" == message._id)
                }.transform(to: ())
            }
        
        emittingOldMessages.whenSuccess {
            // TODO: Horizontal scaling with change streams
            req.application.webSocketManager.addSocket(websocket, forDevice: device)
        }
    }
    
    // TODO: Read receipts and acknowledge receiving a message on the client (receive receipt), so the server can remove it and the other user also gets a heads up
}
