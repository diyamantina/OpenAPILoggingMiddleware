import Foundation
import Logging

/// A `LogHandler` that appends structured log entries to a JSON array on disk.
/// The file is rewritten atomically on each log; suitable for low-volume use.
public final class JSONFileLogHandler: LogHandler {
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

    private let label: String
    private let fileHandle: FileHandle
    private let logFileURL: URL
    private let logFileName: String
    nonisolated(unsafe) private var _logLevel: Logger.Level = .info
    private let logPrefix: String

    public init(label: String, logFileURL: URL, logPrefix: String = "") {
        self.label = label
        self.logFileURL = logFileURL
        self.logFileName = logFileURL.lastPathComponent
        self.logPrefix = logPrefix

        // Open or create the log file
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        // Print the path to the log file only once
        print("\(logPrefix)JSON log file created at path: \(logFileURL.path)")

        // File handle for writing
        self.fileHandle = try! FileHandle(forWritingTo: logFileURL)
    }

    deinit {
        self.fileHandle.closeFile() // Ensure the file is closed when done
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
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let logFileURL = documentsPath.appendingPathComponent(logFileName)

        do {
            // Convert the `logs` array to JSON data
            let jsonData = try JSONSerialization.data(withJSONObject: logs, options: .prettyPrinted)

            // Overwrite the file by writing the JSON data
            try jsonData.write(to: logFileURL, options: .atomic)

        } catch {
            print("\(logPrefix)Error saving log: \(error)")
        }
    }

    func loadExistingLogs() -> [[String: Any]] {
        let logFileURL = documentsPath.appendingPathComponent(logFileName)
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
