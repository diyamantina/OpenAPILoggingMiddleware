import Testing
import Foundation
import Logging
import HTTPTypes
import OpenAPIRuntime
@testable import OpenAPILoggingMiddleware

@Suite("LoggingMiddleware")
struct LoggingMiddlewareTests {

    @Test("Default initializer sets expected values")
    func defaultInit() async {
        let middleware = LoggingMiddleware()
        let prefix = await middleware.logPrefix
        let appName = await middleware.appName
        #expect(prefix == "")
        #expect(appName == nil)
    }

    @Test("Custom initializer preserves values")
    func customInit() async {
        let middleware = LoggingMiddleware(
            bodyLoggingConfiguration: .never,
            appName: "TestApp",
            logPrefix: "[TEST]"
        )
        let prefix = await middleware.logPrefix
        let appName = await middleware.appName
        #expect(prefix == "[TEST]")
        #expect(appName == "TestApp")
    }

    @Test("Client middleware intercept passes through")
    func clientMiddlewareIntercept() async throws {
        let middleware = LoggingMiddleware(bodyLoggingConfiguration: .never)
        let request = HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/test")
        let (response, _) = try await middleware.intercept(
            request,
            body: nil,
            baseURL: URL(string: "https://example.com")!,
            operationID: "testOp",
            next: { _, _, _ in
                (HTTPResponse(status: .ok), nil)
            }
        )
        #expect(response.status == .ok)
    }

    @Test("Server middleware intercept passes through")
    func serverMiddlewareIntercept() async throws {
        let middleware = LoggingMiddleware(bodyLoggingConfiguration: .never)
        let request = HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/test")
        let (response, _) = try await middleware.intercept(
            request,
            body: nil,
            metadata: .init(),
            operationID: "testOp",
            next: { _, _, _ in
                (HTTPResponse(status: .created), nil)
            }
        )
        #expect(response.status == .created)
    }
}

// MARK: - Gap fillers: client + server semantics, body policies at the
//                     middleware level, single-pass body re-wrap.
//
// These mirror the EventSink pattern used by IntegrationTests: a synchronous
// NSLock-guarded sink, wrapped in MultiplexLogHandler, with the logger pinned
// to `.debug` so swift-log doesn't filter the middleware's request/response
// log entries before they reach the observer.

@Suite("LoggingMiddleware: client + server semantics")
struct LoggingMiddlewareSemanticTests {

    final class EventSink: @unchecked Sendable {
        let lock = NSLock()
        var events: [ObserverLogHandler.Event] = []
        func append(_ event: ObserverLogHandler.Event) {
            lock.lock(); defer { lock.unlock() }
            events.append(event)
        }
    }

    private func makeLogger(_ sink: EventSink) -> Logger {
        let observer = ObserverLogHandler(label: "semantic") { sink.append($0) }
        var logger = Logger(label: "semantic") { _ in
            MultiplexLogHandler([observer])
        }
        logger.logLevel = .debug
        return logger
    }

    private let baseURL = URL(string: "https://example.com")!

    // MARK: - client emits Request + Response events

    @Test("Client middleware intercept emits Request + Response events")
    func clientEmitsRequestAndResponse() async throws {
        let sink = EventSink()
        let mw = LoggingMiddleware(logger: makeLogger(sink), bodyLoggingConfiguration: .never)
        let request = HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/probe")

        _ = try await mw.intercept(
            request,
            body: nil,
            baseURL: baseURL,
            operationID: "probe",
            next: { _, _, _ in (HTTPResponse(status: .ok), nil) }
        )

        let messages = sink.events.map(\.message)
        #expect(messages.contains("Request"))
        #expect(messages.contains("Response"))
    }

    // MARK: - server emits Request + Response (already in IntegrationTests, kept here as a sanity guard)

    @Test("Server middleware intercept emits Request + Response events")
    func serverEmitsRequestAndResponse() async throws {
        let sink = EventSink()
        let mw = LoggingMiddleware(logger: makeLogger(sink), bodyLoggingConfiguration: .never)
        let request = HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/probe")

        _ = try await mw.intercept(
            request,
            body: nil,
            metadata: .init(),
            operationID: "probe",
            next: { _, _, _ in (HTTPResponse(status: .ok), nil) }
        )

        let messages = sink.events.map(\.message)
        #expect(messages.contains("Request"))
        #expect(messages.contains("Response"))
    }

    // MARK: - body policy at the middleware level

    @Test("Body policy .never marks request and response bodies as redacted in metadata")
    func neverPolicyRedactsBodies() async throws {
        let sink = EventSink()
        let mw = LoggingMiddleware(logger: makeLogger(sink), bodyLoggingConfiguration: .never)
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/echo")
        let payload = #"{"x":1}"#.data(using: .utf8)!

        _ = try await mw.intercept(
            request,
            body: HTTPBody(payload),
            baseURL: baseURL,
            operationID: "echo",
            next: { _, _, _ in (HTTPResponse(status: .ok), HTTPBody(payload)) }
        )

        let bodyValues = sink.events.compactMap {
            $0.metadata["requestBody"] ?? $0.metadata["responseBody"]
        }
        #expect(!bodyValues.isEmpty)
        #expect(bodyValues.allSatisfy { $0 == "<redacted>" })
    }

    @Test("Body policy .upTo lets a small body land verbatim in request-body metadata")
    func smallBodyLandsInMetadata() async throws {
        let sink = EventSink()
        let mw = LoggingMiddleware(logger: makeLogger(sink), bodyLoggingConfiguration: .upTo(maxBytes: 1024))
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/echo")
        let payload = #"{"hello":"world"}"#.data(using: .utf8)!

        _ = try await mw.intercept(
            request,
            body: HTTPBody(payload),
            baseURL: baseURL,
            operationID: "echo",
            next: { _, _, _ in (HTTPResponse(status: .ok), nil) }
        )

        let requestBody = sink.events
            .first(where: { $0.message == "Request" })?
            .metadata["requestBody"]
        #expect(requestBody == #"{"hello":"world"}"#)
    }

    // MARK: - single-pass body re-wrap safety

    @Test("After middleware logs the body, next() still receives the full bytes")
    func bodyForwardedToNextAfterLogging() async throws {
        let sink = EventSink()
        let mw = LoggingMiddleware(logger: makeLogger(sink), bodyLoggingConfiguration: .upTo(maxBytes: 1024))
        let request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/echo")
        let payload = #"{"hello":"world"}"#.data(using: .utf8)!

        // The next closure consumes the body it receives. If the middleware
        // failed to re-wrap a single-pass body after logging, this would yield
        // empty data instead of the original 18 bytes.
        var observedByNext: Data?
        _ = try await mw.intercept(
            request,
            body: HTTPBody(payload),
            baseURL: baseURL,
            operationID: "echo",
            next: { _, body, _ in
                if let body = body {
                    observedByNext = try await Data(collecting: body, upTo: 1024)
                }
                return (HTTPResponse(status: .ok), nil)
            }
        )

        #expect(observedByNext == payload)
    }
}
