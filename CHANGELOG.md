# Changelog

All notable changes to this project will be documented in this file. Earlier
releases are reconstructed from git history; the entries from 1.2.0 onward are
authoritative going forward.

## [1.3.1] — 2026-06-02

No library code or public API changed in this release; `Sources/` and
`Package.swift` are identical to 1.3.0. Repository and documentation only.

### Added
- Community health files: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`
  (Contributor Covenant 2.1), `SECURITY.md`, GitHub issue forms
  (bug report / feature request) with a config that routes security reports to
  the private advisory flow, and a pull-request template.

### Changed
- CI is split into dedicated `Linux` and `Apple` workflows (previously one
  combined `test` workflow), each with its own status badge in the README.

### Fixed
- README license section corrected from "Apache 2.0" to **MIT**, matching the
  `LICENSE` file (which has always been MIT).

## [1.3.0] — 2026-05-10

### Added
- **Cross-platform `StateLock`.** Aliases `os.OSAllocatedUnfairLock` on Apple
  platforms and falls back to an `NSLock`-backed shim on Linux, exposing the
  same `withLock(_:)` surface so handlers stay thread-safe everywhere.
- **Header redaction.** A default set of sensitive headers (`Authorization`,
  `Cookie`, `Set-Cookie`) is redacted in logs, with `redacted(redacting:)` on
  `HTTPFields` and a configurable redaction set.
- **Adversarial / robustness test suite** (+9 tests) plus gap-filler suites,
  bringing the package to 74 tests across 12 suites.
- **Five-platform CI** covering Linux, macOS, iOS, tvOS, and watchOS.

### Changed
- Explicit `#if os(...)` / `#if canImport(...)` gating in `OSLogHandler` and
  `LoggingMiddleware`; expanded declared platform support.
- `JSONFileLogHandler` writes to a user-supplied URL, creates intermediate
  directories, and uses a Linux-friendly default path.

### Fixed
- Response-headers logging path, single-pass body re-wrap, and oversize body
  truncation.

## [1.2.2] — 2026-04-27

### Fixed
- **`ObserverLogHandler` is now thread-safe.** Mutable state (`logLevel`,
  `metadata`) is guarded by an `OSAllocatedUnfairLock<State>`. The previous
  `nonisolated(unsafe) var metadata: Logger.Metadata = [:]` raced its
  copy-on-write buffer under concurrent writes and crashed the host process
  with `SIGABRT` from libmalloc's "pointer being freed was not allocated"
  guard. Reproducible whenever the handler was shared across threads —
  typically when wired into `LoggingSystem.bootstrap` so multiple `Logger`s
  with the same label fanned into the same handler instance — and the host
  served concurrent OpenAPI traffic. The `nonisolated(unsafe)` annotations on
  the storage are gone; the lock owns the state.
  ([#5](https://github.com/diyamantina/OpenAPILoggingMiddleware/issues/5))

### Added
- Concurrency stress tests:
  - `ObserverLogHandlerTests.concurrentMetadataIsRaceFree` — 64 tasks × 500 ops
    mixing subscript writes, full `metadata` replacement, and `log(...)` calls.
  - `ObserverLogHandlerTests.concurrentSubscriptSetters` — 32 tasks × 1000 ops
    focused on the subscript-setter path at the top of the production trace.
  - `IntegrationTests.concurrentInterceptsAcrossSharedObserver` — 32 tasks × 50
    `LoggingMiddleware.intercept` calls flowing through one shared
    `ObserverLogHandler`. End-to-end reproduction of the production crash.

### Notes
- Full incident write-up:
  [`docs/incidents/2026-04-27-observerloghandler-thread-safety.md`](docs/incidents/2026-04-27-observerloghandler-thread-safety.md).

## [1.2.1] — 2026-04-24

### Fixed
- `HTTPFields`: do not trap on duplicate header names. Previous behaviour
  preconditioned that header names were unique; in practice clients send
  multi-valued headers (e.g. `Set-Cookie`, `X-Forwarded-For`) and the trap
  killed otherwise-valid request logging. ([#4])

### Docs
- README updated for the v1.2.0 surface (public handlers, `ObserverLogHandler`,
  per-event levels).

## [1.2.0] — 2026-04-20

### Added
- **`ObserverLogHandler`** — pluggable handler that forwards every log event to
  a user-supplied closure. Useful for wiring log activity into admin
  dashboards, WebSocket broadcasts, analytics pipelines, or test harnesses.
- **Per-event log levels**: `requestLogLevel`, `responseLogLevel`, and
  `errorLogLevel` are configurable on `LoggingMiddleware` independently.
- All four built-in handlers (plus the new `ObserverLogHandler`) are now
  `public` so consumers can compose their own `Logger` via
  `MultiplexLogHandler`. ([#2])

### Internal
- Replaced the in-package multiplex shim with swift-log's stock
  `MultiplexLogHandler`.
- Comprehensive test suite landed: 30 tests across 6 suites.

## [1.1.2] — 2026-03-17

### Internal
- Added the comprehensive test suite as a separate release on top of 1.1.1.

## [1.1.1] — 2026-03-17

### Fixed
- `StreamLogHandler`: replaced `fputs(..., stdout)` with `print(...)` for Swift
  6 strict-concurrency safety. The C-level write was not Sendable-clean and
  produced warnings under stricter checking.

## [1.1.0] — 2025-10-19

### Added
- OSLog handler integration (Apple unified logging).
- Internal serial queue for ordering log writes.

### Docs
- README: badges + clarified usage.

## [1.0.0] — 2025-10-16

Initial public release. Console / file / OSLog handlers, dual-parameter
`appName` + `logPrefix` system, Client- and Server-side `intercept`
implementations.

[#2]: https://github.com/diyamantina/OpenAPILoggingMiddleware/pull/2
[#4]: https://github.com/diyamantina/OpenAPILoggingMiddleware/pull/4
