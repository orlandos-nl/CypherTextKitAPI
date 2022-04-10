import Meow
import Vapor

struct ReadReceipt: Codable {
    enum State: Int, Codable {
        case received = 0
        case displayed = 1
    }
    
    let messageId: String
    let state: State
    let sender: Reference<User>
    let senderDevice: UserDeviceId
    let recipient: UserDeviceId
    let receivedAt: Date
}
