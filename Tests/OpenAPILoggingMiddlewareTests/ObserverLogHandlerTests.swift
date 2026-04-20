import Testing
import Foundation
import Logging
@testable import OpenAPILoggingMiddleware

@Suite("ObserverLogHandler")
struct ObserverLogHandlerTests {

    final class EventCollector: @unchecked Sendable {
        var events: [ObserverLogHandler.Event] = []
        func append(_ event: ObserverLogHandler.Event) { events.append(event) }
    }

    @Test("Observer closure receives every logged event")
    func observerReceivesEvents() {
        let collector = EventCollector()
        var handler = ObserverLogHandler(label: "test") { event in
            collector.append(event)
        }
        handler.log(
            level: .info,
            message: "hello",
            metadata: ["k": "v"],
            source: "test",
            file: "f.swift",
            function: "fn()",
            line: 42
        )

        #expect(collector.events.count == 1)
        let event = collector.events[0]
        #expect(event.level == .info)
        #expect(event.label == "test")
        #expect(event.message == "hello")
        #expect(event.metadata["k"] == "v")
        #expect(event.line == 42)
    }

    @Test("Handler-scope metadata merges with per-call metadata")
    func metadataMerging() {
        let collector = EventCollector()
        var handler = ObserverLogHandler(label: "test") { event in
            collector.append(event)
        }
        handler[metadataKey: "scope"] = .string("handler")
        handler.log(
            level: .debug,
            message: "x",
            metadata: ["per-call": "true", "scope": "override"],
            source: "s", file: "f", function: "fn", line: 1
        )

        let event = collector.events[0]
        #expect(event.metadata["scope"] == "override")
        #expect(event.metadata["per-call"] == "true")
    }

    @Test("Log level get/set round-trips")
    func logLevelRoundTrip() {
        var handler = ObserverLogHandler(label: "test") { _ in }
        #expect(handler.logLevel == .info)
        handler.logLevel = .warning
        #expect(handler.logLevel == .warning)
    }

    @Test("Works inside a MultiplexLogHandler alongside a stream handler")
    func pluggableIntoMultiplex() {
        let collector = EventCollector()
        let capture = CapturedOutputStream()
        let observer = ObserverLogHandler(label: "test") { collector.append($0) }
        let stream = PrefixedStreamLogHandler(label: "test", stream: capture, logPrefix: "[PX]")

        let logger = Logger(label: "test") { _ in
            MultiplexLogHandler([stream, observer])
        }
        logger.info("hi", metadata: ["a": "1"])

        #expect(collector.events.count == 1)
        #expect(collector.events[0].metadata["a"] == "1")
        #expect(capture.captured.contains("[PX]"))
    }

    // Shared stream capture helper (mirrors PrefixedStreamLogHandlerTests)
    final class CapturedOutputStream: TextOutputStream, @unchecked Sendable {
        var captured = ""
        func write(_ string: String) {
            captured += string
        }
    }
}
