import Foundation

/// The one shared action exposed by terminal-capable app-specific pages.
/// Physical cell 12 is intentionally spare in Utility and becomes useful only
/// after the user has selected a terminal context.
public enum TerminalModeAction: String, CaseIterable, Equatable, Sendable {
    case previousTab
    case nextTab
    case find
    case clearScreen
    case newTab
    case zoomOut
    case zoomIn
    case closeTab
    case settings
    case interruptTerminal

    public var cell: PhysicalCell {
        switch self {
        case .previousTab: return PhysicalCell(rawValue: 1)!
        case .nextTab: return PhysicalCell(rawValue: 3)!
        case .find: return PhysicalCell(rawValue: 4)!
        case .clearScreen: return PhysicalCell(rawValue: 5)!
        case .newTab: return PhysicalCell(rawValue: 6)!
        case .zoomOut: return PhysicalCell(rawValue: 7)!
        case .zoomIn: return PhysicalCell(rawValue: 8)!
        case .closeTab: return PhysicalCell(rawValue: 9)!
        case .settings: return PhysicalCell(rawValue: 11)!
        case .interruptTerminal: return .interruptTerminal
        }
    }

    public var title: String {
        switch self {
        case .previousTab: return "Previous tab"
        case .nextTab: return "Next tab"
        case .find: return "Find"
        case .clearScreen: return "Clear screen"
        case .newTab: return "New tab"
        case .zoomOut: return "Zoom out"
        case .zoomIn: return "Zoom in"
        case .closeTab: return "Close tab"
        case .settings: return "Settings"
        case .interruptTerminal: return "Interrupt terminal"
        }
    }

    public static func action(for cell: PhysicalCell) -> TerminalModeAction? {
        allCases.first { $0.cell == cell }
    }
}

public enum TerminalMode {
    public static let terminalAccent = RGBColor(red: 0, green: 210, blue: 92)
    public static let iTermAccent = RGBColor(red: 255, green: 56, blue: 112)
    public static let interruptAccent = RGBColor(red: 255, green: 78, blue: 78)

    public static func definition(
        displayName: String,
        accent: RGBColor,
        bundleIdentifier: String
    ) -> AppSpecificModeDefinition {
        AppSpecificModeDefinition(
            title: "\(displayName) mode",
            footerTitle: "\(displayName) mode",
            accent: accent,
            legend: PhysicalCell.all.map { cell in
                if cell.isAppSpecificModeExit {
                    return ModeHUDLegendItem(
                        cell: cell,
                        actionTitle: "Exit \(displayName) mode",
                        accent: accent
                    )
                }
                if let action = TerminalModeAction.action(for: cell) {
                    return ModeHUDLegendItem(
                        cell: cell,
                        actionTitle: action.title,
                        accent: interruptAccent
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
}
