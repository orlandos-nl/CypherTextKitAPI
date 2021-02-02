import Meow
import Vapor

public struct UserDeviceId: Hashable, Codable {
    let user: Reference<User>
    let device: ObjectId
    
    public func makePrimitive() -> Primitive? {
        try? BSONEncoder().encode(self)
    }
}

public struct PublicKey: Codable, Equatable {
    fileprivate let publicKey: Curve25519.KeyAgreement.PublicKey
    
    fileprivate init(publicKey: Curve25519.KeyAgreement.PublicKey) {
        self.publicKey = publicKey
    }
    
    public func encode(to encoder: Encoder) throws {
        try publicKey.rawRepresentation.encode(to: encoder)
    }
    
    public init(from decoder: Decoder) throws {
        publicKey = try .init(rawRepresentation: Data(from: decoder))
    }
    
    public static func ==(lhs: PublicKey, rhs: PublicKey) -> Bool {
        lhs.publicKey.rawRepresentation == rhs.publicKey.rawRepresentation
    }
}

/// This publicKey can be used to contact it's owner and exchange a shared secret for communication
/// Once contact is established, it can be safely replaced as both ends now know the shared secret
public struct SignedPublicKey: Codable {
    public let publicKey: PublicKey
    public let signature: Data
    
    public func verifySignature(signedBy publicIdentity: PublicSigningKey) throws {
        try publicIdentity.validateSignature(
            signature,
            forData: publicKey.publicKey.rawRepresentation
        )
    }
}

struct UserDeviceConfig: Codable {
    let publicKey: SignedPublicKey
}

public struct UserDevice: Model, Content {
    public static let defaultContentType = HTTPMediaType.bson
    
    @CompoundId<UserDeviceId> public var _id: Document
    var config: UserDeviceConfig?
}

@propertyWrapper
public struct CompoundId<C: Codable & Hashable>: Codable, Hashable {
    public let wrappedValue: Document
    public let projectedValue: C
    
    public func hash(into hasher: inout Hasher) {
        projectedValue.hash(into: &hasher)
    }
    
    public init(_ compound: C) throws {
        self.projectedValue = compound
        self.wrappedValue = try BSONEncoder().encode(compound)
    }
    
    public init(_ document: Document) throws {
        self.projectedValue = try BSONDecoder().decode(C.self, from: document)
        self.wrappedValue = document
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(projectedValue)
    }
    
    public init(from decoder: Decoder) throws {
        projectedValue = try .init(from: decoder)
        wrappedValue = try BSONEncoder().encode(projectedValue)
    }
}

extension Reference where M.Identifier == Document {
    init<E: Encodable>(unsafeToEncoded encoded: E) throws {
        try self.init(unsafeTo: BSONEncoder().encode(encoded))
    }
}
