import CouchDB
import Cryptor
import Foundation
import HeliumLogger
import Kitura
import KituraNet
import KituraSession
import KituraStencil
import LoggerAPI
import SwiftyJSON

func send(error: String, code: HTTPStatusCode, to response: RouterResponse) {
  _ = try? response.status(code).send(error).end()
}

func context(for request: RouterRequest) -> [String: Any] {
  var result = [String: String]()
  result["username"] = "testing"
  return result
}

HeliumLogger.use()

let connectionProperties = ConnectionProperties(host: "localhost", port: 5984, secured: false)
let client = CouchDBClient(connectionProperties: connectionProperties)
let database = client.database("forum")

let router = Router()
router.setDefault(templateEngine: StencilTemplateEngine())
router.post("/", middleware: BodyParser())
router.all("/static", middleware: StaticFileServer())

router.get("/") {
  request, response, next in

  database.queryByView("forums", ofDesign: "forum", usingParameters: []) { forums, error in
    defer { next() }

    if let error = error {
      //something went wrong
      send(error: error.localizedDescription, code: .internalServerError, to: response)
    } else if let forums = forums {
      //success!
      var forumContext = context(for: request)
      forumContext["forums"] = forums["rows"].arrayObject

      _ = try? response.render("home", context: forumContext)
    }
  }
}

Kitura.addHTTPServer(onPort: 8090, with: router)
Kitura.run()
