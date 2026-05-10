import Foundation

/// Cross-platform state-protecting lock used by ``ObserverLogHandler`` to
/// guard its mutable bookkeeping (`logLevel`, `metadata`).
///
/// Per-platform mapping:
///
/// - **macOS** / **iOS** / **tvOS** / **watchOS**: aliases to
///   `os.OSAllocatedUnfairLock<State>` — Apple's recommended low-cost
///   non-recursive lock that owns its protected state. Callers can't forget
///   to lock; every access goes through `withLock { ... }`. The
///   `os_unfair_lock` underneath is a plain non-recursive mutex.
/// - **Linux** (and any other non-Apple platform): an `NSLock`-backed class
///   with the same surface. swift-corelibs-foundation ships `NSLock`, so
///   this works under Vapor-on-Linux without an extra dependency.
///
/// The handler protocol is sync, so we never hold this lock across an
/// `await`; the implementations don't need to be reentrant or fair.
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import struct os.OSAllocatedUnfairLock

typealias StateLock<State: Sendable> = OSAllocatedUnfairLock<State>

#elseif os(Linux)

final class StateLock<State: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: State

    init(initialState: State) {
        self._state = initialState
    }

    @discardableResult
    func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&_state)
    }
}

#else

// Defensive fallback for any future Swift platform we haven't qualified yet
// (FreeBSD, Windows server, etc.). Same NSLock-backed implementation as
// Linux — Foundation's `NSLock` is required by the protocol on every
// platform that ships swift-corelibs-foundation.
final class StateLock<State: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: State

    init(initialState: State) {
        self._state = initialState
    }

    @discardableResult
    func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&_state)
    }
}

#endif
