import Foundation
import Logging

#if canImport(OSLog)
import OSLog

/// Thread safety provided by MultiplexLogHandler's serial queue synchronization
@available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
final class OSLogHandler: LogHandler {
    private let osLogger: os.Logger
    private let label: String
    nonisolated(unsafe) private var _logLevel: Logging.Logger.Level = .info
    private let logPrefix: String

    init(subsystem: String, category: String, logPrefix: String = "") {
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
        self.label = category
        self.logPrefix = logPrefix
    }

    // MARK: LogHandler Protocol

    var logLevel: Logging.Logger.Level {
        get { _logLevel }
        set { _logLevel = newValue }
    }

    nonisolated(unsafe) var metadata: Logging.Logger.Metadata = [:]

    subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { return metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(level: Logging.Logger.Level,
             message: Logging.Logger.Message,
             metadata: Logging.Logger.Metadata?,
             source: String,
             file: String,
             function: String,
             line: UInt) {

        guard let metadata = metadata else { return }

        let osLogType = self.osLogType(from: level)

        // Log each metadata key-value pair
        for (key, value) in metadata {
            if key == LogMetadataKey.requestHeadersArray.rawValue || key == LogMetadataKey.responseHeadersArray.rawValue {
                // Log headers
                let headerArrayString = value.description
                let headerDictionary = headerArrayString.convertHeaderStringToDictionary()

                if let headerStringDictionary = headerDictionary as? [String: String] {
                    for (headerKey, headerValue) in headerStringDictionary {
                        let logMessage = "\(self.logPrefix)\(key) Header: \(headerKey) = \(headerValue)"
                        osLogger.log(level: osLogType, "\(logMessage)")
                    }
                }
            } else if key == LogMetadataKey.requestHeadersJSON.rawValue || key == LogMetadataKey.responseHeadersJSON.rawValue {
                // Log JSON headers
                if let dictionary = value.description.meAsJSONStringToDictionary() {
                    for (headerKey, headerValue) in dictionary {
                        let logMessage = "\(self.logPrefix)\(key) Header: \(headerKey) = \(String(describing: headerValue))"
                        osLogger.log(level: osLogType, "\(logMessage)")
                    }
                }
            } else {
                // Log regular metadata
                let logMessage = "\(self.logPrefix)\(key) = \(value.description)"
                osLogger.log(level: osLogType, "\(logMessage)")
            }
        }
    }

    // MARK: Helper Methods

    private func osLogType(from loggerLevel: Logging.Logger.Level) -> OSLogType {
        switch loggerLevel {
        case .trace:
            return .debug
        case .debug:
            return .debug
        case .info:
            return .info
        case .notice:
            return .default
        case .warning:
            return .error
        case .error:
            return .error
        case .critical:
            return .fault
        }
    }
}
#endif
