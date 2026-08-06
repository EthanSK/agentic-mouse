import Foundation

public enum InputTransportError: Error, Equatable {
    case accessibilityPermissionMissing
    case eventTapCreationFailed
    case sessionNotConnected
    case deviceNotSelected
    /// The device did not report the full set of macro keys we need.
    case macroKeysUnavailable(expected: Int, found: Int)
    /// `CorsairRequestControl` refused. Raw SDK code included.
    case keyControlRefused(code: Int32)
    /// One or more `CorsairConfigureKeyEvent` calls failed; everything already
    /// configured has been rolled back before this is thrown.
    case interceptionIncomplete(configured: Int, failedKey: Int, code: Int32)
    case notAvailable(String)
}

/// Result of the pre-entry readiness check.
///
/// Multi-tap mode fails **closed**: unless every precondition is satisfied, the
/// mode is not entered, the HUD is not shown, and the mouse lighting is not
/// changed. A half-entered mode is the one outcome that could strand the mouse
/// in a state the user cannot escape, so it is never allowed to exist.
public enum InputTransportReadiness: Equatable {
    case ready
    case notReady([String])

    public var isReady: Bool { self == .ready }

    public var reasons: [String] {
        if case .notReady(let reasons) = self { return reasons }
        return []
    }

    public static func combine(_ results: [InputTransportReadiness]) -> InputTransportReadiness {
        let reasons = results.flatMap(\.reasons)
        return reasons.isEmpty ? .ready : .notReady(reasons)
    }
}

/// Delivers physical button events and, transactionally, takes them away from
/// their normal handlers.
///
/// The interception contract is deliberately strict:
///
///  * `beginInterception()` is all-or-nothing. Either every key in the grid is
///    intercepted, or the transport is left exactly as it was and the call
///    throws. There is no partial state.
///  * `endInterception()` never throws and is idempotent. It undoes every step
///    that `beginInterception()` performed, in reverse order.
///  * If the process dies, iCUE observes the client disappearing and restores
///    the device to shared access on its own, so even `SIGKILL` cannot strand
///    the mouse.
public protocol InputTransport: AnyObject {
    var delegate: InputTransportDelegate? { get set }
    var name: String { get }
    var isRunning: Bool { get }
    var isInterceptionEnabled: Bool { get }

    /// Starts observing. Does **not** intercept anything.
    func start() throws
    /// Stops observing and guarantees interception is undone first.
    func stop()

    /// Everything that must be true before the mode may be entered.
    func preflight() -> InputTransportReadiness

    /// Takes exclusive ownership of the grid buttons. All-or-nothing.
    func beginInterception() throws
    /// Returns the grid buttons to their normal behaviour. Idempotent.
    func endInterception()
}

public protocol InputTransportDelegate: AnyObject {
    func inputTransport(_ transport: InputTransport, didReceive event: PhysicalInputEvent)
    /// The transport lost its ability to observe or intercept: iCUE session
    /// dropped, the mouse disconnected, the tap was disabled, permission was
    /// revoked. The coordinator responds by leaving multi-tap mode at once.
    func inputTransport(_ transport: InputTransport, didFailWith error: Error)
}

// MARK: - Test double

/// Fully synthetic transport. Records the exact interception lifecycle so tests
/// can prove that every failure path still ends in a released mouse.
public final class SimulatedInputTransport: InputTransport {
    public enum LifecycleEvent: Equatable {
        case started
        case stopped
        case interceptionBegan
        case interceptionEnded
        case interceptionFailed
    }

    public weak var delegate: InputTransportDelegate?
    public var name: String { "simulated" }
    public private(set) var isRunning = false
    public private(set) var isInterceptionEnabled = false
    public private(set) var lifecycle: [LifecycleEvent] = []

    public var startError: Error?
    public var beginInterceptionError: Error?
    public var readiness: InputTransportReadiness = .ready

    private let clock: MonotonicClock

    public init(clock: MonotonicClock = SystemMonotonicClock()) {
        self.clock = clock
    }

    public func start() throws {
        if let startError { throw startError }
        isRunning = true
        lifecycle.append(.started)
    }

    public func stop() {
        endInterception()
        isRunning = false
        lifecycle.append(.stopped)
    }

    public func preflight() -> InputTransportReadiness { readiness }

    public func beginInterception() throws {
        if let beginInterceptionError {
            // Contract: a failed begin leaves nothing behind.
            isInterceptionEnabled = false
            lifecycle.append(.interceptionFailed)
            throw beginInterceptionError
        }
        isInterceptionEnabled = true
        lifecycle.append(.interceptionBegan)
    }

    public func endInterception() {
        guard isInterceptionEnabled else { return }
        isInterceptionEnabled = false
        lifecycle.append(.interceptionEnded)
    }

    // MARK: Simulation helpers

    public func simulate(
        _ binding: InputBinding,
        phase: PhysicalInputEvent.Phase,
        at timestamp: TimeInterval? = nil
    ) {
        delegate?.inputTransport(
            self,
            didReceive: PhysicalInputEvent(binding: binding, phase: phase, timestamp: timestamp ?? clock.now)
        )
    }

    public func simulateTap(_ binding: InputBinding, at timestamp: TimeInterval? = nil) {
        let stamp = timestamp ?? clock.now
        simulate(binding, phase: .press, at: stamp)
        simulate(binding, phase: .release, at: stamp)
    }

    public func simulateKey(_ key: MultiTapKey, phase: PhysicalInputEvent.Phase, at timestamp: TimeInterval? = nil) {
        simulate(.icueMacroKey(key.rawValue), phase: phase, at: timestamp)
    }

    public func simulateFailure(_ error: Error) {
        delegate?.inputTransport(self, didFailWith: error)
    }
}
