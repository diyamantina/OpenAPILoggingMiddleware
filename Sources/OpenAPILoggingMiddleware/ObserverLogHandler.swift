import Foundation
import Logging
// Submodule import: pulls in `OSAllocatedUnfairLock` only and avoids clashing
// with `os.Logger` (Apple's unified logging) which would shadow swift-log's
// `Logging.Logger` if the whole `os` module were imported.
import struct os.OSAllocatedUnfairLock

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

    /// State protected by an `OSAllocatedUnfairLock`. swift-log's `LogHandler`
    /// API is sync and called from any thread — Vapor request handlers and the
    /// OpenAPI runtime hammer the same handler instance from many threads at
    /// once. The previous `nonisolated(unsafe) var metadata: Dictionary` was a
    /// race on a non-thread-safe container; concurrent writes corrupted the
    /// heap and crashed the host process with `SIGABRT` from libmalloc's
    /// "pointer being freed was not allocated" guard.
    ///
    /// `OSAllocatedUnfairLock<State>` is Apple's recommended primitive for
    /// this shape on macOS 13+/iOS 16+ (this package's deployment targets).
    /// It owns the state, so callers can't forget to lock — every access goes
    /// through `withLock { … }`. The `os_unfair_lock` underneath is a plain
    /// non-recursive mutex, so we never hold it across an `await` (the
    /// protocol API is sync; `log(...)` snapshots state under the lock and
    /// drops it before invoking the user's observer closure).
    private struct State {
        var logLevel: Logger.Level = .info
        var metadata: Logger.Metadata = [:]
    }
    private let state = OSAllocatedUnfairLock<State>(initialState: State())

    public init(label: String, observe: @escaping @Sendable (Event) -> Void) {
        self.label = label
        self.observe = observe
    }

    public var logLevel: Logger.Level {
        get { state.withLock { $0.logLevel } }
        set { state.withLock { $0.logLevel = newValue } }
    }

    public var metadata: Logger.Metadata {
        get { state.withLock { $0.metadata } }
        set { state.withLock { $0.metadata = newValue } }
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { state.withLock { $0.metadata[key] } }
        set { state.withLock { $0.metadata[key] = newValue } }
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
        // Snapshot the handler's own metadata under the lock; merge OUTSIDE
        // the lock so we never call user-supplied code (`observe`) while
        // holding it (the closure is allowed to do anything, including
        // re-enter this handler).
        let snapshot = state.withLock { $0.metadata }

        let merged = snapshot.merging(metadata ?? [:]) { _, new in new }
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
