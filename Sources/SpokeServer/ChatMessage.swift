import Vapor
import Meow

enum ReceivedNotificationState: Int, Codable {
    case inTransit = 0
    case received = 1
    case receiveEmitted = 2
}

struct ChatMessage: Model, Content {
    let _id: ObjectId
    let messageId: String
    let createdAt: Date
    let sender: UserDeviceId
    let recipient: UserDeviceId
    let multiRecipientMessage: MultiRecipientSpokeMessage?
    let message: RatchetedSpokeMessage?
    
    init(
        messageId: String,
        message: MultiRecipientSpokeMessage,
        from sender: UserDeviceId,
        to recipient: UserDeviceId
    ) {
        self._id = ObjectId()
        self.createdAt = Date()
        self.messageId = messageId
        self.message = nil
        self.multiRecipientMessage = message
        self.sender = sender
        self.recipient = recipient
    }
    
    init(
        messageId: String,
        message: RatchetedSpokeMessage,
        from sender: UserDeviceId,
        to recipient: UserDeviceId
    ) {
        self._id = ObjectId()
        self.createdAt = Date()
        self.messageId = messageId
        self.message = message
        self.multiRecipientMessage = nil
        self.sender = sender
        self.recipient = recipient
    }
}
