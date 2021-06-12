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
    let message: MultiRecipientSpokeMessage
    
    init(
        messageId: String,
        message: MultiRecipientSpokeMessage,
        from sender: UserDeviceId,
        to recipient: UserDeviceId
    ) {
        self._id = ObjectId()
        self.createdAt = Date()
        self.messageId = messageId
        self.message = message
        self.sender = sender
        self.recipient = recipient
    }
}
