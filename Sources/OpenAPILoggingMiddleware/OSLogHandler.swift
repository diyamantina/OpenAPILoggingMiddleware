import Foundation
import Logging

#if canImport(OSLog)
import OSLog

/// A `LogHandler` that forwards log events to Apple's unified logging system
/// (`os.Logger`) on Apple platforms.
///
/// ## Overview
///
/// Use this handler when you want OpenAPI request/response activity to show
/// up in the macOS Console app, the Xcode debug console, or alongside the
/// rest of your `os_log` output. Each metadata key is logged as a separate
/// line so the unified log stays grep-able.
///
/// Header collections (`request-headers-array`, `response-headers-array`,
/// `request-headers-json`, `response-headers-json`) are unpacked into one
/// log line per header. All other metadata is logged as `<key> = <value>`.
///
/// Compose with `Logging.MultiplexLogHandler` to log to multiple sinks at
/// once — see ``LoggingMiddleware/defaultLogger(logPrefix:jsonLogFileName:)``
/// for the bundled multiplex set.
///
/// - Note: Available on Apple platforms only (`canImport(OSLog)` guarded).
///
/// ## Topics
///
/// ### Creating the handler
/// - ``init(subsystem:category:logPrefix:)``
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
public final class OSLogHandler: LogHandler {
    private let osLogger: os.Logger
    private let label: String
    nonisolated(unsafe) private var _logLevel: Logging.Logger.Level = .info
    private let logPrefix: String

    /// Creates a new handler bound to a specific OSLog subsystem + category.
    ///
    /// - Parameters:
    ///   - subsystem: Reverse-DNS identifier of the subsystem (e.g.
    ///     `"com.example.MyApp"`). Used by the unified log to scope filters.
    ///   - category: Within the subsystem, the category (e.g.
    ///     `"network"`). Appears alongside subsystem in Console.
    ///   - logPrefix: Optional string prepended to every log line. Useful
    ///     for visually distinguishing client logs from server logs in a
    ///     mixed app/server build (e.g. `"🟦 client"` vs `"🟧 server"`).
    public init(subsystem: String, category: String, logPrefix: String = "") {
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
        self.label = category
        self.logPrefix = logPrefix
    }

    // MARK: LogHandler Protocol

    public var logLevel: Logging.Logger.Level {
        get { _logLevel }
        set { _logLevel = newValue }
    }

    nonisolated(unsafe) public var metadata: Logging.Logger.Metadata = [:]

    public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { return metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(level: Logging.Logger.Level,
                    message: Logging.Logger.Message,
                    metadata: Logging.Logger.Metadata?,
                    source: String,
                    file: String,
                    function: String,
                    line: UInt) {

        guard let metadata = metadata else { return }

        let osLogType = self.osLogType(from: level)

        for (key, value) in metadata {
            if key == LogMetadataKey.requestHeadersArray.rawValue || key == LogMetadataKey.responseHeadersArray.rawValue {
                let headerArrayString = value.description
                let headerDictionary = headerArrayString.convertHeaderStringToDictionary()

                if let headerStringDictionary = headerDictionary as? [String: String] {
                    for (headerKey, headerValue) in headerStringDictionary {
                        let logMessage = "\(self.logPrefix)\(key) Header: \(headerKey) = \(headerValue)"
                        osLogger.log(level: osLogType, "\(logMessage)")
                    }
                }
            } else if key == LogMetadataKey.requestHeadersJSON.rawValue || key == LogMetadataKey.responseHeadersJSON.rawValue {
                if let dictionary = value.description.meAsJSONStringToDictionary() {
                    for (headerKey, headerValue) in dictionary {
                        let logMessage = "\(self.logPrefix)\(key) Header: \(headerKey) = \(String(describing: headerValue))"
                        osLogger.log(level: osLogType, "\(logMessage)")
                    }
                }
            } else {
                let logMessage = "\(self.logPrefix)\(key) = \(value.description)"
                osLogger.log(level: osLogType, "\(logMessage)")
            }
        }
    }

    // MARK: Helper Methods

    private func osLogType(from loggerLevel: Logging.Logger.Level) -> OSLogType {
        switch loggerLevel {
        case .trace: return .debug
        case .debug: return .debug
        case .info: return .info
        case .notice: return .default
        case .warning: return .error
        case .error: return .error
        case .critical: return .fault
        }
    }
}
#endif
