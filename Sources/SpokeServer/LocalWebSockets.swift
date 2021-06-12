import Vapor

extension Application {
    var webSocketManager: WebSocketManager {
        if let manager = storage.get(WebSocketManagerKey.self) {
            return manager
        }
        
        let manager = WebSocketManager(eventLoop: eventLoopGroup.next())
        storage.set(WebSocketManagerKey.self, to: manager)
        return manager
    }
}

struct WebSocketManagerKey: StorageKey {
    typealias Value = WebSocketManager
}

final class WebSocketManager {
    let eventLoop: EventLoop
    init(eventLoop: EventLoop) {
        self.eventLoop = eventLoop
    }
    private var webSockets = [WebSocketClient]()
    
    public func addSocket(_ socket: WebSocket, forDevice device: UserDeviceId) {
        eventLoop.execute {
            if let index = self.webSockets.firstIndex(where: { $0.device == device }) {
                let client = self.webSockets.remove(at: index)
                _ = client.socket.close()
            }
            
            self.webSockets.append(WebSocketClient(device: device, socket: socket))
            
            socket.onClose.hop(to: self.eventLoop).whenComplete { _ in
                self.webSockets.removeAll { $0.device == device }
            }
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
