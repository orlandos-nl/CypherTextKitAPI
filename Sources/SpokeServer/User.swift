import Crypto
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
    public var appleIdentifier: String?
    public var config: UserConfig
    public var blockedUsers: Set<Reference<User>>
    private var tokens: [String: String]?
    public var deviceTokens: [String: String] {
        get { tokens ?? [:] }
        set { tokens = newValue }
    }
    
    init(username: String, appleIdentifier: String?, config: UserConfig) {
        self._id = username
        self.appleIdentifier = appleIdentifier
        self.config = config
        self.blockedUsers = []
        self.tokens = [:]
    }
}

public struct UserProfile: ReadableModel, Content {
    public static let defaultContentType = HTTPMediaType.bson
    public static var collectionName: String { User.collectionName }
    
    public let _id: String
    public let config: UserConfig
    public let blockedUsers: Set<Reference<User>>
    
    public func encode(to encoder: Encoder) throws {
        enum EncodingKeys: String, CodingKey {
            case _id = "username"
            case config, blockedUsers
        }
        
        var container = encoder.container(keyedBy: EncodingKeys.self)
        
        try container.encode(_id, forKey: ._id)
        try container.encode(config, forKey: .config)
        try container.encode(blockedUsers, forKey: .blockedUsers)
    }
    
    init(representing user: User) {
        self._id = user._id
        self.config = user.config
        self.blockedUsers = user.blockedUsers
    }
}

extension Reference: Hashable where M.Identifier: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}
