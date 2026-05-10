import Foundation

/// Cross-platform state-protecting lock used by ``ObserverLogHandler`` to
/// guard its mutable bookkeeping (`logLevel`, `metadata`).
///
/// On Apple platforms the implementation aliases to
/// `os.OSAllocatedUnfairLock<State>` — Apple's recommended low-cost
/// non-recursive lock that owns its protected state, so callers can't forget
/// to lock; every access goes through `withLock { ... }`.
///
/// On non-Apple platforms (Linux deployments) the same surface is provided by
/// a small `NSLock`-backed class. The semantics match: a non-recursive mutex
/// guarding owned state, with a `withLock` API. swift-corelibs-foundation
/// ships `NSLock`, so this works under Vapor-on-Linux without an extra
/// dependency.
///
/// The handler protocol is sync, so we never hold this lock across an `await`;
/// the implementations don't need to be reentrant or fair.
#if canImport(os)
import struct os.OSAllocatedUnfairLock

typealias StateLock<State: Sendable> = OSAllocatedUnfairLock<State>
#else
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
