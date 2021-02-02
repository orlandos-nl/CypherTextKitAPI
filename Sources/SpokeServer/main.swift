import Vapor
import Meow

let app = Application()
try app.initializeMongoDB(connectionString: "mongodb+srv://joannis:rpdcgvbRoeXO0dz2@ok0-xkvc1.mongodb.net/spoke?retryWrites=true&w=majority")

ContentConfiguration.global.use(encoder: BSONEncoder(), for: .bson)
ContentConfiguration.global.use(decoder: BSONDecoder(), for: .bson)
registerRoutes(to: app)

try app.run()
