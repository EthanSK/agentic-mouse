import Foundation

/// The vendor can wait forever for an iCUE reply. Keep that wait off the input
/// thread, admit at most one call, and fail promptly while that call is stuck.
/// A timed-out operation owns its buffers until it actually returns.
final class ICUEVendorCallExecutor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.ethan.agentic-mouse.icue-calls")
    private let lock = NSLock()
    private var busy = false
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 0.2) { self.timeout = timeout }

    var isBusy: Bool {
        lock.lock(); defer { lock.unlock() }
        return busy
    }

    private final class Work<Value>: @unchecked Sendable {
        let operation: () -> Value
        let finished = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var value: Value?
        init(_ operation: @escaping () -> Value) { self.operation = operation }
        func run() {
            let result = operation()
            lock.lock(); value = result; lock.unlock()
        }
        func result(or fallback: Value) -> Value {
            lock.lock(); defer { lock.unlock() }
            return value ?? fallback
        }
    }

    func perform<Value>(fallback: Value, _ operation: @escaping () -> Value) -> Value {
        lock.lock()
        guard !busy else { lock.unlock(); return fallback }
        busy = true
        lock.unlock()
        let work = Work(operation)
        queue.async { [self, work] in
            work.run()
            lock.lock(); busy = false; lock.unlock()
            work.finished.signal()
        }
        guard work.finished.wait(timeout: .now() + timeout) == .success else { return fallback }
        return work.result(or: fallback)
    }
}
