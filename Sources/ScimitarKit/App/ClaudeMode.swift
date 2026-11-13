import Foundation

public enum ClaudeModeAction: String, CaseIterable, Equatable, Sendable {
    case toggleDictation
    case newChat
    case pressEnter
    case toggleFastMode
    case chooseEffort
    case openSideChat
    case closePane

    public var cell: PhysicalCell {
        switch self {
        case .toggleDictation: return CodexModeAction.toggleVoiceMode.cell
        case .newChat: return CodexModeAction.newTask.cell
        case .pressEnter: return CodexModeAction.pressEnter.cell
        case .toggleFastMode: return CodexMode.responseSpeedWheelCell
        case .chooseEffort: return CodexMode.reasoningEffortWheelCell
        case .openSideChat: return CodexModeAction.openSideChat.cell
        case .closePane: return CodexModeAction.closeTab.cell
        }
    }

    public var title: String {
        switch self {
        case .toggleDictation: return "Dictation"
        case .newChat: return "New chat"
        case .pressEnter: return CodexModeAction.pressEnter.title
        case .toggleFastMode: return "Fast mode"
        case .chooseEffort: return "Choose effort"
        case .openSideChat: return CodexModeAction.openSideChat.title
        case .closePane: return "Close pane"
        }
    }

    public var hudAccent: RGBColor {
        switch self {
        case .toggleDictation: return RGBColor(red: 29, green: 211, blue: 211)
        case .newChat: return RGBColor(red: 52, green: 150, blue: 255)
        case .pressEnter: return CodexModeAction.pressEnter.hudAccent
        case .toggleFastMode: return WheelChordControl.codexResponseSpeed.hudAccent
        case .chooseEffort: return WheelChordControl.codexReasoningEffort.hudAccent
        case .openSideChat: return CodexModeAction.openSideChat.hudAccent
        case .closePane: return CodexModeAction.closeTab.hudAccent
        }
    }

    public static func action(for cell: PhysicalCell) -> ClaudeModeAction? {
        allCases.first { $0.cell == cell }
    }
}

public enum ClaudeMode {
    public static let bundleIdentifier = "com.anthropic.claudefordesktop"
    public static let accent = RGBColor(red: 222, green: 121, blue: 82)
    // Match Codex muscle memory while using Claude's own native commands.
    public static let pinToggleCell = CodexMode.pinToggleCell
    public static let tabsWheelCell = CodexMode.chatHistoryWheelCell

    public static let definition = AppSpecificModeDefinition(
        title: "Claude mode",
        footerTitle: "Claude mode",
        accent: accent,
        outlineWidth: 4.5,
        legend: PhysicalCell.all.map { cell in
            if cell.isAppSpecificModeExit {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Exit Claude mode",
                    accent: accent,
                    appBackdrop: ModeHUDAppBackdrop(bundleIdentifier: bundleIdentifier)
                ).withWandTitle("Exit Claude mode")
            }
            if cell == pinToggleCell {
                let pin = WheelChordControl.claudePin
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: CodexModeAction.togglePin.title,
                    accent: pin.hudAccent
                ).withWandTitle("\(pin.hudHoldTitle) \(pin.wandHUDMotion.glyph)")
            }
            if let control = WheelChordControl.appSpecificControl(for: .claude, cell: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    gesture: control.hudGesture,
                    accent: control.hudAccent
                )
            }
            if let action = ClaudeModeAction.action(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.title,
                    accent: action.hudAccent
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
