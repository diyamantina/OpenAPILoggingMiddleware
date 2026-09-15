# OpenAPILoggingMiddleware

[![Linux](https://github.com/diyamantina/OpenAPILoggingMiddleware/actions/workflows/linux.yml/badge.svg)](https://github.com/diyamantina/OpenAPILoggingMiddleware/actions/workflows/linux.yml)
[![Apple](https://github.com/diyamantina/OpenAPILoggingMiddleware/actions/workflows/apple.yml/badge.svg)](https://github.com/diyamantina/OpenAPILoggingMiddleware/actions/workflows/apple.yml)
![Swift 6.0+](https://img.shields.io/badge/Swift-6.0+-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-macOS%2013+%20%7C%20iOS%2016+%20%7C%20Linux-blue.svg)

Request and response logging middleware for Swift OpenAPI clients and servers.

`OpenAPILoggingMiddleware` conforms to both OpenAPI client and server
middleware protocols, so the same package can log generated client calls,
generated server handlers, or both. It supports bounded body capture, default
credential-header redaction, and several bundled log handlers for stream, JSON
file, OSLog, and observer-based pipelines.

Use it when you need:

- Debuggable OpenAPI traffic on the client, server, or both.
- Request and response metadata without leaking bearer tokens or cookies.
- Optional body logging with a byte cap.
- A testable observer hook for dashboards, integration tests, or live tooling.

## Installation

```swift
.package(url: "https://github.com/diyamantina/OpenAPILoggingMiddleware", from: "1.3.0"),
```

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "OpenAPILoggingMiddleware", package: "OpenAPILoggingMiddleware"),
    ]
),
```

## Quick Start

```swift
import OpenAPILoggingMiddleware
import OpenAPIAsyncHTTPClient

let logging = LoggingMiddleware(appName: "MyAPI", logPrefix: "client ")

let client = Client(
    serverURL: serverURL,
    transport: AsyncHTTPClientTransport(),
    middlewares: [logging]
)
```

Use the same middleware type on the generated server side:

```swift
try handler.registerHandlers(
    on: transport,
    serverURL: try Servers.Server1.url(),
    middlewares: [LoggingMiddleware(appName: "MyAPI", logPrefix: "server ")]
)
```

The default logger writes stream output, appends JSON records to a temporary
file, and uses OSLog on Apple platforms.

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

| Parameter | Default | Purpose |
|---|---|---|
| `logger` | default multiplex logger | Pass your own `Logger` to route events to custom log handlers. |
| `bodyLoggingConfiguration` | `.upTo(maxBytes: 2 MiB)` | Controls whether request/response bodies are logged and how much is captured. |
| `appName` | `nil` | Used to derive the JSON log file name. |
| `logPrefix` | `""` | Prepended to emitted log lines. Useful for distinguishing client and server instances. |
| `requestLogLevel` | `.debug` | Log level for request entries. |
| `responseLogLevel` | `.debug` | Log level for response entries. |
| `errorLogLevel` | `.error` | Log level when the next middleware or transport throws. |
| `redactedHeaderFields` | auth and cookie headers | Header names whose values are replaced by `"<redacted>"` before logging. |

## Header Redaction

The default redaction set covers:

- `Authorization`
- `Proxy-Authorization`
- `Cookie`
- `Set-Cookie`

```swift
// Default credential-header redaction.
let normal = LoggingMiddleware(appName: "api")

// Extend the default set.
let strict = LoggingMiddleware(
    appName: "api",
    redactedHeaderFields: LoggingMiddleware.defaultRedactedHeaderFields
        .union([HTTPField.Name("X-Api-Key")!])
)

// Disable redaction. Avoid this in production.
let unsafe = LoggingMiddleware(appName: "api", redactedHeaderFields: [])
```

Use `HTTPFields.redacted(redacting:)` when your own logging code needs the same
scrubbing behavior.

## Body Logging

`BodyLoggingPolicy` decides how request and response bodies are handled:

| Policy | Behavior |
|---|---|
| `.never` | Redacts every body. |
| `.upTo(maxBytes:)` | Logs bodies up to the cap. Oversized bodies are summarized as `<N bytes>`. |

When the middleware consumes a body to log it, it re-wraps the bytes in a fresh
`HTTPBody` before forwarding. Downstream middleware and handlers still receive a
readable body.

## Bundled Log Handlers

| Handler | Purpose |
|---|---|
| `PrefixedStreamLogHandler` | Writes readable metadata lines to stdout or another `TextOutputStream`. |
| `JSONFileLogHandler` | Appends one structured JSON record per request to a file. |
| `OSLogHandler` | Forwards events to Apple's unified logging system. Apple platforms only. |
| `ObserverLogHandler` | Sends every log event to a closure for dashboards, tests, WebSocket streams, or analytics hooks. |

Pass a custom `Logger` when you want to compose your own handler stack with
`Logging.MultiplexLogHandler`.

## Companion Packages

- [`BearerTokenAuthMiddleware`](https://github.com/diyamantina/BearerTokenAuthMiddleware)
  stamps bearer tokens on generated OpenAPI clients and enforces bearer tokens
  in Vapor servers.
- [`ClientIpMiddleware`](https://github.com/diyamantina/ClientIpMiddleware)
  captures client IP and user-agent context for generated OpenAPI handlers.

## Platform Support

| Platform | CI coverage |
|---|---|
| macOS 13+ | `swift build` and `swift test` |
| Linux, Swift 6.0 container | `swift build` and `swift test` |
| iOS 16+ | `xcodebuild build` for iOS Simulator |
| tvOS 16+ | `xcodebuild build` for tvOS Simulator |
| watchOS 9+ | `xcodebuild build` for watchOS Simulator |

`OSLogHandler` is Apple-only. Linux consumers can compose
`PrefixedStreamLogHandler`, `JSONFileLogHandler`, and `ObserverLogHandler`.

## Documentation

DocC is enabled:

```bash
swift package --allow-writing-to-directory ./docs generate-documentation \
    --target OpenAPILoggingMiddleware \
    --output-path ./docs/OpenAPILoggingMiddleware.doccarchive
```

## Testing

The package ships with **74 tests across 12 suites** covering:

- Client and server intercept paths.
- Header redaction.
- Body logging policy behavior and single-pass body re-wrapping.
- Stream, JSON file, OSLog-adjacent, and observer handler behavior.
- Concurrent request stress cases and malformed input handling.
- Public API and `Sendable` conformance checks.

Run them with:

```bash
swift test
```

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup,
style, and PR expectations. Security issues should be reported privately; see
[SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE](LICENSE).
