import Testing
import Foundation
import HTTPTypes
import Logging
import OpenAPIRuntime
@testable import OpenAPILoggingMiddleware

/// Adversarial coverage for `LoggingMiddleware` and the bundled handlers.
/// Each test feeds the middleware something a real workload or a hostile
/// input might emit and asserts the output stays well-defined (no crash,
/// no memory blow-up, no leaked credentials).
@Suite("LoggingMiddleware: adversarial / robustness")
struct LoggingMiddlewareRobustnessTests {

    final class EventSink: @unchecked Sendable {
        let lock = NSLock()
        var events: [ObserverLogHandler.Event] = []
        func append(_ event: ObserverLogHandler.Event) {
            lock.lock(); defer { lock.unlock() }
            events.append(event)
        }
        func snapshot() -> [ObserverLogHandler.Event] {
            lock.lock(); defer { lock.unlock() }
            return events
        }
    }

    private func makeMiddleware(
        observer: ObserverLogHandler,
        bodyLoggingPolicy: BodyLoggingPolicy = .never,
        redactedHeaderFields: Set<HTTPField.Name> = LoggingMiddleware.defaultRedactedHeaderFields
    ) -> LoggingMiddleware {
        var logger = Logger(label: "robustness") { _ in MultiplexLogHandler([observer]) }
        logger.logLevel = .debug
        return LoggingMiddleware(
            logger: logger,
            bodyLoggingConfiguration: bodyLoggingPolicy,
            redactedHeaderFields: redactedHeaderFields
        )
    }

    // MARK: - Header redaction edges

    @Test("redaction on a request with NO Authorization header is a no-op (does not synthesise a redacted entry)")
    func redactionNoAuthorizationHeader() async throws {
        let sink = EventSink()
        let mw = makeMiddleware(observer: ObserverLogHandler(label: "t") { sink.append($0) })

        let request = HTTPRequest(method: .get, scheme: "https", authority: "x.test", path: "/p")
        let metadata = ServerRequestMetadata(pathParameters: [:])
        _ = try await mw.intercept(
            request, body: nil, metadata: metadata, operationID: "op",
            next: { _, _, _ in (HTTPResponse(status: .ok), nil) }
        )

        let req = sink.snapshot().first { $0.message == "Request" }
        let headers = req?.metadata["requestHeadersJSON"] ?? ""
        #expect(!headers.contains("\"Authorization\""))
        #expect(!headers.contains("<redacted>"))
    }

    @Test("Cookie + Set-Cookie are both redacted by default")
    func cookieRedactionDefault() async throws {
        let sink = EventSink()
        let mw = makeMiddleware(observer: ObserverLogHandler(label: "t") { sink.append($0) })

        var request = HTTPRequest(method: .get, scheme: "https", authority: "x.test", path: "/p")
        request.headerFields[.cookie] = "session=secret-1"
        let metadata = ServerRequestMetadata(pathParameters: [:])

        let response: HTTPResponse = {
            var r = HTTPResponse(status: .ok)
            r.headerFields[.setCookie] = "sid=secret-2"
            return r
        }()

        _ = try await mw.intercept(
            request, body: nil, metadata: metadata, operationID: "op",
            next: { _, _, _ in (response, nil) }
        )

        let events = sink.snapshot()
        let reqHeaders = events.first { $0.message == "Request" }?.metadata["requestHeadersJSON"] ?? ""
        let respHeaders = events.first { $0.message == "Response" }?.metadata["responseHeadersJSON"] ?? ""

        #expect(!reqHeaders.contains("secret-1"))
        #expect(reqHeaders.contains("<redacted>"))
        #expect(!respHeaders.contains("secret-2"))
        #expect(respHeaders.contains("<redacted>"))
    }

    @Test("repeated Set-Cookie headers collapse to a single <redacted> entry")
    func repeatedSetCookieCollapses() {
        var fields = HTTPFields()
        fields.append(HTTPField(name: .setCookie, value: "a=1"))
        fields.append(HTTPField(name: .setCookie, value: "b=2"))
        fields.append(HTTPField(name: .setCookie, value: "c=3"))
        let dict = fields.redacted(redacting: [.setCookie]).toDictionary()
        #expect(dict["Set-Cookie"] == "<redacted>")
    }

    @Test("custom redaction set redacts a non-default header (X-Api-Key)")
    func customRedactionSet() async throws {
        let key = HTTPField.Name("X-Api-Key")!
        let sink = EventSink()
        let mw = makeMiddleware(
            observer: ObserverLogHandler(label: "t") { sink.append($0) },
            redactedHeaderFields: LoggingMiddleware.defaultRedactedHeaderFields.union([key])
        )

        var request = HTTPRequest(method: .get, scheme: "https", authority: "x.test", path: "/p")
        request.headerFields[key] = "very-secret-key"
        let metadata = ServerRequestMetadata(pathParameters: [:])
        _ = try await mw.intercept(
            request, body: nil, metadata: metadata, operationID: "op",
            next: { _, _, _ in (HTTPResponse(status: .ok), nil) }
        )

        let req = sink.snapshot().first { $0.message == "Request" }
        let headers = req?.metadata["requestHeadersJSON"] ?? ""
        #expect(!headers.contains("very-secret-key"))
        #expect(headers.contains("<redacted>"))
    }

    // MARK: - Body re-wrap safety

    @Test("body of unknown length is consumed once, re-wrapped, then forwarded intact to next")
    func bodyConsumedOnceRewrapped() async throws {
        let sink = EventSink()
        let mw = makeMiddleware(
            observer: ObserverLogHandler(label: "t") { sink.append($0) },
            bodyLoggingPolicy: .upTo(maxBytes: 64 * 1024)
        )

        let payload = "hello world"
        let body = HTTPBody(payload)
        let request = HTTPRequest(method: .post, scheme: "https", authority: "x.test", path: "/p")
        let metadata = ServerRequestMetadata(pathParameters: [:])

        actor Captured {
            var bodyText: String?
            func record(_ s: String?) { bodyText = s }
        }
        let captured = Captured()

        _ = try await mw.intercept(
            request, body: body, metadata: metadata, operationID: "op",
            next: { _, body, _ in
                if let body {
                    let bytes = try await ArraySlice(collecting: body, upTo: 1024)
                    await captured.record(String(decoding: bytes, as: UTF8.self))
                }
                return (HTTPResponse(status: .ok), nil)
            }
        )

        await #expect(captured.bodyText == payload)
    }

    @Test("body of unknown length larger than the cap is forwarded but NOT logged in full")
    func oversizedBodyIsTruncatedInLog() async throws {
        let sink = EventSink()
        let mw = makeMiddleware(
            observer: ObserverLogHandler(label: "t") { sink.append($0) },
            bodyLoggingPolicy: .upTo(maxBytes: 16) // tiny cap
        )

        let payload = String(repeating: "x", count: 1024)
        let body = HTTPBody(payload)
        let request = HTTPRequest(method: .post, scheme: "https", authority: "x.test", path: "/p")
        let metadata = ServerRequestMetadata(pathParameters: [:])

        actor Captured { var len: Int?; func record(_ n: Int?) { len = n } }
        let captured = Captured()

        _ = try await mw.intercept(
            request, body: body, metadata: metadata, operationID: "op",
            next: { _, body, _ in
                if let body {
                    let bytes = try await ArraySlice(collecting: body, upTo: 8 * 1024)
                    await captured.record(bytes.count)
                }
                return (HTTPResponse(status: .ok), nil)
            }
        )

        // Handler still receives the full body...
        await #expect(captured.len == 1024)

        // ...but the request log entry only carries the truncated marker, not
        // the full payload.
        let req = sink.snapshot().first { $0.message == "Request" }
        let bodyMeta = req?.metadata["requestBody"] ?? ""
        #expect(!bodyMeta.contains(payload))
    }

    // MARK: - Concurrent log emission (StateLock proves itself)

    @Test("ObserverLogHandler under 200 concurrent log calls captures every event without crash")
    func observerHandlerConcurrentLoad() async throws {
        let sink = EventSink()
        let observer = ObserverLogHandler(label: "concurrent") { sink.append($0) }
        let logger: Logger = {
            var l = Logger(label: "concurrent") { _ in MultiplexLogHandler([observer]) }
            l.logLevel = .debug
            return l
        }()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<200 {
                group.addTask {
                    logger.log(level: .debug, "evt-\(i)", source: "t", file: "f", function: "fn", line: UInt(i))
                }
            }
            await group.waitForAll()
        }

        #expect(sink.snapshot().count == 200)
    }

    @Test("ObserverLogHandler subscript metadata mutation under concurrency does not corrupt state")
    func observerHandlerConcurrentMetadataMutation() async throws {
        let observer = ObserverLogHandler(label: "concurrent") { _ in }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<500 {
                group.addTask {
                    var copy = observer
                    copy[metadataKey: "k\(i)"] = .string("v\(i)")
                }
            }
            await group.waitForAll()
        }

        // No crash, no SIGABRT from heap corruption: success.
    }

    // MARK: - Pathological inputs

    @Test("very long header value (~1 MB) does not crash redaction or JSON serialisation")
    func longHeaderValueDoesNotCrash() async throws {
        let sink = EventSink()
        let mw = makeMiddleware(observer: ObserverLogHandler(label: "t") { sink.append($0) })

        // 1 MB of "a" — Authorization gets redacted, the response path
        // serialises whatever else is there.
        let huge = String(repeating: "a", count: 1024 * 1024)
        var request = HTTPRequest(method: .get, scheme: "https", authority: "x.test", path: "/p")
        request.headerFields[.authorization] = "Bearer \(huge)"
        let metadata = ServerRequestMetadata(pathParameters: [:])

        _ = try await mw.intercept(
            request, body: nil, metadata: metadata, operationID: "op",
            next: { _, _, _ in (HTTPResponse(status: .ok), nil) }
        )

        let req = sink.snapshot().first { $0.message == "Request" }
        let headers = req?.metadata["requestHeadersJSON"] ?? ""
        #expect(headers.contains("<redacted>"))
        #expect(!headers.contains(huge))
    }
}
