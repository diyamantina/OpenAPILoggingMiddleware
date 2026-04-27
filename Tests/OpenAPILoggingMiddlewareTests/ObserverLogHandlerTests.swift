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

    // MARK: - Concurrency stress

    /// High-fidelity reproduction of the production crash on g2xi's
    /// apiserverapp (2026-04-26 → 2026-04-27): under load, multiple Vapor
    /// request handlers and the OpenAPI runtime stamped metadata onto the
    /// same `ObserverLogHandler` instance simultaneously, the underlying
    /// `Dictionary` was not thread-safe (`nonisolated(unsafe)`), and the
    /// concurrent writes corrupted the heap → `SIGABRT` from libmalloc's
    /// `pointer being freed was not allocated` guard.
    ///
    /// Stack frame at crash: `ObserverLogHandler.subscript.setter` →
    /// `Dictionary.subscript.setter` → `_NativeDictionary._copyOrMoveAndResize`
    /// → `_swift_release_dealloc` → `malloc_report` → `__abort`.
    ///
    /// This test mirrors that exact pattern: one shared handler, dozens of
    /// tasks doing a tight loop of subscript writes, full-metadata
    /// replacements, and `log(...)` calls (which read metadata). Without the
    /// `OSAllocatedUnfairLock` fix, this test reliably reproduces the crash;
    /// with it, the test must complete cleanly and every event must reach
    /// the observer.
    @Test("Concurrent metadata mutations do not crash the heap")
    func concurrentMetadataIsRaceFree() async {
        let taskCount = 64        // matches Vapor's per-event-loop concurrency * a few cores
        let opsPerTask = 500      // ~32k total operations — enough to trip the race historically
        let totalLogCalls = taskCount * opsPerTask

        let collector = EventCollector()
        let handlerLock = NSLock() // guards collector.append, NOT the handler under test
        let handler = ObserverLogHandler(label: "stress") { event in
            handlerLock.lock(); defer { handlerLock.unlock() }
            collector.append(event)
        }

        await withTaskGroup(of: Void.self) { group in
            for taskID in 0 ..< taskCount {
                group.addTask {
                    for op in 0 ..< opsPerTask {
                        let key = "k\(taskID % 8)"          // 8 hot keys → forced contention
                        let value: Logger.Metadata.Value = .string("\(taskID)-\(op)")

                        // Mix of operations the production stack actually does:
                        switch op % 4 {
                        case 0:
                            // Vapor stamps a request-id via subscript.
                            handler[metadataKey: key] = value
                        case 1:
                            // OpenAPI runtime sometimes replaces the whole bag.
                            handler.metadata = ["task": .string("\(taskID)"), key: value]
                        case 2:
                            // Per-call log with its own metadata — this reads
                            // handler.metadata under the hood.
                            handler.log(
                                level: .debug,
                                message: "evt-\(taskID)-\(op)",
                                metadata: ["per-call": .string("\(op)")],
                                source: "stress",
                                file: #file,
                                function: #function,
                                line: #line
                            )
                        default:
                            // Read-after-write — exercises the get-side race too.
                            _ = handler[metadataKey: key]
                        }
                    }
                }
            }
        }

        // If we reach this line at all, no thread crashed the heap. The
        // exact event count depends on which `op % 4 == 2` branches ran;
        // every task contributes opsPerTask/4 (rounded) `log` calls.
        let expectedLogs = taskCount * (opsPerTask / 4)
        #expect(collector.events.count == expectedLogs,
                "Expected \(expectedLogs) log events from \(totalLogCalls) total operations")

        // Final state should be a valid (non-corrupted) dictionary that we
        // can read without crashing.
        _ = handler.metadata
        _ = handler[metadataKey: "k0"]
    }

    /// Lighter-weight version of the same scenario, focused only on the
    /// subscript setter path that appears at the top of the production
    /// crash stack. Kept separate so a regression is easy to localise.
    @Test("Concurrent subscript setters do not corrupt the metadata dictionary")
    func concurrentSubscriptSetters() async {
        let taskCount = 32
        let opsPerTask = 1000
        let handler = ObserverLogHandler(label: "subscript-stress") { _ in }

        await withTaskGroup(of: Void.self) { group in
            for taskID in 0 ..< taskCount {
                group.addTask {
                    for op in 0 ..< opsPerTask {
                        handler[metadataKey: "k\(op % 16)"] = .string("\(taskID)-\(op)")
                    }
                }
            }
        }

        // Reaching here without `SIGABRT` is the assertion. The dictionary's
        // final size is bounded by 16 (the number of distinct keys); any
        // value present is fine — we just need it to be readable.
        let final = handler.metadata
        #expect(final.count <= 16)
    }
}
