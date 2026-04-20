import Testing
import Foundation
import HTTPTypes
import Logging
import OpenAPIRuntime
@testable import OpenAPILoggingMiddleware

/// End-to-end tests for the intended real-world use case: a custom Logger built
/// via Apple's `MultiplexLogHandler`, wired into `LoggingMiddleware`, capturing
/// OpenAPI operation logs into a user-supplied sink.
@Suite("Integration: LoggingMiddleware + ObserverLogHandler")
struct IntegrationTests {

    final class EventSink: @unchecked Sendable {
        var events: [ObserverLogHandler.Event] = []
        func append(_ event: ObserverLogHandler.Event) { events.append(event) }
    }

    private func makeLogger(observer: ObserverLogHandler) -> Logger {
        var logger = Logger(label: "integration") { _ in
            MultiplexLogHandler([observer])
        }
        // `LoggingMiddleware` logs at `.debug`, so we need to lower the level
        // or swift-log filters events before the handler sees them.
        logger.logLevel = .debug
        return logger
    }

    @Test("Observer receives Request + Response events from ServerMiddleware.intercept")
    func serverInterceptFeedsObserver() async throws {
        let sink = EventSink()
        let observer = ObserverLogHandler(label: "t") { sink.append($0) }
        let logger = makeLogger(observer: observer)

        let middleware = LoggingMiddleware(
            logger: logger,
            bodyLoggingConfiguration: .never,
            appName: "IntegrationTest",
            logPrefix: "[I]"
        )

        let request = HTTPRequest(method: .post, scheme: "https", authority: "x.test", path: "/v1/thing")
        let metadata = ServerRequestMetadata(pathParameters: [:])

        let (response, _) = try await middleware.intercept(
            request,
            body: nil,
            metadata: metadata,
            operationID: "doThing",
            next: { _, _, _ in
                (HTTPResponse(status: .ok), nil)
            }
        )

        #expect(response.status == .ok)
        // ServerMiddleware logs: 1 Request + 1 Response = 2 events.
        #expect(sink.events.count == 2)

        let requestEvent = sink.events.first { $0.message == "Request" }
        #expect(requestEvent != nil)
        #expect(requestEvent?.metadata["operationID"] == "doThing")
        #expect(requestEvent?.metadata["path"] == "/v1/thing")
        #expect(requestEvent?.metadata["method"] == "POST")

        let responseEvent = sink.events.first { $0.message == "Response" }
        #expect(responseEvent != nil)
        #expect(responseEvent?.metadata["statusCode"] == "200")
    }

    @Test("Error path: middleware emits an error event and rethrows")
    func serverInterceptErrorEvent() async {
        let sink = EventSink()
        let observer = ObserverLogHandler(label: "t") { sink.append($0) }
        let middleware = LoggingMiddleware(
            logger: makeLogger(observer: observer),
            bodyLoggingConfiguration: .never
        )
        struct Boom: Error {}

        let request = HTTPRequest(method: .get, scheme: "https", authority: "x.test", path: "/fail")
        let metadata = ServerRequestMetadata(pathParameters: [:])

        var thrown: Error?
        do {
            _ = try await middleware.intercept(
                request, body: nil, metadata: metadata, operationID: "fail",
                next: { _, _, _ in throw Boom() }
            )
        } catch {
            thrown = error
        }

        #expect(thrown is Boom)
        #expect(sink.events.contains { $0.message == "Request error" })
    }

    @Test("Multiplex across two observers: both receive every event")
    func multiplexTwoObservers() {
        let a = EventSink()
        let b = EventSink()
        let logger = Logger(label: "mx") { label in
            MultiplexLogHandler([
                ObserverLogHandler(label: label) { a.append($0) },
                ObserverLogHandler(label: label) { b.append($0) },
            ])
        }
        logger.info("fanned out")
        #expect(a.events.count == 1)
        #expect(b.events.count == 1)
    }

    @Test("Logger.logLevel filters below-threshold events across multiplex")
    func logLevelFilteringAcrossMultiplex() {
        let sink = EventSink()
        var logger = Logger(label: "lvl") { label in
            MultiplexLogHandler([
                ObserverLogHandler(label: label) { sink.append($0) }
            ])
        }
        logger.logLevel = .warning
        logger.debug("below threshold")
        logger.info("below threshold")
        logger.warning("at threshold")
        logger.error("above threshold")

        // Apple's MultiplexLogHandler respects the level set on the Logger.
        #expect(sink.events.count == 2)
        #expect(sink.events.map(\.level) == [.warning, .error])
    }

    @Test("Per-event log levels default to debug/debug/error and are configurable")
    func perEventLogLevels() async throws {
        // Default defaults: request=.debug, response=.debug, error=.error
        let defaultMw = LoggingMiddleware()
        #expect(await defaultMw.requestLogLevel == .debug)
        #expect(await defaultMw.responseLogLevel == .debug)
        #expect(await defaultMw.errorLogLevel == .error)

        // Custom override: verify the configured level ends up on the event.
        let sink = EventSink()
        let observer = ObserverLogHandler(label: "t") { sink.append($0) }
        var logger = Logger(label: "t") { _ in MultiplexLogHandler([observer]) }
        logger.logLevel = .trace

        let mw = LoggingMiddleware(
            logger: logger,
            bodyLoggingConfiguration: .never,
            requestLogLevel: .info,
            responseLogLevel: .notice,
            errorLogLevel: .critical
        )

        struct Boom: Error {}
        _ = try? await mw.intercept(
            HTTPRequest(method: .get, scheme: "https", authority: "x.test", path: "/ok"),
            body: nil,
            metadata: ServerRequestMetadata(pathParameters: [:]),
            operationID: "ok",
            next: { _, _, _ in (HTTPResponse(status: .ok), nil) }
        )
        _ = try? await mw.intercept(
            HTTPRequest(method: .get, scheme: "https", authority: "x.test", path: "/fail"),
            body: nil,
            metadata: ServerRequestMetadata(pathParameters: [:]),
            operationID: "fail",
            next: { _, _, _ in throw Boom() }
        )

        let requestEvent = sink.events.first { $0.message == "Request" && $0.metadata["operationID"] == "ok" }
        let responseEvent = sink.events.first { $0.message == "Response" }
        let errorEvent = sink.events.first { $0.message == "Request error" }
        #expect(requestEvent?.level == .info)
        #expect(responseEvent?.level == .notice)
        #expect(errorEvent?.level == .critical)
    }

    @Test("Renamed PrefixedStreamLogHandler writes prefix to stream")
    func prefixedStreamRenameWorks() {
        final class Capture: TextOutputStream, @unchecked Sendable {
            var s = ""
            func write(_ string: String) { s += string }
        }
        let capture = Capture()
        var h = PrefixedStreamLogHandler(label: "t", stream: capture, logPrefix: "[NEW]")
        h.log(level: .info, message: "x", metadata: ["k": "v"],
              source: "s", file: "f", function: "fn", line: 1)
        #expect(capture.s.contains("[NEW]"))
        #expect(capture.s.contains("`k` = `v`"))
    }
}
