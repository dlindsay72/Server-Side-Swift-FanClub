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
import Stencil

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
let namespace = Namespace()

namespace.registerFilter("format_date") { (value: Any?) in
  if let value = value as? String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"

    if let date = formatter.date(from: value) {
      formatter.dateStyle = .long
      formatter.timeStyle = .medium
      return formatter.string(from: date)
    }
  }
  return value
}

router.setDefault(templateEngine: StencilTemplateEngine(namespace: namespace))
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

router.get("/forum/:forumid") {
  request, response, next in

  guard let forumID = request.parameters["forumid"] else {
    send(error: "Missing forum ID", code: .badRequest, to: response)
    return
  }

  database.retrieve(forumID) { forum, error in
    if let error = error {
      send(error: error.localizedDescription, code: .notFound, to: response)
    } else if let forum = forum {
      database.queryByView("forum_posts", ofDesign: "forum", usingParameters: [.keys([forumID as Database.KeyType]), .descending(true)]) { messages, error in
        defer { next() }

        if let error = error {

          send(error: error.localizedDescription, code: .internalServerError, to: response)
        } else if let messages = messages {

          var pageContext = context(for: request)
          pageContext["forum_id"] = forum["_id"].stringValue
          pageContext["forum_name"] = forum["name"].stringValue
          pageContext["messages"] = messages["rows"].arrayObject
          _ = try? response.render("forum", context: pageContext)
        }
      }
    }
  }
}

router.get("/forum/:forumid/:messageid") {
  request, response, next in

  guard let forumID = request.parameters["forumid"], let messageID = request.parameters["messageid"] else {
    try response.status(.badRequest).end()
    return
  }

  database.retrieve(forumID) { forum, error in
    if let error = error {
      send(error: error.localizedDescription, code: .notFound, to: response)
    } else if let forum = forum {
      database.retrieve(messageID) { message, error in
        if let error = error {
          send(error: error.localizedDescription, code: .notFound, to: response)
        } else if let message = message {
          // success!
          database.queryByView("forum_replies", ofDesign: "forum", usingParameters: [.keys([messageID as Database.KeyType])]) { replies, error in
            defer { next() }

            if let error = error {
              send(error: error.localizedDescription, code: .internalServerError, to: response)
            } else if let replies = replies {
              var pageContext = context(for: request)
              pageContext["forum_id"] = forum["_id"].stringValue
              pageContext["forum_name"] = forum["name"].stringValue
              pageContext["message"] = message.dictionaryObject!
              pageContext["replies"] = replies["rows"].arrayObject

              _ = try? response.render("message", context: pageContext)
            }
          }
        }
      }
    }
  }
}


Kitura.addHTTPServer(onPort: 8090, with: router)










Kitura.run()
