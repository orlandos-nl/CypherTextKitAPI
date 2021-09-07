import Meow
import Vapor
import JWTKit
import Crypto

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
            let deviceId = request.headers["X-Api-Device"].first,
            let token = request.headers["X-Api-Token"].first
        else {
            return request.eventLoop.makeFailedFuture(CypherTextKitServerError.badLogin)
        }
        
        let user = Reference<User>(unsafeTo: username)
        return user.resolve(in: request.meow).flatMap { user in
            do {
                let devices = try user.config.readAndValidateDevices()
                
                guard let currentDevice = devices.first(where: {
                    $0.deviceId == deviceId
                }) else {
                    if let appleToken = request.headers["X-Apple-Token"].first {
                        // Unknown device, but 'verified' through apple
                        // Can be used for intra-device communications only
                        return request.jwt.apple.verify(appleToken).flatMap { appleToken in
                            request.storage.set(UserDeviceIdKey.self, to: UserDeviceId(user: user*, device: deviceId))
                            request.storage.set(UserKey.self, to: user)
                            request.storage.set(IsAppleAuthenticatedKey.self, to: true)
                            return next.respond(to: request)
                        }
                    } else {
                        // Device is not a known device, user is not signed in
                        throw CypherTextKitServerError.badLogin
                    }
                }
                
                let signer = JWTSigner(algorithm: currentDevice.identity)
                let token = try signer.verify(token, as: Token.self)
                request.storage.set(UserDeviceIdKey.self, to: token.device)
                request.storage.set(UserKey.self, to: user)
                request.storage.set(IsMasterDeviceKey.self, to: currentDevice.isMasterDevice)
                
                return next.respond(to: request)
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

fileprivate struct UserDeviceIdKey: StorageKey {
    typealias Value = UserDeviceId
}

fileprivate struct UserKey: StorageKey {
    typealias Value = User
}

fileprivate struct IsMasterDeviceKey: StorageKey {
    typealias Value = Bool
}

fileprivate struct IsAppleAuthenticatedKey: StorageKey {
    typealias Value = Bool
}

extension Request {
    var device: UserDeviceId? {
        storage.get(UserDeviceIdKey.self)
    }
    
    var isMasterDevice: Bool {
        storage.get(IsMasterDeviceKey.self) ?? false
    }
    
    var isAppleAuthenticated: Bool {
        storage.get(IsAppleAuthenticatedKey.self) ?? false
    }
    
    var user: User? {
        storage.get(UserKey.self)
    }
    
    var username: String? {
        device.map(\.user.reference)
    }
    
    var deviceId: String? {
        device.map(\.device)
    }
    
    var userId: Reference<User>? {
        username.map(Reference<User>.init)
    }
}
