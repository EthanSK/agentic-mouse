import Foundation

/// Owns the mouse's colour.
///
/// Two independent producers feed it — the Hue room observer and multi-tap mode
/// — and a single arbiter decides which one wins. The rules that matter:
///
///  * The newest Hue frame is **always** cached, even while multi-tap mode is
///    overriding the mouse. Leaving the mode therefore restores the room's
///    current colour instantly, not the colour it had when the mode started.
///  * Multi-tap mode outranks Hue, so the indicator is never ambiguous.
///  * Nothing at all wanting the mouse means the layer is released with alpha
///    0, handing the device back to ordinary iCUE lighting.
///  * Every write goes through the throttle, so a lamp fade or the mode pulse
///    cannot flood iCUE, and an unchanged frame is never re-sent.
public final class LightingCoordinator {
    private var arbiter = LightingArbiter()
    private let controller: ThrottlingLightingController
    private let modeStyle: ModeIndicatorStyle
    private let clock: MonotonicClock
    private let log: Log

    /// The most recent frame Hue produced, regardless of what is on screen.
    public private(set) var cachedHueFrame: LightingFrame?
    public private(set) var isModeActive = false
    public private(set) var lastResolvedFrame: LightingFrame?

    private var pulseScheduler: TickScheduler?
    private var deferredFlushScheduler: TickScheduler?
    private let pulseInterval: TimeInterval

    public init(
        controller: ThrottlingLightingController,
        modeStyle: ModeIndicatorStyle,
        clock: MonotonicClock,
        log: Log,
        pulseScheduler: TickScheduler? = nil,
        deferredFlushScheduler: TickScheduler? = nil,
        pulseInterval: TimeInterval = 1.0 / 20.0
    ) {
        self.controller = controller
        self.modeStyle = modeStyle
        self.clock = clock
        self.log = log
        self.pulseScheduler = pulseScheduler
        self.deferredFlushScheduler = deferredFlushScheduler
        self.pulseInterval = pulseInterval
    }

    deinit { releaseEverything() }

    // MARK: - Producers

    /// A new (or absent) frame from the Hue room observer.
    ///
    /// `nil` means the bridge is unreachable, disabled, or nothing is
    /// configured — in every one of those cases the mouse should stop being
    /// driven rather than freeze on a stale colour.
    public func updateHueFrame(_ frame: LightingFrame?) {
        cachedHueFrame = frame
        arbiter.set(.hueMirror, frame: frame)
        // While the mode is active the frame is cached but not shown; the
        // arbiter already knows the mode outranks it.
        flush()
    }

    /// Multi-tap mode turning on or off.
    public func setModeActive(_ active: Bool) {
        guard active != isModeActive else { return }
        isModeActive = active

        if active {
            arbiter.set(.modeIndicator, frame: modeStyle.frame(at: clock.now))
            startPulse()
        } else {
            stopPulse()
            arbiter.clear(.modeIndicator)
            // Restoring is simply "let the arbiter fall through to the newest
            // cached Hue frame" — which is already in place.
            controller.invalidateCache()
        }
        flush()
    }

    /// A transient alert that outranks everything, e.g. a failed entry.
    public func setAlert(_ frame: LightingFrame?) {
        arbiter.set(.alert, frame: frame)
        flush()
    }

    // MARK: - Output

    /// Pushes the arbitrated frame to the device.
    public func flush() {
        let resolved = arbiter.resolved
        lastResolvedFrame = resolved

        do {
            if let resolved {
                try controller.apply(resolved)
            } else {
                try controller.release()
            }
        } catch LightingError.deviceNotFound {
            // The mouse slept or dropped its wireless link. Not an error worth
            // shouting about; the next refresh re-selects it.
            log.debug("lighting write skipped: device not currently available")
        } catch LightingError.notConnected {
            log.debug("lighting write skipped: iCUE not connected")
        } catch {
            log.error("lighting write failed: \(error)")
        }
        scheduleDeferredFlushIfNeeded()
    }

    /// Clears our shared layer entirely. Called on quit, on iCUE loss and from
    /// `deinit`, so ordinary iCUE lighting always comes back.
    public func releaseEverything() {
        stopPulse()
        stopDeferredFlush()
        arbiter.clearAll()
        lastResolvedFrame = nil
        do {
            try controller.release()
        } catch {
            // Even if this fails, iCUE reclaims the layer when the process
            // exits, so there is nothing further to do.
            log.debug("release on teardown returned \(error)")
        }
    }

    /// iCUE went away. Drop local state so a reconnect starts clean.
    public func handleSessionLost() {
        stopPulse()
        stopDeferredFlush()
        arbiter.clearAll()
        controller.invalidateCache()
        lastResolvedFrame = nil
    }

    /// iCUE came back: re-apply whatever should currently be showing.
    public func handleSessionRestored() {
        controller.invalidateCache()
        if isModeActive {
            arbiter.set(.modeIndicator, frame: modeStyle.frame(at: clock.now))
            startPulse()
        }
        arbiter.set(.hueMirror, frame: cachedHueFrame)
        flush()
    }

    // MARK: - Pulse

    private func startPulse() {
        guard modeStyle.pulse != nil, let scheduler = pulseScheduler else { return }
        scheduler.start(interval: pulseInterval) { [weak self] in
            guard let self, self.isModeActive else { return }
            self.arbiter.set(.modeIndicator, frame: self.modeStyle.frame(at: self.clock.now))
            self.flush()
        }
    }

    private func stopPulse() {
        pulseScheduler?.stop()
    }

    // MARK: - Deferred rate-limit flush

    private func scheduleDeferredFlushIfNeeded() {
        guard controller.hasDeferredFrame, let scheduler = deferredFlushScheduler else {
            stopDeferredFlush()
            return
        }
        scheduler.start(interval: max(0.001, controller.deferredFlushDelay)) { [weak self] in
            self?.flushDeferred()
        }
    }

    private func flushDeferred() {
        do {
            try controller.flushDeferred()
            if controller.hasDeferredFrame {
                scheduleDeferredFlushIfNeeded()
            } else {
                stopDeferredFlush()
            }
        } catch {
            stopDeferredFlush()
            log.error("deferred lighting write failed: \(error)")
        }
    }

    private func stopDeferredFlush() {
        deferredFlushScheduler?.stop()
    }

    // MARK: - Introspection (doctor / tests)

    public var winningSource: LightingSource? { arbiter.winningSource }
    public var writeCount: Int { controller.writeCount }
    public var suppressedCount: Int { controller.suppressedCount }
}
