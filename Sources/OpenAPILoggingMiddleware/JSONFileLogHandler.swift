import Foundation
import Logging

/// A `LogHandler` that appends structured log entries to a JSON array on disk.
///
/// ## Overview
///
/// Each `log(...)` call serialises the level, label, message, and metadata
/// into a JSON object and appends it to a JSON array file at a configured
/// location. The file is created (empty) on init if it doesn't yet exist;
/// subsequent calls read the existing array, append the new record, and
/// rewrite the file atomically.
///
/// Use this handler when you want a machine-readable record of every request
/// / response that crossed the middleware (post-mortem replay, offline log
/// analysis, attaching to bug reports). For real-time observation pair it
/// with ``ObserverLogHandler`` instead, and for human-readable console
/// output use ``PrefixedStreamLogHandler``.
///
/// - Important: This handler writes synchronously on the calling thread,
///   reading and rewriting the entire JSON array on every log call. It is
///   suitable for low-to-moderate request volume; behind a high-throughput
///   service, prefer a buffered/async logging strategy.
///
/// - Note: Cross-platform: works on macOS, iOS, and Linux. The default JSON
///   log file path used by ``LoggingMiddleware`` lands under
///   `FileManager.default.temporaryDirectory`, which exists on every
///   supported platform.
///
/// ## Topics
///
/// ### Creating the handler
/// - ``init(label:logFileURL:logPrefix:)``
public final class JSONFileLogHandler: LogHandler {

    private let label: String
    private let logFileURL: URL
    nonisolated(unsafe) private var _logLevel: Logger.Level = .info
    private let logPrefix: String

    /// Creates a handler bound to a specific JSON log file.
    ///
    /// The file is created (empty) if it does not yet exist; otherwise it is
    /// opened and new entries are appended to the existing JSON array.
    ///
    /// - Parameters:
    ///   - label: A short identifier for the logger; surfaced in each entry.
    ///   - logFileURL: Absolute file URL where the JSON array should be
    ///     written. The caller is responsible for choosing an appropriate
    ///     directory (e.g. a per-app sandbox subfolder, or
    ///     `FileManager.default.temporaryDirectory.appendingPathComponent(...)`
    ///     on Linux). The handler reads and rewrites this exact URL.
    ///   - logPrefix: Optional string included in entries for visual
    ///     distinction across multiplexed handlers.
    public init(label: String, logFileURL: URL, logPrefix: String = "") {
        self.label = label
        self.logFileURL = logFileURL
        self.logPrefix = logPrefix

        // Make sure the parent directory exists (safe for nested defaults).
        let parent = logFileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try? FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
        }

        // Open or create the log file.
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        // Print the path to the log file only once.
        print("\(logPrefix)JSON log file created at path: \(logFileURL.path)")
    }

    // MARK: Metadata -

    // Required for LogHandler protocol
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { return metadata[key] }
        set { metadata[key] = newValue }
    }

    nonisolated(unsafe) public var metadata: Logger.Metadata = [:]

    public var logLevel: Logger.Level {
        get { self._logLevel }
        set { self._logLevel = newValue }
    }

    public func log(level: Logger.Level,
                    message: Logger.Message,
                    metadata: Logger.Metadata?,
                    source: String,
                    file: String,
                    function: String,
                    line: UInt) {

        guard let metadata = metadata else { return }

        // Create the log entry dictionary
        var logEntry: [String: Any] = [
            LogKey.timestamp.rawValue: Date.loggableCurrentDate()
        ]

        // Process metadata and headers as before
        for (key, value) in metadata {
            if key == LogMetadataKey.requestHeadersArray.rawValue || key == LogMetadataKey.responseHeadersArray.rawValue {
                // Convert headers from array of strings to a dictionary
                let headerArrayString = value.description
                let headerDictionary = headerArrayString.convertHeaderStringToDictionary()
                let source = key == LogMetadataKey.requestHeadersArray.rawValue ? "request": "response"
                let name = "\(source) headers"
                logEntry[name] = headerDictionary
            } else if key == LogMetadataKey.requestHeadersJSON.rawValue || key == LogMetadataKey.responseHeadersJSON.rawValue {
                if let dictionary = value.description.meAsJSONStringToDictionary() {
                    let source = key == LogMetadataKey.requestHeadersJSON.rawValue ? "request": "response"
                    let name = "\(source) headers"
                    logEntry[name] = dictionary
                }
            } else {
                logEntry[key] = value.description
            }
        }

        var existingLogs = loadExistingLogs()
        existingLogs.append(logEntry)
        saveLogAsJSON(existingLogs)
    }
}

private extension JSONFileLogHandler {

    func saveLogAsJSON(_ logs: [[String: Any]]) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: logs, options: .prettyPrinted)
            try jsonData.write(to: logFileURL, options: .atomic)
        } catch {
            print("\(logPrefix)Error saving log: \(error)")
        }
    }

    func loadExistingLogs() -> [[String: Any]] {
        if let data = try? Data(contentsOf: logFileURL),
           let existingLogs = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
            return existingLogs
        }
        return []
    }
}

public extension Date {
    static func loggableCurrentDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy. HH:mm:ss"
        return dateFormatter.string(from: Date())
    }
}
