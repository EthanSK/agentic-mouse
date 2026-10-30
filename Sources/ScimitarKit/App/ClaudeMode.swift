import Foundation

public enum ClaudeModeAction: String, CaseIterable, Equatable, Sendable {
    case toggleVoiceMode
    case newChat
    case toggleMicrophoneMute
    case pressEnter

    public var cell: PhysicalCell {
        switch self {
        case .toggleVoiceMode: return PhysicalCell(rawValue: 12)!
        case .newChat: return PhysicalCell(rawValue: 5)!
        case .toggleMicrophoneMute: return PhysicalCell(rawValue: 11)!
        case .pressEnter: return PhysicalCell(rawValue: 7)!
        }
    }

    public var title: String {
        switch self {
        case .toggleVoiceMode: return "Voice mode"
        case .newChat: return "New chat"
        case .toggleMicrophoneMute: return "Mute / unmute voice mic"
        case .pressEnter: return "Enter"
        }
    }

    public var hudAccent: RGBColor {
        switch self {
        case .toggleVoiceMode: return RGBColor(red: 29, green: 211, blue: 211)
        case .newChat: return RGBColor(red: 52, green: 150, blue: 255)
        case .toggleMicrophoneMute: return RGBColor(red: 255, green: 72, blue: 137)
        case .pressEnter: return ModeHUDActionFamilyPalette.enter
        }
    }

    public static func action(for cell: PhysicalCell) -> ClaudeModeAction? {
        allCases.first { $0.cell == cell }
    }
}

public enum ClaudeMode {
    public static let bundleIdentifier = "com.anthropic.claudefordesktop"
    public static let accent = RGBColor(red: 222, green: 121, blue: 82)
    public static let pinToggleCell = PhysicalCell(rawValue: 3)!
    public static let tabsWheelCell = PhysicalCell(rawValue: 6)!

    private static let unavailableTitles: [Int: String] = [
        8: "Toggle side panel",
        9: "Open side chat",
    ]
    /// Mirrors Codex's held-wheel card; Claude exposes no equivalent.
    private static let unavailableGestures: [Int: ModeHUDGesture] = [
        4: WheelChordControl.codexReasoningEffort.hudGesture,
    ]

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
                )
            }
            if let control = WheelChordControl.appSpecificControl(for: .claude, cell: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    gesture: control.hudGesture,
                    accent: control.hudAccent,
                    controlStatus: control == .claudePin ? .reportedBroken : .normal
                )
            }
            if let action = ClaudeModeAction.action(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.title,
                    accent: action.hudAccent
                )
            }
            if let gesture = unavailableGestures[cell.rawValue] {
                return ModeHUDLegendItem(
                    cell: cell,
                    gesture: gesture,
                    accent: RGBColor(red: 118, green: 126, blue: 142),
                    controlStatus: .unavailable
                )
            }
            if let title = unavailableTitles[cell.rawValue] {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: title,
                    accent: RGBColor(red: 118, green: 126, blue: 142),
                    controlStatus: .unavailable
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
