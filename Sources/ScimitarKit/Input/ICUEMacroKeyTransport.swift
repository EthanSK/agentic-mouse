import Foundation

/// The slice of the iCUE session the input layer needs. Injected so the whole
/// transactional interception lifecycle can be tested with no iCUE, no SDK and
/// no mouse.
public protocol ICUEKeyControlling: AnyObject {
    var isSessionUsable: Bool { get }
    /// Delivered on the main queue for every macro key on every device; the
    /// transport is responsible for filtering to its own device.
    var onMacroKeyEvent: ((ICUEKeyEvent) -> Void)? { get set }

    func subscribeToMacroKeyEvents() -> Result<Void, LightingError>
    func macroKeyIdentifiers(of deviceIdentifier: String) -> [Int]
    func requestKeyControl(deviceIdentifier: String, level: ICUEAccessLevel) -> Int32
    @discardableResult func releaseControl(deviceIdentifier: String) -> Int32
    @discardableResult func configureKeyEvent(
        deviceIdentifier: String,
        macroKeyId: Int,
        intercepted: Bool
    ) -> Int32
    /// Last-resort safety path. Disconnecting the SDK client makes iCUE reclaim
    /// any input ownership the normal rollback could not prove it released.
    func disconnectForRollbackSafety()
}

extension ICUESession: ICUEKeyControlling {
    public var isSessionUsable: Bool { isLibraryLoaded && state.isUsable }

    public var onMacroKeyEvent: ((ICUEKeyEvent) -> Void)? {
        get { onKeyEvent }
        set { onKeyEvent = newValue }
    }

    public func subscribeToMacroKeyEvents() -> Result<Void, LightingError> {
        subscribeToEvents()
    }

    public func disconnectForRollbackSafety() {
        disconnect()
        // Unlike an ordinary app teardown, a safety disconnect happened while
        // the helper still wants iCUE. Notify the lifecycle owner after the
        // current rollback unwinds so it can reconnect without re-entering the
        // modal state.
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(.closed)
        }
    }
}

/// **The primary input route.**
///
/// The connected `SCIMITAR ELITE WIRELESS SE` reports `CDPI_MacroKeyArray` =
/// `CMKI_1 … CMKI_12`, one macro key per side button, so the twelve buttons are
/// visible to `CorsairSubscribeForEvents` as raw device events carrying the
/// originating device id. That is a far better ingress than watching synthesised
/// mouse buttons:
///
///  * Events are attributed to a *specific device id*, so another mouse (or the
///    Logitech) can never be mistaken for the Scimitar.
///  * The signal is the physical button itself, independent of whatever the
///    iCUE profile has assigned to it.
///  * `CorsairConfigureKeyEvent` under `CAL_ExclusiveKeyEventsListening` stops
///    the normal assignment firing while the mode is active, which is what
///    makes the mode genuinely modal instead of merely additive.
///
/// The access level taken is level **2**, "exclusive key events, but shared
/// lightings". Lighting stays shared for the whole lifetime of the process; the
/// C bridge refuses levels 1 and 3 outright.
///
/// Scope: only `CMKI_1 … CMKI_12` are ever configured. The left button, right
/// button, wheel, wheel click, pointer motion and the DPI Toggle button are not
/// macro keys and are never touched by this transport — not even while the mode
/// is active. (Speech-to-text lives on *side button 4*, which is part of the
/// grid and is therefore suspended along with the rest of it while the mode is
/// on; the DPI Toggle button is disabled in iCUE and has no speech role at all.)
public final class ICUEMacroKeyTransport: InputTransport {

    /// The buttons the grid uses. Exactly the twelve side keys.
    public static let gridMacroKeys: [Int] = Array(1...12)

    public weak var delegate: InputTransportDelegate?
    public var name: String { "icueMacroKey" }

    public private(set) var isRunning = false
    public private(set) var isInterceptionEnabled = false

    /// Keys that `beginInterception()` has actually configured. Rollback walks
    /// exactly this list, so a partial transaction is undone precisely.
    public private(set) var configuredKeys: [Int] = []
    private var holdsKeyControl = false

    private let session: ICUEKeyControlling
    private let deviceIdentifier: String
    private let expectedMacroKeys: [Int]
    private let clock: MonotonicClock
    private let log: Log

    /// Press start times guard against duplicate callbacks while still letting
    /// the user recover if iCUE drops a release. A sufficiently later press is
    /// treated as a new physical press, with an implicit release delivered
    /// first so the state machine sees a coherent sequence.
    private var pressedAt: [Int: TimeInterval] = [:]
    private let stuckPressRecoveryInterval: TimeInterval

    public init(
        session: ICUEKeyControlling,
        deviceIdentifier: String,
        expectedMacroKeys: [Int] = ICUEMacroKeyTransport.gridMacroKeys,
        clock: MonotonicClock = SystemMonotonicClock(),
        stuckPressRecoveryInterval: TimeInterval = 1.5,
        log: Log
    ) {
        self.session = session
        self.deviceIdentifier = deviceIdentifier
        self.expectedMacroKeys = expectedMacroKeys
        self.clock = clock
        self.stuckPressRecoveryInterval = max(0.1, stuckPressRecoveryInterval)
        self.log = log
    }

    deinit {
        // Belt and braces: even a deallocation without an explicit stop must
        // not leave the device in an exclusive access level.
        rollbackInterception(reason: "deinit")
    }

    // MARK: - Lifecycle

    public func start() throws {
        guard !isRunning else { return }
        guard session.isSessionUsable else { throw InputTransportError.sessionNotConnected }

        if case .failure(let error) = session.subscribeToMacroKeyEvents() {
            throw InputTransportError.notAvailable("event subscription failed: \(error)")
        }

        session.onMacroKeyEvent = { [weak self] event in
            self?.handle(event)
        }
        Self.handlerOwnership.claim(session: session, owner: self)

        isRunning = true
        log.info("macro-key transport started for \(Redaction.identifier(deviceIdentifier))")
    }

    public func stop() {
        endInterception()
        // The session has exactly one callback slot, so a transport must only
        // clear it while it is still the installed owner. Without this, tearing
        // down an old transport *after* a replacement had started would leave
        // the new one subscribed to nothing and the mode permanently deaf.
        if Self.handlerOwnership.relinquish(session: session, owner: self) {
            session.onMacroKeyEvent = nil
        }
        pressedAt.removeAll()
        isRunning = false
        log.info("macro-key transport stopped")
    }

    /// The callback slot belongs to the session, not to the transport type as a
    /// whole. Keeping ownership per session prevents a test/fallback session
    /// from making a stopped transport on another session remain subscribed.
    private final class HandlerOwnership: @unchecked Sendable {
        private final class WeakOwner {
            weak var value: ICUEMacroKeyTransport?
            init(_ value: ICUEMacroKeyTransport) { self.value = value }
        }

        private let lock = NSLock()
        private var owners: [ObjectIdentifier: WeakOwner] = [:]

        func claim(session: ICUEKeyControlling, owner: ICUEMacroKeyTransport) {
            lock.lock()
            owners[ObjectIdentifier(session)] = WeakOwner(owner)
            lock.unlock()
        }

        func relinquish(session: ICUEKeyControlling, owner: ICUEMacroKeyTransport) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let identifier = ObjectIdentifier(session)
            guard owners[identifier]?.value === owner else { return false }
            owners.removeValue(forKey: identifier)
            return true
        }
    }

    private static let handlerOwnership = HandlerOwnership()

    // MARK: - Readiness

    /// Every precondition for entering the mode, evaluated together so the user
    /// gets the complete list of what is wrong rather than one item at a time.
    public func preflight() -> InputTransportReadiness {
        var reasons: [String] = []

        if !session.isSessionUsable {
            reasons.append("iCUE is not connected (start iCUE and enable SDK / third-party control).")
        }
        if deviceIdentifier.isEmpty {
            reasons.append("No Scimitar selected.")
        }
        if !isRunning {
            reasons.append("Macro-key event subscription is not running.")
        }

        if session.isSessionUsable && !deviceIdentifier.isEmpty {
            let reported = Set(session.macroKeyIdentifiers(of: deviceIdentifier))
            let missing = expectedMacroKeys.filter { !reported.contains($0) }
            if !missing.isEmpty {
                reasons.append(
                    "The mouse reported \(reported.count) macro keys; "
                    + "\(missing.count) of the \(expectedMacroKeys.count) grid buttons are missing."
                )
            }
        }

        return reasons.isEmpty ? .ready : .notReady(reasons)
    }

    // MARK: - Transactional interception

    /// Takes exclusive key-event ownership of the twelve grid buttons.
    ///
    /// Order matters and is unwound in reverse on any failure:
    ///   1. verify the device still reports all twelve macro keys
    ///   2. `CorsairRequestControl(device, CAL_ExclusiveKeyEventsListening)`
    ///   3. `CorsairConfigureKeyEvent(key, intercepted: true)` for each key
    ///
    /// If step 3 fails on key *n*, keys 1…*n-1* are un-configured and control
    /// is released before the error is thrown. The caller therefore never has
    /// to reason about partial ownership.
    public func beginInterception() throws {
        guard !isInterceptionEnabled else { return }
        guard isRunning else { throw InputTransportError.notAvailable("transport not started") }
        guard session.isSessionUsable else { throw InputTransportError.sessionNotConnected }
        guard !deviceIdentifier.isEmpty else { throw InputTransportError.deviceNotSelected }

        // 1 — the mouse must still be the thing we think it is.
        let reported = Set(session.macroKeyIdentifiers(of: deviceIdentifier))
        let missing = expectedMacroKeys.filter { !reported.contains($0) }
        guard missing.isEmpty else {
            throw InputTransportError.macroKeysUnavailable(
                expected: expectedMacroKeys.count,
                found: expectedMacroKeys.count - missing.count
            )
        }

        // 2 — input-only exclusivity, scoped to this one device.
        let controlCode = session.requestKeyControl(
            deviceIdentifier: deviceIdentifier,
            level: .exclusiveKeyEvents
        )
        guard controlCode == 0 else {
            log.error("key control refused (code \(controlCode)); mode not entered")
            throw InputTransportError.keyControlRefused(code: controlCode)
        }
        holdsKeyControl = true

        // 3 — claim each grid key, remembering exactly what succeeded.
        for key in expectedMacroKeys {
            let code = session.configureKeyEvent(
                deviceIdentifier: deviceIdentifier,
                macroKeyId: key,
                intercepted: true
            )
            guard code == 0 else {
                let configured = configuredKeys.count
                rollbackInterception(reason: "configure failed on key \(key)")
                throw InputTransportError.interceptionIncomplete(
                    configured: configured,
                    failedKey: key,
                    code: code
                )
            }
            configuredKeys.append(key)
        }

        isInterceptionEnabled = true
        log.info("interception active: \(configuredKeys.count) grid keys, exclusive key events only")
    }

    /// Idempotent, non-throwing teardown. Called on exit, on every failure
    /// path, on disconnect, on quit and from `deinit`.
    public func endInterception() {
        rollbackInterception(reason: "exit")
    }

    private func rollbackInterception(reason: String) {
        guard holdsKeyControl || !configuredKeys.isEmpty else {
            isInterceptionEnabled = false
            return
        }

        // Un-configure in reverse order so the last thing claimed is the first
        // thing given back.
        var failedUnconfigurations: Set<Int> = []
        for key in configuredKeys.reversed() {
            let code = session.configureKeyEvent(
                deviceIdentifier: deviceIdentifier,
                macroKeyId: key,
                intercepted: false
            )
            if code != 0 {
                failedUnconfigurations.insert(key)
                // Keep going: a successful releaseControl below still restores
                // the whole device even if one per-key update was refused.
                log.notice("un-configure of key \(key) returned code \(code); continuing rollback")
            }
        }
        configuredKeys = configuredKeys.filter { failedUnconfigurations.contains($0) }

        var releaseFailed = false
        if holdsKeyControl {
            let code = session.releaseControl(deviceIdentifier: deviceIdentifier)
            if code != 0 {
                releaseFailed = true
                log.error("releaseControl returned code \(code); disconnecting the SDK session for safety")
            } else {
                // Releasing device control supersedes any per-key rollback
                // failures and proves all normal assignments are restored.
                configuredKeys.removeAll()
                holdsKeyControl = false
            }
        }

        if releaseFailed || !configuredKeys.isEmpty {
            // Never clear local state and claim success while the SDK may still
            // own a button. Closing the client session is the vendor-guaranteed
            // fail-safe that returns every key and lighting layer to iCUE.
            session.disconnectForRollbackSafety()
            configuredKeys.removeAll()
            holdsKeyControl = false
            isRunning = false
        }

        pressedAt.removeAll()
        isInterceptionEnabled = false
        log.info("interception rolled back (\(reason)); normal side-button actions restored")
    }

    // MARK: - Events

    private func handle(_ event: ICUEKeyEvent) {
        // Exact-device filter. Events from any other Corsair device — a second
        // mouse, a keyboard's G keys — are discarded before they can reach the
        // state machine.
        guard event.deviceIdentifier == deviceIdentifier else { return }
        guard expectedMacroKeys.contains(event.macroKeyId) else { return }

        if event.isPressed {
            if let originalPress = pressedAt[event.macroKeyId] {
                guard clock.now - originalPress >= stuckPressRecoveryInterval else {
                    // Immediate duplicate callback / key repeat.
                    return
                }
                // The old release was lost. Retire it before admitting this
                // press; this is especially important for k12, whose next
                // physical press must always remain able to exit the mode.
                deliver(macroKeyId: event.macroKeyId, phase: .release)
            }
            pressedAt[event.macroKeyId] = clock.now
        } else {
            guard pressedAt[event.macroKeyId] != nil else { return }
            pressedAt.removeValue(forKey: event.macroKeyId)
        }

        deliver(
            macroKeyId: event.macroKeyId,
            phase: event.isPressed ? .press : .release
        )
    }

    private func deliver(macroKeyId: Int, phase: PhysicalInputEvent.Phase) {
        delegate?.inputTransport(
            self,
            didReceive: PhysicalInputEvent(
                binding: .icueMacroKey(macroKeyId),
                phase: phase,
                timestamp: clock.now
            )
        )
    }

    /// Called by the coordinator when iCUE or the device goes away. Rolls back
    /// without attempting SDK calls that would fail anyway.
    public func handleSessionLoss() {
        configuredKeys.removeAll()
        holdsKeyControl = false
        pressedAt.removeAll()
        isInterceptionEnabled = false
        isRunning = false
        log.notice("iCUE session lost; interception state cleared locally")
    }
}
