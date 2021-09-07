import Vapor
import WebSocketKit

public final class VaporAdminHooks {
    public init(logLevel: Logger.Level) {
        self.eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: 1).next()
        let logger = VaporAdminLogHandler(logLevel: logLevel, onLog: sendLog)
        LoggingSystem.bootstrap { _ in
            logger
        }
    }
    
    let eventLoop: EventLoop
    var websockets = [WebSocket]()
    
    public func connectClient(_ client: WebSocket) {
        eventLoop.execute {
            self.websockets.append(client)
        }
        
        client.onClose.hop(to: eventLoop).whenComplete { _ in
            self.websockets.removeAll { $0 === client }
        }
    }
    
    public func sendLog(_ log: JSONObject) {
        sendEvent(log, ofType: .log)
    }
    
    func onWebSocket(request: Request, webSocket: WebSocket) {
        connectClient(webSocket)
    }
    
    private func sendEvent(_ object: JSONObject, ofType type: VaporAdminEventType) {
        let event: JSONObject = [
            "type": type.rawValue,
            "event": object
        ]
        let string = event.string!
        
        for websocket in websockets {
            websocket.send(string, promise: nil)
        }
    }
}

struct AdminHookKey: StorageKey {
    typealias Value = VaporAdminHooks
}

extension Application {
    public func setupAdminHooks(_ hooks: VaporAdminHooks, atPath path: PathComponent...) {
        self.storage.set(AdminHookKey.self, to: hooks)
        webSocket(path, onUpgrade: hooks.onWebSocket)
    }
}

import Logging
import Foundation
import IkigaJSON

public struct VaporAdminLogHandler: LogHandler {
    private let onLog: (JSONObject) -> ()
    
    init(
        logLevel: Logger.Level,
        onLog: @escaping (JSONObject) -> ()
    ) {
        self.onLog = onLog
        self.logLevel = logLevel
    }
    
    public var metadata = Logger.Metadata()
    
    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            return self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }
    
    public var logLevel: Logger.Level
    
    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        onLog([
            "id": UUID().uuidString,
            "level": level.rawValue,
            "message": message.description,
            "metadata": metadata?.jsonObject ?? NSNull(),
            "source": source,
            "file": file,
            "function": function,
            "line": Int(line),
        ])
    }
}

extension Logger.Metadata {
    var jsonObject: JSONObject {
        var object = JSONObject()
        
        for (key, value) in self {
            object[key] = value.json
        }
        
        return object
    }
}

extension Logger.MetadataValue {
    var json: JSONValue {
        switch self {
        case .array(let values):
            var array = JSONArray()
            
            for value in values {
                array.append(value.json)
            }
            
            return array
        case .dictionary(let object):
            return object.jsonObject
        case .string(let value):
            return value
        case .stringConvertible(let value):
            return value.description
        }
    }
}

public enum VaporAdminEventType: String, Codable {
    case log
}
