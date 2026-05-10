import Foundation
import Logging

/// A `LogHandler` that writes formatted metadata lines to any `TextOutputStream`
/// (stdout by default), prefixing each line with an optional string.
///
/// ## Overview
///
/// `PrefixedStreamLogHandler` is a drop-in replacement for swift-log's
/// `StreamLogHandler.standardOutput` that adds a per-line prefix and formats
/// metadata in `key = value` form. Use it when you want OpenAPI request /
/// response activity in your console output, with a visual marker
/// distinguishing client-side from server-side lines:
///
///     PrefixedStreamLogHandler(label: "client", logPrefix: "🟦 ")
///     PrefixedStreamLogHandler(label: "server", logPrefix: "🟧 ")
///
/// Header collections (`*-headers-array`, `*-headers-json`) are unpacked into
/// one log line per header so headers stay greppable.
///
/// - Note: Renamed from `StreamLogHandler` in v1.2.0 to avoid collision with
///   `Logging.StreamLogHandler.standardOutput` from swift-log.
///
/// ## Topics
///
/// ### Creating the handler
/// - ``init(label:stream:logPrefix:)``
///
/// ### Companion stream
/// - ``StandardOutputStream``
public final class PrefixedStreamLogHandler: LogHandler {
    private let label: String
    nonisolated(unsafe) private var _logLevel: Logger.Level = .info
    nonisolated(unsafe) public var stream: TextOutputStream
    private let logPrefix: String

    /// Creates a new handler.
    ///
    /// - Parameters:
    ///   - label: A short identifier for the logger; carried into output for
    ///     consistency with `Logging.LogHandler` semantics.
    ///   - stream: The destination for log lines. Defaults to stdout via
    ///     ``StandardOutputStream``.
    ///   - logPrefix: Optional string prepended to every line. Useful for
    ///     visually distinguishing client vs server log output.
    public init(label: String, stream: TextOutputStream = StandardOutputStream(), logPrefix: String = "") {
        self.label = label
        self.stream = stream
        self.logPrefix = logPrefix
    }

    public var logLevel: Logger.Level {
        get { _logLevel }
        set { _logLevel = newValue }
    }

    nonisolated(unsafe) public var metadata: Logger.Metadata = [:]

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { return metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(level: Logger.Level,
                    message: Logger.Message,
                    metadata: Logger.Metadata?,
                    source: String,
                    file: String,
                    function: String,
                    line: UInt) {

        guard let metadata = metadata else { return }

        for (key, value) in metadata {

            if key == LogMetadataKey.responseHeadersArray.rawValue || key == LogMetadataKey.requestHeadersArray.rawValue {
                self.stream.write("\(logPrefix)\(key) Headers:\n")
                let headerArrayString = value.description
                let headerDictionary = headerArrayString.convertHeaderStringToDictionary()

                if let headerStringDictionary = headerDictionary as? [String: String] {
                    for (headerKey, headerValue) in headerStringDictionary {
                        self.stream.write("\(logPrefix)header: `\(headerKey)` = `\(headerValue.description)`\n")
                    }
                }
            } else if key == LogMetadataKey.requestHeadersJSON.rawValue || key == LogMetadataKey.responseHeadersJSON.rawValue {
                if let dictionary = value.description.meAsJSONStringToDictionary() {
                    for (headerKey, headerValue) in dictionary {
                        self.stream.write("\(logPrefix)\(key) Header: `\(headerKey)` = `\(headerValue)`\n")
                    }
                }
            } else {
                self.stream.write("\(logPrefix)`\(key)` = `\(value.description)`\n")
            }
        }
    }
}

/// `TextOutputStream` that wraps Swift's `print(_:terminator:)` and writes to
/// the host process's standard output.
///
/// Default destination for ``PrefixedStreamLogHandler``. Substitute your own
/// `TextOutputStream` (a buffer, a file, a network socket) at construction
/// time to redirect output without changing the handler.
public struct StandardOutputStream: TextOutputStream, @unchecked Sendable {
    /// Creates a new stream. No configuration.
    public init() {}

    /// Writes the given string to standard output without a trailing newline.
    public func write(_ string: String) {
        print(string, terminator: "")
    }
}
