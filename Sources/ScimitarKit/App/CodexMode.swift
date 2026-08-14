import Foundation

public enum CodexModeAction: String, CaseIterable, Equatable, Sendable {
    case newTask
    case togglePin
    case toggleMicrophoneMute
    case toggleVoiceMode
    case steerQueuedMessage
    case pressEnter
    case startNewVoiceChat
    case increaseReasoningEffort
    case decreaseReasoningEffort

    public var cell: PhysicalCell {
        switch self {
        case .newTask: return PhysicalCell(rawValue: 8)!
        case .togglePin: return PhysicalCell(rawValue: 9)!
        case .toggleMicrophoneMute: return PhysicalCell(rawValue: 1)!
        case .toggleVoiceMode: return PhysicalCell(rawValue: 4)!
        case .steerQueuedMessage: return PhysicalCell(rawValue: 7)!
        case .pressEnter: return PhysicalCell(rawValue: 6)!
        case .startNewVoiceChat: return PhysicalCell(rawValue: 5)!
        case .increaseReasoningEffort: return PhysicalCell(rawValue: 12)!
        case .decreaseReasoningEffort: return PhysicalCell(rawValue: 11)!
        }
    }

    public var title: String {
        switch self {
        case .newTask: return "New task"
        case .togglePin: return "Pin / unpin"
        case .toggleMicrophoneMute: return "Mute / unmute mic"
        case .toggleVoiceMode: return "Start voice mode"
        case .steerQueuedMessage: return "Steer queued message"
        case .pressEnter: return "Enter"
        case .startNewVoiceChat: return "New voice chat"
        case .increaseReasoningEffort: return "Reasoning effort up"
        case .decreaseReasoningEffort: return "Reasoning effort down"
        }
    }

    public var hudAccent: RGBColor {
        switch self {
        case .newTask: return RGBColor(red: 52, green: 150, blue: 255)
        case .togglePin: return RGBColor(red: 255, green: 188, blue: 58)
        case .toggleMicrophoneMute: return RGBColor(red: 255, green: 72, blue: 137)
        case .toggleVoiceMode: return RGBColor(red: 29, green: 211, blue: 211)
        case .steerQueuedMessage: return RGBColor(red: 255, green: 121, blue: 48)
        case .pressEnter: return ModeHUDActionFamilyPalette.enter
        case .startNewVoiceChat: return RGBColor(red: 105, green: 111, blue: 255)
        case .increaseReasoningEffort, .decreaseReasoningEffort:
            return ModeHUDActionFamilyPalette.reasoningEffort
        }
    }

    public static func action(for cell: PhysicalCell) -> CodexModeAction? {
        allCases.first { $0.cell == cell }
    }
}

public enum CodexMode {
    public static let bundleIdentifier = "com.openai.codex"
    public static let accent = RGBColor(red: 0, green: 218, blue: 184)

    public static let definition = AppSpecificModeDefinition(
        title: "Codex mode",
        footerTitle: "Codex mode",
        footerHint: nil,
        accent: accent,
        legend: PhysicalCell.all.map { cell in
            if let action = CodexModeAction.action(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.title,
                    accent: action.hudAccent
                )
            }
            if cell == .modeExit {
                return ModeHUDLegendItem(cell: cell, actionTitle: "Exit Codex mode", accent: accent)
            }
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Spare",
                accent: RGBColor(red: 96, green: 108, blue: 120)
            )
        }
    )
}
