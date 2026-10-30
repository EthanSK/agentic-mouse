import Foundation

public enum VSCodeModeAction: String, CaseIterable, Equatable, Sendable {
    case closeTab
    case find
    case previousChange
    case nextChange
    case stageAndNext
    case toggleTerminal
    case commandPalette
    case goToDefinition
    case interruptTerminal

    public var cell: PhysicalCell {
        switch self {
        case .closeTab: return PhysicalCell(rawValue: 1)!
        case .find: return PhysicalCell(rawValue: 3)!
        case .previousChange: return PhysicalCell(rawValue: 5)!
        case .nextChange: return PhysicalCell(rawValue: 8)!
        case .stageAndNext: return PhysicalCell(rawValue: 9)!
        case .toggleTerminal: return PhysicalCell(rawValue: 4)!
        case .commandPalette: return PhysicalCell(rawValue: 7)!
        case .goToDefinition: return PhysicalCell(rawValue: 11)!
        case .interruptTerminal: return .interruptTerminal
        }
    }

    public var title: String {
        switch self {
        case .closeTab: return "Close tab"
        case .find: return "Find"
        case .previousChange: return "Prev / Hold stage"
        case .nextChange: return "Next / Hold stage"
        case .stageAndNext: return "Stage + Next / Undo Stage ×2"
        case .toggleTerminal: return "Toggle Terminal"
        case .commandPalette: return "Command Palette"
        case .goToDefinition: return "Go to Definition"
        case .interruptTerminal: return "Interrupt terminal"
        }
    }

    /// The same Better Git command pairs used by the ordinary VS Code layer.
    /// Keeping the gesture semantics here means the automatic and manually
    /// selected VS Code pages cannot drift from their own HUD copy.
    public var singlePressCommand: VSCodeModeCommand {
        switch self {
        case .closeTab: return .closeTab
        case .find: return .find
        case .previousChange: return .previousChange
        case .nextChange: return .nextChange
        case .stageAndNext: return .stageAndNext
        case .toggleTerminal: return .toggleTerminal
        case .commandPalette: return .commandPalette
        case .goToDefinition: return .goToDefinition
        case .interruptTerminal: return .interruptTerminal
        }
    }

    public var doublePressCommand: VSCodeModeCommand? {
        switch self {
        case .previousChange: return .stageAndPrevious
        case .nextChange: return .stageAndNext
        case .stageAndNext: return .undoLastStageAndAdvance
        case .closeTab, .find,
             .toggleTerminal, .commandPalette, .goToDefinition,
             .interruptTerminal:
            return nil
        }
    }

    public var accent: RGBColor {
        switch self {
        case .closeTab:
            return RGBColor(red: 86, green: 156, blue: 255)
        case .find, .commandPalette, .goToDefinition:
            return RGBColor(red: 255, green: 190, blue: 62)
        case .previousChange, .nextChange:
            return RGBColor(red: 0, green: 168, blue: 255)
        case .stageAndNext:
            return RGBColor(red: 72, green: 215, blue: 112)
        case .toggleTerminal:
            return RGBColor(red: 183, green: 128, blue: 255)
        case .interruptTerminal:
            return TerminalMode.interruptAccent
        }
    }

    public var hudControlStatus: ModeHUDControlStatus {
        .normal
    }

    public static func action(for cell: PhysicalCell) -> VSCodeModeAction? {
        allCases.first { $0.cell == cell }
    }
}

/// Semantic commands emitted by both VS Code mode journeys. The app shell is
/// the only layer that translates these into macOS key codes.
public enum VSCodeModeCommand: String, Equatable, Sendable {
    case beginNextChangeHold
    case beginPreviousChangeHold
    case finishNextChangeHold
    case finishPreviousChangeHold
    case cancelNavigationHold
    case stageHoldReady
    case stageHoldClear
    case closeTab
    case find
    case previousChange
    case nextChange
    case stageAndPrevious
    case stageAndNext
    case undoLastStageAndAdvance
    case toggleTerminal
    case commandPalette
    case goToDefinition
    case interruptTerminal
    case navigateBack
    case navigateForward
}

/// Owns runtime-page holds and the separate Stage button's existing double click.
/// Default navigation uses native Karabiner holds; runtime pages dispatch to their
/// selected app, so they use this source-owned classifier instead. Both share the
/// 200 ms release-based hold contract. Better Git owns all undo data.
public final class VSCodeModeGestureClassifier {
    private struct PendingPress {
        let action: VSCodeModeAction
        let pressedAt: TimeInterval
        let emit: (VSCodeModeCommand) -> Void
    }

    private let clock: MonotonicClock
    private let scheduler: TickScheduler
    private let doubleClickInterval: TimeInterval
    private var pending: PendingPress?
    private var heldNavigation: (action: VSCodeModeAction, pressedAt: TimeInterval)?
    private var undoChordConsumed = false
    private var stageHoldReady = false
    private var stageRangeWheelArmed = false
    private var stageRangeNavigationChordDown = false
    private var adjacentPreviewChordDown: PhysicalCell?
    private let stageRangePreviewNavigationEnabled: Bool
    public var onStageHoldReadyChange: ((Bool) -> Void)?
    public var onStageRangeWheelReadyChange: ((Bool) -> Void)?
    public var onStageRangeNavigationChange: ((Bool) -> Void)?
    public static let stageHoldThreshold: TimeInterval = 0.20

    public var isStageRangeNavigationActive: Bool {
        stageRangeWheelArmed && stageRangeNavigationChordDown
    }

    public init(
        clock: MonotonicClock,
        scheduler: TickScheduler,
        doubleClickInterval: TimeInterval = 0.3,
        stageRangePreviewNavigationEnabled: Bool = VSCodeModeFeatureFlags.stageRangePreviewNavigation
    ) {
        self.clock = clock
        self.scheduler = scheduler
        self.doubleClickInterval = max(0.15, doubleClickInterval)
        self.stageRangePreviewNavigationEnabled = stageRangePreviewNavigationEnabled
    }

    public func handlePress(
        action: VSCodeModeAction,
        emit: @escaping (VSCodeModeCommand) -> Void
    ) {
        clearStageHoldFeedback()
        heldNavigation = nil
        undoChordConsumed = false
        guard let doubleCommand = action.doublePressCommand else {
            commitPendingSinglePress()
            emit(action.singlePressCommand)
            return
        }

        if let pending {
            let isSameGesture = pending.action == action
                && clock.now - pending.pressedAt <= doubleClickInterval
            if isSameGesture {
                scheduler.stop()
                self.pending = nil
                emit(doubleCommand)
                return
            }
            commitPendingSinglePress()
        }

        pending = PendingPress(action: action, pressedAt: clock.now, emit: emit)
        scheduler.start(interval: doubleClickInterval) { [weak self] in
            self?.commitPendingSinglePress()
        }
    }

    /// Decide on release using socket-ingress timing, never the delayed main-thread clock.
    public func handleNavigation(
        action: VSCodeModeAction,
        phase: ModePickerCommand.Phase,
        inputTime: TimeInterval,
        emit: @escaping (VSCodeModeCommand) -> Void
    ) {
        guard action == .nextChange || action == .previousChange else { return }
        switch phase {
        case .press:
            guard heldNavigation?.action != action else { return }
            commitPendingSinglePress()
            clearStageHoldFeedback()
            heldNavigation = (action, inputTime)
            undoChordConsumed = false
            emit(action == .nextChange ? .beginNextChangeHold : .beginPreviousChangeHold)
            scheduler.start(interval: max(0.001, Self.stageHoldThreshold - (clock.now - inputTime))) { [weak self] in
                guard let self, self.heldNavigation?.action == action,
                      self.heldNavigation?.pressedAt == inputTime, !self.undoChordConsumed else { return }
                self.scheduler.stop()
                self.stageHoldReady = true // A delayed timer may show readiness, but must never stage; only the original ingress duration on release decides. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
                self.onStageHoldReadyChange?(true)
                self.stageRangeWheelArmed = true
                self.onStageRangeWheelReadyChange?(true)
            }
        case .release:
            guard let held = heldNavigation, held.action == action else { return }
            scheduler.stop()
            heldNavigation = nil
            setStageRangeNavigationMode(false)
            adjacentPreviewChordDown = nil
            let consumed = undoChordConsumed
            undoChordConsumed = false
            guard !consumed else {
                clearStageHoldFeedback()
                return
            }
            guard inputTime >= held.pressedAt else {
                disarmStageRangeWheel()
                finishStageHoldTransaction()
                return
            }
            let isHold = inputTime - held.pressedAt >= Self.stageHoldThreshold
            disarmStageRangeWheel()
            emit(isHold
                ? (action == .nextChange ? .finishNextChangeHold : .finishPreviousChangeHold)
                : .cancelNavigationHold)
            finishStageHoldTransaction()
        }
    }

    /// Holding Next + Enter, or Previous + Copy, consumes both buttons and undoes once.
    public func handleUndoChord(cell: PhysicalCell, emit: (VSCodeModeCommand) -> Void) -> Bool {
        guard let held = heldNavigation,
              (held.action == .nextChange && cell.rawValue == 7)
                || (held.action == .previousChange && cell.rawValue == 4)
        else { return false }
        guard !undoChordConsumed else { return true }
        scheduler.stop()
        undoChordConsumed = true // Waiting until release to stage lets Undo consume even an already-long hold. Repeated long holds must stage independently, never undo. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
        disarmStageRangeWheel()
        emit(.cancelNavigationHold)
        emit(.undoLastStageAndAdvance)
        finishStageHoldTransaction()
        return true
    }

    /// The adjacent button enables wheel review only while it remains held
    /// alongside the navigation owner. Consume early presses too, so they
    /// cannot open Keys or run Stage + Next.
    public func handleAdjacentPreviewChord(
        cell: PhysicalCell,
        phase: ModePickerCommand.Phase
    ) -> (handled: Bool, direction: VSCodeStagePreviewDirection?) {
        switch phase {
        case .press:
            guard let held = heldNavigation, !undoChordConsumed,
                  (held.action == .nextChange && cell.rawValue == 9)
                    || (held.action == .previousChange && cell.rawValue == 6)
            else { return (false, nil) }
            guard adjacentPreviewChordDown != cell else { return (true, nil) }
            adjacentPreviewChordDown = cell
            if stageRangePreviewNavigationEnabled { setStageRangeNavigationMode(true) }
            return (true, stageHoldReady && stageRangeNavigationChordDown
                ? (held.action == .nextChange ? .next : .previous)
                : nil)
        case .release:
            guard adjacentPreviewChordDown == cell else { return (false, nil) }
            adjacentPreviewChordDown = nil
            if stageRangePreviewNavigationEnabled { setStageRangeNavigationMode(false) }
            return (true, nil)
        }
    }

    /// While a navigation hold owns the stage-range wheel, physical cell 9 is
    /// a momentary modifier for preview navigation. Consuming both phases here
    /// prevents its normal Stage + Next / double-click Undo gesture from
    /// firing, while leaving the selected batch and release staging intact.
    public func handleStageRangeNavigationChord(
        action: VSCodeModeAction,
        phase: ModePickerCommand.Phase
    ) -> Bool {
        guard stageRangePreviewNavigationEnabled else { return false }
        guard action == .stageAndNext else { return false }
        return handleAdjacentPreviewChord(cell: action.cell, phase: phase).handled
    }

    public func commitPendingSinglePress() {
        scheduler.stop()
        guard let pending else { return }
        self.pending = nil
        pending.emit(pending.action.singlePressCommand)
    }

    public func cancel() {
        clearStageHoldFeedback()
        pending = nil
        heldNavigation = nil
        undoChordConsumed = false
        stageRangeNavigationChordDown = false
        adjacentPreviewChordDown = nil
    }

    private func clearStageHoldFeedback() {
        scheduler.stop()
        setStageRangeNavigationMode(false)
        adjacentPreviewChordDown = nil
        disarmStageRangeWheel()
        guard stageHoldReady else { return }
        stageHoldReady = false
        onStageHoldReadyChange?(false)
    }

    /// F15 is the release transaction boundary Better Git uses to distinguish
    /// a short F14 from the adjacent-cancel F14/F16 sequence. Emit it after the
    /// final release command even when the hold never reached readiness.
    private func finishStageHoldTransaction() {
        scheduler.stop()
        disarmStageRangeWheel()
        stageHoldReady = false
        stageRangeNavigationChordDown = false
        onStageHoldReadyChange?(false)
    }

    private func disarmStageRangeWheel() {
        setStageRangeNavigationMode(false)
        guard stageRangeWheelArmed else { return }
        stageRangeWheelArmed = false
        onStageRangeWheelReadyChange?(false)
    }

    private func setStageRangeNavigationMode(_ active: Bool) {
        let wasActive = isStageRangeNavigationActive
        stageRangeNavigationChordDown = active
        let isActive = isStageRangeNavigationActive
        if wasActive != isActive { onStageRangeNavigationChange?(isActive) }
    }
}

public enum VSCodeModeFeatureFlags {
    /// An adjacent press toggles wheel review until the navigation owner releases.
    public static let stageRangePreviewNavigation = true
}

/// A Default-layer adjacent tap toggles between preview and range selection.
/// The stage owner starts in preview mode and controls its lifetime.
public struct VSCodeStagePreviewModifierCommand: Codable, Equatable, Sendable {
    public static let commandName = "agentic_mouse_vscode_stage_preview_modifier"

    public enum Event: String, Codable, Equatable, Sendable {
        case toggle
    }

    public let command: String
    public let source: MouseSource
    public let event: Event

    public init(source: MouseSource, event: Event = .toggle) {
        command = Self.commandName
        self.source = source
        self.event = event
    }

    public static func decode(_ data: Data) throws -> Self {
        let decoded = try JSONDecoder().decode(Self.self, from: data)
        guard decoded.command == commandName else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [], debugDescription: "unexpected user-command namespace"
            ))
        }
        return decoded
    }
}

public final class VSCodeStagePreviewModifierState {
    public enum CleanupReason {
        case ownerRelease
        case cancellation
    }

    private var activeSources = Set<MouseSource>()

    public init() {}

    @discardableResult
    public func setActive(_ active: Bool, for source: MouseSource) -> Bool {
        if active {
            return activeSources.insert(source).inserted
        }
        return activeSources.remove(source) != nil
    }

    /// Enables default Eyes only for the top-level layer; the entered VS Code
    /// page keeps its independent momentary adjacent-button interaction.
    @discardableResult
    public func activateDefaultForReadyStage(
        source: MouseSource,
        appSpecificModeActive: Bool
    ) -> Bool {
        guard !appSpecificModeActive else { return false }
        _ = setActive(true, for: source)
        return true
    }

    /// Ignores adjacent taps until the same source owns a ready stage range.
    /// Returns the new state when a toggle is accepted.
    public func handle(
        _ command: VSCodeStagePreviewModifierCommand,
        whileStageRangeActive: Bool
    ) -> Bool? {
        guard whileStageRangeActive else { return nil }
        switch command.event {
        case .toggle:
            let active = !isActive(for: command.source)
            _ = setActive(active, for: command.source)
            return active
        }
    }

    public func isActive(for source: MouseSource) -> Bool {
        activeSources.contains(source)
    }

    /// Clears the local latch and returns whether Better Git needs a mode-off
    /// request. On normal owner release, Better Git must retain Eyes until its
    /// release transaction excludes the final previewed file, then clear it.
    @discardableResult
    public func clear(source: MouseSource, reason: CleanupReason = .cancellation) -> Bool {
        let wasActive = activeSources.remove(source) != nil
        return wasActive && reason == .cancellation
    }

    public func clearAll() {
        activeSources.removeAll()
    }
}

/// Source-owned, one-step Better Git preview navigation from a Default-layer
/// adjacent button. The extension keeps the active stage selection intact.
public struct VSCodeStagePreviewCommand: Codable, Equatable, Sendable {
    public static let commandName = "agentic_mouse_vscode_stage_preview"

    public let command: String
    public let source: MouseSource
    public let direction: VSCodeStagePreviewDirection

    public init(source: MouseSource, direction: VSCodeStagePreviewDirection) {
        command = Self.commandName
        self.source = source
        self.direction = direction
    }

    public static func decode(_ data: Data) throws -> Self {
        let decoded = try JSONDecoder().decode(Self.self, from: data)
        guard decoded.command == commandName else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [], debugDescription: "unexpected user-command namespace"
            ))
        }
        return decoded
    }
}

public enum VSCodeMode {
    public static func undoHint(source: MouseSource) -> String {
        let previousPartner = PhysicalCell(rawValue: 4)!.printedSide(on: source)!
        let nextPartner = PhysicalCell(rawValue: 7)!.printedSide(on: source)!
        return "Undo: hold 5 + \(previousPartner) or 8 + \(nextPartner)"
    }

    public static let accent = RGBColor(red: 0, green: 168, blue: 255)
    public static let cursorHistoryWheelCell = PhysicalCell(rawValue: 6)!

    public static let definition = AppSpecificModeDefinition(
        title: "VS Code mode",
        footerTitle: "VS Code mode",
        accent: accent,
        legend: PhysicalCell.all.map { cell in
            if cell.isAppSpecificModeExit {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Exit VS Code mode",
                    accent: accent
                )
            }
            if let control = WheelChordControl.appSpecificControl(for: .vsCode, cell: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    gesture: control.hudGesture,
                    accent: control.hudAccent,
                    controlStatus: control.hudControlStatus
                )
            }
            if let action = VSCodeModeAction.action(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.title,
                    accent: action.accent,
                    controlStatus: action.hudControlStatus
                )
            }
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Spare",
                accent: RGBColor(red: 118, green: 126, blue: 142)
            )
        }
    )
}
