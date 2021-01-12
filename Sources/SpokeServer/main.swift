import Vapor
import Meow

let app = Application()
try app.initializeMongoDB(connectionString: "mongodb://localhost/my_database")

try app.run()
