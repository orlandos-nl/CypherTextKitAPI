import Vapor
import Meow

enum ReceivedNotificationState: Int, Codable, CaseIterable {
    case received = 0
}

struct ChatNotification: Codable {
    private enum CodingKeys: String, CodingKey {
        case username = "u"
        case deviceId = "d"
        case multiRecipientMessage = "M"
        case message = "m"
    }
    
    let username: String
    let deviceId: String
    let multiRecipientMessage: MultiRecipientMessage?
    let message: RatchetedMessage?
}

struct ChatMessage: Model, Content {
    let _id: ObjectId
    let messageId: String
    let createdAt: Date
    let sender: UserDeviceId
    let recipient: UserDeviceId
    let multiRecipientMessage: MultiRecipientMessage?
    let message: RatchetedMessage?
    let requestsAcknowledgement: Bool?
    let receiveNotification: ReadReceipt.State?
    
    var type: MessageType? {
        if message != nil {
            return .message
        } else if multiRecipientMessage != nil {
            return .multiRecipientMessage
        } else {
            return .receipt
        }
    }
    
    init(
        messageId: String,
        message: MultiRecipientMessage,
        from sender: UserDeviceId,
        to recipient: UserDeviceId,
        requestsAcknowledgement: Bool
    ) {
        self._id = ObjectId()
        self.createdAt = Date()
        self.messageId = messageId
        self.message = nil
        self.multiRecipientMessage = message
        self.receiveNotification = nil
        self.sender = sender
        self.recipient = recipient
        self.requestsAcknowledgement = requestsAcknowledgement
    }
    
    init(
        messageId: String,
        message: RatchetedMessage,
        from sender: UserDeviceId,
        to recipient: UserDeviceId,
        requestsAcknowledgement: Bool
    ) {
        self._id = ObjectId()
        self.createdAt = Date()
        self.messageId = messageId
        self.message = message
        self.multiRecipientMessage = nil
        self.receiveNotification = nil
        self.sender = sender
        self.recipient = recipient
        self.requestsAcknowledgement = requestsAcknowledgement
    }
    
    init(
        messageId: String,
        receiveNotification: ReadReceipt.State,
        from sender: UserDeviceId,
        to recipient: UserDeviceId
    ) {
        self._id = ObjectId()
        self.createdAt = Date()
        self.messageId = messageId
        self.message = nil
        self.multiRecipientMessage = nil
        self.receiveNotification = receiveNotification
        self.requestsAcknowledgement = false
        self.sender = sender
        self.recipient = recipient
    }
}
