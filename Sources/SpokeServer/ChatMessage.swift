import Vapor
import Meow

struct ChatMessage: Model, Content {
    let _id: ObjectId
    let creationDate: Date
    let sender: Reference<User>
    let recipient: Reference<User>
    let message: Document
    
    init(message: Document, from sender: Reference<User>, to recipient: Reference<User>) {
        self._id = ObjectId()
        self.creationDate = Date()
        self.message = message
        self.sender = sender
        self.recipient = recipient
    }
}
