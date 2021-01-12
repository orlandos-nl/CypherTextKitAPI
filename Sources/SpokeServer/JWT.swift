import Meow
import Vapor
import JWTKit

struct Token: JWTPayload {
    let sub: SubjectClaim
    let exp: ExpirationClaim
    
    func verify(using signer: JWTSigner) throws {
        try exp.verifyNotExpired()
    }
    
    init(user: User, validFor duration: Double) {
        self.sub = .init(value: user._id)
        self.exp = .init(value: Date().addingTimeInterval(duration))
    }
}

struct TokenAuthenticationMiddleware: Middleware {
    func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
        guard let token = request.headers["X-Api-Token"].first else {
            return request.eventLoop.makeFailedFuture(SpokeServerError.badLogin)
        }
        
        do {
            let token = try Application.signer.verify(token, as: Token.self)
            request.storage.set(UsernameKey.self, to: token.sub.value)
        } catch {
            return request.eventLoop.makeFailedFuture(error)
        }
        
        return next.respond(to: request)
    }
}

extension Application {
    static var signer: JWTSigner = {
        try! JWTSigner.es512(key: .generate())
    }()
}

fileprivate struct UsernameKey: StorageKey {
    typealias Value = User.Identifier
}

extension Request {
    var username: String? {
        storage.get(UsernameKey.self)
    }
    
    var user: Reference<User>? {
        username.map(Reference<User>.init)
    }
}
