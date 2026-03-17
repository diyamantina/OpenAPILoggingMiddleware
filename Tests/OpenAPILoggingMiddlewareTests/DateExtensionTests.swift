import Testing
import Foundation
@testable import OpenAPILoggingMiddleware

@Suite("Date Extensions")
struct DateExtensionTests {

    @Test("loggableCurrentDate returns non-empty string")
    func loggableDateNotEmpty() {
        let result = Date.loggableCurrentDate()
        #expect(!result.isEmpty)
    }

    @Test("loggableCurrentDate contains expected format separators")
    func loggableDateFormat() {
        let result = Date.loggableCurrentDate()
        #expect(result.contains("."))
        #expect(result.contains(":"))
    }
}
