import Foundation

/// Modifier vocabulary shared by the data-driven app-specific pages. Keeping
/// this in ScimitarKit lets the HUD and the runtime consume one action record
/// without importing CoreGraphics into the model layer.
public struct AppModeShortcutModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let shift = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let control = Self(rawValue: 1 << 3)
}

/// One simple keyboard action in a standard app-specific page. Specialized
/// pages (Codex, Chrome, VS Code and terminal apps) keep their purpose-built
/// action types where press/release, wheel, verification or gesture semantics
/// are required.
public struct StandardAppModeAction: Equatable, Sendable {
    public let cell: PhysicalCell
    public let title: String
    public let keyCode: UInt16
    public let modifiers: AppModeShortcutModifiers

    public init(
        cell: PhysicalCell,
        title: String,
        keyCode: UInt16,
        modifiers: AppModeShortcutModifiers = []
    ) {
        self.cell = cell
        self.title = title
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// The measured high-use apps whose useful commands are ordinary, stable
/// macOS shortcuts. These profiles are deliberately data-driven so automatic
/// frontmost-app mode and the manual app selector cannot drift.
public enum StandardAppMode {
    public static let spotifyVolumeWheelCell = PhysicalCell(rawValue: 7)!

    public static func action(
        for target: AppSpecificTarget,
        cell: PhysicalCell
    ) -> StandardAppModeAction? {
        actions(for: target).first { $0.cell == cell }
    }

    public static func definition(for target: AppSpecificTarget) -> AppSpecificModeDefinition {
        let actions = actions(for: target)
        return AppSpecificModeDefinition(
            title: "\(target.displayName) mode",
            footerTitle: "\(target.displayName) mode",
            accent: target.accent,
            legend: PhysicalCell.all.map { cell in
                if cell.isAppSpecificModeExit {
                    return ModeHUDLegendItem(
                        cell: cell,
                        actionTitle: "Exit \(target.displayName) mode",
                        accent: target.accent
                    )
                }
                if let control = WheelChordControl.appSpecificControl(
                    for: target,
                    cell: cell
                ) {
                    return ModeHUDLegendItem(
                        cell: cell,
                        actionTitle: "\(control.actionTitle) + Wheel",
                        accent: control.hudAccent,
                        controlStatus: control.hudControlStatus
                    )
                }
                if let action = actions.first(where: { $0.cell == cell }) {
                    return ModeHUDLegendItem(
                        cell: cell,
                        actionTitle: action.title,
                        accent: target.accent
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

    public static func actions(for target: AppSpecificTarget) -> [StandardAppModeAction] {
        switch target {
        case .spotify:
            return [
                a(1, "Search", 40, [.command]),
                a(3, "Previous track", 123, [.command]),
                a(4, "Next track", 124, [.command]),
                a(5, "Seek backward", 123, [.command, .shift]),
                a(6, "Seek forward", 124, [.command, .shift]),
                a(9, "Shuffle", 1, [.option]),
                a(11, "Repeat", 15, [.option]),
                a(12, "Queue", 12, [.option, .shift]),
            ]
        case .notion:
            return [
                a(1, "New page", 45, [.command]),
                a(3, "New tab", 17, [.command]),
                a(4, "Find page", 3, [.command]),
                a(5, "Back", 33, [.command]),
                a(6, "Forward", 30, [.command]),
                a(7, "New window", 45, [.command, .shift]),
                a(8, "Copy page link", 37, [.command]),
                a(9, "Toggle theme", 37, [.command, .shift]),
                a(11, "Reload", 15, [.command]),
                a(12, "Reopen tab", 17, [.command, .shift]),
            ]
        case .obs:
            return [
                a(1, "Undo", 6, [.command]),
                a(3, "Copy source", 8, [.command]),
                a(4, "Paste source", 9, [.command]),
                a(5, "Move source up", 126, [.command]),
                a(6, "Move source down", 125, [.command]),
                a(7, "Edit transform", 14, [.command]),
                a(8, "Fit to screen", 3, [.command]),
                a(9, "Reset transform", 15, [.command]),
                a(11, "Centre to screen", 2, [.command]),
                a(12, "Stretch to screen", 1, [.command]),
            ]
        case .telegram:
            return [
                a(1, "Quick Search", 40, [.command]),
                a(3, "Settings", 43, [.command]),
                a(4, "Undo", 6, [.command]),
                a(5, "Redo", 6, [.command, .shift]),
                a(6, "Copy", 8, [.command]),
                a(7, "Paste", 9, [.command]),
                a(8, "Select all", 0, [.command]),
                a(9, "Full screen", 3, [.control, .command]),
                a(11, "Minimise", 46, [.command]),
                a(12, "Close window", 13, [.command]),
            ]
        case .safari:
            return safariActions()
        case .firefox, .opera:
            return browserActions(downloadsKeyCode: 38, downloadsModifiers: [.command])
        case .restreamChat:
            return [
                a(1, "Settings", 43, [.command]),
                a(3, "Reload", 15, [.command]),
                a(4, "Force reload", 15, [.command, .shift]),
                a(5, "Open DevTools", 34, [.command, .option]),
                a(6, "Zoom in", 24, [.command, .shift]),
                a(7, "Zoom out", 27, [.command]),
                a(8, "Actual size", 29, [.command]),
                a(9, "Full screen", 3, [.control, .command]),
                a(11, "Copy", 8, [.command]),
                a(12, "Paste", 9, [.command]),
            ]
        case .preview:
            return [
                a(1, "Previous page", 126, [.option]),
                a(3, "Zoom in", 24, [.command, .shift]),
                a(4, "Zoom out", 27, [.command]),
                a(5, "Zoom to fit", 25, [.command]),
                a(6, "Actual size", 29, [.command]),
                a(7, "Find", 3, [.command]),
                a(8, "Markup toolbar", 0, [.command, .shift]),
                a(9, "Inspector", 34, [.command]),
                a(11, "Rotate left", 37, [.command]),
                a(12, "Rotate right", 15, [.command]),
            ]
        case .mail:
            return [
                a(1, "New message", 45, [.command]),
                a(3, "Reply all", 15, [.command, .shift]),
                a(4, "Forward", 3, [.command, .shift]),
                a(5, "Get new mail", 45, [.command, .shift]),
                a(6, "Mailbox search", 3, [.command, .option]),
                a(7, "Archive", 0, [.control, .command]),
                a(8, "Read / Unread", 32, [.command, .shift]),
                a(9, "Flag / Unflag", 37, [.command, .shift]),
                a(11, "Message filter", 37, [.command]),
                a(12, "Toggle sidebar", 1, [.control, .command]),
            ]
        case .finder:
            return [
                a(1, "New window", 45, [.command]),
                a(3, "Find", 3, [.command]),
                a(4, "Back", 33, [.command]),
                a(5, "Forward", 30, [.command]),
                a(6, "Go to folder", 5, [.command, .shift]),
                a(7, "Downloads", 37, [.command, .option]),
                a(8, "Applications", 0, [.command, .shift]),
                a(9, "Quick Look", 16, [.command]),
                a(11, "Get Info", 34, [.command]),
                a(12, "Home", 4, [.command, .shift]),
            ]
        case .systemSettings:
            return [
                a(1, "Back", 33, [.command]),
                a(7, "Forward", 30, [.command]),
                a(3, "Search", 3, [.command]),
                a(4, "Close", 13, [.command]),
                a(5, "Minimise", 46, [.command]),
                a(6, "Help", 44, [.command, .shift]),
            ]
        case .iCue:
            return [
                a(1, "Open profile", 31, [.command]),
                a(4, "Preferences", 43, [.command]),
                a(3, "Minimise", 46, [.command]),
            ]
        case .karabinerSettings, .karabinerEventViewer:
            return [
                a(1, "Close", 13, [.command]),
                a(4, "Minimise", 46, [.command]),
                a(3, "Full screen", 3, [.control, .command]),
            ]
        case .codex, .chrome, .vsCode, .claude, .terminal, .iTerm, .iPhoneMirroring:
            return []
        }
    }

    public static func spotifyVolumeAction(
        for direction: WheelChordDirection
    ) -> StandardAppModeAction {
        switch direction {
        case .up:
            return StandardAppModeAction(
                cell: spotifyVolumeWheelCell,
                title: "Volume up",
                keyCode: 126,
                modifiers: [.command]
            )
        case .down:
            return StandardAppModeAction(
                cell: spotifyVolumeWheelCell,
                title: "Volume down",
                keyCode: 125,
                modifiers: [.command]
            )
        }
    }

    private static func browserActions(
        downloadsKeyCode: UInt16,
        downloadsModifiers: AppModeShortcutModifiers
    ) -> [StandardAppModeAction] {
        [
            a(1, "Back", 33, [.command]),
            a(3, "Find page", 3, [.command]),
            a(4, "Previous tab", 48, [.control, .shift]),
            a(5, "Forward", 30, [.command]),
            a(6, "New tab", 17, [.command]),
            a(7, "Next tab", 48, [.control]),
            a(8, "Reload", 15, [.command]),
            a(9, "Close tab", 13, [.command]),
            a(11, "Reopen tab", 17, [.command, .shift]),
            a(12, "Downloads", downloadsKeyCode, downloadsModifiers),
        ]
    }

    /// Safari places equivalent actions on the same canonical cells as Chrome
    /// wherever Chrome exposes that action. Cell 8 deliberately duplicates
    /// New tab, while Safari-only Forward and tab-direction controls remain.
    private static func safariActions() -> [StandardAppModeAction] {
        [
            a(1, "Reload", 15, [.command]),
            a(3, "Close tab", 13, [.command]),
            a(4, "Previous tab", 48, [.control, .shift]),
            a(5, "New tab", 17, [.command]),
            a(6, "Open DevTools", 34, [.command, .option]),
            a(7, "Next tab", 48, [.control]),
            a(8, "New tab", 17, [.command]),
            a(9, "Forward", 30, [.command]),
            a(11, "Reopen tab", 17, [.command, .shift]),
            a(12, "Find page", 3, [.command]),
        ]
    }

    private static func a(
        _ cell: Int,
        _ title: String,
        _ keyCode: UInt16,
        _ modifiers: AppModeShortcutModifiers = []
    ) -> StandardAppModeAction {
        StandardAppModeAction(
            cell: PhysicalCell(rawValue: cell)!,
            title: title,
            keyCode: keyCode,
            modifiers: modifiers
        )
    }
}
