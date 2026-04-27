# Changelog

All notable changes to this project will be documented in this file. Earlier
releases are reconstructed from git history; the entries from 1.2.0 onward are
authoritative going forward.

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
  ([#5](https://github.com/mihaelamj/OpenAPILoggingMiddleware/issues/5))

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

[#2]: https://github.com/mihaelamj/OpenAPILoggingMiddleware/pull/2
[#4]: https://github.com/mihaelamj/OpenAPILoggingMiddleware/pull/4
