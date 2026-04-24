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

    // MARK: - Regression: duplicate header names

    /// Regression for the crash that aborted every host process logging a
    /// request with more than one `Cookie` header. HTTP allows repeated
    /// header names (see RFC 9110 §5.3); `Dictionary(uniqueKeysWithValues:)`
    /// traps on duplicate keys, so the old implementation turned a legal
    /// request into a fatal error at the middleware layer. Real trigger:
    /// a client sending two separate `Cookie:` lines instead of one merged
    /// line, or a browser after a `Set-Cookie` collision.
    @Test("toDictionary does not trap on duplicate Cookie headers (regression)")
    func toDictionaryWithDuplicateCookies() {
        var fields = HTTPFields()
        fields.append(HTTPField(name: .cookie, value: "session=abc"))
        fields.append(HTTPField(name: .cookie, value: "pref=dark"))

        // Must not trap. Pre-fix: `Dictionary(uniqueKeysWithValues:)`
        // triggered `Fatal error: Duplicate values for key: 'Cookie'`.
        let dict = fields.toDictionary()

        // Last value wins — documented behavior of the new implementation.
        #expect(dict["Cookie"] == "pref=dark")
    }

    /// Same regression, expressed through the JSON serializer — the path
    /// the `LoggingMiddleware` actually takes when building log metadata.
    @Test("toJSONString does not trap on duplicate Cookie headers (regression)")
    func toJSONStringWithDuplicateCookies() {
        var fields = HTTPFields()
        fields.append(HTTPField(name: .cookie, value: "session=abc"))
        fields.append(HTTPField(name: .cookie, value: "pref=dark"))

        let json = fields.toJSONString()
        #expect(json != nil)
        #expect(json?.contains("Cookie") == true)
    }

    /// Covers the other common duplicate-allowed header family.
    @Test("toDictionary does not trap on duplicate Set-Cookie headers")
    func toDictionaryWithDuplicateSetCookies() {
        var fields = HTTPFields()
        fields.append(HTTPField(name: .setCookie, value: "a=1; Path=/"))
        fields.append(HTTPField(name: .setCookie, value: "b=2; Path=/"))

        let dict = fields.toDictionary()
        #expect(dict["Set-Cookie"] == "b=2; Path=/")
    }
}
