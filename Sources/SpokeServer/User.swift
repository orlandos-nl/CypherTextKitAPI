import Meow
import Vapor

public struct User: Model {
    public let _id: String
    private var passwordHash: String
    public var publicKeys: Document
    public var contactAdvertisedData: Data?
    public var blockedUsers: Set<Reference<User>>
    
    init(username: String, password: String, publicKeys: Document) throws {
        self.init(
            username: username,
            passwordHash: try Bcrypt.hash(password),
            publicKeys: publicKeys
        )
    }
    
    init(username: String, passwordHash: String, publicKeys: Document) {
        self._id = username
        self.passwordHash = passwordHash
        self.blockedUsers = []
        self.publicKeys = publicKeys
    }
    
    public func authenticate(_ password: String) throws {
        guard try Bcrypt.verify(password, created: passwordHash) else {
            throw SpokeServerError.badLogin
        }
    }
    
    public mutating func changePassword(to newPassword: String) throws {
        self.passwordHash = try Bcrypt.hash(newPassword)
    }
}

public struct UserProfile: ReadableModel, Content {
    public static var collectionName: String { User.collectionName }
    
    private enum EncodingKeys: String, CodingKey {
        case _id = "username"
        case publicKeys, contactAdvertisedData, blockedUsers
    }
    
    public var _id: String
    public var publicKeys: Document
    public var contactAdvertisedData: Data?
    public var blockedUsers: Set<Reference<User>>
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)
        
        try container.encode(_id, forKey: ._id)
        try container.encode(publicKeys, forKey: .publicKeys)
        try container.encode(contactAdvertisedData, forKey: .contactAdvertisedData)
        try container.encode(blockedUsers, forKey: .blockedUsers)
    }
    
    init(representing user: User) {
        self._id = user._id
        self.publicKeys = user.publicKeys
        self.contactAdvertisedData = user.contactAdvertisedData
        self.blockedUsers = user.blockedUsers
    }
}

extension Reference: Hashable where M.Identifier: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(reference)
    }
}
