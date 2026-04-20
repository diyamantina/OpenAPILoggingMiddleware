import Testing
import Foundation
import Logging
@testable import OpenAPILoggingMiddleware

@Suite("PrefixedStreamLogHandler")
struct PrefixedStreamLogHandlerTests {

    // MARK: - StandardOutputStream

    @Test("StandardOutputStream conforms to TextOutputStream")
    func standardOutputStreamConforms() {
        let stream = StandardOutputStream()
        var mutableStream: TextOutputStream = stream
        mutableStream.write("test")
    }

    // MARK: - Custom Stream Capture

    final class CapturedOutputStream: TextOutputStream, @unchecked Sendable {
        var captured = ""
        func write(_ string: String) {
            captured += string
        }
    }

    @Test("PrefixedStreamLogHandler writes metadata to stream")
    func streamLogHandlerWritesMetadata() {
        let capture = CapturedOutputStream()
        var handler = PrefixedStreamLogHandler(label: "test", stream: capture, logPrefix: "[PREFIX]")
        handler.log(
            level: .info,
            message: "test message",
            metadata: ["key": "value"],
            source: "test",
            file: #file,
            function: #function,
            line: #line
        )
        #expect(capture.captured.contains("`key`"))
        #expect(capture.captured.contains("`value`"))
        #expect(capture.captured.contains("[PREFIX]"))
    }

    @Test("PrefixedStreamLogHandler skips logging when metadata is nil")
    func streamLogHandlerSkipsNilMetadata() {
        let capture = CapturedOutputStream()
        var handler = PrefixedStreamLogHandler(label: "test", stream: capture)
        handler.log(
            level: .info,
            message: "test",
            metadata: nil,
            source: "test",
            file: #file,
            function: #function,
            line: #line
        )
        #expect(capture.captured.isEmpty)
    }

    @Test("PrefixedStreamLogHandler log level get/set")
    func streamLogHandlerLogLevel() {
        var handler = PrefixedStreamLogHandler(label: "test")
        handler.logLevel = .debug
        #expect(handler.logLevel == .debug)
        handler.logLevel = .error
        #expect(handler.logLevel == .error)
    }

    @Test("PrefixedStreamLogHandler metadata get/set")
    func streamLogHandlerMetadata() {
        var handler = PrefixedStreamLogHandler(label: "test")
        handler[metadataKey: "foo"] = "bar"
        #expect(handler[metadataKey: "foo"] == "bar")
        #expect(handler[metadataKey: "missing"] == nil)
    }
}
