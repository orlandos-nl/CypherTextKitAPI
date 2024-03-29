import Vapor
import JWT
import Meow
import Metrics
import APNS

let env = try Environment.detect()
let app = Application(env)
try app.initializeMongoDB(connectionString: Environment.get("MONGODB") ?? "mongodb://localhost/workspaces")

let p8 = Environment.get("APNS_P8") ?? "LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0tCk1JR1RBZ0VBTUJNR0J5cUdTTTQ5QWdFR0NDcUdTTTQ5QXdFSEJIa3dkd0lCQVFRZ090aW9KWTdZS25CaXNndGsKeW9XTGwzeStZZ2RLZjJ4TGRPS2lRaWoraitlZ0NnWUlLb1pJemowREFRZWhSQU5DQUFUTmEvd0k5MkFSY0lqUwpjRkt3Mkg3Y0txOFFtWEh0cGlkK2lxMzU2QnJNaVh4cmJIcFplT2pnU1ZUUXYxS0FZZ1YwOGhhMnVSa0srNk51CmttY0loSHBJCi0tLS0tRU5EIFBSSVZBVEUgS0VZLS0tLS0="

app.routes.defaultMaxBodySize = 4_500_000
app.apns.configuration = try .init(
    authenticationMethod: .jwt(
        key: .private(pem: Data(base64Encoded: p8)!),
        keyIdentifier: JWKIdentifier(string: Environment.get("APNS_KEY_ID") ?? "PS3FZW2NSG"),
        teamIdentifier: Environment.get("APNS_TEAM") ?? "6U5LP2533T"
    ),
    topic: Environment.get("APNS_TOPIC") ?? "nl.orlandos.Workspaces",
    environment: .production
)

ContentConfiguration.global.use(encoder: BSONEncoder(), for: .bson)
ContentConfiguration.global.use(decoder: BSONDecoder(), for: .bson)
registerRoutes(to: app)

try app.run()
