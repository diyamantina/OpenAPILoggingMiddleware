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
