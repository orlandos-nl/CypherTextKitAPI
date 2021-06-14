import Vapor
import Meow
import Metrics

let app = Application()
try app.initializeMongoDB(connectionString: "mongodb://localhost/workspaces")

let cer = "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"
let pem = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUdNRENDQlJpZ0F3SUJBZ0lJVTNHbjJFL3MvRVV3RFFZSktvWklodmNOQVFFTEJRQXdnWll4Q3pBSkJnTlYKQkFZVEFsVlRNUk13RVFZRFZRUUtEQXBCY0hCc1pTQkpibU11TVN3d0tnWURWUVFMRENOQmNIQnNaU0JYYjNKcwpaSGRwWkdVZ1JHVjJaV3h2Y0dWeUlGSmxiR0YwYVc5dWN6RkVNRUlHQTFVRUF3dzdRWEJ3YkdVZ1YyOXliR1IzCmFXUmxJRVJsZG1Wc2IzQmxjaUJTWld4aGRHbHZibk1nUTJWeWRHbG1hV05oZEdsdmJpQkJkWFJvYjNKcGRIa3cKSGhjTk1qRXdOakUwTVRJME16RTNXaGNOTWpJd056RTBNVEkwTXpFMldqQ0JtekVtTUNRR0NnbVNKb21UOGl4awpBUUVNRm01c0xtOXliR0Z1Wkc5ekxsZHZjbXR6Y0dGalpYTXhOREF5QmdOVkJBTU1LMEZ3Y0d4bElGQjFjMmdnClUyVnlkbWxqWlhNNklHNXNMbTl5YkdGdVpHOXpMbGR2Y210emNHRmpaWE14RXpBUkJnTlZCQXNNQ2paVk5VeFEKTWpVek0xUXhHVEFYQmdOVkJBb01FRXB2WVc1dWFYTWdUM0pzWVc1a2IzTXhDekFKQmdOVkJBWVRBazVNTUlJQgpJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBdjNTczhWMkUydE54bEtqeUNzQktDYXEvClBXdSt0YlpGNTlkZHc1cVFKWVNBYWdKdFYyU3JQOWhWbWdYUTBwSkRKbmtPbzIzNi82dXlNSGI4Mi9tWjZ3YUoKTlkwckhEMk1zVzBTcnlYMXFKUG8xa3NRMXJRaHgwY3lEME1QRTJNMEdpd0RYdWdMYThiWWJzTTA4N3laMERxUAp2bEtZUVVybTRNOEJMNS8rN3RNMHVlNVVraGZmd2Y0Tk5KMHBaT2NHYTZpM2YrbWoyRmJmWHh0amkwa3I2bkRFCkd0KzI3NExPcFBsdUdtbWlzaXUzNThURXh0b0JZZ3lWUkQwZGNQV3lsTjl3blYzaXkrNThKL3dRWC80TDRHL0IKMTYrZ2QzWWlxTmM3c2lYUEJXT0x1UFNMelZOYUJsSlJ1RzlVSi9mbi8wWHltc0IyMm5LQkRtbFhjYWdJZndJRApBUUFCbzRJQ2VUQ0NBblV3REFZRFZSMFRBUUgvQkFJd0FEQWZCZ05WSFNNRUdEQVdnQlNJSnhjSnFiWVlZSXZzCjY3cjJSMW5GVWxTanR6Q0NBUndHQTFVZElBU0NBUk13Z2dFUE1JSUJDd1lKS29aSWh2ZGpaQVVCTUlIOU1JSEQKQmdnckJnRUZCUWNDQWpDQnRneUJzMUpsYkdsaGJtTmxJRzl1SUhSb2FYTWdZMlZ5ZEdsbWFXTmhkR1VnWW5rZwpZVzU1SUhCaGNuUjVJR0Z6YzNWdFpYTWdZV05qWlhCMFlXNWpaU0J2WmlCMGFHVWdkR2hsYmlCaGNIQnNhV05oCllteGxJSE4wWVc1a1lYSmtJSFJsY20xeklHRnVaQ0JqYjI1a2FYUnBiMjV6SUc5bUlIVnpaU3dnWTJWeWRHbG0KYVdOaGRHVWdjRzlzYVdONUlHRnVaQ0JqWlhKMGFXWnBZMkYwYVc5dUlIQnlZV04wYVdObElITjBZWFJsYldWdQpkSE11TURVR0NDc0dBUVVGQndJQkZpbG9kSFJ3T2k4dmQzZDNMbUZ3Y0d4bExtTnZiUzlqWlhKMGFXWnBZMkYwClpXRjFkR2h2Y21sMGVUQVRCZ05WSFNVRUREQUtCZ2dyQmdFRkJRY0RBakF3QmdOVkhSOEVLVEFuTUNXZ0k2QWgKaGg5b2RIUndPaTh2WTNKc0xtRndjR3hsTG1OdmJTOTNkMlJ5WTJFdVkzSnNNQjBHQTFVZERnUVdCQlFuQnpGVApiNlJoMHQ2b3hTYTZaWmE0alZoZHZEQU9CZ05WSFE4QkFmOEVCQU1DQjRBd0VBWUtLb1pJaHZkalpBWURBUVFDCkJRQXdFQVlLS29aSWh2ZGpaQVlEQWdRQ0JRQXdnWWtHQ2lxR1NJYjNZMlFHQXdZRWV6QjVEQlp1YkM1dmNteGgKYm1SdmN5NVhiM0pyYzNCaFkyVnpNQVVNQTJGd2NBd2JibXd1YjNKc1lXNWtiM011VjI5eWEzTndZV05sY3k1MgpiMmx3TUFZTUJIWnZhWEFNSTI1c0xtOXliR0Z1Wkc5ekxsZHZjbXR6Y0dGalpYTXVZMjl0Y0d4cFkyRjBhVzl1Ck1BNE1ER052YlhCc2FXTmhkR2x2YmpBTkJna3Foa2lHOXcwQkFRc0ZBQU9DQVFFQVJOOVA4VkhGWGYvQktuY2QKSWExWkppZ0VSc1dlZjFsOGVTRzRTU3R5OWhFUGlWZlNMYnJHZjZiMGo0MXU5enVGTVVzN0NrWk9TWmtyajNvbApzNzlZR0hoYS9yYzdUNnZhdzQzVUdET3Q0T2I3MkR0d29iN2R5ZmVkTnR2U1RhUVhKd0o4clpHZXJEK0VrZjJoCmxWclkydmJNSjhUbFhwbytMYTJhVkFmQVNEYlp0T0ZHTUFlcm9jRElNTmVIOWsxaXpYYnBvNUJDR0J3UXU4WjYKc2N4ZDZKSWg1SFhHeWVCOFpZc3M0Z051aElHVVIyYUQ5MmduN1orS2RBSlI5UTM0ZG92aWozTklXY05FR0t5cQpySCs0V2V2cmVUUHkrdmcyenpDTFBsU3BqSFNHS2xjaFJpc0ZtVmJCeXFxMW5CR0pDTlJXSWZVdGdDWktUYWszClMyOW9GUT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K"
app.apns.configuration = try .init(
    authenticationMethod: .tls(
        keyBytes: Array(cer.utf8),
        certificateBytes: Array(pem.utf8),
        pemPassword: nil
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
