import Foundation

public struct MultiRecipientContainer: Codable {
    private enum CodingKeys: String, CodingKey {
        case message = "a"
        case signature = "b"
    }
    
    let message: Data
    let signature: Data
}

public struct MultiRecipientSpokeMessage: Codable {
    public struct ContainerKey: Codable {
        private enum CodingKeys: String, CodingKey {
            case user = "a"
            case deviceId = "b"
            case message = "c"
        }
        
        public let user: String
        public let deviceId: String
        public let message: RatchetedSpokeMessage
    }
    
    private enum CodingKeys: String, CodingKey {
        case tag = "_"
        case container = "a"
        case keys = "b"
    }
    
    private(set) var tag: SpokeMesageTag?
    public let container: MultiRecipientContainer
    public let keys: [ContainerKey]
}

enum SpokeMesageTag: String, Codable {
    case privateMessage = "a"
    case multiRecipientMessage = "b"
}

public struct RatchetedSpokeMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case tag = "_"
        case message = "a"
        case signature = "b"
        case rekey = "c"
    }
    
    private(set) var tag: SpokeMesageTag?
    private let message: Data
    private let signature: Data
    
    // If `true`, the conversation needs to be re-encrypted with a new ratchet engine
    // Rekey must be sent as part of the first message of a new converstion
    // If the other party has no history, and rekey is set, the handshake is done
    // If the other party has a history (and thus has a key), the handshake is redone and the chat is unverified
    // If the other party sees no `rekey == true` and the data cannot be decrypted, the user gets the choice to rekey
    public let rekey: Bool
}
