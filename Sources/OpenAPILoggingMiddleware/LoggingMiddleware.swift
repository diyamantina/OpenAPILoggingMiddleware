import OpenAPIRuntime
import Foundation
import HTTPTypes
import Logging

/// OpenAPI middleware that logs each request and response on both the client
/// and the server, with optional body capture governed by a configurable
/// ``BodyLoggingPolicy``.
///
/// ## Overview
///
/// `LoggingMiddleware` conforms to both `OpenAPIRuntime.ClientMiddleware`
/// and `OpenAPIRuntime.ServerMiddleware`, so a single instance can be wired
/// into the client side (via the generated `Client(middlewares:)` array) and
/// the server side (via `registerHandlers(on:middlewares:)` produced by the
/// OpenAPI generator). Pair it with the bundled handlers for a useful
/// out-of-the-box logging stack:
///
/// - ``PrefixedStreamLogHandler`` writes one line per metadata key to stdout.
/// - ``JSONFileLogHandler`` appends a structured JSON record per request to
///   a file on disk.
/// - ``OSLogHandler`` (Apple platforms) forwards to the unified log.
/// - ``ObserverLogHandler`` pipes events into a closure (use this for live
///   admin dashboards, WebSocket broadcasts, or test harnesses).
///
/// The actor is `Sendable` and safe to share across concurrent intercepts.
///
///     let middleware = LoggingMiddleware(appName: "MyAPI", logPrefix: "🟦 ")
///
///     let client = Client(
///         serverURL: serverURL,
///         transport: AsyncHTTPClientTransport(),
///         middlewares: [middleware]
///     )
///
/// On the server side:
///
///     try handler.registerHandlers(
///         on: transport,
///         serverURL: try Servers.Server1.url(),
///         middlewares: [middleware]
///     )
///
/// ## Topics
///
/// ### Creating the middleware
/// - ``init(logger:bodyLoggingConfiguration:appName:logPrefix:requestLogLevel:responseLogLevel:errorLogLevel:redactedHeaderFields:)``
///
/// ### Inspecting configuration
/// - ``bodyLoggingPolicy``
/// - ``logPrefix``
/// - ``appName``
/// - ``requestLogLevel``
/// - ``responseLogLevel``
/// - ``errorLogLevel``
///
/// ### Default logger
/// - ``defaultLogger(logPrefix:jsonLogFileName:)``
///
/// ### Companion types
/// - ``BodyLoggingPolicy``
/// - ``ObserverLogHandler``
/// - ``PrefixedStreamLogHandler``
/// - ``JSONFileLogHandler``
public actor LoggingMiddleware {

    // MARK: Properties -

    private let logger: Logger

    /// Active body logging policy. See ``BodyLoggingPolicy``.
    public let bodyLoggingPolicy: BodyLoggingPolicy

    /// String prepended to every log line written by the bundled handlers.
    /// Use this to visually distinguish client output from server output in
    /// a mixed app/server build (e.g. `"🟦 client"` vs `"🟧 server"`).
    public let logPrefix: String

    /// Application identifier used to derive the JSON log file name. When
    /// `nil`, the middleware uses ``logPrefix`` (or `"OpenAPILog"`) instead.
    public let appName: String?

    /// Log level used for the per-request log line. Defaults to `.debug`.
    public let requestLogLevel: Logger.Level

    /// Log level used for the per-response log line. Defaults to `.debug`.
    public let responseLogLevel: Logger.Level

    /// Log level used when the next responder throws. Defaults to `.error`.
    public let errorLogLevel: Logger.Level

    /// Header names whose values are replaced by `"<redacted>"` before being
    /// rendered into log metadata. See ``defaultRedactedHeaderFields``.
    public let redactedHeaderFields: Set<HTTPField.Name>

    private let logFileName: String
    private let jsonLogFileName: String

    /// Conservative default for ``redactedHeaderFields``. Covers the common
    /// authentication and session-cookie header names so a permissive
    /// `BodyLoggingPolicy` (or a downstream `LogHandler` that reads the
    /// `requestHeadersJSON` / `responseHeadersJSON` metadata keys) cannot
    /// surface bearer tokens or session cookies to log files.
    ///
    /// - `Authorization`
    /// - `Proxy-Authorization`
    /// - `Cookie`
    /// - `Set-Cookie`
    public static let defaultRedactedHeaderFields: Set<HTTPField.Name> = [
        .authorization,
        .proxyAuthorization,
        .cookie,
        .setCookie,
    ]

    // MARK: init -

    /// Creates a logging middleware ready to drop into a client or server
    /// `middlewares:` array.
    ///
    /// All parameters have sensible defaults; a parameter-less call gives
    /// you a 2 MiB body cap, debug-level request/response logging, error-
    /// level fault logging, and the default multiplex of stream + JSON file
    /// + OSLog handlers.
    ///
    /// - Parameters:
    ///   - logger: An explicit `Logger` to write through. When `nil`, the
    ///     middleware constructs one via
    ///     ``defaultLogger(logPrefix:jsonLogFileName:)`` so the standard
    ///     bundled handlers are wired in. Pass your own `Logger` (typically
    ///     a `Logger(label:factory:)` returning a `MultiplexLogHandler`)
    ///     to layer additional handlers — for example
    ///     ``ObserverLogHandler`` for a live admin dashboard.
    ///   - bodyLoggingConfiguration: Policy for whether/how to log request
    ///     and response bodies. Defaults to `.upTo(maxBytes: 2 MiB)`.
    ///   - appName: Identifier used to derive the JSON log file name. When
    ///     `nil`, the middleware falls back to `logPrefix` and finally to a
    ///     generic `"OpenAPILog"`.
    ///   - logPrefix: String prepended to every line written by the bundled
    ///     handlers. Useful for visually distinguishing multiple middleware
    ///     instances in the same console.
    ///   - requestLogLevel: Log level for the per-request entry. Default
    ///     `.debug`.
    ///   - responseLogLevel: Log level for the per-response entry. Default
    ///     `.debug`.
    ///   - errorLogLevel: Log level used when the next responder throws.
    ///     Default `.error`.
    ///   - redactedHeaderFields: Header names whose values are replaced by
    ///     `"<redacted>"` before being written to log metadata. Defaults to
    ///     ``defaultRedactedHeaderFields`` (Authorization, Proxy-Authorization,
    ///     Cookie, Set-Cookie). Pass `[]` to disable redaction (not
    ///     recommended for production), or extend the default set with
    ///     additional names you treat as sensitive.
    public init(logger: Logger? = nil,
                bodyLoggingConfiguration: BodyLoggingPolicy = .upTo(maxBytes: 1024 * 1024 * 2),
                appName: String? = nil,
                logPrefix: String = "",
                requestLogLevel: Logger.Level = .debug,
                responseLogLevel: Logger.Level = .debug,
                errorLogLevel: Logger.Level = .error,
                redactedHeaderFields: Set<HTTPField.Name> = LoggingMiddleware.defaultRedactedHeaderFields) {
        self.logPrefix = logPrefix
        self.appName = appName
        self.requestLogLevel = requestLogLevel
        self.responseLogLevel = responseLogLevel
        self.errorLogLevel = errorLogLevel
        self.redactedHeaderFields = redactedHeaderFields

        // Generate file names based on appName and logPrefix
        let cleanAppName = appName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }

        let cleanPrefix = logPrefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }

        // Build file prefix: appName_logPrefix or fallback to one of them or default
        let filePrefix: String
        if let appName = cleanAppName, !appName.isEmpty {
            if !cleanPrefix.isEmpty {
                filePrefix = "\(appName)_\(cleanPrefix)"
            } else {
                filePrefix = appName
            }
        } else if !cleanPrefix.isEmpty {
            filePrefix = cleanPrefix
        } else {
            filePrefix = "OpenAPILog"
        }

        self.logFileName = "_\(filePrefix).log"
        self.jsonLogFileName = "_\(filePrefix).json"

        if let logger = logger {
            self.logger = logger
        } else {
            self.logger = Self.defaultLogger(
                logPrefix: logPrefix,
                jsonLogFileName: self.jsonLogFileName
            )
        }
        self.bodyLoggingPolicy = bodyLoggingConfiguration
    }

    // MARK: File Handling -

    private static func createStreamLogHandler(label: String, logPrefix: String) -> PrefixedStreamLogHandler {
        return PrefixedStreamLogHandler(label: label, logPrefix: logPrefix)
    }

    private static func createJSONFileLogHandler(label: String, logPrefix: String, jsonLogFileName: String) -> JSONFileLogHandler {
        // `temporaryDirectory` works on every platform Foundation supports
        // (macOS, iOS, Linux). On macOS it lands under `/var/folders/.../T/`,
        // on Linux under `/tmp`. Consumers who want a different location can
        // build a `JSONFileLogHandler` directly with their own URL and pass
        // a custom `logger:` into ``LoggingMiddleware``.
        let logFileURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(jsonLogFileName)
        return JSONFileLogHandler(label: label, logFileURL: logFileURL, logPrefix: logPrefix)
    }

    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    private static func createOSLogHandler(subsystem: String, category: String, logPrefix: String) -> OSLogHandler {
        return OSLogHandler(subsystem: subsystem, category: category, logPrefix: logPrefix)
    }
    #endif

    // MARK: Default Logger -

    /// Build the default `Logger` used when no `logger` is passed to the
    /// designated initialiser ``LoggingMiddleware/init(logger:bodyLoggingConfiguration:appName:logPrefix:requestLogLevel:responseLogLevel:errorLogLevel:redactedHeaderFields:)``.
    ///
    /// Exposed as public so consumers can start from the built-in handler
    /// set and layer their own handlers on top via
    /// `Logging.MultiplexLogHandler`. The default set is:
    /// - ``PrefixedStreamLogHandler`` (stdout, every platform)
    /// - ``JSONFileLogHandler`` (file under
    ///   `FileManager.default.temporaryDirectory`, every platform)
    /// - ``OSLogHandler`` (Apple platforms only — guarded by
    ///   `#if canImport(OSLog)` so Linux builds skip it)
    ///
    /// - Parameters:
    ///   - logPrefix: String prepended to each line written by the bundled
    ///     handlers.
    ///   - jsonLogFileName: File name used by the JSON handler. The file
    ///     lands under `FileManager.default.temporaryDirectory`.
    /// - Returns: A `Logger` ready to pass to ``init(logger:bodyLoggingConfiguration:appName:logPrefix:requestLogLevel:responseLogLevel:errorLogLevel:redactedHeaderFields:)``.
    public static func defaultLogger(logPrefix: String = "", jsonLogFileName: String = "OpenAPILog.json") -> Logger {
        let label = "com.openapi.logger"

        // Set up the logger with a multiplex log handler that includes stream, file, and OSLog handlers
        var logger = Logger(label: label, factory: { _ in
            var handlers: [any LogHandler] = [
                createStreamLogHandler(label: label, logPrefix: logPrefix),
                createJSONFileLogHandler(label: label, logPrefix: logPrefix, jsonLogFileName: jsonLogFileName)
            ]

            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
                handlers.append(createOSLogHandler(subsystem: "com.openapi", category: "logging-middleware", logPrefix: logPrefix))
            }
            #endif

            return MultiplexLogHandler(handlers)
        })
        logger.logLevel = .debug // Set the desired log level
        return logger
    }
}

// MARK: Client -

extension LoggingMiddleware: ClientMiddleware {
    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (requestBodyToLog, requestBodyForNext) = try await bodyLoggingPolicy.process(body)

        log(request, requestBodyToLog, operationID, baseURL)

        do {
            let (response, responseBody) = try await next(request, requestBodyForNext, baseURL)
            let (responseBodyToLog, responseBodyForNext) = try await bodyLoggingPolicy.process(responseBody)

            log(request, response, responseBodyToLog, operationID, response.status.code, response.status.reasonPhrase)
            return (response, responseBodyForNext)
        } catch {

            log(request, failedWith: error, operationID: operationID)

            throw error
        }
    }
}

// MARK: Server -

extension LoggingMiddleware: ServerMiddleware {
    public func intercept(
        _ request: HTTPTypes.HTTPRequest,
        body: OpenAPIRuntime.HTTPBody?,
        metadata: OpenAPIRuntime.ServerRequestMetadata,
        operationID: String,
        next: @Sendable (HTTPTypes.HTTPRequest, OpenAPIRuntime.HTTPBody?, OpenAPIRuntime.ServerRequestMetadata)
            async throws -> (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?)
    ) async throws -> (HTTPTypes.HTTPResponse, OpenAPIRuntime.HTTPBody?) {

        let (requestBodyToLog, requestBodyForNext) = try await bodyLoggingPolicy.process(body)
        log(request, requestBodyToLog, operationID)
        do {
            let (response, responseBody) = try await next(request, requestBodyForNext, metadata)
            let (responseBodyToLog, responseBodyForNext) = try await bodyLoggingPolicy.process(responseBody)
            log(request, response, responseBodyToLog, operationID, response.status.code, response.status.reasonPhrase)
            return (response, responseBodyForNext)
        } catch {
            log(request, failedWith: error, operationID: operationID)
            throw error
        }
    }
}


// MARK: Logging -

extension LoggingMiddleware {
    func log(_ request: HTTPRequest,
             _ requestBody: BodyLoggingPolicy.BodyLog,
             _ operationID: String,
             _ baseURL: URL? = nil) {
        let fullURL = baseURL?.appendingPathComponent(request.path ?? "")
        let headersString = request.headerFields
            .redacted(redacting: redactedHeaderFields)
            .toJSONString() ?? ""

        var metadata: Logger.Metadata = [
            LogMetadataKey.method.rawValue: .stringConvertible(request.method),
            LogMetadataKey.path.rawValue: .stringConvertible(request.path ?? "<nil>"),
            LogMetadataKey.baseURL.rawValue: .stringConvertible(baseURL?.absoluteString ?? "<nil>"),
            LogMetadataKey.fullPath.rawValue: .stringConvertible(fullURL?.absoluteString ?? "<nil>"),
            LogMetadataKey.requestHeadersJSON.rawValue: .stringConvertible(headersString),
            LogMetadataKey.requestBody.rawValue: .stringConvertible(requestBody),
            LogMetadataKey.operationID.rawValue: .stringConvertible(operationID)
        ]

        // Ensure unique keys in metadata
        metadata[LogMetadataKey.uniqueKey.rawValue] = .stringConvertible(UUID().uuidString) // Example for a unique key
        logger.log(level: requestLogLevel, "Request", metadata: metadata)
    }

    func log(_ request: HTTPRequest,
             _ response: HTTPResponse,
             _ responseBody: BodyLoggingPolicy.BodyLog,
             _ operationID: String,
             _ statusCode: Int,
             _ statusReason: String,
             _ baseURL: URL? = nil) {
        let fullURL = baseURL?.appendingPathComponent(request.path ?? "")
        let headersString = response.headerFields
            .redacted(redacting: redactedHeaderFields)
            .toJSONString() ?? ""

        // Cache the response JSON for potential decoding errors

        var metadata: Logger.Metadata = [
            LogMetadataKey.method.rawValue: .stringConvertible(request.method),
            LogMetadataKey.path.rawValue: .stringConvertible(request.path ?? "<nil>"),
            LogMetadataKey.baseURL.rawValue: .stringConvertible(baseURL?.absoluteString ?? "<nil>"),
            LogMetadataKey.fullPath.rawValue: .stringConvertible(fullURL?.absoluteString ?? "<nil>"),
            LogMetadataKey.responseHeadersJSON.rawValue: .stringConvertible(headersString),
            LogMetadataKey.responseBody.rawValue: .stringConvertible(responseBody),
            LogMetadataKey.operationID.rawValue: .stringConvertible(operationID),
            LogMetadataKey.statusCode.rawValue: .stringConvertible(statusCode),
            LogMetadataKey.statusReason.rawValue: .stringConvertible(statusReason)
        ]

        // Ensure unique keys in metadata
        metadata[LogMetadataKey.uniqueKey.rawValue] = .stringConvertible(UUID().uuidString) // Example for a unique key
        logger.log(level: responseLogLevel, "Response", metadata: metadata)
    }

    func log(_ request: HTTPRequest, failedWith error: any Error, operationID: String) {

        var metadata: Logger.Metadata = [
            LogMetadataKey.method.rawValue: .stringConvertible(request.method),
            LogMetadataKey.path.rawValue: .stringConvertible(request.path ?? "<nil>"),
            LogMetadataKey.error.rawValue: .string(error.localizedDescription),
            LogMetadataKey.operationID.rawValue: .stringConvertible(operationID)
        ]
        // Ensure unique keys in metadata
        metadata[LogMetadataKey.uniqueKey.rawValue] = .stringConvertible(UUID().uuidString) // Example for a unique key
        logger.log(level: errorLogLevel, "Request error", metadata: metadata)
    }
}
