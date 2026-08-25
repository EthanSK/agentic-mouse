import Foundation

/// A two-way action selected by holding one thumb-grid cell and moving that
/// same mouse's ratcheted wheel. Phase-free wheel events are consumed while a
/// chord is armed. Continuous controls act for every accepted event, one-shot
/// controls act once per physical hold, and discrete selectors reject the
/// short duplicate-event burst that one physical ratchet can produce.
public enum WheelChordControl: String, Codable, CaseIterable, Sendable {
    case horizontalScroll
    case youtubeScrub
    case brightness
    case zoom
    case clipboard
    case systemOverview
    case applicationWindows
    case magnetWindow
    case spaces
    case chromeTabs
    case spotifyVolume
    case vsCodeCursorHistory
    case codexReasoningEffort
    case codexChatHistory

    public var actionTitle: String {
        switch self {
        case .horizontalScroll: return "Horizontal Scroll"
        case .youtubeScrub: return "YouTube Scrub"
        case .brightness: return "Brightness"
        case .zoom: return "Zoom"
        case .clipboard: return "Copy / Paste"
        case .systemOverview: return "Mission / Desktop"
        case .applicationWindows: return "App Exposé"
        case .magnetWindow: return "Magnet"
        case .spaces: return "Spaces"
        case .chromeTabs: return "Tabs"
        case .spotifyVolume: return "Volume"
        case .vsCodeCursorHistory: return "Cursor History"
        case .codexReasoningEffort: return "Reasoning Effort"
        case .codexChatHistory: return "Chats Selection"
        }
    }

    public var hudAccent: RGBColor {
        switch self {
        case .horizontalScroll: return ModeHUDActionFamilyPalette.horizontalScroll
        case .youtubeScrub: return ModeHUDActionFamilyPalette.media
        case .brightness: return ModeHUDActionFamilyPalette.brightness
        case .zoom: return ModeHUDActionFamilyPalette.applicationZoom
        case .clipboard: return ModeHUDActionFamilyPalette.clipboard
        case .systemOverview: return ModeHUDActionFamilyPalette.systemOverview
        case .applicationWindows: return ModeHUDActionFamilyPalette.windowManagement
        case .magnetWindow: return ModeHUDActionFamilyPalette.windowManagement
        case .spaces: return ModeHUDActionFamilyPalette.desktopSpaces
        case .chromeTabs: return ModeHUDActionFamilyPalette.browserTabs
        case .spotifyVolume: return ModeHUDActionFamilyPalette.media
        case .vsCodeCursorHistory: return ModeHUDActionFamilyPalette.historyNavigation
        case .codexReasoningEffort: return ModeHUDActionFamilyPalette.reasoningEffort
        case .codexChatHistory: return ModeHUDActionFamilyPalette.historyNavigation
        }
    }

    /// Repair markers follow the latest explicit physical report. A newly
    /// added or otherwise untested control remains normal; only an explicit
    /// unresolved failure report earns a repair marker.
    public var hudControlStatus: ModeHUDControlStatus {
        .normal
    }

    /// Utility deliberately spends one cell per two-way family. The opposite
    /// member of each former pair is now available for future actions.
    public var utilityCell: PhysicalCell? {
        switch self {
        case .brightness: return .brightnessWheelControl
        case .zoom: return .zoomWheelControl
        case .spaces: return .spacesWheelControl
        case .systemOverview: return .systemOverviewWheelControl
        case .applicationWindows: return .applicationWindowsWheelControl
        case .magnetWindow: return .magnetWheelControl
        case .clipboard, .horizontalScroll, .youtubeScrub, .chromeTabs, .spotifyVolume,
             .vsCodeCursorHistory, .codexReasoningEffort, .codexChatHistory: return nil
        }
    }

    public static func utilityControl(for cell: PhysicalCell) -> WheelChordControl? {
        allCases.first { $0.utilityCell == cell }
    }

    /// Ordinary-layer chords bypass runtime-mode state entirely. Exact-device
    /// Karabiner press/release commands arm these controls directly.
    public var topLevelCell: PhysicalCell? {
        switch self {
        case .clipboard: return .clipboardWheelControl
        case .horizontalScroll: return .horizontalScrollWheelControl
        case .youtubeScrub: return .youtubeScrubWheelControl
        case .brightness, .zoom, .spaces, .systemOverview, .applicationWindows,
             .magnetWindow, .chromeTabs, .spotifyVolume,
             .vsCodeCursorHistory, .codexReasoningEffort, .codexChatHistory: return nil
        }
    }

    public static func topLevelControl(for cell: PhysicalCell) -> WheelChordControl? {
        allCases.first { $0.topLevelCell == cell }
    }

    /// Stateful app controls resolve through the same canonical cell in both
    /// automatic and manually chosen app-specific journeys.
    public static func appSpecificControl(
        for target: AppSpecificTarget,
        cell: PhysicalCell
    ) -> WheelChordControl? {
        switch target {
        case .codex where cell == PhysicalCell(rawValue: 4)!:
            return .codexReasoningEffort
        case .codex where cell == PhysicalCell(rawValue: 11)!:
            return .codexChatHistory
        case .chrome where ChromeModeAction.action(for: cell) == .cycleTabsWithWheel:
            return .chromeTabs
        case .spotify where cell == StandardAppMode.spotifyVolumeWheelCell:
            return .spotifyVolume
        case .vsCode where cell == VSCodeMode.cursorHistoryWheelCell:
            return .vsCodeCursorHistory
        default:
            return nil
        }
    }

    /// The canonical physical cell displayed in live wheel diagnostics. App-
    /// specific chords do not belong to the Utility or Default page, so they
    /// need their owning page's shared cell instead of falling through to B0.
    public var diagnosticCell: PhysicalCell {
        switch self {
        case .chromeTabs:
            return ChromeModeAction.cycleTabsWithWheel.cell
        case .spotifyVolume:
            return StandardAppMode.spotifyVolumeWheelCell
        case .vsCodeCursorHistory:
            return VSCodeMode.cursorHistoryWheelCell
        case .codexReasoningEffort:
            return PhysicalCell(rawValue: 4)!
        case .codexChatHistory:
            return PhysicalCell(rawValue: 11)!
        default:
            return topLevelCell ?? utilityCell!
        }
    }

    /// Resolves the ordinary-layer system action without consulting Utility
    /// page state. Horizontal scrolling has its own wheel-event output path.
    public func topLevelSystemAction(
        for direction: WheelChordDirection
    ) -> ModeUtilityAction? {
        guard topLevelCell != nil, self == .clipboard else { return nil }
        return utilityAction(for: direction)
    }

    public func utilityAction(for direction: WheelChordDirection) -> ModeUtilityAction? {
        switch (self, direction) {
        // Ethan's physical ratchet reads more naturally with the opposite
        // semantic polarity from Quartz's conventional vertical sign.
        case (.brightness, .up): return .decreaseDisplayBrightness
        case (.brightness, .down): return .increaseDisplayBrightness
        case (.zoom, .up): return .zoomOut
        case (.zoom, .down): return .zoomIn
        case (.clipboard, .up): return .paste
        case (.clipboard, .down): return .copy
        case (.systemOverview, .up): return .missionControl
        case (.systemOverview, .down): return .showDesktop
        case (.applicationWindows, .up): return nil
        case (.applicationWindows, .down): return .showApplicationWindows
        case (.magnetWindow, .up): return .moveWindowLeftWithMagnet
        case (.magnetWindow, .down): return .moveWindowRightWithMagnet
        case (.spaces, .up): return .moveToSpaceRight
        case (.spaces, .down): return .moveToSpaceLeft
        case (.horizontalScroll, _), (.youtubeScrub, _), (.chromeTabs, _), (.spotifyVolume, _),
             (.vsCodeCursorHistory, _), (.codexReasoningEffort, _),
             (.codexChatHistory, _): return nil
        }
    }

    public func chromeTabAction(
        for direction: WheelChordDirection
    ) -> ChromeTabNavigationAction? {
        guard self == .chromeTabs else { return nil }
        // Match Ethan's accepted held-wheel convention: wheel up advances to
        // the item on the right; wheel down returns to the item on the left.
        return direction == .up ? .nextTab : .previousTab
    }

    public func youtubeSeekAction(
        for direction: WheelChordDirection
    ) -> YouTubeSeekAction? {
        guard self == .youtubeScrub else { return nil }
        // `WheelChordDirection` names Quartz's normalized delta sign, not the
        // physical ratchet direction Ethan feels. On both accepted mice, a
        // physical upward ratchet reaches this resolver as `.down`. Keep this
        // inversion local to YouTube Scrub so physical up advances and
        // physical down returns without changing another wheel family.
        return direction == .down ? .forwardFiveSeconds : .backwardFiveSeconds
    }

    public func spotifyVolumeAction(
        for direction: WheelChordDirection
    ) -> StandardAppModeAction? {
        guard self == .spotifyVolume else { return nil }
        return StandardAppMode.spotifyVolumeAction(for: direction)
    }

    public func vsCodeCursorHistoryCommand(
        for direction: WheelChordDirection
    ) -> VSCodeModeCommand? {
        guard self == .vsCodeCursorHistory else { return nil }
        // Match the accepted shared held-wheel convention: physical wheel up
        // advances, while physical wheel down returns.
        return direction == .up ? .navigateForward : .navigateBack
    }

    public func codexReasoningEffortAction(
        for direction: WheelChordDirection
    ) -> CodexReasoningEffortAction? {
        guard self == .codexReasoningEffort else { return nil }
        // `WheelChordDirection` names Quartz's normalized delta sign, not the
        // physical ratchet direction Ethan feels. On both accepted mice, a
        // physical upward ratchet reaches this resolver as `.down`. Keep this
        // inversion local to Reasoning Effort; other wheel families have their
        // own physically accepted polarity contracts.
        return direction == .down ? .increase : .decrease
    }

    public func codexChatHistoryAction(
        for direction: WheelChordDirection
    ) -> CodexChatHistoryAction? {
        guard self == .codexChatHistory else { return nil }
        // Match the shared held-wheel navigation convention: wheel up moves
        // right/forward and wheel down moves left/back.
        return direction == .up ? .forward : .back
    }

    /// Concise action copy for the shared HUD footer after the corresponding
    /// output route has actually accepted the request. Keep this semantic and
    /// source-independent so Corsair and Razer present the same result.
    public func feedbackActionTitle(for direction: WheelChordDirection) -> String? {
        if let action = utilityAction(for: direction) {
            return action.actionTitle
        }
        switch self {
        case .horizontalScroll:
            return direction == .up ? "Scroll Right" : "Scroll Left"
        case .youtubeScrub:
            return youtubeSeekAction(for: direction) == .forwardFiveSeconds
                ? "YouTube +5 sec"
                : "YouTube −5 sec"
        case .chromeTabs:
            return direction == .up ? "Next Tab" : "Previous Tab"
        case .spotifyVolume:
            return spotifyVolumeAction(for: direction)?.title
        case .vsCodeCursorHistory:
            return vsCodeCursorHistoryCommand(for: direction) == .navigateForward
                ? "Cursor History Forward"
                : "Cursor History Back"
        case .codexReasoningEffort:
            return codexReasoningEffortAction(for: direction) == .increase
                ? "Reasoning Effort Up"
                : "Reasoning Effort Down"
        case .codexChatHistory:
            return codexChatHistoryAction(for: direction) == .forward
                ? "Chat Forward"
                : "Chat Back"
        case .applicationWindows:
            // Wheel-up is intentionally consumed without an action.
            return nil
        case .brightness, .zoom, .clipboard, .systemOverview, .magnetWindow, .spaces:
            return nil
        }
    }

    public func hudFeedback(
        for direction: WheelChordDirection,
        detentCount: Int,
        outcome: WheelChordActionOutcome = .sent
    ) -> ModeHUDFeedback? {
        guard let actionTitle = feedbackActionTitle(for: direction) else { return nil }
        let count = max(1, detentCount)
        return ModeHUDFeedback(
            message: "\(actionTitle) \(outcome.copy) · \(count) "
                + (count == 1 ? "ratchet" : "ratchets"),
            tone: outcome.tone
        )
    }

    /// Some held-wheel controls deliberately reserve only one direction. The
    /// opposite detent remains consumed so the underlying page never scrolls,
    /// but it must not surface a false action-failed banner.
    public func accepts(_ direction: WheelChordDirection) -> Bool {
        self != .applicationWindows || direction == .down
    }

    /// One physical ratchet is not guaranteed to arrive as one Quartz event.
    /// Choose action cadence from semantics rather than treating each event as
    /// a new user request.
    public var dispatchPolicy: WheelChordDispatchPolicy {
        switch self {
        case .brightness, .zoom:
            return .everyAcceptedEvent
        case .systemOverview, .applicationWindows, .spaces:
            return .oncePerHold
        case .clipboard:
            return .debounced(minimumInterval: 0.12)
        case .horizontalScroll, .youtubeScrub, .chromeTabs, .spotifyVolume, .codexChatHistory:
            // Chats Selection deliberately uses this fixed leading-edge window:
            // collapse one detent's duplicate raw events, but do not let those
            // duplicates extend a quiet gap and swallow later ratchets.
            return .debounced(minimumInterval: 0.08)
        case .vsCodeCursorHistory, .codexReasoningEffort:
            // Measure duplicate same-direction bursts from the latest raw
            // event rather than the last dispatched action. This reconstructs
            // one semantic step per physical ratchet while preserving an
            // intentional immediate direction reversal.
            return .coalescedRatchet(quietGap: 0.15)
        case .magnetWindow:
            return .debounced(minimumInterval: 0.15)
        }
    }
}

public enum YouTubeSeekAction: Equatable, Sendable {
    case backwardFiveSeconds
    case forwardFiveSeconds

    public var seconds: Int {
        switch self {
        case .backwardFiveSeconds: return -5
        case .forwardFiveSeconds: return 5
        }
    }
}

public enum CodexReasoningEffortAction: Equatable, Sendable {
    case increase
    case decrease
}

public enum CodexChatHistoryAction: Equatable, Sendable {
    case back
    case forward
}

public enum WheelChordActionOutcome: Equatable, Sendable {
    case sent
    case couldNotBeSent
    case couldNotBeQueued

    fileprivate var copy: String {
        switch self {
        case .sent: return "sent"
        case .couldNotBeSent: return "could not be sent"
        case .couldNotBeQueued: return "could not be queued"
        }
    }

    fileprivate var tone: ModeHUDFeedback.Tone {
        self == .sent ? .informational : .notConfirmed
    }
}

public enum WheelChordDispatchPolicy: Equatable, Sendable {
    /// Continuous values retain every accepted event so the held control still
    /// feels analogue. Discrete native scrolling reconstructs ratchets instead.
    case everyAcceptedEvent
    /// A press-plus-wheel gesture represents exactly one action. Later wheel
    /// events remain consumed until the physical control is released.
    case oncePerHold
    /// Discrete selectors may repeat during one hold, but only after the short
    /// duplicate burst associated with the prior physical ratchet has ended.
    case debounced(minimumInterval: TimeInterval)
    /// Reconstruct one ratchet from a same-direction burst by sliding the
    /// quiet window from every raw event. An immediate reversal remains a
    /// deliberate selection of the paired action.
    case coalescedRatchet(quietGap: TimeInterval)
}

public enum ChromeTabNavigationAction: Equatable, Sendable {
    case previousTab
    case nextTab
}

public enum WheelChordDirection: Equatable, Sendable {
    case up
    case down

    /// Quartz line-wheel convention: positive primary-axis movement is up.
    public init?(verticalDelta: Int64) {
        guard verticalDelta != 0 else { return nil }
        self = verticalDelta > 0 ? .up : .down
    }

    /// Conventional mouse drivers normally populate the line delta, while a
    /// virtual pointing device may populate only the point or 16.16 fixed-
    /// point field. Direction needs only a sign, so prefer the most semantic
    /// line value and then fall back without scaling or accumulating pixels.
    public static func effectiveVerticalDelta(
        lineDelta: Int64,
        pointDelta: Int64,
        fixedPointDelta: Int64
    ) -> Int64 {
        if lineDelta != 0 { return lineDelta }
        if pointDelta != 0 { return pointDelta }
        return fixedPointDelta == 0 ? 0 : (fixedPointDelta > 0 ? 1 : -1)
    }

    /// The output polarity is intentionally inverted from the initial Quartz
    /// convention after Ethan's physical acceptance: wheel up moves right and
    /// wheel down moves left.
    public var horizontalWheelDelta: Int32 {
        switch self {
        case .up: return -1
        case .down: return 1
        }
    }
}

/// Bounded per-source throttle for the temporary wheel trace shown in the HUD.
///
/// The action path never consults this object. Only diagnostic rendering is
/// rate-limited, so a noisy virtual pointer cannot flood SwiftUI or obscure the
/// useful routing verdict.
public final class WheelChordDiagnosticThrottle {
    private let clock: MonotonicClock
    private let minimumInterval: TimeInterval
    private var lastEmissionBySource: [MouseSource: TimeInterval] = [:]

    public init(
        clock: MonotonicClock = SystemMonotonicClock(),
        minimumInterval: TimeInterval = 0.125
    ) {
        self.clock = clock
        self.minimumInterval = max(0, minimumInterval)
    }

    public func shouldEmit(for source: MouseSource) -> Bool {
        let now = clock.now
        if let last = lastEmissionBySource[source], now - last < minimumInterval {
            return false
        }
        lastEmissionBySource[source] = now
        return true
    }

    public func reset(source: MouseSource) {
        lastEmissionBySource[source] = nil
    }

    public func resetAll() {
        lastEmissionBySource.removeAll()
    }
}

/// Pure state model kept outside the event tap so lifecycle, ambiguity, and
/// bounded routing can be tested without Accessibility or connected mice.
public final class WheelChordStateMachine {
    public struct Step: Equatable, Sendable {
        public let source: MouseSource
        public let control: WheelChordControl
        public let direction: WheelChordDirection
        /// One-based count of accepted wheel detents since this source chord
        /// was armed. It resets on every press/release lifecycle.
        public let detentCount: Int

        public init(
            source: MouseSource,
            control: WheelChordControl,
            direction: WheelChordDirection,
            detentCount: Int = 1
        ) {
            self.source = source
            self.control = control
            self.direction = direction
            self.detentCount = detentCount
        }
    }

    public enum Routing: Equatable, Sendable {
        case passThrough
        case consume(Step)
        /// The held control deliberately does not own this wheel direction.
        /// Consume it without dispatching or presenting an error.
        case consumeInactiveDirection(Step)
        /// A one-shot held control already acted during this physical hold.
        /// Consume the later event without dispatching another shortcut.
        case consumeAfterFirstHoldAction(Step)
        /// A discrete control received another Quartz event too soon to be a
        /// distinct intentional ratchet. Consume it without dispatching.
        case consumeDebounced(Step)
        case consumeAmbiguous
    }

    private let clock: MonotonicClock
    private var activeBySource: [MouseSource: WheelChordControl] = [:]
    private var acceptedDetentCountBySource: [MouseSource: Int] = [:]
    private var didActBySource: [MouseSource: Bool] = [:]
    private var lastActionBySource: [MouseSource: (WheelChordDirection, TimeInterval)] = [:]

    public init(clock: MonotonicClock = SystemMonotonicClock()) {
        self.clock = clock
    }

    public func setActive(
        _ control: WheelChordControl?,
        for source: MouseSource
    ) {
        let previous = activeBySource[source]
        activeBySource[source] = control
        if control == nil {
            acceptedDetentCountBySource[source] = nil
            didActBySource[source] = nil
            lastActionBySource[source] = nil
        } else if previous != control || acceptedDetentCountBySource[source] == nil {
            acceptedDetentCountBySource[source] = 0
            didActBySource[source] = false
            lastActionBySource[source] = nil
        }
    }

    public func clear(source: MouseSource) {
        activeBySource[source] = nil
        acceptedDetentCountBySource[source] = nil
        didActBySource[source] = nil
        lastActionBySource[source] = nil
    }

    public func clearAll() {
        activeBySource.removeAll()
        acceptedDetentCountBySource.removeAll()
        didActBySource.removeAll()
        lastActionBySource.removeAll()
    }

    public func activeControl(for source: MouseSource) -> WheelChordControl? {
        activeBySource[source]
    }

    public var soleActiveChord: (source: MouseSource, control: WheelChordControl)? {
        guard activeBySource.count == 1,
              let (source, control) = activeBySource.first
        else { return nil }
        return (source, control)
    }

    public func route(
        verticalDelta: Int64,
        isContinuous: Bool,
        scrollPhase: Int64 = 0,
        momentumPhase: Int64 = 0
    ) -> Routing {
        guard let direction = WheelChordDirection(verticalDelta: verticalDelta) else {
            return .passThrough
        }

        // Karabiner's VirtualHIDPointing can mark a conventional ratcheted
        // mouse wheel as continuous even though it carries no gesture or
        // momentum phase. Treat phase-bearing input as a trackpad gesture,
        // but accept phase-free detents so exact-device held chords work
        // through both physical mouse adapters.
        let isGestureScroll = isContinuous && (scrollPhase != 0 || momentumPhase != 0)
        guard !isGestureScroll else {
            return .passThrough
        }
        guard activeBySource.count == 1, let (source, control) = activeBySource.first else {
            return activeBySource.isEmpty ? .passThrough : .consumeAmbiguous
        }
        let detentCount = acceptedDetentCountBySource[source, default: 0] + 1
        acceptedDetentCountBySource[source] = detentCount
        let step = Step(
            source: source,
            control: control,
            direction: direction,
            detentCount: detentCount
        )
        guard control.accepts(direction) else {
            return .consumeInactiveDirection(step)
        }
        switch control.dispatchPolicy {
        case .everyAcceptedEvent:
            break
        case .oncePerHold:
            guard didActBySource[source] != true else {
                return .consumeAfterFirstHoldAction(step)
            }
            didActBySource[source] = true
        case .debounced(let minimumInterval):
            let now = clock.now
            if let (lastDirection, lastActionTime) = lastActionBySource[source],
               lastDirection == direction,
               now - lastActionTime < max(0, minimumInterval) {
                return .consumeDebounced(step)
            }
            // A reversal selects the opposite half of the paired control and
            // is therefore intentional even inside the same quiet window.
            lastActionBySource[source] = (direction, now)
        case .coalescedRatchet(let quietGap):
            let now = clock.now
            if let (lastDirection, lastInputTime) = lastActionBySource[source],
               lastDirection == direction,
               now - lastInputTime < max(0, quietGap) {
                // Extend the quiet window from the latest raw event. A long
                // physical ratchet burst therefore cannot escape merely
                // because its first event is now old.
                lastActionBySource[source] = (direction, now)
                return .consumeDebounced(step)
            }
            // A reversal intentionally selects the opposite half of the pair
            // and therefore dispatches immediately.
            lastActionBySource[source] = (direction, now)
        }
        return .consume(step)
    }
}

/// Top-level exact-device ingress for ordinary Copy/Paste, Horizontal Scroll,
/// and YouTube Scrub chords. Spaces, Brightness, and Zoom use the Utility mode
/// press/release stream.
public struct WheelChordCommand: Equatable, Codable, Sendable {
    public static let commandName = "agentic_mouse_wheel_chord"

    public let command: String
    public let control: WheelChordControl
    public let source: MouseSource
    public let phase: ModePickerCommand.Phase

    public init(
        control: WheelChordControl,
        source: MouseSource,
        phase: ModePickerCommand.Phase
    ) {
        command = Self.commandName
        self.control = control
        self.source = source
        self.phase = phase
    }

    public static func decode(_ data: Data) throws -> WheelChordCommand {
        let decoded = try JSONDecoder().decode(WheelChordCommand.self, from: data)
        guard decoded.command == commandName else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "unexpected user-command namespace")
            )
        }
        return decoded
    }

    /// The ordinary-layer command socket accepts only controls that have a
    /// canonical top-level cell. Utility-only controls are armed through the
    /// active mode coordinator and must not cross this ingress boundary.
    public static func decodeTopLevel(_ data: Data) throws -> WheelChordCommand {
        let decoded = try decode(data)
        guard decoded.control.topLevelCell != nil else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "control has no top-level cell")
            )
        }
        return decoded
    }
}
