import Testing
import Foundation
import HTTPTypes
import OpenAPIRuntime
@testable import OpenAPILoggingMiddleware

@Suite("BodyLoggingPolicy")
struct BodyLoggingPolicyTests {

    // MARK: - BodyLog Description

    @Test("BodyLog.none description")
    func bodyLogNoneDescription() {
        let log = BodyLoggingPolicy.BodyLog.none
        #expect(log.description == "<none>")
    }

    @Test("BodyLog.redacted description")
    func bodyLogRedactedDescription() {
        let log = BodyLoggingPolicy.BodyLog.redacted
        #expect(log.description == "<redacted>")
    }

    @Test("BodyLog.unknownLength description")
    func bodyLogUnknownLengthDescription() {
        let log = BodyLoggingPolicy.BodyLog.unknownLength
        #expect(log.description == "<unknown length>")
    }

    @Test("BodyLog.tooManyBytesToLog description")
    func bodyLogTooManyBytesDescription() {
        let log = BodyLoggingPolicy.BodyLog.tooManyBytesToLog(2048)
        #expect(log.description == "<2048 bytes>")
    }

    @Test("BodyLog.complete description with valid UTF-8")
    func bodyLogCompleteDescription() {
        let data = Data("hello world".utf8)
        let log = BodyLoggingPolicy.BodyLog.complete(data)
        #expect(log.description == "hello world")
    }

    @Test("BodyLog.complete description with non-UTF-8 data")
    func bodyLogCompleteNonUTF8() {
        let data = Data([0xFF, 0xFE, 0xFD])
        let log = BodyLoggingPolicy.BodyLog.complete(data)
        #expect(log.description == "<non-textual data or unsupported encoding>")
    }

    // MARK: - BodyLog Equatable

    @Test("BodyLog equatable")
    func bodyLogEquatable() {
        #expect(BodyLoggingPolicy.BodyLog.none == .none)
        #expect(BodyLoggingPolicy.BodyLog.redacted == .redacted)
        #expect(BodyLoggingPolicy.BodyLog.unknownLength == .unknownLength)
        #expect(BodyLoggingPolicy.BodyLog.none != .redacted)
    }

    // MARK: - Policy: never

    @Test("Policy never returns redacted for body with data")
    func policyNeverRedactsBody() async throws {
        let policy = BodyLoggingPolicy.never
        let body = HTTPBody("test data")
        let (bodyLog, passthrough) = try await policy.process(body)
        #expect(bodyLog == .redacted)
        #expect(passthrough != nil)
    }

    @Test("Policy never returns none for nil body")
    func policyNeverNilBody() async throws {
        let policy = BodyLoggingPolicy.never
        let (bodyLog, passthrough) = try await policy.process(nil)
        #expect(bodyLog == .none)
        #expect(passthrough == nil)
    }

    // MARK: - Policy: upTo

    @Test("Policy upTo logs small body completely")
    func policyUpToSmallBody() async throws {
        let policy = BodyLoggingPolicy.upTo(maxBytes: 1024)
        let data = Data("small".utf8)
        let body = HTTPBody(data)
        let (bodyLog, passthrough) = try await policy.process(body)
        #expect(bodyLog == .complete(data))
        #expect(passthrough != nil)
    }

    @Test("Policy upTo returns none for nil body")
    func policyUpToNilBody() async throws {
        let policy = BodyLoggingPolicy.upTo(maxBytes: 1024)
        let (bodyLog, passthrough) = try await policy.process(nil)
        #expect(bodyLog == .none)
        #expect(passthrough == nil)
    }
}
