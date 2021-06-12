import Meow
import Vapor

public struct UserDeviceId: Hashable, Codable {
    let user: Reference<User>
    let device: String
    
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

struct Signed<T: Codable>: Codable {
    let value: Document
    let signature: Data
    
    public func verifySignature(signedBy publicIdentity: PublicSigningKey) throws {
        try publicIdentity.validateSignature(
            signature,
            forData: value.makeData()
        )
    }
    
    public func readAndVerifySignature(signedBy publicIdentity: PublicSigningKey) throws -> T {
        try publicIdentity.validateSignature(
            signature,
            forData: value.makeData()
        )
        
        return try BSONDecoder().decode(T.self, from: value)
    }
}

public struct UserConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case identity = "a"
        case devices = "b"
    }
    
    /// Identity is a public key used to validate messages sidned by `identity`
    /// This is the main device's identity, which when trusted verified all other devices' validity
    public let identity: PublicSigningKey
    
    /// Devices are signed by `identity`, so you only need to trust `identity`'s validity
    private var devices: Signed<[UserDeviceConfig]>
    
    public func readAndValidateDevices() throws -> [UserDeviceConfig] {
        try devices.readAndVerifySignature(signedBy: identity)
    }
}

public struct UserDeviceConfig: Codable {
    private enum CodingKeys: String, CodingKey {
        case deviceId = "a"
        case identity = "b"
        case publicKey = "c"
        case isMasterDevice = "d"
    }
    
    public let deviceId: String
    public let identity: PublicSigningKey
    public let publicKey: PublicKey
    public let isMasterDevice: Bool
    
    public init(
        deviceId: String,
        identity: PublicSigningKey,
        publicKey: PublicKey,
        isMasterDevice: Bool
    ) {
        self.deviceId = deviceId
        self.identity = identity
        self.publicKey = publicKey
        self.isMasterDevice = isMasterDevice
    }
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
