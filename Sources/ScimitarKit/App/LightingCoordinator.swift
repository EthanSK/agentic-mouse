import Foundation

/// Owns the mouse's colour.
///
/// Multi-tap mode and transient alerts feed a single arbiter. The rules that
/// matter:
///
///  * Alerts outrank the mode indicator, so the result is never ambiguous.
///  * When configured, the idle frame remains visible whenever no explicit
///    mode or alert owns the mouse. A missing idle frame retains the legacy
///    release-to-iCUE behaviour for callers that do not want a baseline.
///  * Every write goes through the throttle, so a lamp fade or the mode pulse
///    cannot flood iCUE, and an unchanged frame is never re-sent.
public final class LightingCoordinator {
    private var arbiter = LightingArbiter()
    private let controller: ThrottlingLightingController
    private let modeStyle: ModeIndicatorStyle
    private let idleFrame: LightingFrame?
    private let clock: MonotonicClock
    private let log: Log

    public private(set) var isModeActive = false
    public private(set) var colorProofColor: RGBColor?
    public private(set) var modeAppearanceFrame: LightingFrame?
    public private(set) var lastResolvedFrame: LightingFrame?

    private var pulseScheduler: TickScheduler?
    private var deferredFlushScheduler: TickScheduler?
    private let pulseInterval: TimeInterval

    public init(
        controller: ThrottlingLightingController,
        modeStyle: ModeIndicatorStyle,
        idleColor: RGBColor? = nil,
        clock: MonotonicClock,
        log: Log,
        pulseScheduler: TickScheduler? = nil,
        deferredFlushScheduler: TickScheduler? = nil,
        pulseInterval: TimeInterval = 1.0 / 20.0
    ) {
        self.controller = controller
        self.modeStyle = modeStyle
        self.idleFrame = idleColor.map(LightingFrame.init(uniform:))
        self.clock = clock
        self.log = log
        self.pulseScheduler = pulseScheduler
        self.deferredFlushScheduler = deferredFlushScheduler
        self.pulseInterval = pulseInterval
    }

    deinit { releaseEverything() }

    // MARK: - Producers

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
            // Exiting the mode falls through to the configured idle frame, or
            // releases the layer for legacy callers with no idle baseline.
            controller.invalidateCache()
        }
        flush()
    }

    /// Paints both audited Scimitar zones with the selected proof colour.
    /// Returning false means the HUD must remain the only claimed indicator.
    @discardableResult
    public func setColorProofColor(_ color: RGBColor?) -> Bool {
        setModeAppearance(modeColor: color, actionColor: nil)
    }

    /// Uses the Scimitar's two audited zones deliberately: the logo identifies
    /// the active mode and the complete thumb-grid zone identifies the last
    /// action. The device does not expose twelve independently writable keys.
    @discardableResult
    public func setModeAppearance(modeColor: RGBColor?, actionColor: RGBColor?) -> Bool {
        let frame = modeColor.map { LightingFrame(logo: $0, side: actionColor ?? $0) }
        if frame != modeAppearanceFrame {
            modeAppearanceFrame = frame
            colorProofColor = modeColor
            stopPulse()

            if let frame {
                arbiter.set(.modeIndicator, frame: frame)
            } else {
                arbiter.clear(.modeIndicator)
                controller.invalidateCache()
            }
        }
        // Repeating the same colour deliberately retries a previous failed or
        // unavailable write. The throttling controller still suppresses a
        // frame that genuinely reached the mouse.
        return flush().isAvailable
    }

    /// A transient alert that outranks everything, e.g. a failed entry.
    public func setAlert(_ frame: LightingFrame?) {
        arbiter.set(.alert, frame: frame)
        flush()
    }

    // MARK: - Output

    /// Pushes the arbitrated frame to the device.
    @discardableResult
    public func flush() -> LightingWriteOutcome {
        let resolved = arbiter.resolved ?? idleFrame

        do {
            if let resolved {
                guard controller.isAvailable else {
                    log.debug("lighting write skipped: controller is unavailable")
                    return .unavailable
                }
                try controller.apply(resolved)
            } else {
                try controller.release()
            }
            lastResolvedFrame = resolved
            scheduleDeferredFlushIfNeeded()
            return resolved == nil ? .released : .applied
        } catch LightingError.deviceNotFound {
            // The mouse slept or dropped its wireless link. Not an error worth
            // shouting about; the next refresh re-selects it.
            log.debug("lighting write skipped: device not currently available")
            return .unavailable
        } catch LightingError.notConnected {
            log.debug("lighting write skipped: iCUE not connected")
            return .unavailable
        } catch {
            log.error("lighting write failed: \(error)")
            return .failed
        }
    }

    /// Clears our shared layer entirely. Called on quit, on iCUE loss and from
    /// `deinit`, so ordinary iCUE lighting always comes back even when a
    /// persistent in-process idle frame is configured.
    public func releaseEverything() {
        stopPulse()
        stopDeferredFlush()
        arbiter.clearAll()
        isModeActive = false
        colorProofColor = nil
        modeAppearanceFrame = nil
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
        if let modeAppearanceFrame {
            arbiter.set(.modeIndicator, frame: modeAppearanceFrame)
        } else if isModeActive {
            arbiter.set(.modeIndicator, frame: modeStyle.frame(at: clock.now))
            startPulse()
        }
        flush()
    }

    // MARK: - Pulse

    private func startPulse() {
        guard modeStyle.pulse != nil, let scheduler = pulseScheduler else { return }
        scheduler.start(interval: pulseInterval) { [weak self] in
            guard let self, self.isModeActive, self.colorProofColor == nil else { return }
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

public enum LightingWriteOutcome: Equatable, Sendable {
    case applied
    case released
    case unavailable
    case failed

    public var isAvailable: Bool { self == .applied }
}
