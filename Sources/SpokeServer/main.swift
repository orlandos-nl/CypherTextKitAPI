import Vapor
import Meow
import Metrics

let app = Application()
try app.initializeMongoDB(connectionString: "mongodb://localhost/workspaces")

(app.mongoDB.pool as! MongoCluster).next(for: .init(writable: true)).whenSuccess { connection in
    connection.isMetricsEnabled = true
}

final class PrintLabelHandler: CounterHandler, RecorderHandler, TimerHandler {
    let label: String
    var total: Int64 = 0
    
    init(label: String) {
        self.label = label
    }
    
    func increment(by: Int64) {
        total += by
        print(label, "incremented by", by, "totalling", total)
    }
    
    func reset() {}
    
    func record(_ value: Int64) {
        print(label, "recorded", value)
    }
    
    func record(_ value: Double) {
        print(label, "recorded", value)
    }
    
    func recordNanoseconds(_ duration: Int64) {
        print(label, "recorded duration", Double(duration) / 1_000_000_000, "s")
    }
}

struct PrintMetrics: MetricsFactory {
    func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
        PrintLabelHandler(label: label)
    }
    
    func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
        PrintLabelHandler(label: label)
    }
    
    func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
        PrintLabelHandler(label: label)
    }
    
    func destroyTimer(_ handler: TimerHandler) { }
    func destroyCounter(_ handler: CounterHandler) { }
    func destroyRecorder(_ handler: RecorderHandler) { }
}

MetricsSystem.bootstrap(PrintMetrics())

ContentConfiguration.global.use(encoder: BSONEncoder(), for: .bson)
ContentConfiguration.global.use(decoder: BSONDecoder(), for: .bson)
registerRoutes(to: app)

app.http.server.configuration.address = .hostname("0.0.0.0", port: 8080)
try app.run()
