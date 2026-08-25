import Foundation

public enum ClaudeModeAction: String, CaseIterable, Equatable, Sendable {
    case settings
    case search
    case toggleVoiceMode
    case newChat
    case toggleMicrophoneMute
    case pressEnter
    case reload
    case toggleSidebar
    case previousTab
    case nextTab

    public var cell: PhysicalCell {
        switch self {
        case .settings: return PhysicalCell(rawValue: 1)!
        case .search: return PhysicalCell(rawValue: 3)!
        case .toggleVoiceMode: return PhysicalCell(rawValue: 4)!
        case .newChat: return PhysicalCell(rawValue: 5)!
        case .toggleMicrophoneMute: return PhysicalCell(rawValue: 6)!
        case .pressEnter: return PhysicalCell(rawValue: 7)!
        case .reload: return PhysicalCell(rawValue: 8)!
        case .toggleSidebar: return PhysicalCell(rawValue: 9)!
        case .previousTab: return PhysicalCell(rawValue: 11)!
        case .nextTab: return PhysicalCell(rawValue: 12)!
        }
    }

    public var title: String {
        switch self {
        case .settings: return "Settings"
        case .search: return "Search"
        case .toggleVoiceMode: return "Voice mode"
        case .newChat: return "New chat"
        case .toggleMicrophoneMute: return "Mute / unmute voice mic"
        case .pressEnter: return "Enter"
        case .reload: return "Reload"
        case .toggleSidebar: return "Toggle sidebar"
        case .previousTab: return "Previous tab"
        case .nextTab: return "Next tab"
        }
    }

    public var hudAccent: RGBColor {
        switch self {
        case .settings: return RGBColor(red: 168, green: 126, blue: 105)
        case .search: return RGBColor(red: 226, green: 144, blue: 93)
        case .toggleVoiceMode: return RGBColor(red: 29, green: 211, blue: 211)
        case .newChat: return RGBColor(red: 52, green: 150, blue: 255)
        case .toggleMicrophoneMute: return RGBColor(red: 255, green: 72, blue: 137)
        case .pressEnter: return ModeHUDActionFamilyPalette.enter
        case .reload: return RGBColor(red: 113, green: 172, blue: 255)
        case .toggleSidebar: return RGBColor(red: 189, green: 128, blue: 255)
        case .previousTab, .nextTab: return ModeHUDActionFamilyPalette.historyNavigation
        }
    }

    public static func action(for cell: PhysicalCell) -> ClaudeModeAction? {
        allCases.first { $0.cell == cell }
    }
}

public enum ClaudeMode {
    public static let bundleIdentifier = "com.anthropic.claudefordesktop"
    public static let accent = RGBColor(red: 222, green: 121, blue: 82)

    public static let definition = AppSpecificModeDefinition(
        title: "Claude mode",
        footerTitle: "Claude mode",
        accent: accent,
        legend: PhysicalCell.all.map { cell in
            if cell.isAppSpecificModeExit {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Exit Claude mode",
                    accent: accent
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
