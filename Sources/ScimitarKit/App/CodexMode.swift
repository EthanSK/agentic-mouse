import Foundation

public enum CodexModeAction: String, CaseIterable, Equatable, Sendable {
    case newTask
    case togglePin
    case toggleMicrophoneMute
    case toggleVoiceMode
    case openSideChat
    case closeTab
    case pressEnter
    case openClaudeSession

    public var cell: PhysicalCell {
        switch self {
        case .newTask: return PhysicalCell(rawValue: 5)!
        case .togglePin: return CodexMode.pinToggleCell
        case .toggleMicrophoneMute: return PhysicalCell(rawValue: 11)!
        case .toggleVoiceMode: return PhysicalCell(rawValue: 12)!
        case .openSideChat: return PhysicalCell(rawValue: 4)!
        case .closeTab: return PhysicalCell(rawValue: 8)!
        case .pressEnter, .openClaudeSession: return PhysicalCell(rawValue: 7)!
        }
    }

    public var title: String {
        switch self {
        case .newTask: return "New chat"
        case .togglePin: return "Pin/Unpin"
        case .toggleMicrophoneMute: return "Mute / unmute voice mic"
        case .toggleVoiceMode: return "Voice mode"
        case .openSideChat: return "Open side chat"
        case .closeTab: return "⌘W Close tab"
        case .pressEnter: return "Enter"
        case .openClaudeSession: return "Claude session"
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
        case .openClaudeSession: return RGBColor(red: 207, green: 128, blue: 96)
        }
    }

    /// Controls whose newest physical report is still failed. Do not clear a
    /// marker for a source-only fix or an install; Ethan's later physical
    /// acceptance is the clearing boundary.
    public var hudControlStatus: ModeHUDControlStatus {
        switch self {
        // Ethan confirmed Voice mode works; retain the shared toggle route.
        case .toggleVoiceMode, .newTask, .togglePin, .toggleMicrophoneMute, .openSideChat,
             .closeTab, .pressEnter, .openClaudeSession:
            return .normal
        }
    }

    public static func action(for cell: PhysicalCell, source: MouseSource = .corsair) -> CodexModeAction? {
        // Ethan explicitly chose Razer 9 for the Claude Session plugin tab.
        // Keep Enter on the other mouse and on the wand.
        if source == .razer, cell == openClaudeSession.cell { return .openClaudeSession }
        return allCases.first { $0 != .openClaudeSession && $0.cell == cell }
    }
}

public enum CodexMode {
    public static func legend(for source: MouseSource, from legend: [ModeHUDLegendItem]) -> [ModeHUDLegendItem] {
        guard source == .razer else { return legend }
        return legend.map { item in
            guard item.cell == CodexModeAction.openClaudeSession.cell else { return item }
            return ModeHUDLegendItem(
                cell: item.cell,
                actionTitle: CodexModeAction.openClaudeSession.title,
                accent: CodexModeAction.openClaudeSession.hudAccent
            )
        }
    }

    // Ethan's Codex layout: "flip pin unpin and speed", put Reasoning on
    // Corsair 6, Open side chat on 4, and Chats Selection on 9. These canonical
    // cells also drive the mirrored Razer HUD and both app-entry journeys.
    public static let responseSpeedWheelCell = PhysicalCell(rawValue: 3)!
    public static let pinToggleCell = PhysicalCell(rawValue: 1)!
    public static let reasoningEffortWheelCell = PhysicalCell(rawValue: 6)!
    public static let screenshotPinWheelCell = pinToggleCell // Compatibility with the retired Codex wheel route.
    public static let bundleIdentifier = "com.openai.codex"
    public static let accent = RGBColor(red: 32, green: 128, blue: 255)
    public static let chatHistoryWheelCell = PhysicalCell(rawValue: 9)!

    public static let definition = AppSpecificModeDefinition(
        title: "Codex mode",
        footerTitle: "Codex mode",
        footerHint: nil,
        accent: accent,
        outlineWidth: 4.5,
        legend: PhysicalCell.all.map { cell in
            if cell.isAppSpecificModeExit {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Exit Codex mode",
                    accent: accent,
                    appBackdrop: ModeHUDAppBackdrop(bundleIdentifier: bundleIdentifier)
                ).withWandTitle("Exit Codex mode")
            }
            if let control = WheelChordControl.appSpecificControl(for: .codex, cell: cell) {
                let item = ModeHUDLegendItem(
                    cell: cell,
                    gesture: control.hudGesture,
                    accent: control.hudAccent,
                    controlStatus: control.hudControlStatus
                )
                // The new wheel-free click belongs to the physical mice only.
                return control == .codexResponseSpeed
                    ? item.withWandTitle("\(control.hudHoldTitle) \(control.wandHUDMotion.glyph)") : item
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
