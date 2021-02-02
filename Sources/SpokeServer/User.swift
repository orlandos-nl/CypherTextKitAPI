import CryptoKit
import Meow
import Vapor
import JWTKit

public struct PublicSigningKey: Codable, JWTAlgorithm {
    public var name: String { "ed25519" }
    
    private struct InvalidSignature: Error {}
    fileprivate let publicKey: Curve25519.Signing.PublicKey
    
    fileprivate init(publicKey: Curve25519.Signing.PublicKey) {
        self.publicKey = publicKey
    }
    
    public func encode(to encoder: Encoder) throws {
        try Binary(buffer: ByteBuffer(data: publicKey.rawRepresentation)).encode(to: encoder)
    }
    
    public init(from decoder: Decoder) throws {
        do {
            publicKey = try .init(rawRepresentation: Binary(from: decoder).data)
        } catch {
            do {
                publicKey = try .init(rawRepresentation: Data(from: decoder))
            } catch {
                publicKey = try .init(rawRepresentation: Data([UInt8](from: decoder)))
            }
        }
    }
    
    public var data: Data {
        publicKey.rawRepresentation
    }
    
    public func validateSignature<
        Signature: DataProtocol,
        D: DataProtocol
    >(
        _ signature: Signature,
        forData data: D
    ) throws {
        guard publicKey.isValidSignature(signature, for: data) else {
            throw InvalidSignature()
        }
    }
    
    public func verify<Signature, Plaintext>(_ signature: Signature, signs plaintext: Plaintext) throws -> Bool where Signature : DataProtocol, Plaintext : DataProtocol {
        try validateSignature(signature, forData: plaintext)
        return true
    }
    
    public func sign<Plaintext>(_ plaintext: Plaintext) throws -> [UInt8] where Plaintext : DataProtocol {
        throw Abort(.internalServerError)
    }
}

public struct User: Model {
    public let _id: String
    private var passwordHash: String
    public var identity: PublicSigningKey?
    public var contactAdvertisedData: Data?
    public var blockedUsers: Set<Reference<User>>
    
    func makeSigner() throws -> JWTSigner? {
        identity.map(JWTSigner.init)
    }
    
    init(username: String, password: String, identity: PublicSigningKey?) throws {
        self.init(
            username: username,
            passwordHash: try Bcrypt.hash(password),
            identity: identity
        )
    }
    
    init(username: String, passwordHash: String, identity: PublicSigningKey?) {
        self._id = username
        self.passwordHash = passwordHash
        self.blockedUsers = []
        self.identity = identity
    }
    
    public func authenticate(_ password: String) throws {
        guard
            identity == nil,
            try Bcrypt.verify(password, created: passwordHash)
        else {
            throw SpokeServerError.badLogin
        }
    }
    
    public mutating func changeIdentity(to identity: PublicSigningKey) throws {
        self.identity = identity
    }
}

public struct UserProfile: ReadableModel, Content {
    public static let defaultContentType = HTTPMediaType.bson
    public static var collectionName: String { User.collectionName }
    
    public let _id: String
    public let identity: PublicSigningKey?
    public let contactAdvertisedData: Data?
    public let blockedUsers: Set<Reference<User>>
    
    public func encode(to encoder: Encoder) throws {
        enum EncodingKeys: String, CodingKey {
            case _id = "username"
            case identity, contactAdvertisedData, blockedUsers
        }
        
        var container = encoder.container(keyedBy: EncodingKeys.self)
        
        try container.encode(_id, forKey: ._id)
        try container.encode(identity, forKey: .identity)
        try container.encode(contactAdvertisedData, forKey: .contactAdvertisedData)
        try container.encode(blockedUsers, forKey: .blockedUsers)
    }
    
    init(representing user: User) {
        self._id = user._id
        self.identity = user.identity
        self.contactAdvertisedData = user.contactAdvertisedData
        self.blockedUsers = user.blockedUsers
    }
}

extension Reference: Hashable where M.Identifier: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}
