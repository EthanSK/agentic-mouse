import ApplicationServices
import CoreGraphics
import Foundation
import ScimitarKit

/// Converts phase-free vertical wheel input into a two-way action while an
/// exact-device thumb-grid control is physically held. Continuous controls act
/// per accepted event; one-shot controls latch for the hold; discrete repeated
/// controls reject the short raw-event burst from one physical ratchet.
///
/// Quartz does not expose mouse identity on a CGEvent. Exact-device ownership
/// therefore comes from the held Karabiner press/release command. Gesture- or
/// momentum-phased trackpad events pass through unchanged. Karabiner may mark
/// a conventional ratchet as continuous, so phase-free detents remain valid.
/// Two simultaneously held source chords are consumed without guessing.
final class ScrollWheelChordMonitor {
    typealias StepHandler = (WheelChordStateMachine.Step) -> Bool
    typealias ReleaseHandler = (WheelChordStateMachine.Release) -> Void
    typealias YouTubeVolumeModifierReleaseHandler = (
        WheelChordStateMachine.YouTubeVolumeModifierRelease
    ) -> Void
    typealias YouTubeVolumeModifierChangeHandler = (_ source: MouseSource) -> Void
    typealias ProblemHandler = (String) -> Void
    typealias DiagnosticHandler = (_ source: MouseSource, _ message: String) -> Void
    typealias InputAllowed = () -> Bool

    private let state = WheelChordStateMachine()
    private let permission: AccessibilityPermissionChecking
    private let inputAllowed: InputAllowed
    private let log: Log
    private let runLoop: CFRunLoop
    private let diagnosticThrottle: WheelChordDiagnosticThrottle

    var onStep: StepHandler?
    var onRelease: ReleaseHandler?
    var onYouTubeVolumeModifierRelease: YouTubeVolumeModifierReleaseHandler?
    var onYouTubeVolumeModifierChange: YouTubeVolumeModifierChangeHandler?
    var onProblem: ProblemHandler?
    var onDiagnostic: DiagnosticHandler?
    var onControlChange: ((_ source: MouseSource, _ control: WheelChordControl) -> Void)?
    var onWheelInput: ((_ source: MouseSource) -> Void)?
    var onClear: ((_ source: MouseSource) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var isRunning: Bool {
        guard let tap, runLoopSource != nil else { return false }
        return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
    }

    init(
        permission: AccessibilityPermissionChecking = AccessibilityPermission(),
        inputAllowed: @escaping InputAllowed,
        log: Log,
        diagnosticThrottle: WheelChordDiagnosticThrottle = .init(),
        runLoop: CFRunLoop = CFRunLoopGetMain()
    ) {
        self.permission = permission
        self.inputAllowed = inputAllowed
        self.log = log
        self.diagnosticThrottle = diagnosticThrottle
        self.runLoop = runLoop
    }

    deinit { stop() }

    func start() throws {
        if tap != nil || runLoopSource != nil {
            guard !isRunning else { return }
            stop()
        }
        guard permission.isTrusted else {
            throw InputTransportError.accessibilityPermissionMissing
        }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<ScrollWheelChordMonitor>
                    .fromOpaque(refcon)
                    .takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: context
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            throw InputTransportError.eventTapCreationFailed
        }

        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        runLoopSource = source
        log.info("wheel-chord event tap started")
    }

    func stop() {
        clearAll()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    func setActive(
        _ control: WheelChordControl?,
        for source: MouseSource
    ) {
        guard let control else {
            finishHold(for: source)
            return
        }
        if state.activeControl(for: source) != control { onClear?(source) }
        state.setActive(control, for: source)
        onControlChange?(source, control)
        diagnosticThrottle.reset(source: source)
        emitDiagnostic(
            source: source,
            message: "\(controlLabel(control, source: source)) ARMED · 0 RATCHETS"
        )
    }

    /// Preserves the exact top-level control on release so an old command
    /// cannot finish a newer hold from the same mouse source.
    func handle(_ command: WheelChordCommand) {
        switch command.phase {
        case .press:
            setActive(command.control, for: command.source)
        case .release:
            finishHold(command.control, for: command.source)
        }
    }

    func handle(_ command: YouTubeVolumeModifierCommand) {
        let release = state.setYouTubeVolumeModifierActive(
            command.phase == .press,
            for: command.source
        )
        onYouTubeVolumeModifierChange?(command.source)
        if let release {
            onYouTubeVolumeModifierRelease?(release)
        }
    }

    private func finishHold(
        _ expectedControl: WheelChordControl? = nil,
        for source: MouseSource
    ) {
        guard let release = state.release(expectedControl, for: source) else { return }
        diagnosticThrottle.reset(source: source)
        log.info("\(controlLabel(release.control, source: source)) released")
        onRelease?(release)
    }

    func clear(source: MouseSource) {
        onClear?(source)
        state.clear(source: source)
        diagnosticThrottle.reset(source: source)
    }

    func clearAll() {
        for source in MouseSource.allCases { onClear?(source) }
        state.clearAll()
        diagnosticThrottle.resetAll()
    }

    func activeControl(for source: MouseSource) -> WheelChordControl? {
        state.activeControl(for: source)
    }

    func isYouTubeVolumeModifierActive(for source: MouseSource) -> Bool {
        state.isYouTubeVolumeModifierActive(for: source)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            log.notice("wheel-chord event tap was disabled by macOS; re-enabled")
            return Unmanaged.passUnretained(event)
        }
        guard type == .scrollWheel, inputAllowed() else {
            return Unmanaged.passUnretained(event)
        }

        let lineDelta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let pointDelta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let fixedPointDelta = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let delta = WheelChordDirection.effectiveVerticalDelta(
            lineDelta: lineDelta,
            pointDelta: pointDelta,
            fixedPointDelta: fixedPointDelta
        )
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let scrollPhase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        if delta != 0 {
            for source in MouseSource.allCases where state.activeControl(for: source) != nil {
                onWheelInput?(source) // Even filtered or ambiguous wheel input must end speed before routing the scrub/volume action.
            }
        }
        let routing = state.route(
            verticalDelta: delta,
            isContinuous: isContinuous,
            scrollPhase: scrollPhase,
            momentumPhase: momentumPhase
        )
        switch routing {
        case .passThrough:
            if let active = state.soleActiveChord,
               delta != 0 || scrollPhase != 0 || momentumPhase != 0 {
                emitWheelDiagnostic(
                    source: active.source,
                    message: "\(controlLabel(active.control, source: active.source)) · "
                        + rawSummary(
                            line: lineDelta,
                            point: pointDelta,
                            fixed: fixedPointDelta,
                            continuous: isContinuous,
                            scrollPhase: scrollPhase,
                            momentumPhase: momentumPhase
                        )
                        + " · PASSED THROUGH"
                )
            }
            return Unmanaged.passUnretained(event)
        case .consumeAmbiguous:
            onProblem?("Release one mouse control before using the wheel")
            return nil
        case .consumeInactiveDirection(let step):
            emitWheelDiagnostic(
                source: step.source,
                message: "\(controlLabel(step.control, source: step.source)) · "
                    + "\(ratchetCountLabel(step.detentCount)) · "
                    + rawSummary(
                        line: lineDelta,
                        point: pointDelta,
                        fixed: fixedPointDelta,
                        continuous: isContinuous,
                        scrollPhase: scrollPhase,
                        momentumPhase: momentumPhase
                    )
                    + " · \(step.direction == .up ? "UP" : "DOWN") "
                    + "CONSUMED · WHEEL DOWN REQUIRED"
            )
            return nil
        case .consumeAfterFirstHoldAction(let step):
            emitWheelDiagnostic(
                source: step.source,
                message: "\(controlLabel(step.control, source: step.source)) · "
                    + "\(ratchetCountLabel(step.detentCount)) · "
                    + rawSummary(
                        line: lineDelta,
                        point: pointDelta,
                        fixed: fixedPointDelta,
                        continuous: isContinuous,
                        scrollPhase: scrollPhase,
                        momentumPhase: momentumPhase
                    )
                    + " · \(step.direction == .up ? "UP" : "DOWN") "
                    + "CONSUMED · HOLD ALREADY ACTED"
            )
            return nil
        case .consumeDebounced(let step):
            emitWheelDiagnostic(
                source: step.source,
                message: "\(controlLabel(step.control, source: step.source)) · "
                    + "\(ratchetCountLabel(step.detentCount)) · "
                    + rawSummary(
                        line: lineDelta,
                        point: pointDelta,
                        fixed: fixedPointDelta,
                        continuous: isContinuous,
                        scrollPhase: scrollPhase,
                        momentumPhase: momentumPhase
                    )
                    + " · \(step.direction == .up ? "UP" : "DOWN") "
                    + "CONSUMED · DUPLICATE BURST"
            )
            return nil
        case .consume(let step):
            let routed = onStep?(step) == true
            emitWheelDiagnostic(
                source: step.source,
                message: "\(controlLabel(step.control, source: step.source)) · "
                    + "\(ratchetCountLabel(step.detentCount)) · "
                    + rawSummary(
                        line: lineDelta,
                        point: pointDelta,
                        fixed: fixedPointDelta,
                        continuous: isContinuous,
                        scrollPhase: scrollPhase,
                        momentumPhase: momentumPhase
                    )
                    + " · \(step.direction == .up ? "UP" : "DOWN") "
                    + (routed ? "CONSUMED + ROUTED" : "ROUTE FAILED")
            )
            guard routed else {
                onProblem?("\(step.control.actionTitle) wheel action could not be performed")
                return nil
            }
            return nil
        }
    }

    private func emitWheelDiagnostic(source: MouseSource, message: String) {
        guard diagnosticThrottle.shouldEmit(for: source) else { return }
        emitDiagnostic(source: source, message: message)
    }

    private func emitDiagnostic(source: MouseSource, message: String) {
        log.info("diagnostic: \(source.displayName): \(message)")
        onDiagnostic?(source, message)
    }

    private func controlLabel(
        _ control: WheelChordControl,
        source: MouseSource
    ) -> String {
        let cell = control.diagnosticCell
        let printed = cell.printedSide(on: source) ?? cell.rawValue
        return "\(control.actionTitle.uppercased()) B\(printed)"
    }

    private func ratchetCountLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "RATCHET" : "RATCHETS")"
    }

    private func rawSummary(
        line: Int64,
        point: Int64,
        fixed: Int64,
        continuous: Bool,
        scrollPhase: Int64,
        momentumPhase: Int64
    ) -> String {
        "L\(line) P\(point) F\(fixed) C\(continuous ? 1 : 0) PH\(scrollPhase)/\(momentumPhase)"
    }

    static func horizontalWheelDelta(
        _ direction: WheelChordDirection,
        linesPerRatchet: Int
    ) -> Int32? {
        guard AppConfiguration.InputConfiguration.horizontalScrollLinesPerRatchetRange.contains(
            linesPerRatchet
        ) else {
            return nil
        }
        return direction.horizontalWheelDelta * Int32(linesPerRatchet)
    }

    static func postHorizontalWheel(
        _ direction: WheelChordDirection,
        linesPerRatchet: Int
    ) -> Bool {
        guard let horizontalDelta = horizontalWheelDelta(
            direction,
            linesPerRatchet: linesPerRatchet
        ) else {
            return false
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .line,
                wheelCount: 2,
                wheel1: 0,
                wheel2: horizontalDelta,
                wheel3: 0
              ) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }
}
