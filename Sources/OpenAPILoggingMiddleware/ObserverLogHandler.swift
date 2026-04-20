import Foundation
import Logging

/// A generic `LogHandler` that forwards every log event to a user-supplied
/// closure. Meant for piping log activity into arbitrary sinks (an admin
/// dashboard, a WebSocket broadcast, an analytics pipeline, a test harness).
///
/// Combine it with `Logging.MultiplexLogHandler` to keep the built-in handlers
/// (stream, file, OSLog) alongside a custom observer:
///
/// ```swift
/// let logger = Logger(label: "app") { label in
///     MultiplexLogHandler([
///         PrefixedStreamLogHandler(label: label, logPrefix: "🖥️"),
///         ObserverLogHandler(label: label) { event in
///             MyLogBuffer.shared.push(event)
///         }
///     ])
/// }
/// let middleware = LoggingMiddleware(logger: logger, ...)
/// ```
public final class ObserverLogHandler: LogHandler {
    /// Immutable snapshot of a single log event handed to the observer closure.
    public struct Event: Sendable {
        public let timestamp: Date
        public let level: Logger.Level
        public let label: String
        public let message: String
        public let metadata: [String: String]
        public let source: String
        public let file: String
        public let function: String
        public let line: UInt

        public init(
            timestamp: Date,
            level: Logger.Level,
            label: String,
            message: String,
            metadata: [String: String],
            source: String,
            file: String,
            function: String,
            line: UInt
        ) {
            self.timestamp = timestamp
            self.level = level
            self.label = label
            self.message = message
            self.metadata = metadata
            self.source = source
            self.file = file
            self.function = function
            self.line = line
        }
    }

    private let label: String
    private let observe: @Sendable (Event) -> Void
    nonisolated(unsafe) private var _logLevel: Logger.Level = .info

    public init(label: String, observe: @escaping @Sendable (Event) -> Void) {
        self.label = label
        self.observe = observe
    }

    public var logLevel: Logger.Level {
        get { _logLevel }
        set { _logLevel = newValue }
    }

    nonisolated(unsafe) public var metadata: Logger.Metadata = [:]

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let merged = self.metadata.merging(metadata ?? [:]) { _, new in new }
        let flat = merged.reduce(into: [String: String]()) { acc, pair in
            acc[pair.key] = "\(pair.value)"
        }
        observe(Event(
            timestamp: Date(),
            level: level,
            label: label,
            message: "\(message)",
            metadata: flat,
            source: source,
            file: file,
            function: function,
            line: line
        ))
    }
}
