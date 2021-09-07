import Vapor
import Meow
import Metrics

let hooks = VaporAdminHooks(logLevel: .info)
let env = try Environment.detect()
let app = Application(env)
#if DEBUG
app.setupAdminHooks(hooks, atPath: "admin")
#endif.
try app.initializeMongoDB(connectionString: "mongodb://localhost/workspaces")

let p8 = "LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JR1RBZ0VBTUJNR0J5cUdTTTQ5QWdFR0NDcUdTTTQ5QXdFSEJIa3dkd0lCQVFRZ090aW9KWTdZS25CaXNndGsKeW9XTGwzeStZZ2RLZjJ4TGRPS2lRaWoraitlZ0NnWUlLb1pJemowREFRZWhSQU5DQUFUTmEvd0k5MkFSY0lqUwpjRkt3Mkg3Y0txOFFtWEh0cGlkK2lxMzU2QnJNaVh4cmJIcFplT2pnU1ZUUXYxS0FZZ1YwOGhhMnVSa0srNk51CmttY0loSHBJCi0tLS0tRU5EIFBSSVZBVEUgS0VZLS0tLS0="

app.apns.configuration = try .init(
    authenticationMethod: .jwt(
        key: .private(pem: Data(base64Encoded: p8)!),
        keyIdentifier: "PS3FZW2NSG",
        teamIdentifier: "6U5LP2533T"
    ),
    topic: "nl.orlandos.Workspaces",
    environment: .sandbox
)

(app.mongoDB.pool as! MongoCluster).next(for: .init(writable: true)).whenSuccess { connection in
//    connection.isMetricsEnabled = true
}

//final class PrintLabelHandler: CounterHandler, RecorderHandler, TimerHandler {
//    let label: String
//    var total: Int64 = 0
//
//    init(label: String) {
//        self.label = label
//    }
//
//    func increment(by: Int64) {
//        total += by
//        print(label, "incremented by", by, "totalling", total)
//    }
//
//    func reset() {}
//
//    func record(_ value: Int64) {
//        print(label, "recorded", value)
//    }
//
//    func record(_ value: Double) {
//        print(label, "recorded", value)
//    }
//
//    func recordNanoseconds(_ duration: Int64) {
//        print(label, "recorded duration", Double(duration) / 1_000_000_000, "s")
//    }
//}
//
//struct PrintMetrics: MetricsFactory {
//    func makeTimer(label: String, dimensions: [(String, String)]) -> TimerHandler {
//        PrintLabelHandler(label: label)
//    }
//
//    func makeCounter(label: String, dimensions: [(String, String)]) -> CounterHandler {
//        PrintLabelHandler(label: label)
//    }
//
//    func makeRecorder(label: String, dimensions: [(String, String)], aggregate: Bool) -> RecorderHandler {
//        PrintLabelHandler(label: label)
//    }
//
//    func destroyTimer(_ handler: TimerHandler) { }
//    func destroyCounter(_ handler: CounterHandler) { }
//    func destroyRecorder(_ handler: RecorderHandler) { }
//}
//
//MetricsSystem.bootstrap(PrintMetrics())

ContentConfiguration.global.use(encoder: BSONEncoder(), for: .bson)
ContentConfiguration.global.use(decoder: BSONDecoder(), for: .bson)
registerRoutes(to: app)

app.http.server.configuration.address = .hostname("0.0.0.0", port: 8080)
try app.run()
