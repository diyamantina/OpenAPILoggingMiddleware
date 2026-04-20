import Testing
import Foundation
import Logging
@testable import OpenAPILoggingMiddleware

@Suite("Public API surface (v1.2.0)")
struct PublicApiTests {

    @Test("defaultLogger is callable from outside the module")
    func defaultLoggerPublic() {
        let logger = LoggingMiddleware.defaultLogger(logPrefix: "[T]", jsonLogFileName: "_PublicApiTest.json")
        // Just ensure it builds and a log call doesn't crash.
        logger.info("smoke", metadata: ["k": "v"])
    }

    @Test("Handlers are public and usable together via Apple MultiplexLogHandler")
    func publicHandlersUsableInApplesMultiplex() {
        let logger = Logger(label: "t") { label in
            MultiplexLogHandler([
                PrefixedStreamLogHandler(label: label, logPrefix: "[S]"),
                ObserverLogHandler(label: label) { _ in },
            ])
        }
        logger.info("hi")
    }
}
