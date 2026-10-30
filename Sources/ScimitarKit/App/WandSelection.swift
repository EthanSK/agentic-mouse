import CoreFoundation
import Foundation

// MARK: - Ingress contract

public enum WandSelectionCommandError: Error, Equatable, CustomStringConvertible {
    case payloadTooLarge
    case notAnObject
    case unsupportedVersion
    case unexpectedKey(String)
    case missingField(String)
    case invalidField(String)

    public var description: String {
        switch self {
        case .payloadTooLarge: return "payload exceeds \(WandSelectionCommand.maximumPayloadBytes) bytes"
        case .notAnObject: return "payload is not one JSON object"
        case .unsupportedVersion: return "unsupported protocol version"
        case .unexpectedKey(let key): return "unexpected key \(key)"
        case .missingField(let key): return "missing \(key)"
        case .invalidField(let key): return "invalid \(key)"
        }
    }
}

/// Bias-corrected rotation accumulated since the gesture's `begin`, in
/// degrees. Signs follow the pointer the wand normally drives: positive `x`
/// is the direction that would move the cursor right, positive `y` the
/// direction that would move it down. Cumulative values make one dropped
/// datagram lose no travel.
public struct WandAngularOffset: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = WandAngularOffset(x: 0, y: 0)
}

/// One validated `agentic_mouse_wand_selection` v1 datagram from the wand
/// receiver. The receiver writes these to the same per-user user-command socket
/// Karabiner uses; the namespace is distinct and carries no mouse source, so a
/// wand payload can never impersonate an exact-device mouse command.
public struct WandSelectionCommand: Equatable, Sendable {
    public enum Phase: String, Sendable {
        case begin
        case update
        case end
        case cancel
    }

    public enum CancelReason: String, Sendable {
        case user
        case disconnect
        case timeout
        case error
    }

    public static let commandName = "agentic_mouse_wand_selection"
    public static let protocolVersion = 1
    public static let maximumPayloadBytes = 512
    public static let maximumAbsoluteDegrees = 7_200.0
    public static let maximumSequence = Int(Int32.max)
    public static let gestureIdentifierLengths = 8...64

    private static let allowedKeys: Set<String> = [
        "command", "version", "phase", "gesture_id", "seq", "x_deg", "y_deg", "reason",
    ]

    public let phase: Phase
    public let gestureID: String
    public let sequence: Int
    public let offset: WandAngularOffset?
    public let cancelReason: CancelReason?

    public init(
        phase: Phase,
        gestureID: String,
        sequence: Int,
        offset: WandAngularOffset? = nil,
        cancelReason: CancelReason? = nil
    ) {
        self.phase = phase
        self.gestureID = gestureID
        self.sequence = sequence
        self.offset = offset
        self.cancelReason = cancelReason
    }

    /// Returns nil for any other user-command namespace. Throws only when the
    /// payload claims the wand namespace but violates the strict v1 schema.
    public static func decodeIfPresent(_ data: Data) throws -> WandSelectionCommand? {
        let claimsNamespace = data.range(of: Data(commandName.utf8)) != nil
        guard data.count <= maximumPayloadBytes else {
            if claimsNamespace { throw WandSelectionCommandError.payloadTooLarge }
            return nil
        }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if claimsNamespace { throw WandSelectionCommandError.notAnObject }
            return nil
        }
        guard object["command"] as? String == commandName else { return nil }

        if let unexpected = object.keys.sorted().first(where: { !allowedKeys.contains($0) }) {
            throw WandSelectionCommandError.unexpectedKey(unexpected)
        }

        guard let versionValue = object["version"] else {
            throw WandSelectionCommandError.missingField("version")
        }
        guard let version = integer(versionValue) else {
            throw WandSelectionCommandError.invalidField("version")
        }
        guard version == protocolVersion else {
            throw WandSelectionCommandError.unsupportedVersion
        }

        guard let phaseValue = object["phase"] else {
            throw WandSelectionCommandError.missingField("phase")
        }
        guard let phaseName = phaseValue as? String, let phase = Phase(rawValue: phaseName) else {
            throw WandSelectionCommandError.invalidField("phase")
        }

        guard let gestureValue = object["gesture_id"] else {
            throw WandSelectionCommandError.missingField("gesture_id")
        }
        guard let gestureID = gestureValue as? String, isValidGestureIdentifier(gestureID) else {
            throw WandSelectionCommandError.invalidField("gesture_id")
        }

        guard let sequenceValue = object["seq"] else {
            throw WandSelectionCommandError.missingField("seq")
        }
        guard let sequence = integer(sequenceValue), (0...maximumSequence).contains(sequence) else {
            throw WandSelectionCommandError.invalidField("seq")
        }

        let xValue = object["x_deg"]
        let yValue = object["y_deg"]
        var offset: WandAngularOffset?
        switch (xValue, yValue) {
        case (nil, nil):
            offset = nil
        case (.some(let rawX), .some(let rawY)):
            guard phase == .update || phase == .end else {
                throw WandSelectionCommandError.unexpectedKey("x_deg")
            }
            guard let x = degrees(rawX) else { throw WandSelectionCommandError.invalidField("x_deg") }
            guard let y = degrees(rawY) else { throw WandSelectionCommandError.invalidField("y_deg") }
            offset = WandAngularOffset(x: x, y: y)
        case (nil, .some):
            throw WandSelectionCommandError.missingField("x_deg")
        case (.some, nil):
            throw WandSelectionCommandError.missingField("y_deg")
        }
        if phase == .update, offset == nil {
            throw WandSelectionCommandError.missingField("x_deg")
        }

        var cancelReason: CancelReason?
        if let reasonValue = object["reason"] {
            guard phase == .cancel else { throw WandSelectionCommandError.unexpectedKey("reason") }
            guard let name = reasonValue as? String, let reason = CancelReason(rawValue: name) else {
                throw WandSelectionCommandError.invalidField("reason")
            }
            cancelReason = reason
        } else if phase == .cancel {
            cancelReason = .user
        }

        return WandSelectionCommand(
            phase: phase,
            gestureID: gestureID,
            sequence: sequence,
            offset: offset,
            cancelReason: cancelReason
        )
    }

    static func isValidGestureIdentifier(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard gestureIdentifierLengths.contains(bytes.count) else { return false }
        return bytes.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                || byte == 45 || byte == 95
        }
    }

    /// JSON booleans also bridge to NSNumber; reject them so `true` can never
    /// stand in for a version or sequence number.
    private static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded(.towardZero) == double,
              abs(double) <= 9_007_199_254_740_992
        else { return nil }
        return Int(double)
    }

    private static func degrees(_ value: Any) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let double = number.doubleValue
        guard double.isFinite, abs(double) <= maximumAbsoluteDegrees else { return nil }
        return double
    }
}

// MARK: - Navigation

/// Angular tolerance for the retired 4 × 3 grid cursor. Its `hysteresis`
/// still sets the wheel-adjustment detent band.
///
/// The outline position is continuous, so one fast sweep crosses several
/// cards. `hysteresis` widens every boundary by a fraction of a cell, so
/// tremor near a boundary cannot flicker between neighbours. Opposite edges
/// join, with whole laps removed so large updates cannot leave movement queued.
///
/// Direction is judged from a short, path-length-smoothed heading rather than
/// from each 30 ms sample. While that heading is axis-dominant (the major axis
/// is at least `dominantAxisRatio` times the minor), the minor axis is
/// attenuated so a long sweep cannot slip a row. Once the heading is clearly
/// diagonal, nothing is attenuated and leaving a card moves straight to the
/// diagonal neighbour instead of stepping through an intermediate card.
public struct WandNavigationTuning: Equatable, Sendable {
    public var degreesPerColumn: Double
    public var degreesPerRow: Double
    public var hysteresis: Double
    /// Axis/diagonal heading boundary as a major:minor ratio (2 ≈ 26.6°).
    public var dominantAxisRatio: Double
    public var minorAxisAttenuation: Double
    /// Each displacement component must reach this fraction of a card,
    /// toward the diagonal neighbour, before a diagonal step is taken.
    public var diagonalCommitment: Double
    /// Path length, in cards, over which recent travel sets the heading.
    public var headingMemory: Double
    /// Angular dead band around the axis/diagonal heading boundary.
    public var headingHysteresisDegrees: Double

    public init(
        degreesPerColumn: Double = 8,
        degreesPerRow: Double = 7,
        hysteresis: Double = 0.18,
        dominantAxisRatio: Double = 2,
        minorAxisAttenuation: Double = 0.6,
        diagonalCommitment: Double = 0.3,
        headingMemory: Double = 0.25,
        headingHysteresisDegrees: Double = 3
    ) {
        self.degreesPerColumn = degreesPerColumn
        self.degreesPerRow = degreesPerRow
        self.hysteresis = hysteresis
        self.dominantAxisRatio = dominantAxisRatio
        self.minorAxisAttenuation = minorAxisAttenuation
        self.diagonalCommitment = diagonalCommitment
        self.headingMemory = headingMemory
        self.headingHysteresisDegrees = headingHysteresisDegrees
    }

    /// Bounded copy so a bad configuration can never divide by zero or
    /// remove the boundary dead band entirely.
    var sanitized: WandNavigationTuning {
        WandNavigationTuning(
            degreesPerColumn: Self.bounded(degreesPerColumn, 1...90, fallback: 8),
            degreesPerRow: Self.bounded(degreesPerRow, 1...90, fallback: 7),
            hysteresis: Self.bounded(hysteresis, 0...0.45, fallback: 0.18),
            dominantAxisRatio: Self.bounded(dominantAxisRatio, 1...20, fallback: 2),
            minorAxisAttenuation: Self.bounded(minorAxisAttenuation, 0...1, fallback: 0.6),
            diagonalCommitment: Self.bounded(diagonalCommitment, 0.05...0.68, fallback: 0.3),
            headingMemory: Self.bounded(headingMemory, 0.05...2, fallback: 0.25),
            headingHysteresisDegrees: Self.bounded(headingHysteresisDegrees, 0...10, fallback: 3)
        )
    }

    private static func bounded(
        _ value: Double,
        _ range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

/// Pure grid cursor. Rows are presentation rows from the top of the mouse
/// toward the desk. The wand HUD no longer uses it: it draws and selects a
/// weapon wheel through `WandRadialLayout` and `WandRadialNavigator`.
public struct WandGridNavigator: Equatable, Sendable {
    public let rows: [[PhysicalCell]]
    public private(set) var column: Int
    public private(set) var row: Int
    private var positionX: Double
    private var positionY: Double
    private let tuning: WandNavigationTuning

    public init?(
        rows: [[PhysicalCell]],
        start: PhysicalCell,
        tuning: WandNavigationTuning = .init()
    ) {
        guard !rows.isEmpty, rows.allSatisfy({ !$0.isEmpty })
        else { return nil }
        self.rows = rows
        self.tuning = tuning.sanitized
        var startRow = 0
        var startColumn = 0
        for (rowIndex, cells) in rows.enumerated() {
            if let columnIndex = cells.firstIndex(of: start) {
                startRow = rowIndex
                startColumn = columnIndex
                break
            }
        }
        row = startRow
        column = startColumn
        positionX = Double(startColumn)
        positionY = Double(startRow)
    }

    public var focusedCell: PhysicalCell { rows[row][column] }

    /// True while the smoothed heading is clearly diagonal.
    public var isDiagonalHeading: Bool { diagonalHeading }

    public var pointerFocus: ModeHUDPointerFocus {
        let boundary = 0.5 + tuning.hysteresis
        return ModeHUDPointerFocus(
            cell: focusedCell,
            pullX: (positionX - Double(column)) / boundary,
            pullY: (positionY - Double(row)) / boundary
        )
    }

    /// Applies one bias-corrected angular delta. Returns true only when the
    /// focused card changed.
    @discardableResult
    public mutating func apply(deltaX: Double, deltaY: Double) -> Bool {
        guard deltaX.isFinite, deltaY.isFinite else { return false }
        let width = rows[row].count
        let height = rows.count
        var dx = width > 1 ? deltaX / tuning.degreesPerColumn : 0
        var dy = height > 1 ? deltaY / tuning.degreesPerRow : 0
        updateHeading(dx: dx, dy: dy)
        if !diagonalHeading {
            // Axis lock comes from the smoothed heading, not from one noisy
            // sample, so the minor axis never stutters between full and cut.
            if abs(headingX) >= abs(headingY) {
                dy *= 1 - tuning.minorAxisAttenuation
            } else {
                dx *= 1 - tuning.minorAxisAttenuation
            }
        }
        let maximumColumn = width - 1
        let maximumRow = height - 1
        // Discard outward travel at an edge instead of wrapping or storing a
        // hidden overshoot that would delay the next deliberate reversal.
        positionX = min(Double(maximumColumn), max(0, positionX + dx))
        positionY = min(Double(maximumRow), max(0, positionY + dy))
        let previousColumn = column
        let previousRow = row
        resolveSteps(maximumColumn: maximumColumn, maximumRow: maximumRow)
        return column != previousColumn || row != previousRow
    }

    private var headingX = 0.0
    private var headingY = 0.0
    private var diagonalHeading = false

    /// Path-length decay keeps roughly the last `headingMemory` cards of
    /// travel. It is independent of sample rate, ignores the direction of a
    /// pause, and lets a deliberate turn take over within a fraction of a card.
    private mutating func updateHeading(dx: Double, dy: Double) {
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return }
        let keep = exp(-length / tuning.headingMemory)
        headingX = headingX * keep + dx
        headingY = headingY * keep + dy
        let major = max(abs(headingX), abs(headingY))
        let minor = min(abs(headingX), abs(headingY))
        guard (major * major + minor * minor).squareRoot() >= 0.05 else { return }
        let offAxisDegrees = atan2(minor, major) * 180 / .pi
        let boundary = atan(1 / tuning.dominantAxisRatio) * 180 / .pi
        if diagonalHeading {
            if offAxisDegrees < boundary - tuning.headingHysteresisDegrees { diagonalHeading = false }
        } else if offAxisDegrees > boundary + tuning.headingHysteresisDegrees {
            diagonalHeading = true
        }
    }

    /// Leaves the current card only past its hysteresis boundary. A diagonal
    /// heading with real travel on both axes steps to the diagonal neighbour
    /// in one move; anything else steps along the axis that left the card.
    /// After every step the position keeps at least the full hysteresis band
    /// of travel before it can return, so a diagonal arrival is never more
    /// fragile than an axis arrival.
    private mutating func resolveSteps(maximumColumn: Int, maximumRow: Int) {
        let boundary = 0.5 + tuning.hysteresis
        let returnLimit = 0.5 - tuning.hysteresis
        for _ in 0...(maximumColumn + maximumRow + 1) {
            let offsetX = positionX - Double(column)
            let offsetY = positionY - Double(row)
            let leavesX = abs(offsetX) > boundary
            let leavesY = abs(offsetY) > boundary
            guard leavesX || leavesY else { return }
            var stepX = 0
            var stepY = 0
            if diagonalHeading, headingX != 0, headingY != 0 {
                let signX = headingX > 0 ? 1 : -1
                let signY = headingY > 0 ? 1 : -1
                if offsetX * Double(signX) >= tuning.diagonalCommitment,
                   offsetY * Double(signY) >= tuning.diagonalCommitment {
                    stepX = signX
                    stepY = signY
                }
            }
            if stepX == 0, stepY == 0 {
                if leavesX, !leavesY || abs(offsetX) >= abs(offsetY) {
                    stepX = offsetX > 0 ? 1 : -1
                } else {
                    stepY = offsetY > 0 ? 1 : -1
                }
            }
            // At an edge a diagonal may continue along the remaining axis.
            if !(0...maximumColumn).contains(column + stepX) { stepX = 0 }
            if !(0...maximumRow).contains(row + stepY) { stepY = 0 }
            guard stepX != 0 || stepY != 0 else { return }
            column += stepX
            row += stepY
            column = min(column, rows[row].count - 1)
            positionX = min(positionX, Double(rows[row].count - 1))
            if stepX != 0, (positionX - Double(column)) * Double(stepX) < -returnLimit {
                positionX = Double(column) - Double(stepX) * returnLimit
            }
            if stepY != 0, (positionY - Double(row)) * Double(stepY) < -returnLimit {
                positionY = Double(row) - Double(stepY) * returnLimit
            }
        }
    }
}

// MARK: - Wheel-card adjustment

/// One reconstructed adjustment detent from vertical wand tilt.
public enum WandAdjustStep: Equatable, Sendable {
    /// Tilting the wand up, as if rolling a physical wheel up.
    case physicalUp
    /// Tilting the wand down, as if rolling a physical wheel down.
    case physicalDown

    /// `WheelChordDirection` names the normalized Quartz delta sign, not the
    /// ratchet direction Ethan feels: both accepted mice deliver a physical
    /// upward ratchet to the shared resolver as `.down`. Feed wand tilt through
    /// the same convention so every wheel family keeps its own accepted
    /// physical polarity without a wand-specific inversion.
    public var wheelDirection: WheelChordDirection {
        switch self {
        case .physicalUp: return .down
        case .physicalDown: return .up
        }
    }
}

/// Converts vertical tilt into discrete detents with the same boundary
/// hysteresis as navigation. Travel is unbounded, but one update can emit at
/// most `maximumStepsPerUpdate` detents; surplus travel is discarded rather
/// than queued so a single jump can never replay a long burst later.
public struct WandAdjustDetentTracker: Equatable, Sendable {
    public static let maximumStepsPerUpdate = 6

    public let degreesPerStep: Double
    public let hysteresis: Double
    private var position: Double = 0
    private var index = 0

    public init(degreesPerStep: Double = 7, hysteresis: Double = 0.18) {
        self.degreesPerStep = degreesPerStep.isFinite ? min(90, max(1, degreesPerStep)) : 7
        self.hysteresis = hysteresis.isFinite ? min(0.45, max(0, hysteresis)) : 0.18
    }

    /// Travel toward the next detent, -1...1. Negative leans toward a
    /// physical-up detent, positive toward physical-down; it returns toward
    /// zero (keeping only the residual) as soon as a detent is emitted.
    public var progress: Double {
        let value = (position - Double(index)) / (0.5 + hysteresis)
        return min(1, max(-1, value))
    }

    public mutating func apply(deltaY: Double) -> [WandAdjustStep] {
        guard deltaY.isFinite, deltaY != 0 else { return [] }
        position += deltaY / degreesPerStep
        var steps: [WandAdjustStep] = []
        while steps.count < Self.maximumStepsPerUpdate,
              position > Double(index) + 0.5 + hysteresis {
            index += 1
            steps.append(.physicalDown)
        }
        while steps.count < Self.maximumStepsPerUpdate,
              position < Double(index) - 0.5 - hysteresis {
            index -= 1
            steps.append(.physicalUp)
        }
        if steps.count == Self.maximumStepsPerUpdate {
            position = Double(index)
        }
        return steps
    }
}

extension WheelChordControl {
    /// Held-wheel cards the wand may adjust with tilt. Each is an
    /// app-specific control with no press-side effect and no release-only
    /// click action, so keeping it armed between two wand gestures cannot
    /// start a hidden hold (YouTube 2×), capture a pointer (window resize),
    /// or emit a click. Others keep the ordinary press/release behaviour.
    public var supportsWandAdjustment: Bool {
        switch self {
        case .codexPin, .codexReasoningEffort, .codexResponseSpeed, .codexChatHistory,
             .claudePin, .claudeTabs, .chromeTabs,
             .spotifyVolume, .vsCodeCursorHistory, .horizontalScroll, .clipboard,
             .brightness, .zoom, .systemOverview, .applicationWindows,
             .magnetWindow, .spaces, .mediaTracks:
            return true
        case .screenshotPaste, .youtubeScrub, .youtubeVolume,
             .windowWidth, .windowHeight, .chromeVSCodeLayout, .vsCodeStageRange:
            return false
        }
    }
    /// A wheel-free click has its own action (Tracks plays the next track).
    /// Ethan: "If it's just a one click wedge, it just sends the click
    /// through" — so a wand click uses that action, and only a held release
    /// enters dotted mode. The wand's Copy / Paste no longer types Space on a
    /// click: Ethan separated Space into its own outer card (2026-10-29), so a
    /// Copy / Paste click enters dotted mode like any other wheel card. The
    /// physical mice keep their Copy / Paste click Space.
    public var hasWandClickAction: Bool { self == .mediaTracks }
    /// Ethan: "where it makes sense to do left and right, we should actually
    /// do that in the HUD. For example, spaces switching should be like
    /// dragging it left and right with the wand." A mouse wheel only goes up
    /// and down; the wand moves along the action's own axis. Value changes
    /// (volume, zoom, brightness, speed, effort) stay vertical. Wand only:
    /// the physical wheels are unchanged.
    public var wandAxis: WandAdjustAxis {
        switch self {
        case .horizontalScroll, .spaces, .magnetWindow, .chromeTabs, .claudeTabs, .codexChatHistory,
             .vsCodeCursorHistory, .mediaTracks, .youtubeScrub, .windowWidth:
            return .horizontal
        default:
            return .vertical
        }
    }
    /// The normalized wheel direction a rightward wand movement sends, read
    /// from each family's own action mapping (Spaces up = space right, Tracks
    /// down = next, Chrome down = forward, Magnet down = right, horizontal
    /// scroll up = right).
    public var wandRightDirection: WheelChordDirection {
        switch self {
        case .mediaTracks, .chromeTabs, .magnetWindow: return .down
        default: return .up
        }
    }
    /// The wheel direction for wand travel along `wandAxis`. `positive` is
    /// screen right or down; vertical keeps the existing tilt convention.
    public func wandDirection(positive: Bool) -> WheelChordDirection {
        switch wandAxis {
        case .vertical: return positive ? .up : .down
        case .horizontal: return positive ? wandRightDirection : (wandRightDirection == .up ? .down : .up)
        }
    }
    /// Travel along this control's wand axis, screen-signed.
    public func wandTravel(dx: Double, dy: Double) -> Double { wandAxis == .horizontal ? dx : dy }
    /// One action per gesture rather than a value: the wand repeats it with a
    /// quick swipe, re-armed by a slow return (`WandSwipeDetector`).
    public var isWandSwipeAction: Bool { supportsWandAdjustment && dispatchPolicy == .oncePerHold }
    /// The wand home page's held-wheel cards (the coordinator routes these).
    public static func wandHomeControl(for cell: PhysicalCell) -> WheelChordControl? {
        [1: .horizontalScroll, 3: .screenshotPaste, 4: .clipboard, 6: .youtubeScrub,
         PhysicalCell.wandZoom.rawValue: .zoom][cell.rawValue]
    }
}

public enum WandAdjustAxis: Equatable, Sendable { case vertical, horizontal }

/// Ethan: "for these ones where it's less of a continuous value thing ... it
/// should detect like a relatively fast swipe ... And then you can slowly
/// reset your wand position". A swipe is enough travel along the axis inside
/// a short window; afterwards the detector waits until movement has slowed
/// to a near stop, so a slow return re-arms it without acting. Nothing is
/// delayed or replayed: a swipe acts on the sample that completes it.
public struct WandSwipeDetector: Equatable, Sendable {
    /// Degrees of travel within `window` that make a swipe (about 30°/s).
    public static let swipeDegrees = 4.0
    public static let window: TimeInterval = 0.15
    /// Travel within `window` below which the wand counts as settled.
    public static let settledDegrees = 1.0
    private var samples: [(time: Double, travel: Double)] = []
    public private(set) var armed = true

    public init() {}
    public static func == (a: Self, b: Self) -> Bool { a.armed == b.armed && a.samples.count == b.samples.count }

    /// Travel inside the window, screen-signed.
    public var recentTravel: Double { samples.reduce(0) { $0 + $1.travel } }
    /// Progress toward the next swipe, -1...1, for the arrows.
    public var progress: Double { armed ? max(-1, min(1, recentTravel / Self.swipeDegrees)) : 0 }

    /// Returns true (positive: right/down) or false when a swipe completes.
    public mutating func sample(travel: Double, now: Double) -> Bool? {
        guard travel.isFinite, now.isFinite else { return nil }
        samples.append((now, travel))
        samples.removeAll { now - $0.time > Self.window }
        let total = recentTravel
        if !armed {
            if abs(total) < Self.settledDegrees { armed = true; samples.removeAll() }
            return nil
        }
        guard abs(total) >= Self.swipeDegrees else { return nil }
        armed = false
        return total > 0
    }
}

/// The wand's private wheel chord. It reuses the shared dispatch policy for
/// each control, but it is a separate state machine: the wand never arms the
/// Quartz wheel tap, so a physical mouse wheel cannot be attributed to the
/// wand while a wand card is armed.
public final class WandVirtualWheel {
    private let state: WheelChordStateMachine

    public init(clock: MonotonicClock = SystemMonotonicClock()) {
        state = WheelChordStateMachine(clock: clock)
    }

    public var activeControl: WheelChordControl? { state.activeControl(for: .wand) }

    /// Nil clears without a release, matching teardown semantics.
    public func setActive(_ control: WheelChordControl?) {
        guard let control else {
            state.clear(source: .wand)
            return
        }
        state.setActive(control, for: .wand)
    }

    public func release(_ expected: WheelChordControl) -> WheelChordStateMachine.Release? {
        state.release(expected, for: .wand)
    }

    public func clear() { state.clearAll() }

    /// See `WheelChordStateMachine.rearmHoldAction`: wand swipes only.
    public func rearmHoldAction() { state.rearmHoldAction(for: .wand) }

    /// Returns a step only when the control's own policy would dispatch it.
    public func step(_ direction: WheelChordDirection) -> WheelChordStateMachine.Step? {
        guard state.activeControl(for: .wand) != nil else { return nil }
        let routing = state.route(
            verticalDelta: direction == .up ? 1 : -1,
            isContinuous: false
        )
        if case .consume(let step) = routing { return step }
        return nil
    }
}

// MARK: - Mode ownership

/// The wand has no Karabiner routing to unlock, so its coordinator needs no
/// Karabiner variable or CLI process. The unlocked-session boundary still
/// applies: the app gates every wand command and tears this mode down on lock.
public final class WandModeLease: ColorProofLeaseControlling {
    public init() {}
    public func activate() throws {}
    public func renew() throws {}
    public func deactivate() {}
}

/// The subset of the shared mode coordinator the wand drives. Using the real
/// coordinator keeps every page, child, wheel card and action on the same
/// definitions and dispatch as the physical mice.
public protocol WandModeControlling: AnyObject {
    var isActive: Bool { get }
    var isWandHome: Bool { get }
    var page: ModePickerPage { get }
    var navigationPath: [ModePickerPage] { get }
    var activeWheelControl: WheelChordControl? { get }
    var pointerFocus: ModeHUDPointerFocus? { get }
    var pageGeneration: UInt64 { get }
    /// The weapon wheel currently drawn for the wand. Selection uses this
    /// exact layout, never a separate grid.
    var wandRadialLayout: WandRadialLayout { get }
    var wandReviewAvailable: Bool { get }
    func setWandReviewSelection(_ cell: PhysicalCell?)
    /// Hides a wand HUD whose action completed, keeping the mode alive briefly.
    func concealWandHUD()
    func enterWandHome(source: MouseSource, pointerFocus: ModeHUDPointerFocus?)
    func handle(_ command: ModePickerCommand, inputTime: TimeInterval)
    func setPointerFocus(_ focus: ModeHUDPointerFocus?)
    func exit(reason: ModePickerExitReason)
    /// The wand-adjustable wheel control a wand press on `cell` would hold on
    /// the visible page, or nil. A query only: it presses nothing.
    func wandAdjustableControl(for cell: PhysicalCell) -> WheelChordControl?
    /// The submenu to reopen after an ordinary action hid the HUD.
    func wandJourneyBookmark() -> WandJourneyBookmark?
    func restoreWandJourney(_ mark: WandJourneyBookmark) -> Bool
}

public extension WandModeControlling {
    var wandReviewAvailable: Bool { false }
    func setWandReviewSelection(_ cell: PhysicalCell?) {}
    func concealWandHUD() {}
    func wandAdjustableControl(for cell: PhysicalCell) -> WheelChordControl? { nil }
    func wandJourneyBookmark() -> WandJourneyBookmark? { nil }
    func restoreWandJourney(_ mark: WandJourneyBookmark) -> Bool { false }
}
extension ModePickerCoordinator: WandModeControlling {
    /// Mirrors `route`'s wheel resolution for a wand press, without pressing.
    /// Cards that the wand's held keys, VS Code's stage-ready button route or
    /// a page change own are never reported as wheels.
    public func wandAdjustableControl(for cell: PhysicalCell) -> WheelChordControl? {
        guard isActive, source == .wand, cell != .modeExit else { return nil }
        let control: WheelChordControl?
        if isWandHome {
            control = WheelChordControl.wandHomeControl(for: cell)
        } else {
            switch page {
            case .modes: control = WheelChordControl.utilityControl(for: cell)
            case .extraUtilities: control = WheelChordControl.extraUtilitiesControl(for: cell)
            case .keys: control = WheelChordControl.keysControl(for: cell)
            case .appSpecific:
                guard let target = appSpecificTarget,
                      target != .chrome || ChromeModeAction.action(for: cell) != .openWebsites,
                      target != .vsCode || cell != VSCodeMode.cursorHistoryWheelCell
                        || shouldRouteVSCodeCursorHistoryAsButton?(.wand) != true else { return nil }
                control = WheelChordControl.appSpecificControl(for: target, cell: cell)
            default: control = nil
            }
        }
        guard let control, control.supportsWandAdjustment else { return nil }
        return control
    }
}

public struct WandSelectionPolicy: Equatable, Sendable {
    /// Retained for its detent hysteresis; card selection uses `radial`.
    public var navigation: WandNavigationTuning
    /// Weapon-wheel selection over the HUD's own `WandRadialLayout`.
    public var radial: WandRadialTuning
    public var adjustDegreesPerStep: Double
    /// Slower apparent motion is treated as residual gyro bias, not intent.
    public var driftFloorDegreesPerSecond: Double
    /// The receiver must send a message (a repeated `update` is fine) at least
    /// this often while the HUD button is held; silence is a lost release.
    public var gestureStallTimeout: TimeInterval
    public var maximumGestureDuration: TimeInterval
    public var armedIdleTimeout: TimeInterval
    public var navigationIdleTimeout: TimeInterval
    /// Keeps the mode alive briefly after an action so bounded follow-up work
    /// (VS Code single/double classification, Codex Edit) is not cancelled by
    /// an immediate mode exit, and so its footer feedback is visible.
    public var postActionLinger: TimeInterval
    public var watchdogInterval: TimeInterval

    public init(
        navigation: WandNavigationTuning = .init(),
        radial: WandRadialTuning = .init(),
        adjustDegreesPerStep: Double = 7,
        driftFloorDegreesPerSecond: Double = 1.5,
        gestureStallTimeout: TimeInterval = 1.0,
        maximumGestureDuration: TimeInterval = 20,
        armedIdleTimeout: TimeInterval = 8,
        navigationIdleTimeout: TimeInterval = 8,
        postActionLinger: TimeInterval = 2,
        watchdogInterval: TimeInterval = 0.25
    ) {
        self.navigation = navigation
        self.radial = radial
        self.adjustDegreesPerStep = adjustDegreesPerStep
        self.driftFloorDegreesPerSecond = driftFloorDegreesPerSecond
        self.gestureStallTimeout = gestureStallTimeout
        self.maximumGestureDuration = maximumGestureDuration
        self.armedIdleTimeout = armedIdleTimeout
        self.navigationIdleTimeout = navigationIdleTimeout
        self.postActionLinger = postActionLinger
        self.watchdogInterval = watchdogInterval
    }
}

// MARK: - Gesture controller

/// Turns one held wand button into a PlayStation-style selection over the
/// shared mode HUD.
///
/// * `begin` opens Default with Switch App outlined, or continues from the
///   outline a previous selection left on the open page.
/// * `update` moves the outline; `end` routes one ordinary `select` press and
///   release for the outlined card through the shared coordinator. A tap with
///   no movement therefore runs Switch App exactly once on a fresh Default.
/// * Releasing on a supported held-wheel card arms it instead. The next wand
///   gesture's vertical tilt becomes wheel detents, and its release ends the
///   hold exactly like letting go of the physical cell. That hold publishes
///   detent progress and sent steps for its own adjustment outline.
/// * Any lost release, unexpected new gesture, cancel, lock or timeout closes
///   the mode without performing the outlined action.
public final class WandSelectionController {
    public enum Phase: Equatable, Sendable {
        case idle
        case navigating
        case armed
        case adjusting
        case lingering
    }

    public static let source: MouseSource = .wand

    private struct Gesture {
        let id: String
        var lastSequence: Int
        var lastOffset: WandAngularOffset
        var lastMessageAt: TimeInterval
        let startedAt: TimeInterval
    }

    private struct ArmedCard {
        let cell: PhysicalCell
        let control: WheelChordControl
        let since: TimeInterval
    }

    /// One adjustment hold. Its feedback starts from zero on every hold and
    /// never shares state with navigation pull.
    private struct AdjustSession {
        var tracker: WandAdjustDetentTracker
        var netSteps = 0
        var sentSteps = 0
        var lastStepWasUp: Bool?

        var adjustment: ModeHUDWheelAdjustment {
            ModeHUDWheelAdjustment(
                pull: tracker.progress,
                netSteps: netSteps,
                sentSteps: sentSteps,
                lastStepWasUp: lastStepWasUp
            )
        }
    }

    private enum State {
        case idle
        case navigating(Gesture, WandRadialNavigator)
        case armed(ArmedCard)
        case adjusting(Gesture, ArmedCard, AdjustSession)
        case lingering(deadline: TimeInterval)
    }

    public let policy: WandSelectionPolicy
    /// Sends one tilt detent to the shared wheel dispatcher. Return true only
    /// when the control's own policy handed it to its output route; only
    /// those detents pulse in the HUD, so a debounced or once-per-hold
    /// consumption never looks like an action.
    public var onAdjustStep: ((WheelChordDirection) -> Bool)?
    /// The card a fresh Default session outlines: a tap switches app.
    public static let homeStartCell: PhysicalCell = .switchApp

    private let target: WandModeControlling
    private let scheduler: TickScheduler
    private let clock: MonotonicClock
    private let inputTime: () -> TimeInterval
    private let inputAllowed: () -> Bool
    private let log: Log
    private var state: State = .idle
    private var lastFinishedGestureID: String?
    private var isDispatching = false
    private var closeRequestedDuringDispatch = false

    public init(
        target: WandModeControlling,
        scheduler: TickScheduler,
        clock: MonotonicClock,
        log: Log,
        policy: WandSelectionPolicy = .init(),
        inputTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        inputAllowed: @escaping () -> Bool = { true }
    ) {
        self.target = target
        self.scheduler = scheduler
        self.clock = clock
        self.log = log
        self.policy = policy
        self.inputTime = inputTime
        self.inputAllowed = inputAllowed
    }

    public var phase: Phase {
        switch state {
        case .idle: return .idle
        case .navigating: return .navigating
        case .armed: return .armed
        case .adjusting: return .adjusting
        case .lingering: return .lingering
        }
    }

    public var focusedCell: PhysicalCell? {
        switch state {
        case .navigating(_, let navigator): return navigator.focusedCell
        case .armed(let card), .adjusting(_, let card, _): return card.cell
        case .idle, .lingering: return nil
        }
    }

    /// The first card a child page outlines: its own exit, so a quick tap
    /// goes back without performing anything. App pages use cell 2 (the same
    /// control that opened them); other pages use cell 10.
    public static func startCell(for page: ModePickerPage) -> PhysicalCell {
        switch page {
        case .appSpecific, .chromeWebsites: return .frontmostAppModeSelector
        case .modes, .keys, .appSelector, .keypad, .extraUtilities: return .modeExit
        }
    }

    public func handle(_ command: WandSelectionCommand) {
        guard !isDispatching else {
            // Mode actions can briefly yield the main run loop. Never start or
            // steer another gesture underneath one; honour only a close.
            if command.phase == .cancel { closeRequestedDuringDispatch = true }
            return
        }
        guard inputAllowed() else {
            close(reason: .systemSleep)
            return
        }
        synchronizeWithTarget()
        let now = clock.now
        switch command.phase {
        case .begin: begin(command, at: now)
        case .update: update(command, at: now)
        case .end: end(command, at: now)
        case .cancel: cancel(command)
        }
    }

    /// Lock, sleep, reload, teardown: drop every gesture and close the mode.
    public func reset(reason: ModePickerExitReason = .shuttingDown) {
        closeRequestedDuringDispatch = false
        close(reason: reason)
    }

    // MARK: Phases

    private func begin(_ command: WandSelectionCommand, at now: TimeInterval) {
        if let gesture = currentGesture {
            if gesture.id == command.gestureID { return }
            // The previous release never arrived. Fail closed: never act on it.
            log.notice("wand gesture began before the previous one ended; closing without selection")
            lastFinishedGestureID = gesture.id
            close(reason: .deviceLost)
        }
        guard command.gestureID != lastFinishedGestureID else { return }

        let gesture = Gesture(
            id: command.gestureID,
            lastSequence: command.sequence,
            lastOffset: .zero,
            lastMessageAt: now,
            startedAt: now
        )
        if case .armed(let card) = state {
            let session = AdjustSession(tracker: WandAdjustDetentTracker(
                degreesPerStep: policy.adjustDegreesPerStep,
                hysteresis: policy.navigation.hysteresis
            ))
            state = .adjusting(gesture, card, session)
            target.setPointerFocus(ModeHUDPointerFocus(cell: card.cell, adjustment: session.adjustment))
            startWatchdog()
            return
        }

        if !target.isActive {
            target.enterWandHome(
                source: Self.source,
                pointerFocus: ModeHUDPointerFocus(cell: Self.homeStartCell)
            )
            guard target.isActive else {
                state = .idle
                stopWatchdog()
                return
            }
        }
        // Continue from the outline the page is already showing (a child's
        // exit, or the card a back navigation returned to) so a new hold
        // never makes the outline jump.
        let start = target.pointerFocus?.cell
            ?? (target.isWandHome ? Self.homeStartCell : Self.startCell(for: target.page))
        guard let navigator = WandRadialNavigator(
            layout: target.wandRadialLayout,
            start: start,
            tuning: policy.radial
        ) else { return }
        state = .navigating(gesture, navigator)
        target.setPointerFocus(ModeHUDPointerFocus(cell: navigator.focusedCell))
        startWatchdog()
    }

    private func update(_ command: WandSelectionCommand, at now: TimeInterval) {
        guard let gesture = currentGesture,
              gesture.id == command.gestureID,
              command.sequence > gesture.lastSequence,
              let offset = command.offset
        else { return }
        applyMotion(to: offset, sequence: command.sequence, at: now)
    }

    private func end(_ command: WandSelectionCommand, at now: TimeInterval) {
        guard let gesture = currentGesture,
              gesture.id == command.gestureID,
              command.sequence > gesture.lastSequence
        else { return }
        if let offset = command.offset {
            applyMotion(to: offset, sequence: command.sequence, at: now)
        }
        lastFinishedGestureID = gesture.id
        switch state {
        case .navigating(_, let navigator):
            // Release always selects the outlined card. Fresh Default starts
            // on Switch App, child pages on their exit and Back on the card
            // that opened the child, so a tap is never an unexpected action.
            activate(navigator.focusedCell, at: now)
        case .adjusting(_, let card, _):
            finishAdjustment(card, at: now)
        case .idle, .armed, .lingering:
            return
        }
    }

    private func cancel(_ command: WandSelectionCommand) {
        if let gesture = currentGesture, gesture.id == command.gestureID {
            lastFinishedGestureID = gesture.id
            close(reason: command.cancelReason == .disconnect ? .deviceLost : .userRequested)
            return
        }
        // Closing is always the safe direction, so a disconnect closes any
        // wand page even when its gesture identity is already gone.
        if command.cancelReason == .disconnect {
            close(reason: .deviceLost)
        }
    }

    // MARK: Motion

    private func applyMotion(to offset: WandAngularOffset, sequence: Int, at now: TimeInterval) {
        guard var gesture = currentGesture else { return }
        let deltaX = offset.x - gesture.lastOffset.x
        let deltaY = offset.y - gesture.lastOffset.y
        let elapsed = max(0.005, now - gesture.lastMessageAt)
        gesture.lastSequence = sequence
        gesture.lastOffset = offset
        gesture.lastMessageAt = now

        let speed = (deltaX * deltaX + deltaY * deltaY).squareRoot() / elapsed
        let isDrift = speed < max(0, policy.driftFloorDegreesPerSecond)
        let filteredX = isDrift ? 0 : deltaX
        let filteredY = isDrift ? 0 : deltaY

        switch state {
        case .navigating(_, var navigator):
            navigator.apply(deltaX: filteredX, deltaY: filteredY)
            state = .navigating(gesture, navigator)
            target.setPointerFocus(navigator.pointerFocus)
        case .adjusting(_, let card, var session):
            // Adjustment is vertical only; sideways travel never changes value.
            let steps = session.tracker.apply(deltaY: filteredY)
            state = .adjusting(gesture, card, session)
            if !steps.isEmpty {
                isDispatching = true
                for step in steps where onAdjustStep?(step.wheelDirection) == true {
                    session.sentSteps += 1
                    session.netSteps += step == .physicalUp ? 1 : -1
                    session.lastStepWasUp = step == .physicalUp
                }
                isDispatching = false
                if closeRequestedDuringDispatch {
                    closeRequestedDuringDispatch = false
                    close(reason: .userRequested)
                    return
                }
                // A dispatched step can disarm the card (a frontmost-app
                // retarget); never redraw adjustment on a vanished card.
                guard case .adjusting = state, target.activeWheelControl == card.control else { return }
                state = .adjusting(gesture, card, session)
            }
            target.setPointerFocus(ModeHUDPointerFocus(cell: card.cell, adjustment: session.adjustment))
        case .idle, .armed, .lingering:
            return
        }
    }

    // MARK: Dispatch

    private func activate(_ cell: PhysicalCell, at now: TimeInterval) {
        let generationBefore = target.pageGeneration
        var armedControl: WheelChordControl?

        isDispatching = true
        target.handle(selectCommand(cell, phase: .press), inputTime: inputTime())
        if target.isActive {
            if target.pageGeneration != generationBefore {
                // The press changed page (forward, back or a child exit). Its
                // paired release belongs to the old page; delivering it to the
                // new page would act on a card the user never selected (on
                // Default, whose cards act on release, cell 10 would close).
            } else if let control = target.activeWheelControl, control.supportsWandAdjustment {
                armedControl = control
            } else {
                target.handle(selectCommand(cell, phase: .release), inputTime: inputTime())
            }
        }
        isDispatching = false

        guard finishDispatch() else { return }
        if let armedControl {
            state = .armed(ArmedCard(cell: cell, control: armedControl, since: now))
            target.setPointerFocus(ModeHUDPointerFocus(cell: cell, isArmed: true))
            log.info("wand armed \(armedControl.actionTitle); tilt on the next hold adjusts it")
            return
        }
        if target.pageGeneration != generationBefore {
            // The coordinator already drew the new page with its outline in
            // the same frame; keep it so the next hold starts there.
            state = .lingering(deadline: now + policy.navigationIdleTimeout)
            return
        }
        target.setPointerFocus(nil)
        state = .lingering(deadline: now + policy.postActionLinger)
    }

    private func finishAdjustment(_ card: ArmedCard, at now: TimeInterval) {
        isDispatching = true
        target.handle(selectCommand(card.cell, phase: .release), inputTime: inputTime())
        isDispatching = false
        guard finishDispatch() else { return }
        target.setPointerFocus(nil)
        state = .lingering(deadline: now + policy.postActionLinger)
    }

    /// Returns false when the dispatch ended the wand session.
    private func finishDispatch() -> Bool {
        if closeRequestedDuringDispatch {
            closeRequestedDuringDispatch = false
            close(reason: .userRequested)
            return false
        }
        guard target.isActive else {
            state = .idle
            stopWatchdog()
            return false
        }
        return true
    }

    private func selectCommand(
        _ cell: PhysicalCell,
        phase: ModePickerCommand.Phase
    ) -> ModePickerCommand {
        ModePickerCommand(action: .select, source: Self.source, physicalCell: cell, phase: phase)
    }

    // MARK: Lifetime

    private var currentGesture: Gesture? {
        switch state {
        case .navigating(let gesture, _), .adjusting(let gesture, _, _): return gesture
        case .idle, .armed, .lingering: return nil
        }
    }

    /// The coordinator can end the mode independently (lock, sleep, a
    /// frontmost-app retarget that disarms a wheel card). Never keep acting
    /// on a page or control that is no longer live.
    private func synchronizeWithTarget() {
        if case .idle = state { return }
        guard target.isActive else {
            state = .idle
            stopWatchdog()
            return
        }
        switch state {
        case .armed(let card) where target.activeWheelControl != card.control:
            target.setPointerFocus(nil)
            state = .lingering(deadline: clock.now + policy.postActionLinger)
        case .adjusting(let gesture, let card, _) where target.activeWheelControl != card.control:
            lastFinishedGestureID = gesture.id
            target.setPointerFocus(nil)
            state = .lingering(deadline: clock.now + policy.postActionLinger)
        default:
            break
        }
    }

    private func close(reason: ModePickerExitReason) {
        state = .idle
        stopWatchdog()
        if target.isActive { target.exit(reason: reason) }
    }

    private func startWatchdog() {
        guard !scheduler.isRunning else { return }
        scheduler.start(interval: max(0.05, policy.watchdogInterval)) { [weak self] in
            self?.tick()
        }
    }

    private func stopWatchdog() { scheduler.stop() }

    private func tick() {
        guard !isDispatching else { return }
        guard inputAllowed() else {
            close(reason: .systemSleep)
            return
        }
        synchronizeWithTarget()
        let now = clock.now
        switch state {
        case .idle:
            stopWatchdog()
        case .navigating(let gesture, _), .adjusting(let gesture, _, _):
            let stalled = now - gesture.lastMessageAt > policy.gestureStallTimeout
            let tooLong = now - gesture.startedAt > policy.maximumGestureDuration
            guard stalled || tooLong else { return }
            log.notice(stalled
                ? "wand release was not received; closing without selection"
                : "wand gesture exceeded its maximum duration; closing without selection")
            lastFinishedGestureID = gesture.id
            close(reason: .deviceLost)
        case .armed(let card):
            if now - card.since > policy.armedIdleTimeout { close(reason: .userRequested) }
        case .lingering(let deadline):
            if now >= deadline { close(reason: .userRequested) }
        }
    }
}
