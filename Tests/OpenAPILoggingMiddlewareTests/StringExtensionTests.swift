import Testing
import Foundation
@testable import OpenAPILoggingMiddleware

@Suite("String Extensions")
struct StringExtensionTests {

    @Test("meAsJSONStringToDictionary parses valid JSON")
    func parseValidJSON() {
        let json = #"{"key": "value", "num": 42}"#
        let result = json.meAsJSONStringToDictionary()
        #expect(result != nil)
        #expect(result?["key"] as? String == "value")
        #expect(result?["num"] as? Int == 42)
    }

    @Test("meAsJSONStringToDictionary returns nil for invalid JSON")
    func parseInvalidJSON() {
        let result = "not json".meAsJSONStringToDictionary()
        #expect(result == nil)
    }

    @Test("meAsJSONStringToDictionary returns nil for empty string")
    func parseEmptyString() {
        let result = "".meAsJSONStringToDictionary()
        #expect(result == nil)
    }

    @Test("convertHeaderStringToDictionary parses header string")
    func convertHeaders() {
        let headerString = #"["Content-Type=application/json", "Accept=text/html"]"#
        let result = headerString.convertHeaderStringToDictionary()
        #expect(result["Content-Type"] as? String == "application/json")
        #expect(result["Accept"] as? String == "text/html")
    }

    @Test("convertDictionaryToJSONString produces valid JSON")
    func dictionaryToJSON() {
        let dict = ["key": "value"]
        let result = String.convertDictionaryToJSONString(dict)
        #expect(result != nil)
        #expect(result!.contains("key"))
        #expect(result!.contains("value"))
    }
}
