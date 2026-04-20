import Foundation
import Logging

/// A `LogHandler` that writes formatted metadata lines to any `TextOutputStream`
/// (stdout by default), prefixing each line with an optional string.
///
/// Renamed from `StreamLogHandler` in v1.2.0 to avoid collision with
/// `Logging.StreamLogHandler.standardOutput` from swift-log.
public final class PrefixedStreamLogHandler: LogHandler {
    private let label: String
    nonisolated(unsafe) private var _logLevel: Logger.Level = .info
    nonisolated(unsafe) public var stream: TextOutputStream
    private let logPrefix: String

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
                // Convert headers from array of strings to a dictionary
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

/// Wraps Swift's `print(_:terminator:)` as a `TextOutputStream`. Default target
/// for `PrefixedStreamLogHandler`.
public struct StandardOutputStream: TextOutputStream, @unchecked Sendable {
    public init() {}
    public func write(_ string: String) {
        print(string, terminator: "")
    }
}
