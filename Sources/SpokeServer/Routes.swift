import BSON
import Vapor
import Meow
import JWTKit

// TODO: Ideally we'd have SCRAM-SHA-256 authentication in the client & server
// SCRAM-SHA-256 doesn't require the password to leave the client's device
// It's also more secure, since the server is being verified as well
// TODO: Use $set queries to prevent simultanious updates to the same model, overwriting one another
struct Credentials: Codable {
    let username: String
    let password: String
    let publicKeys: Document
}

struct ChangeCredentials: Codable {
    let oldPassword: String
    let newPassword: String
}

struct AuthResponse: Content {
    let profile: UserProfile
    let token: String
}

func registerRoutes(to routes: RoutesBuilder) {
    routes.post("auth", "register") { req -> EventLoopFuture<AuthResponse> in
        let credentials = try req.content.decode(Credentials.self, using: BSONDecoder())
        
        let user = try User(username: credentials.username, password: credentials.password, publicKeys: credentials.publicKeys)
        let token = try Application.signer.sign(Token(user: user, validFor: 24 * 3600))
        
        let authResponse = AuthResponse(profile: UserProfile(representing: user), token: token)
        return user.save(in: req.meow).transform(to: authResponse)
    }
    
    routes.post("auth", "login") { req -> EventLoopFuture<AuthResponse> in
        let credentials = try req.content.decode(Credentials.self)
        
        return Reference<User>(unsafeTo: credentials.username).resolve(in: req.meow).flatMapThrowing { user in
            try user.authenticate(credentials.password)
            let token = try Application.signer.sign(Token(user: user, validFor: 24 * 3600))
            
            return AuthResponse(profile: UserProfile(representing: user), token: token)
        }
    }
    
    let routes = routes.grouped(TokenAuthenticationMiddleware())
    
    // TODO: Use $set instead of `save`
    routes.post("auth", "change-password") { req -> EventLoopFuture<UserProfile> in
        guard let currentUser = req.user else {
            throw Abort(.unauthorized)
        }
        
        let changeCredentials = try req.content.decode(ChangeCredentials.self, using: BSONDecoder())
        
        return currentUser.resolve(in: req.meow).flatMapThrowing { user -> User in
            var user = user
            try user.authenticate(changeCredentials.oldPassword)
            try user.changePassword(to: changeCredentials.newPassword)
            return user
        }.flatMap { user in
            user.save(in: req.meow).transform(to: UserProfile(representing: user))
        }
    }
    
    routes.get("users", ":id") { req -> EventLoopFuture<UserProfile> in
        guard let user = req.parameters.get("id", as: Reference<UserProfile>.self) else {
            throw Abort(.notFound)
        }
        
        return user.resolve(in: req.meow)
    }
    
    // TODO: Use update op with $push
    routes.post("users", ":id", "block") { req -> EventLoopFuture<UserProfile> in
        guard let currentUser = req.user, let otherUser = req.parameters.get("id", as: Reference<User>.self) else {
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
    routes.post("users", ":id", "unblock") { req -> EventLoopFuture<UserProfile> in
        guard let currentUser = req.user, let otherUser = req.parameters.get("id", as: Reference<User>.self) else {
            throw Abort(.unauthorized)
        }
        
        return currentUser.resolve(in: req.meow).flatMap { currentUser in
            var currentUser = currentUser
            currentUser.blockedUsers.remove(otherUser)
            
            return currentUser.save(in: req.meow)
                .transform(to: UserProfile(representing: currentUser))
        }
    }
    
    routes.post("users", ":id", "messages", "send") { req -> EventLoopFuture<ChatMessage> in
        guard let currentUser = req.user, let otherUser = req.parameters.get("id", as: Reference<User>.self) else {
            throw Abort(.unauthorized)
        }
        
        return otherUser.resolve(in: req.meow).flatMap { otherUser in
            if otherUser.blockedUsers.contains(currentUser) {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden))
            }
            
            return req.body.collect()
                .unwrap(or: Abort(.badRequest))
                .flatMap { buffer in
                    let message = ChatMessage(
                        message: Document(buffer: buffer),
                        from: currentUser,
                        to: otherUser*
                    )
                    
                    return message.save(in: req.meow).transform(to: message)
                }
        }
    }
    
    routes.webSocket("messages", "watch") { req, websocket in
        guard let user = req.user else {
            _ = websocket.close(code: .unexpectedServerError)
            return
        }
        
        let chatMessages = req.meow(ChatMessage.self)
        
        let emittingOldMessages = chatMessages
            .find(where: "recipient" == user.reference)
            .sequentialForEach { message in
                let bson = try BSONEncoder().encode(message)
                let promise = req.eventLoop.makePromise(of: Void.self)
                websocket.send(raw: bson.makeData(), opcode: .binary, promise: promise)
                return promise.futureResult.flatMap {
                    // TODO: Multi-Device Support?
                    // TODO: What is a message never arrives at the client? Do we use acknowledgements (which become a receive-receipt)?
                    chatMessages.deleteOne(where: "_id" == message._id).transform(to: ())
                }
            }
        
        emittingOldMessages.flatMap {
            chatMessages.buildChangeStream {
                match("recipient" == user.reference)
            }
        }.whenComplete { result in
            switch result {
            case .success(let changeStream):
                changeStream.forEach { notification in
                    guard notification.operationType == .insert, let message = notification.fullDocument else {
                        return true
                    }
                    
                    do {
                        let bson = try BSONEncoder().encode(message)
                        let promise = req.eventLoop.makePromise(of: Void.self)
                        websocket.send(raw: bson.makeData(), opcode: .binary, promise: promise)
                        _ = promise.futureResult.flatMap {
                            chatMessages.deleteOne(where: "_id" == message._id).transform(to: ())
                        }
                        return true
                    } catch {
                        _ = websocket.close(code: .unexpectedServerError)
                        return false
                    }
                }
            case .failure:
                _ = websocket.close(code: .unexpectedServerError)
            }
        }
    }
    
    // TODO: Create and manage group chat configs
    // TODO: Read receipts and acknowledge receiving a message on the client (receive receipt), so the server can remove it and the other user also gets a heads up
}
