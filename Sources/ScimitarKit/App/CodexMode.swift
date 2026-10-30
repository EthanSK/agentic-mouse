import Foundation

public enum CodexModeAction: String, CaseIterable, Equatable, Sendable {
    case newTask
    case togglePin
    case toggleMicrophoneMute
    case toggleVoiceMode
    case openSideChat
    case closeTab
    case pressEnter

    public var cell: PhysicalCell {
        switch self {
        case .newTask: return PhysicalCell(rawValue: 5)!
        case .togglePin: return PhysicalCell(rawValue: 3)!
        case .toggleMicrophoneMute: return PhysicalCell(rawValue: 11)!
        case .toggleVoiceMode: return PhysicalCell(rawValue: 12)!
        case .openSideChat: return PhysicalCell(rawValue: 9)!
        case .closeTab: return PhysicalCell(rawValue: 8)!
        case .pressEnter: return PhysicalCell(rawValue: 7)!
        }
    }

    public var title: String {
        switch self {
        case .newTask: return "New chat"
        case .togglePin: return "Pin/Unpin + Hold 2"
        case .toggleMicrophoneMute: return "Mute / unmute voice mic"
        case .toggleVoiceMode: return "Voice mode"
        case .openSideChat: return "Open side chat"
        case .closeTab: return "⌘W Close tab"
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
        case .closeTab: return RGBColor(red: 72, green: 189, blue: 255)
        case .pressEnter: return ModeHUDActionFamilyPalette.enter
        }
    }

    /// Controls whose newest physical report is still failed. Do not clear a
    /// marker for a source-only fix or an install; Ethan's later physical
    /// acceptance is the clearing boundary.
    public var hudControlStatus: ModeHUDControlStatus {
        switch self {
        // Ethan confirmed Voice mode works; retain the shared toggle route.
        case .toggleVoiceMode, .newTask, .togglePin, .toggleMicrophoneMute, .openSideChat,
             .closeTab, .pressEnter:
            return .normal
        }
    }

    public static func action(for cell: PhysicalCell) -> CodexModeAction? {
        allCases.first { $0.cell == cell }
    }
}

public enum CodexMode {
    public static let responseSpeedWheelCell = PhysicalCell(rawValue: 1)!
    public static let pinToggleCell = PhysicalCell(rawValue: 3)!
    public static let pinModifierCell = PhysicalCell.frontmostAppModeSelector
    public static let screenshotPinWheelCell = pinToggleCell // Compatibility with the retired Codex wheel route.
    public static let bundleIdentifier = "com.openai.codex"
    public static let accent = RGBColor(red: 32, green: 128, blue: 255)
    public static let chatHistoryWheelCell = PhysicalCell(rawValue: 6)! // Swap Codex cells 6 and 11 on both mice; share this cell between routing, the HUD and wheel feedback. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)

    public static let definition = AppSpecificModeDefinition(
        title: "Codex mode",
        footerTitle: "Codex mode",
        footerHint: nil,
        accent: accent,
        outlineWidth: 4.5,
        legend: PhysicalCell.all.map { cell in
            if cell.isAppSpecificModeExit {
                // The wand's centre only exits: holding the wand aims, so
                // "Hold for Pin/Unpin" is the physical mice's cell-2 chord.
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: cell == pinModifierCell ? "Exit · Hold for Pin/Unpin" : "Exit Codex mode",
                    accent: accent,
                    appBackdrop: ModeHUDAppBackdrop(bundleIdentifier: bundleIdentifier)
                ).withWandTitle("Exit Codex mode")
            }
            if let control = WheelChordControl.appSpecificControl(for: .codex, cell: cell) {
                if control == .codexPin {
                    return ModeHUDLegendItem(
                        cell: cell,
                        actionTitle: CodexModeAction.togglePin.title,
                        accent: control.hudAccent,
                        controlStatus: control.hudControlStatus
                    ).withWandTitle("Pin/Unpin")
                }
                return ModeHUDLegendItem(
                    cell: cell,
                    gesture: control.hudGesture,
                    accent: control.hudAccent,
                    controlStatus: control.hudControlStatus
                )
            }
            if let action = CodexModeAction.action(for: cell) {
                let item = ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.title,
                    accent: action.hudAccent,
                    controlStatus: action.hudControlStatus
                )
                // Ethan (2026-10-30): "we don't need to do that hold 2x thing"
                // on the wand. A wand click sends the Pin shortcut directly;
                // "+ Hold 2" is the physical mice's cell-2 chord.
                return action == .togglePin ? item.withWandTitle("Pin/Unpin") : item
            }
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Spare",
                accent: RGBColor(red: 96, green: 108, blue: 120)
            )
        }
    )
}
