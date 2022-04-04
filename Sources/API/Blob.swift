import Foundation
import Meow
import Vapor

public struct Blob: Model, Content {
    public let _id: String
    public let creator: Reference<User>
    public var document: Document
    
    init(creator: Reference<User>, document: Document) {
        self._id = UUID().uuidString
        self.creator = creator
        self.document = document
    }
}