import Vapor
import Meow

struct ChatMessage: Model, Content {
    let _id: String
    let creationDate: Date
    let sender: Reference<UserDevice>
    let recipient: Reference<User>
    let devices: Set<ObjectId>
    var devicesReceived: Set<ObjectId>
    let message: Document
    
    init(
        _id: String?,
        message: Document,
        from sender: Reference<UserDevice>,
        to recipient: Reference<User>,
        devices: Set<ObjectId>
    ) {
        self._id = _id ?? UUID().uuidString
        self.creationDate = Date()
        self.message = message
        self.sender = sender
        self.recipient = recipient
        self.devices = devices
        self.devicesReceived = []
    }
}
