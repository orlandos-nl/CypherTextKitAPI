import Meow
import BSON
import Vapor

extension Application {
    var webSocketManager: WebSocketManager {
        if let manager = storage.get(WebSocketManagerKey.self) {
            return manager
        }
        
        let manager = WebSocketManager(app: app)
        storage.set(WebSocketManagerKey.self, to: manager)
        return manager
    }
}

struct WebSocketManagerKey: StorageKey {
    typealias Value = WebSocketManager
}

extension Request {
    public func expectWebSocketAck(forId id: ObjectId, forDevice device: UserDeviceId) -> EventLoopFuture<Void> {
        struct Timeout: Error {}
        let manager = application.webSocketManager
        return manager.eventLoop.flatSubmit {
            let ack = self.eventLoop.makePromise(of: Void.self)
            
            self.eventLoop.scheduleTask(in: .seconds(10)) {
                ack.fail(Timeout())
            }
            
            manager.acks[id] = (device, ack)
            return ack.futureResult
        }
    }
}

final class WebSocketManager {
    let app: Application
    let eventLoop: EventLoop
    init(app: Application) {
        self.app = app
        self.eventLoop = app.eventLoopGroup.next()
    }
    private var webSockets = [WebSocketClient]()
    fileprivate var acks = [ObjectId: (UserDeviceId, EventLoopPromise<Void>)]()
    
    public func addSocket(_ socket: WebSocket, forDevice device: UserDeviceId) {
        eventLoop.execute {
            if let index = self.webSockets.firstIndex(where: { $0.device == device }) {
                let client = self.webSockets.remove(at: index)
                self.app.logger.info("Killing existing socket for replacement")
                _ = client.socket.close()
            }
            
            self.webSockets.append(WebSocketClient(device: device, socket: socket))
            
            socket.onClose.hop(to: self.eventLoop).whenComplete { _ in
                self.webSockets.removeAll { $0.device == device }
            }
        }
    }
    
    public func acknowledge(id: ObjectId, forDevice device: UserDeviceId) {
        eventLoop.execute {
            if let ack = self.acks[id], ack.0 == device {
                ack.1.succeed(())
            }
        }
    }
    
    public func hasWebsocket(forUser user: Reference<User>) -> EventLoopFuture<Bool> {
        eventLoop.submit {
            self.webSockets.contains { $0.device.user == user }
        }
    }
    
    public func websocket(forDevice device: UserDeviceId) -> EventLoopFuture<WebSocket?> {
        eventLoop.submit {
            self.webSockets.first(where: { $0.device == device })?.socket
        }
    }
}

public struct WebSocketClient {
    let device: UserDeviceId
    let socket: WebSocket
}
