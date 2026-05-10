# OpenAPILoggingMiddleware

![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-macOS%2013+%20%7C%20iOS%2016+%20%7C%20Linux-blue.svg)

OpenAPI middleware that logs each request and response on both the client and
the server side, with optional body capture, multiple bundled log handlers
(stream, JSON file, OSLog, observer), and a pluggable architecture so you can
ship log events anywhere.

## Installation

```swift
.package(url: "https://github.com/mihaelamj/OpenAPILoggingMiddleware", from: "1.3.0"),
```

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "OpenAPILoggingMiddleware", package: "OpenAPILoggingMiddleware"),
    ]
),
```

## Quick start

```swift
import OpenAPILoggingMiddleware
import OpenAPIAsyncHTTPClient

let logging = LoggingMiddleware(appName: "MyAPI", logPrefix: "🟦 ")

// Client side
let client = Client(
    serverURL: serverURL,
    transport: AsyncHTTPClientTransport(),
    middlewares: [logging]
)

// Server side — same instance, same actor
try handler.registerHandlers(
    on: transport,
    serverURL: try Servers.Server1.url(),
    middlewares: [logging]
)
```

That gives you stream output to stdout, a JSON record per request appended to
a file in your documents directory, and (on Apple platforms) entries in the
unified log — all out of the box.

## Configuration

```swift
public init(
    logger: Logger? = nil,
    bodyLoggingConfiguration: BodyLoggingPolicy = .upTo(maxBytes: 2 * 1024 * 1024),
    appName: String? = nil,
    logPrefix: String = "",
    requestLogLevel: Logger.Level = .debug,
    responseLogLevel: Logger.Level = .debug,
    errorLogLevel: Logger.Level = .error,
    redactedHeaderFields: Set<HTTPField.Name> = LoggingMiddleware.defaultRedactedHeaderFields
)
```

| Parameter | Default | Notes |
|---|---|---|
| `logger` | `nil` (uses `defaultLogger`) | Pass your own `Logger` to layer custom handlers via `MultiplexLogHandler`. |
| `bodyLoggingConfiguration` | `.upTo(maxBytes: 2 MiB)` | Pick `.never` to redact every body, or `.upTo(maxBytes:)` with your own cap. |
| `appName` | `nil` | Identifier used to derive the JSON log file name. Falls back to `logPrefix`, then to `OpenAPILog`. |
| `logPrefix` | `""` | Prepended to every line. Useful for distinguishing client vs server output (`"🟦 "` vs `"🟧 "`). |
| `requestLogLevel` | `.debug` | Per-request log line. |
| `responseLogLevel` | `.debug` | Per-response log line. |
| `errorLogLevel` | `.error` | Used when the next responder throws. |
| `redactedHeaderFields` | `[.authorization, .proxyAuthorization, .cookie, .setCookie]` | Header values replaced by `"<redacted>"` before being written to log metadata. Pass `[]` to disable, or extend the default set with your own sensitive names (e.g. `X-Api-Key`). |

## Header redaction

`Authorization`, `Proxy-Authorization`, `Cookie`, and `Set-Cookie` are replaced
by `"<redacted>"` in the rendered request/response header JSON before it
reaches any `LogHandler`. This closes the leak channel where a permissive
`BodyLoggingPolicy` plus a downstream observer would otherwise stamp valid
bearer tokens or session cookies into log files.

```swift
// Default — redacts the four common credential headers
let lm1 = LoggingMiddleware(appName: "api")

// Disable redaction (not recommended in production)
let lm2 = LoggingMiddleware(appName: "api", redactedHeaderFields: [])

// Extend the default set with an extra header
let lm3 = LoggingMiddleware(
    appName: "api",
    redactedHeaderFields: LoggingMiddleware.defaultRedactedHeaderFields
        .union([HTTPField.Name("X-Api-Key")!])
)
```

Use `HTTPFields.redacted(redacting:)` directly when you need the same scrub
in your own log paths.

## Body logging

`BodyLoggingPolicy` is the single switch for whether and how request/response
bodies appear in logs:

| Policy | Behaviour |
|---|---|
| `.never` | Redact every body unconditionally. |
| `.upTo(maxBytes:)` | Log bodies of known length up to the cap; bodies of unknown length are buffered up to the cap and logged in full. Bodies that exceed the cap are surfaced as `<N bytes>`. |

The middleware re-wraps any consumed body (`HTTPBody` is a single-pass stream)
before forwarding to the next responder, so logging never strips a body the
consumer was about to read.

## Bundled log handlers

| Handler | Purpose |
|---|---|
| `PrefixedStreamLogHandler` | One line per metadata key on stdout (or any `TextOutputStream` you supply). Renamed from `StreamLogHandler` in 1.2.0 to avoid collision with swift-log's own `StreamLogHandler`. |
| `JSONFileLogHandler` | Appends a structured JSON record per request to the user-supplied URL. Suitable for low-to-moderate volume. The default location used by `LoggingMiddleware` is under `FileManager.default.temporaryDirectory`, which exists on every supported platform. |
| `OSLogHandler` | Forwards to Apple's unified logging system. Apple platforms only — guarded by `#if canImport(OSLog)` so Linux builds skip it. |
| `ObserverLogHandler` | Forwards every log event to a user-supplied closure. Pipe to admin dashboards, WebSocket broadcasts, analytics pipelines, or test harnesses. Thread-safe via `StateLock`, which aliases to `os.OSAllocatedUnfairLock` on Apple platforms and uses an `NSLock`-backed shim on Linux. |

Compose them at boot with `Logging.MultiplexLogHandler` and pass the resulting
`Logger` into `LoggingMiddleware(logger: ...)`.

## Documentation

DocC is enabled. Generate the archive locally with:

```bash
swift package --allow-writing-to-directory ./docs generate-documentation \
    --target OpenAPILoggingMiddleware \
    --output-path ./docs/OpenAPILoggingMiddleware.doccarchive
```

The archive opens in Xcode (or via `xcrun docc preview-documentation`) and
exposes Topics-grouped navigation across `LoggingMiddleware`, `BodyLoggingPolicy`,
and the four bundled handlers.

## Companion packages

- [`mihaelamj/BearerTokenAuthMiddleware`](https://github.com/mihaelamj/BearerTokenAuthMiddleware)
  — client-side bearer-token stamping plus a server-side enforcement
  middleware with `AuthMode` + validation strategies.
- [`mihaelamj/ClientIpMiddleware`](https://github.com/mihaelamj/ClientIpMiddleware)
  — captures client IP and User-Agent into task-locals so OpenAPI-generated
  handlers can read them.
- [`mihaelamj/swift-server-middleware-petshop`](https://github.com/mihaelamj/swift-server-middleware-petshop)
  end-to-end integration tests for all three middlewares composed inside
  a real Vapor + OpenAPI 3.1 app, with macOS + Linux CI.

## Platform support

| Platform | How CI proves it |
|---|---|
| macOS 13+ | full `swift build` + `swift test` (74 tests) |
| Linux (Swift 6.0 container) | full `swift build` + `swift test` (74 tests) |
| iOS 16+ | `xcodebuild build` for `iOS Simulator` |
| tvOS 16+ | `xcodebuild build` for `tvOS Simulator` |
| watchOS 9+ | `xcodebuild build` for `watchOS Simulator` |

Apple-only types (`OSLogHandler`, `OSAllocatedUnfairLock`-backed
`StateLock`) are gated by explicit `#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)`
in the source. On Linux the `StateLock` falls back to an `NSLock`-backed
class with the same `withLock(_:)` surface; `OSLogHandler` does not exist
and consumers compose with `PrefixedStreamLogHandler` and/or
`JSONFileLogHandler` instead.

## Testing

The package ships with **74 tests across 12 suites**:

| Area | Tests |
|---|---|
| `BodyLoggingPolicy` (process / never / upTo / BodyLog) | 11 |
| Integration: `LoggingMiddleware` + `ObserverLogHandler` (concurrency, full intercept paths, header redaction, response-headers fix) | 11 |
| `HTTPFields+Extension` (toArrayString / toDictionary / toJSONString / `redacted(redacting:)`) | 11 |
| `ObserverLogHandler` (event delivery, thread-safety, multiplex) | 6 |
| `PrefixedStreamLogHandler` (formatting, custom streams) | 5 |
| `String+Extension` (header parsing, JSON conversion) | 5 |
| `LoggingMiddleware` (client + server intercept paths) | 4 |
| `LoggingMiddleware: client + server semantics` (gap-fillers: events, body policy at middleware level, single-pass body re-wrap) | 5 |
| `JSONFileLogHandler` (writes to user-supplied URL, intermediate dir creation, Linux-friendly default path) | 3 |
| `LoggingMiddleware: adversarial / robustness` (no-Authorization no-op, Cookie/Set-Cookie default redaction, repeated headers, custom set, body re-wrap, oversize body truncation, 200/500-fold concurrent stress, 1 MB header value) | 9 |
| `Date` / time formatting | 2 |
| Public API surface (visibility + Sendable conformance) | 2 |

Run with `swift test`.

CI runs the suite on macOS and on Linux (Swift 6.0 container).

## License

Apache 2.0 — see [LICENSE](LICENSE).
