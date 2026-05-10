# OpenAPILoggingMiddleware

![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-macOS%2013+%20%7C%20iOS%2016+-blue.svg)

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
    errorLogLevel: Logger.Level = .error
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
| `JSONFileLogHandler` | Appends a structured JSON record per request to a file. Suitable for low-to-moderate volume. |
| `OSLogHandler` | Forwards to Apple's unified logging system. Apple platforms only. |
| `ObserverLogHandler` | Forwards every log event to a user-supplied closure. Pipe to admin dashboards, WebSocket broadcasts, analytics pipelines, or test harnesses. Thread-safe since 1.2.2 (`OSAllocatedUnfairLock`-guarded). |

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

## Testing

The package ships with **48 tests across 9 suites**:

| Area | Tests |
|---|---|
| `BodyLoggingPolicy` (process / never / upTo / BodyLog) | 11 |
| Integration: `LoggingMiddleware` + `ObserverLogHandler` (concurrency, full intercept paths) | 7 |
| `HTTPFields+Extension` (toArrayString / toDictionary / toJSONString) | 6 |
| `ObserverLogHandler` (event delivery, thread-safety, multiplex) | 6 |
| `PrefixedStreamLogHandler` (formatting, custom streams) | 5 |
| `String+Extension` (header parsing, JSON conversion) | 5 |
| `LoggingMiddleware` (client + server intercept paths) | 4 |
| `Date` / time formatting | 2 |
| Public API surface (visibility + Sendable conformance) | 2 |

Run with `swift test`.

## License

Apache 2.0 — see [LICENSE](LICENSE).
