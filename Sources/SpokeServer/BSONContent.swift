import Vapor
import BSON

extension BSONEncoder: ContentEncoder {
    public func encode<E>(_ encodable: E, to body: inout ByteBuffer, headers: inout HTTPHeaders) throws where E : Encodable {
        let document = try self.encode(encodable)
        body = document.makeByteBuffer()
        headers.add(name: .contentType, value: "application/bson")
    }
}

extension BSONDecoder: ContentDecoder {
    public func decode<D>(_ decodable: D.Type, from body: ByteBuffer, headers: HTTPHeaders) throws -> D where D : Decodable {
        try self.decode(decodable, from: Document(buffer: body))
    }
}

extension HTTPMediaType {
    static var bson: HTTPMediaType {
        HTTPMediaType(type: "application", subType: "bson")
    }
}
