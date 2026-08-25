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
        case .previousChange: return "Previous Change"
        case .nextChange: return "Next Change"
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

/// Applies the proven 300 ms Better Git single/double-click classifier inside
/// an app-specific page. AppDelegate creates one instance per exact mouse so
/// the two independent mode/HUD journeys can never combine their clicks.
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

    public init(
        clock: MonotonicClock,
        scheduler: TickScheduler,
        doubleClickInterval: TimeInterval = 0.3
    ) {
        self.clock = clock
        self.scheduler = scheduler
        self.doubleClickInterval = max(0.15, doubleClickInterval)
    }

    public func handlePress(
        action: VSCodeModeAction,
        emit: @escaping (VSCodeModeCommand) -> Void
    ) {
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

    public func commitPendingSinglePress() {
        scheduler.stop()
        guard let pending else { return }
        self.pending = nil
        pending.emit(pending.action.singlePressCommand)
    }

    public func cancel() {
        scheduler.stop()
        pending = nil
    }
}

public enum VSCodeMode {
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
                    actionTitle: "\(control.actionTitle) + Wheel",
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
