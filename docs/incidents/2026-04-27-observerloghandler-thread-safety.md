# Incident: `ObserverLogHandler` heap corruption under concurrent metadata writes

- **Date observed**: 2026-04-26 → 2026-04-27 (5 crash reports in 24h)
- **Affected versions**: `OpenAPILoggingMiddleware` ≤ 1.2.1
- **Affected hosts**: Apple-platform Vapor servers using
  `LoggingSystem.bootstrap` to fan log events into an `ObserverLogHandler` for
  a live admin dashboard. Linux unaffected only because the Linux build wasn't
  exercising this code path at the same load.
- **Symptom**: process killed by `SIGABRT`, `EXC_CRASH (Code Signature Invalid)`
  paths *not* involved. macOS crash reports show:

  ```
  __pthread_kill
  pthread_kill
  abort
  malloc_vreport
  malloc_report
  ___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED
  _swift_release_dealloc
  swift::RefCounts<…>::doDecrementSlow
  _NativeDictionary._copyOrMoveAndResize(capacity:moveElements:)
  _NativeDictionary.ensureUnique(isUnique:capacity:)
  _NativeDictionary.mutatingFind(_:isUnique:)
  _NativeDictionary.setValue(_:forKey:isUnique:)
  Dictionary._Variant.setValue(_:forKey:)
  Dictionary.subscript.setter
  ObserverLogHandler.subscript.setter ObserverLogHandler.swift:76
  ```

## Root cause

`ObserverLogHandler` stored its log-level and metadata as plain stored
properties marked `nonisolated(unsafe)`:

```swift
nonisolated(unsafe) private var _logLevel: Logger.Level = .info
nonisolated(unsafe) public var metadata: Logger.Metadata = [:]

public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }   // ← line 76 in the crash trace
}
```

`nonisolated(unsafe)` is a Swift-6 escape hatch that tells the compiler
"trust me, this access is safe." The compiler stops checking — it does not
add any synchronisation. The annotation is **only** appropriate for storage
that is in fact protected by something else (a lock, an actor's executor,
an external synchronisation contract). On `ObserverLogHandler`, nothing was
protecting the dictionary.

`swift-log`'s `LogHandler` API is fully synchronous and explicitly designed
to be called from any thread. In practice:

- Vapor's per-request logger forwards every request through the same
  underlying handler (the `LoggingSystem.bootstrap` factory caches handlers
  by label).
- `MultiplexLogHandler` propagates `metadata` and `subscript(metadataKey:)`
  writes to **every** wrapped handler. Any code that sets a top-level
  Logger's metadata cascades into every multiplexed handler — including
  the shared `ObserverLogHandler`.
- The OpenAPI runtime + bodies of work spawned from
  `LoggingMiddleware.intercept(...)` run concurrently across NIO event
  loops and Swift Concurrency tasks.

So under load, dozens of threads can be assigning into the same
`Dictionary` storage at the same instant. `Swift.Dictionary` is **not**
thread-safe; concurrent mutation interleaves at the level of the buffer's
internal references. `_NativeDictionary._copyOrMoveAndResize` is the
copy-on-write resize step that runs whenever the buffer needs to grow or
become uniquely owned. Two threads racing through that path can both
believe they own the buffer, both call `_swift_release_dealloc` on the
old one, and the second free hits libmalloc's "pointer being freed was
not allocated" guard → `SIGABRT`.

This is a textbook double-free / use-after-free, not a logic bug. The
specific stack frame in the crash report points at
`subscript.setter` because that's the most common entry point for writes,
but assignment to `metadata` directly, the `log(...)` method's read of
`self.metadata`, and the handler-level `logLevel` setter all sat on the
same storage and were equally exposed.

## Why now and not before

The package shipped with this code path since `1.2.0`. The race had
always been there. Two recent changes pushed contention high enough to
trip it reliably:

1. The downstream g2xi project switched its `ApiClient` `LoggingMiddleware`
   instance from the package's own default logger (which used
   `JSONFileLogHandler` — a per-instance, never-shared sink) to
   `Logger(label: "OpenAPI")`. That label resolves through
   `LoggingSystem.bootstrap`'s factory, which fans into a
   `MultiplexLogHandler` containing one shared `ObserverLogHandler` —
   so every API call now flows through that one handler.
2. Production traffic on the admin server (a Mac mini behind ngrok)
   started seeing real concurrent iOS clients. Multiple in-flight
   requests = multiple threads stamping metadata on the same handler.

The combination took crashes from "rare and hard to reproduce" to
"every few minutes under load". 5 crash reports in the first 24h.

## Fix

`Sources/OpenAPILoggingMiddleware/ObserverLogHandler.swift` was rewritten
to put all mutable state behind an `OSAllocatedUnfairLock<State>`:

```swift
import struct os.OSAllocatedUnfairLock

private struct State {
    var logLevel: Logger.Level = .info
    var metadata: Logger.Metadata = [:]
}
private let state = OSAllocatedUnfairLock<State>(initialState: State())

public var metadata: Logger.Metadata {
    get { state.withLock { $0.metadata } }
    set { state.withLock { $0.metadata = newValue } }
}

public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
    get { state.withLock { $0.metadata[key] } }
    set { state.withLock { $0.metadata[key] = newValue } }
}

public func log(level: …, metadata: …, …) {
    let snapshot = state.withLock { $0.metadata }    // snapshot under lock
    let merged = snapshot.merging(metadata ?? [:]) { _, new in new }
    …
    observe(Event(…))                                // observer outside lock
}
```

Why `OSAllocatedUnfairLock<State>` rather than `NSLock`:

- It owns the state — callers can't forget to lock or pair the wrong
  `lock()`/`unlock()` calls. The compiler enforces "you only touch state
  through `withLock`".
- Apple recommends it as the Swift-native primitive for this shape on
  macOS 13+ / iOS 16+, which match this package's deployment targets.
- `os_unfair_lock` is the fastest non-recursive mutex on Apple platforms.
- It conforms to `Sendable`, which lets us drop the
  `nonisolated(unsafe)` annotations on the storage entirely.
- Submodule import (`import struct os.OSAllocatedUnfairLock`) avoids
  pulling in `os.Logger`, which would otherwise shadow `Logging.Logger`
  (swift-log).

`log(...)` snapshots `metadata` under the lock and drops it before
invoking the user's `observe` closure. The lock is never held across an
`await` (the API is sync) nor across user code (the closure is allowed
to do anything, including re-entering the handler).

## Tests added

Two stress tests in
`Tests/OpenAPILoggingMiddlewareTests/ObserverLogHandlerTests.swift`:

- **"Concurrent metadata mutations do not crash the heap"** — 64 tasks
  × 500 ops each (~32k operations), mixing subscript writes, full
  `metadata` replacement, and `log(...)` calls on a shared handler.
  Exercises the exact code path from the crash trace.
- **"Concurrent subscript setters do not corrupt the metadata
  dictionary"** — 32 tasks × 1000 ops each, focused only on the
  subscript-setter path that appears at the top of the production
  trace.

Both pass on the fix; both reliably reproduce the `SIGABRT` against the
unpatched `1.2.1`.

## Release

- Tag `1.2.2` from `fix/observer-log-handler-thread-safety`.
- Bump downstream consumers' `Package.swift` from `from: "1.2.1"` to
  `from: "1.2.2"`.

## Lessons

- **`nonisolated(unsafe)` is a load-bearing assertion.** It must be
  paired with an external synchronisation mechanism. Anywhere it appears
  in the codebase deserves a comment explaining what protects the
  storage.
- A passing build under Swift 6 strict concurrency does **not** prove
  thread safety — it only proves the compiler accepts the unsafe
  annotation. Concurrency stress tests are the only way to catch this
  shape of bug.
- The crash was invisible until usage went from "one process per
  Logger" to "many concurrent producers per Logger". When public API
  goes from a controlled internal sink to a fan-out hub, the contract
  changes — re-audit every container that was previously assumed to be
  single-writer.
