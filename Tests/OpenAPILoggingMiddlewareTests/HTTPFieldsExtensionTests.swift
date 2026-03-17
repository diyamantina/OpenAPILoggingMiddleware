import Testing
import Foundation
import HTTPTypes
@testable import OpenAPILoggingMiddleware

@Suite("HTTPFields Extensions")
struct HTTPFieldsExtensionTests {

    @Test("toArrayString returns comma-separated header pairs")
    func toArrayString() {
        var fields = HTTPFields()
        fields.append(HTTPField(name: .contentType, value: "application/json"))
        fields.append(HTTPField(name: .accept, value: "text/html"))
        let result = fields.toArrayString()
        #expect(result.contains("Content-Type=application/json"))
        #expect(result.contains("Accept=text/html"))
    }

    @Test("toArrayString returns empty for no headers")
    func toArrayStringEmpty() {
        let fields = HTTPFields()
        let result = fields.toArrayString()
        #expect(result.isEmpty)
    }

    @Test("toDictionary converts fields to dictionary")
    func toDictionary() {
        var fields = HTTPFields()
        fields.append(HTTPField(name: .contentType, value: "application/json"))
        let dict = fields.toDictionary()
        #expect(dict["Content-Type"] == "application/json")
    }
}
