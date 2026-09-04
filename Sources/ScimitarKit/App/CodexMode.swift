import Foundation

public enum CodexModeAction: String, CaseIterable, Equatable, Sendable {
    case newTask
    case togglePin
    case toggleMicrophoneMute
    case toggleVoiceMode
    case openSideChat
    case steerQueuedMessage
    case editQueuedMessage
    case pressEnter

    public var cell: PhysicalCell {
        switch self {
        case .newTask: return PhysicalCell(rawValue: 5)!
        case .togglePin: return PhysicalCell(rawValue: 3)!
        case .toggleMicrophoneMute: return PhysicalCell(rawValue: 11)!
        case .toggleVoiceMode: return PhysicalCell(rawValue: 12)!
        case .openSideChat: return PhysicalCell(rawValue: 9)!
        case .steerQueuedMessage: return PhysicalCell(rawValue: 1)!
        case .editQueuedMessage: return PhysicalCell(rawValue: 8)!
        case .pressEnter: return PhysicalCell(rawValue: 7)!
        }
    }

    public var title: String {
        switch self {
        case .newTask: return "New chat"
        case .togglePin: return "Pin / unpin"
        case .toggleMicrophoneMute: return "Mute / unmute voice mic"
        case .toggleVoiceMode: return "Voice mode"
        case .openSideChat: return "Open side chat"
        case .steerQueuedMessage: return "Steer queued message"
        case .editQueuedMessage: return "Edit queued message"
        case .pressEnter: return "Enter"
        }
    }

    public var hudAccent: RGBColor {
        switch self {
        case .newTask: return RGBColor(red: 52, green: 150, blue: 255)
        case .togglePin: return RGBColor(red: 255, green: 188, blue: 58)
        case .toggleMicrophoneMute: return RGBColor(red: 255, green: 72, blue: 137)
        case .toggleVoiceMode: return RGBColor(red: 29, green: 211, blue: 211)
        case .openSideChat: return RGBColor(red: 72, green: 189, blue: 255)
        case .steerQueuedMessage: return RGBColor(red: 255, green: 121, blue: 48)
        case .editQueuedMessage: return RGBColor(red: 255, green: 149, blue: 64)
        case .pressEnter: return ModeHUDActionFamilyPalette.enter
        }
    }

    /// Controls whose newest physical report is still failed. Do not clear a
    /// marker for a source-only fix or an install; Ethan's later physical
    /// acceptance is the clearing boundary.
    public var hudControlStatus: ModeHUDControlStatus {
        switch self {
        case .toggleVoiceMode, .editQueuedMessage:
            return .reportedBroken
        case .newTask, .togglePin, .toggleMicrophoneMute, .openSideChat,
             .steerQueuedMessage, .pressEnter:
            return .normal
        }
    }

    public static func action(for cell: PhysicalCell) -> CodexModeAction? {
        allCases.first { $0.cell == cell }
    }
}

public enum CodexMode {
    public static let bundleIdentifier = "com.openai.codex"
    public static let accent = RGBColor(red: 0, green: 218, blue: 184)
    public static let chatHistoryWheelCell = PhysicalCell(rawValue: 6)! // Swap Codex cells 6 and 11 on both mice; share this cell between routing, the HUD and wheel feedback. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)

    public static let definition = AppSpecificModeDefinition(
        title: "Codex mode",
        footerTitle: "Codex mode",
        footerHint: nil,
        accent: accent,
        legend: PhysicalCell.all.map { cell in
            if cell.isAppSpecificModeExit {
                return ModeHUDLegendItem(cell: cell, actionTitle: "Exit Codex mode", accent: accent)
            }
            if let control = WheelChordControl.appSpecificControl(for: .codex, cell: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "\(control.actionTitle) + Wheel",
                    accent: control.hudAccent,
                    controlStatus: control.hudControlStatus
                )
            }
            if let action = CodexModeAction.action(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.title,
                    accent: action.hudAccent,
                    controlStatus: action.hudControlStatus
                )
            }
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Spare",
                accent: RGBColor(red: 96, green: 108, blue: 120)
            )
        }
    )
}
