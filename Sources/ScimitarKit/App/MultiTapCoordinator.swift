import Foundation

/// What the HUD needs to draw itself. Pure data.
public struct HUDSnapshot: Equatable, Sendable {
    public var isActive: Bool
    public var keymap: MultiTapKeymap
    public var state: MultiTapState
    public var multiTapTimeout: TimeInterval
    public var now: TimeInterval
    /// Populated when the mode could not be entered, or was force-exited.
    public var problem: String?

    public init(
        isActive: Bool,
        keymap: MultiTapKeymap,
        state: MultiTapState,
        multiTapTimeout: TimeInterval,
        now: TimeInterval,
        problem: String? = nil
    ) {
        self.isActive = isActive
        self.keymap = keymap
        self.state = state
        self.multiTapTimeout = multiTapTimeout
        self.now = now
        self.problem = problem
    }
}

/// The HUD boundary. Injected so the whole coordinator can be tested with no
/// AppKit and no window server.
public protocol HUDPresenting: AnyObject {
    /// Shows the panel **without** activating the app or taking key focus.
    func show(_ snapshot: HUDSnapshot)
    func update(_ snapshot: HUDSnapshot)
    func hide()
    /// Briefly explains why the mode could not be entered.
    func flashProblem(_ message: String)
    var isVisible: Bool { get }
}

public final class RecordingHUDPresenter: HUDPresenting {
    public private(set) var isVisible = false
    public private(set) var showCount = 0
    public private(set) var hideCount = 0
    public private(set) var problems: [String] = []
    public private(set) var lastSnapshot: HUDSnapshot?

    public init() {}

    public func show(_ snapshot: HUDSnapshot) {
        isVisible = true
        showCount += 1
        lastSnapshot = snapshot
    }

    public func update(_ snapshot: HUDSnapshot) { lastSnapshot = snapshot }

    public func hide() {
        guard isVisible else { return }
        isVisible = false
        hideCount += 1
    }

    public func flashProblem(_ message: String) { problems.append(message) }
}

/// Why the mode ended. Drives what the user is told.
public enum ModeExitReason: Equatable, Sendable {
    case userRequested
    case idleTimeout
    case focusPolicy
    case transportFailure(String)
    case sessionLost
    case deviceLost
    case permissionLost
    case shuttingDown

    public var isFailure: Bool {
        switch self {
        case .userRequested, .idleTimeout, .shuttingDown, .focusPolicy: return false
        default: return true
        }
    }

    public var explanation: String {
        switch self {
        case .userRequested: return "Multi-tap mode off."
        case .idleTimeout: return "Multi-tap mode timed out."
        case .focusPolicy: return "Multi-tap mode ended because focus moved."
        case .transportFailure(let detail): return "Multi-tap mode ended: \(detail)"
        case .sessionLost: return "Multi-tap mode ended: iCUE disconnected."
        case .deviceLost: return "Multi-tap mode ended: the Scimitar disconnected."
        case .permissionLost: return "Multi-tap mode ended: Accessibility permission was revoked."
        case .shuttingDown: return "Multi-tap mode ended: quitting."
        }
    }
}

/// Owns the multi-tap mode lifecycle.
///
/// Entry is a transaction with a strict order, and *every* step must succeed
/// before the user sees anything change:
///
///   1. multi-tap enabled in config
///   2. Accessibility permission present
///   3. transport preflight: iCUE connected, exact device selected, all twelve
///      macro keys reported, event subscription healthy
///   4. `beginInterception()` — exclusive key events + all twelve keys claimed
///   5. only now: reset the engine, show the HUD, apply mode lighting
///
/// A text field is deliberately not an entry precondition: the user may enter
/// the mode and then focus a destination. The initial HUD snapshot shows the
/// current target refusal, and the engine emits no text until a target is safe.
///
/// If any step fails, nothing before it is left half-applied: the HUD is not
/// shown, the lighting is untouched, interception is rolled back, and the user
/// is told exactly which precondition failed.
///
/// Exit runs the same list backwards and is used for *every* ending — the user
/// pressing button 12, an idle timeout, iCUE dropping, the mouse sleeping,
/// permission being revoked, or the app quitting.
public final class MultiTapCoordinator {
    public private(set) var isActive = false

    private let engine: MultiTapEngine
    private let transport: InputTransport
    private let textOutput: TextOutput
    private let targetResolver: TextTargetResolving
    private let permission: AccessibilityPermissionChecking
    private let hud: HUDPresenting
    private let clock: MonotonicClock
    private let scheduler: TickScheduler
    private let log: Log

    private let toggleKey: MultiTapKey
    private let autoExitAfterIdle: TimeInterval
    private let toggleDebounce: TimeInterval
    private let tickInterval: TimeInterval

    private var lastToggleAt: TimeInterval = -.greatestFiniteMagnitude
    private var lastInputAt: TimeInterval = 0
    /// Activation id; a tick or release from a previous activation is ignored.
    private var activationGeneration: UInt64 = 0

    /// Called when the mode turns on or off, so lighting can follow.
    public var onModeChange: ((Bool) -> Void)?
    /// Called when an entry attempt is refused, with the list of reasons.
    public var onEntryRefused: (([String]) -> Void)?
    public var onExit: ((ModeExitReason) -> Void)?

    public init(
        engine: MultiTapEngine,
        transport: InputTransport,
        textOutput: TextOutput,
        targetResolver: TextTargetResolving,
        permission: AccessibilityPermissionChecking,
        hud: HUDPresenting,
        clock: MonotonicClock,
        scheduler: TickScheduler,
        log: Log,
        toggleKey: MultiTapKey = .k12,
        autoExitAfterIdle: TimeInterval = 180,
        toggleDebounce: TimeInterval = 0.25,
        tickInterval: TimeInterval = 1.0 / 30.0
    ) {
        self.engine = engine
        self.transport = transport
        self.textOutput = textOutput
        self.targetResolver = targetResolver
        self.permission = permission
        self.hud = hud
        self.clock = clock
        self.scheduler = scheduler
        self.log = log
        self.toggleKey = toggleKey
        self.autoExitAfterIdle = autoExitAfterIdle
        self.toggleDebounce = toggleDebounce
        self.tickInterval = tickInterval
    }

    deinit {
        // A coordinator can never be deallocated while still holding the mouse.
        if isActive { forceExit(reason: .shuttingDown) }
    }

    // MARK: - Entry / exit

    /// Everything that must be true before the mode may be entered.
    public func preflight() -> InputTransportReadiness {
        var reasons: [String] = []
        if !permission.isTrusted {
            reasons.append("Accessibility permission is not granted.")
        }
        let transportReadiness = transport.preflight()
        reasons.append(contentsOf: transportReadiness.reasons)
        return reasons.isEmpty ? .ready : .notReady(reasons)
    }

    @discardableResult
    public func enter() -> Bool {
        guard !isActive else { return true }

        let readiness = preflight()
        guard readiness.isReady else {
            // Fail closed. Nothing is shown, nothing is intercepted, no
            // lighting changes — the mouse behaves exactly as it did.
            log.notice("multi-tap entry refused: \(readiness.reasons.joined(separator: " "))")
            onEntryRefused?(readiness.reasons)
            hud.flashProblem(readiness.reasons.first ?? "Multi-tap mode is unavailable.")
            return false
        }

        do {
            try transport.beginInterception()
        } catch {
            let description = Self.describe(error)
            log.error("multi-tap entry failed during interception: \(description)")
            // `beginInterception` guarantees full rollback before throwing, but
            // asking again costs nothing and removes all doubt.
            transport.endInterception()
            onEntryRefused?([description])
            hud.flashProblem(description)
            return false
        }

        // Past this point the transaction has committed.
        activationGeneration &+= 1
        engine.reset()
        _ = engine.tick(at: clock.now, target: targetResolver.resolveCurrentTarget())
        isActive = true
        lastInputAt = clock.now

        hud.show(snapshot())
        scheduler.start(interval: tickInterval) { [weak self] in self?.tick() }
        onModeChange?(true)
        log.info("multi-tap mode ON")
        return true
    }

    public func exit(reason: ModeExitReason = .userRequested) {
        guard isActive else { return }
        forceExit(reason: reason)
    }

    /// The single teardown path. Idempotent, non-throwing, and safe to call
    /// from any state — including from `deinit` and from failure handlers.
    private func forceExit(reason: ModeExitReason) {
        let wasActive = isActive
        isActive = false
        activationGeneration &+= 1

        scheduler.stop()
        // Any half-typed character is dropped rather than flushed: committing
        // it during a teardown could type into whatever ended up in front.
        engine.reset()
        transport.endInterception()
        hud.hide()

        if wasActive {
            onModeChange?(false)
            onExit?(reason)
            if reason.isFailure {
                log.notice("multi-tap mode OFF — \(reason.explanation)")
                hud.flashProblem(reason.explanation)
            } else {
                log.info("multi-tap mode OFF — \(reason.explanation)")
            }
        }
    }

    /// Called by the app delegate on quit, and by signal handling.
    public func shutdown() {
        forceExit(reason: .shuttingDown)
        transport.stop()
    }

    // MARK: - Input routing

    public func handle(_ event: PhysicalInputEvent) {
        guard let key = Self.key(for: event.binding) else { return }
        let now = clock.now

        // The toggle is handled outside the engine when the mode is off, so it
        // is the one button that works in both states.
        if key == toggleKey && !isActive {
            guard event.phase == .press else { return }
            guard now - lastToggleAt >= toggleDebounce else { return }
            lastToggleAt = now
            _ = enter()
            return
        }

        guard isActive else { return }
        lastInputAt = now

        if key == toggleKey && event.phase == .press {
            guard now - lastToggleAt >= toggleDebounce else { return }
            lastToggleAt = now
        }

        let resolution = targetResolver.resolveCurrentTarget()
        let outcome: MultiTapOutcome
        switch event.phase {
        case .press:
            outcome = engine.press(key, at: now, target: resolution)
        case .release:
            outcome = engine.release(key, at: now, target: resolution)
        }
        apply(outcome, reason: .userRequested)
    }

    /// Explicit focus-change notification from the workspace observer.
    public func handleFocusChange() {
        guard isActive else { return }
        let outcome = engine.focusChanged(at: clock.now, to: targetResolver.resolveCurrentTarget())
        apply(outcome, reason: .focusPolicy)
    }

    /// Transport-level failure: iCUE dropped, tap disabled, device gone.
    public func handleTransportFailure(_ error: Error) {
        guard isActive else { return }
        forceExit(reason: .transportFailure(Self.describe(error)))
    }

    public func handleSessionLost() { forceExit(reason: .sessionLost) }
    public func handleDeviceLost() { forceExit(reason: .deviceLost) }

    // MARK: - Tick

    private func tick() {
        guard isActive else { return }
        let generation = activationGeneration
        let now = clock.now

        // Permission can be revoked while the mode is running. Notice it here
        // rather than discovering it when a character fails to type.
        guard permission.isTrusted else {
            forceExit(reason: .permissionLost)
            return
        }

        if autoExitAfterIdle > 0, now - lastInputAt >= autoExitAfterIdle {
            forceExit(reason: .idleTimeout)
            return
        }

        let outcome = engine.tick(at: now, target: targetResolver.resolveCurrentTarget())
        // A tick scheduled before the last exit must not resurrect the mode.
        guard generation == activationGeneration, isActive else { return }
        apply(outcome, reason: .userRequested)
        hud.update(snapshot())
    }

    // MARK: - Outcome handling

    private func apply(_ outcome: MultiTapOutcome, reason: ModeExitReason) {
        if !outcome.textCommands.isEmpty, let target = outcome.textTarget {
            do {
                try textOutput.apply(outcome.textCommands, to: target)
            } catch TextOutputError.accessibilityPermissionMissing {
                forceExit(reason: .permissionLost)
                return
            } catch TextOutputError.targetChanged {
                forceExit(reason: .focusPolicy)
                return
            } catch {
                log.error("text output failed: \(Self.describe(error))")
            }
        }

        if outcome.exitRequested {
            forceExit(reason: outcome.focusExitRequested || reason == .focusPolicy ? .focusPolicy : .userRequested)
            return
        }

        if outcome.stateChanged, isActive {
            hud.update(snapshot())
        }
    }

    private func snapshot(problem: String? = nil) -> HUDSnapshot {
        HUDSnapshot(
            isActive: isActive,
            keymap: engine.keymap,
            state: engine.state,
            multiTapTimeout: engine.configuration.multiTapTimeout,
            now: clock.now,
            problem: problem
        )
    }

    static func key(for binding: InputBinding) -> MultiTapKey? {
        switch binding {
        case .icueMacroKey(let id):
            return MultiTapKey(rawValue: id)
        case .mouseButton, .keyCode:
            // The fallback transport maps its bindings before handing them over.
            return nil
        }
    }

    public static func describe(_ error: Error) -> String {
        switch error {
        case InputTransportError.accessibilityPermissionMissing:
            return "Accessibility permission is required."
        case InputTransportError.sessionNotConnected:
            return "iCUE is not connected."
        case InputTransportError.deviceNotSelected:
            return "No Scimitar is selected."
        case InputTransportError.macroKeysUnavailable(let expected, let found):
            return "The mouse reported \(found) of \(expected) side buttons."
        case InputTransportError.keyControlRefused(let code):
            return code == 7
                ? "iCUE has key interception disabled — enable it in iCUE's settings."
                : "iCUE refused key control (code \(code))."
        case InputTransportError.interceptionIncomplete(_, let key, let code):
            return "Could not claim side button \(key) (code \(code)); nothing was changed."
        case InputTransportError.eventTapCreationFailed:
            return "Could not create the input event tap."
        case InputTransportError.notAvailable(let reason):
            return reason
        default:
            return "\(error)"
        }
    }
}

// MARK: - Delegate glue

extension MultiTapCoordinator: InputTransportDelegate {
    public func inputTransport(_ transport: InputTransport, didReceive event: PhysicalInputEvent) {
        handle(event)
    }

    public func inputTransport(_ transport: InputTransport, didFailWith error: Error) {
        handleTransportFailure(error)
    }
}
