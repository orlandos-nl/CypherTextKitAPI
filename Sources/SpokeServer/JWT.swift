import Meow
import Vapor
import JWTKit
import CryptoKit

struct Token: JWTPayload {
    let device: UserDeviceId
    let exp: ExpirationClaim
    
    func verify(using signer: JWTSigner) throws {
        try exp.verifyNotExpired()
    }
}

struct TokenAuthenticationMiddleware: Middleware {
    func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        guard
            let username = request.headers["X-Api-User"].first,
            let token = request.headers["X-Api-Token"].first
        else {
            return request.eventLoop.makeFailedFuture(SpokeServerError.badLogin)
        }
        
        let user = Reference<User>(unsafeTo: username)
        
        return user.resolve(in: request.meow).flatMap { user in
            do {
                let signer: JWTSigner
                
                if let publicKeySigner = try user.makeSigner() {
                    signer = publicKeySigner
                } else {
                    // User hasn't set up their account yet
                    signer = Application.signer
                }
                
                let token = try signer.verify(token, as: Token.self)
                let device = try Reference<UserDevice>(unsafeToEncoded: token.device)
                
                return device.resolve(in: request.meow).flatMap { device in
                    request.storage.set(UserDeviceKey.self, to: device)
                    request.storage.set(UserKey.self, to: user)
                    
                    return next.respond(to: request)
                }
            } catch {
                return request.eventLoop.makeFailedFuture(error)
            }
        }
    }
}

extension Application {
    static var signer: JWTSigner = {
        try! JWTSigner.es512(key: .generate())
    }()
}

fileprivate struct UserDeviceKey: StorageKey {
    typealias Value = UserDevice
}

fileprivate struct UserKey: StorageKey {
    typealias Value = User
}

extension Request {
    var device: UserDevice? {
        storage.get(UserDeviceKey.self)
    }
    
    var user: User? {
        storage.get(UserKey.self)
    }
    
    var username: String? {
        device.map(\.$_id.user.reference)
    }
    
    var deviceId: ObjectId? {
        device.map(\.$_id.device)
    }
    
    var userId: Reference<User>? {
        username.map(Reference<User>.init)
    }
    
    var userDeviceId: Reference<UserDevice>? {
        device.map(Reference.init)
    }
}
