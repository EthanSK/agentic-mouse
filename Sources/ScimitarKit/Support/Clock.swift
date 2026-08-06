import Foundation

/// Monotonic time source. Injected everywhere so timeout, debounce, hold and
/// rate-limit behaviour can be tested deterministically without sleeping.
public protocol MonotonicClock: AnyObject {
    /// Seconds since an arbitrary fixed origin. Never goes backwards and is
    /// unaffected by wall-clock adjustments.
    var now: TimeInterval { get }
}

public final class SystemMonotonicClock: MonotonicClock {
    public init() {}

    public var now: TimeInterval {
        // `uptimeNanoseconds` is mach_absolute_time based: monotonic, and it
        // does not advance while the machine is asleep, which is exactly the
        // behaviour we want for input timeouts.
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }
}

/// Test clock. Advance it by hand.
public final class ManualClock: MonotonicClock {
    private var value: TimeInterval

    public init(now: TimeInterval = 0) {
        self.value = now
    }

    public var now: TimeInterval { value }

    @discardableResult
    public func advance(by interval: TimeInterval) -> TimeInterval {
        value += interval
        return value
    }

    public func set(_ newValue: TimeInterval) {
        value = newValue
    }
}

/// Repeating timer abstraction so the coordinator's tick loop can be driven by
/// tests instead of a run loop.
public protocol TickScheduler: AnyObject {
    func start(interval: TimeInterval, handler: @escaping () -> Void)
    func stop()
    var isRunning: Bool { get }
}

public final class DispatchTickScheduler: TickScheduler {
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    public var isRunning: Bool { timer != nil }

    public func start(interval: TimeInterval, handler: @escaping () -> Void) {
        stop()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(5))
        source.setEventHandler(handler: handler)
        source.resume()
        timer = source
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit { timer?.cancel() }
}

/// Test scheduler: records the interval and fires only when told to.
public final class ManualTickScheduler: TickScheduler {
    public private(set) var interval: TimeInterval?
    private var handler: (() -> Void)?

    public init() {}

    public var isRunning: Bool { handler != nil }

    public func start(interval: TimeInterval, handler: @escaping () -> Void) {
        self.interval = interval
        self.handler = handler
    }

    public func stop() {
        handler = nil
        interval = nil
    }

    public func fire(times: Int = 1) {
        for _ in 0..<times { handler?() }
    }
}
