import Meow
import Vapor

struct ReadReceipt: Model {
    enum State: Int, Codable {
        case received = 0
        case displayed = 1
    }
    
    let _id: ObjectId
    let messageId: String
    let state: State
    let sender: Reference<User>
    let senderDevice: UserDeviceId
    let recipient: UserDeviceId
}
