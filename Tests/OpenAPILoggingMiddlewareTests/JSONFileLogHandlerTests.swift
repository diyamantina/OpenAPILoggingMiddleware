import Testing
import Foundation
import Logging
@testable import OpenAPILoggingMiddleware

@Suite("JSONFileLogHandler")
struct JSONFileLogHandlerTests {

    /// Returns a fresh URL under `temporaryDirectory` for the test to write
    /// into, plus a closure that deletes it on teardown.
    private func makeTempLogURL(name: String) -> (URL, () -> Void) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenAPILoggingMiddleware-tests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        return (url, { try? FileManager.default.removeItem(at: dir) })
    }

    // MARK: - Path-bug regression: writes land at the user-supplied URL

    @Test("init writes the JSON file to the user-supplied URL, not the system documents directory")
    func writesToSuppliedURL() throws {
        let (url, cleanup) = makeTempLogURL(name: "regression.json")
        defer { cleanup() }

        let handler = JSONFileLogHandler(label: "t", logFileURL: url)

        // Drive a single log call so the file actually gets written to.
        handler.log(
            level: .info,
            message: "hello",
            metadata: ["k": .string("v")],
            source: "test", file: "f", function: "fn", line: 1
        )

        #expect(FileManager.default.fileExists(atPath: url.path))

        // Sanity check: the JSON parses and contains our value.
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        #expect(json?.count == 1)
        #expect(json?.first?["k"] as? String == "v")
    }

    @Test("init creates intermediate directories under the supplied URL")
    func createsIntermediateDirectories() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenAPILoggingMiddleware-tests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("nested")
            .appendingPathComponent("deep")
        defer {
            try? FileManager.default.removeItem(
                at: dir.deletingLastPathComponent().deletingLastPathComponent()
            )
        }
        let url = dir.appendingPathComponent("file.json")

        let handler = JSONFileLogHandler(label: "t", logFileURL: url)
        handler.log(
            level: .info,
            message: "ok",
            metadata: ["k": .string("v")],
            source: "test", file: "f", function: "fn", line: 1
        )

        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Linux-friendly default location

    @Test("default JSON log path used by LoggingMiddleware is under temporaryDirectory")
    func defaultPathIsTemporaryDirectory() async throws {
        // Drive `LoggingMiddleware.defaultLogger(...)` and verify the file
        // lands under `FileManager.default.temporaryDirectory`. This is the
        // path that needs to work on Linux (where `.documentDirectory` does
        // not exist).
        let fileName = "openapi-tmp-\(UUID().uuidString).json"
        let expectedPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName).path
        defer { try? FileManager.default.removeItem(atPath: expectedPath) }

        var logger = LoggingMiddleware.defaultLogger(jsonLogFileName: fileName)
        logger.logLevel = .debug
        logger.log(
            level: .info, "ping",
            metadata: ["k": .string("v")],
            source: "t", file: "f", function: "fn", line: 1
        )

        #expect(FileManager.default.fileExists(atPath: expectedPath))
    }
}
