import Foundation
import OpenAPIRuntime

/// Policy that decides whether request/response bodies are logged and how
/// large a body may be before it is summarised.
///
/// ## Overview
///
/// Bodies in flight are an HTTP byte stream of unknown total length until they
/// are consumed. ``LoggingMiddleware`` calls ``process(_:)`` on every body it
/// sees; the policy returns:
///
/// 1. A ``BodyLog`` value that describes whatever the policy decided was
///    safe / useful to log, and
/// 2. The body to forward to the next middleware — the same body if logging
///    was skipped, or a freshly-buffered `HTTPBody` if the policy collected
///    bytes (the original stream is single-pass and would be exhausted
///    otherwise).
///
/// Pick ``never`` to redact every body unconditionally, or
/// ``upTo(maxBytes:)`` with a sensible cap (the default in
/// ``LoggingMiddleware`` is 2 MiB).
///
/// ## Topics
///
/// ### Policies
/// - ``never``
/// - ``upTo(maxBytes:)``
///
/// ### Processing a body
/// - ``process(_:)``
/// - ``BodyLog``
public enum BodyLoggingPolicy: Sendable {

    /// Never log request or response bodies.
    case never

    /// Log request and response bodies that have a known length less than or
    /// equal to `maxBytes`. Bodies of unknown length are buffered up to
    /// `maxBytes` then logged in full; bodies that exceed the cap are not
    /// buffered, and ``BodyLog/tooManyBytesToLog(_:)`` carries their size.
    case upTo(maxBytes: Int)

    /// What ``BodyLoggingPolicy/process(_:)`` decided to log for a given body.
    ///
    /// ## Topics
    ///
    /// ### Cases
    /// - ``none``
    /// - ``redacted``
    /// - ``unknownLength``
    /// - ``tooManyBytesToLog(_:)``
    /// - ``complete(_:)``
    public enum BodyLog: Equatable, CustomStringConvertible, Sendable {
        /// There is no body to log (the underlying body was `nil`).
        case none
        /// The policy forbids logging the body (``BodyLoggingPolicy/never``).
        case redacted
        /// The body is a stream of unknown length and the policy is not set
        /// up to buffer unknown-length streams under a cap.
        case unknownLength
        /// The body's known length exceeds the configured `maxBytes` cap.
        /// The associated value is the body's full byte count.
        case tooManyBytesToLog(Int64)
        /// The body's bytes were collected and may be logged. The associated
        /// data has already been re-wrapped in an `HTTPBody` for the next
        /// middleware (the original stream is single-pass).
        case complete(Data)

        /// A human-readable rendering. Bodies that decode as UTF-8 (or, as a
        /// fallback, ASCII) are returned as text; everything else returns a
        /// short placeholder. Use this in log lines.
        public var description: String {
            switch self {
            case .none: return "<none>"
            case .redacted: return "<redacted>"
            case .unknownLength: return "<unknown length>"
            case .tooManyBytesToLog(let byteCount): return "<\(byteCount) bytes>"
            case .complete(let data):
                if let string = String(data: data, encoding: .utf8) {
                    return string
                } else if let asciiString = String(data: data, encoding: .ascii) {
                    return asciiString // Fallback to ASCII encoding
                } else {
                    return "<non-textual data or unsupported encoding>"
                }
            }
        }
    }

    /// Apply the policy to a body. Returns the value to log and the body to
    /// forward to the next middleware.
    ///
    /// - Parameter body: The body returned by the previous middleware (or
    ///   `nil` for bodyless requests/responses).
    /// - Returns: A tuple `(bodyToLog, bodyForNext)`. When the policy
    ///   collects bytes (the `.complete` path), `bodyForNext` is a freshly
    ///   wrapped `HTTPBody` because the original stream has been consumed.
    /// - Throws: Rethrows any error from `Data(collecting:upTo:)`.
    public func process(_ body: HTTPBody?) async throws -> (bodyToLog: BodyLog, bodyForNext: HTTPBody?) {
        switch (body?.length, self) {
        case (.none, _): return (.none, body)
        case (_, .never): return (.redacted, body)
        case (.unknown, .upTo(let maxBytesToLog)):
            let bodyData = try await Data(collecting: body!, upTo: maxBytesToLog)
            return (.complete(bodyData), HTTPBody(bodyData))
        case (.unknown, _): return (.unknownLength, body)
        case (.known(let length), .upTo(let maxBytesToLog)) where length > maxBytesToLog:
            return (.tooManyBytesToLog(length), body)
        case (.known, .upTo(let maxBytesToLog)):
            let bodyData = try await Data(collecting: body!, upTo: maxBytesToLog)
            return (.complete(bodyData), HTTPBody(bodyData))
        }
    }
}
