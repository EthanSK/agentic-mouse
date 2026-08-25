import Foundation

public enum ChromeModeAction: String, CaseIterable, Equatable, Sendable {
    case closeCurrentTab
    case closeCurrentWindow
    case holdYouTubeDoubleSpeed
    case openDevTools
    case cycleTabsWithWheel
    case reloadCurrentTab
    case newTab
    case focusAddress
    case reopenClosedTab
    case findPage

    public var cell: PhysicalCell {
        switch self {
        case .closeCurrentTab: return PhysicalCell(rawValue: 1)!
        case .closeCurrentWindow: return PhysicalCell(rawValue: 8)!
        case .holdYouTubeDoubleSpeed: return PhysicalCell(rawValue: 7)!
        case .openDevTools: return PhysicalCell(rawValue: 3)!
        case .cycleTabsWithWheel: return PhysicalCell(rawValue: 4)!
        case .reloadCurrentTab: return PhysicalCell(rawValue: 6)!
        case .newTab: return PhysicalCell(rawValue: 5)!
        case .focusAddress: return PhysicalCell(rawValue: 9)!
        case .reopenClosedTab: return PhysicalCell(rawValue: 11)!
        case .findPage: return PhysicalCell(rawValue: 12)!
        }
    }

    public var title: String {
        switch self {
        case .closeCurrentTab: return "Close current tab"
        case .closeCurrentWindow: return "Close current window"
        case .holdYouTubeDoubleSpeed: return "Hold 2× speed"
        case .openDevTools: return "Open DevTools"
        case .cycleTabsWithWheel: return "Tabs + Wheel"
        case .reloadCurrentTab: return "Reload current tab"
        case .newTab: return "New tab"
        case .focusAddress: return "Address / Search"
        case .reopenClosedTab: return "Reopen tab"
        case .findPage: return "Find page"
        }
    }

    public static func action(for cell: PhysicalCell) -> ChromeModeAction? {
        allCases.first { $0.cell == cell }
    }
}

public enum ChromeMode {
    public static let accent = RGBColor(red: 40, green: 118, blue: 255)

    public static let definition = AppSpecificModeDefinition(
        title: "Chrome mode",
        footerTitle: "Chrome mode",
        accent: accent,
        legend: PhysicalCell.all.map { cell in
            if cell.isAppSpecificModeExit {
                return ModeHUDLegendItem(cell: cell, actionTitle: "Exit Chrome mode", accent: accent)
            }
            if let action = ChromeModeAction.action(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.title,
                    accent: RGBColor(red: 66, green: 133, blue: 244)
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
