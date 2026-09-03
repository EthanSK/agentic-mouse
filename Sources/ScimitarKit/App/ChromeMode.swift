import Foundation

public enum ChromeModeAction: String, CaseIterable, Equatable, Sendable {
    case closeCurrentTab
    case holdYouTubeDoubleSpeed
    case openDevTools
    case cycleTabsWithWheel
    case reloadCurrentTab
    case newTab
    case openWebsites
    case focusAddress
    case reopenClosedTab
    case findPage

    public var cell: PhysicalCell {
        switch self {
        case .closeCurrentTab: return PhysicalCell(rawValue: 3)!
        case .holdYouTubeDoubleSpeed: return PhysicalCell(rawValue: 7)!
        case .openDevTools: return PhysicalCell(rawValue: 6)!
        case .cycleTabsWithWheel: return PhysicalCell(rawValue: 4)!
        case .reloadCurrentTab: return PhysicalCell(rawValue: 1)!
        case .newTab: return PhysicalCell(rawValue: 5)!
        case .openWebsites: return PhysicalCell(rawValue: 8)!
        case .focusAddress: return PhysicalCell(rawValue: 9)!
        case .reopenClosedTab: return PhysicalCell(rawValue: 11)!
        case .findPage: return PhysicalCell(rawValue: 12)!
        }
    }

    public var title: String {
        switch self {
        case .closeCurrentTab: return "Close current tab"
        case .holdYouTubeDoubleSpeed: return "Hold 2× speed"
        case .openDevTools: return "Open DevTools"
        case .cycleTabsWithWheel: return "Tab History + Wheel"
        case .reloadCurrentTab: return "Reload current tab"
        case .newTab: return "New tab"
        case .openWebsites: return "Open website"
        case .focusAddress: return "Address / Search"
        case .reopenClosedTab: return "Reopen tab"
        case .findPage: return "Find page"
        }
    }

    public static func action(for cell: PhysicalCell) -> ChromeModeAction? {
        return allCases.first { $0.cell == cell }
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
                    accent: RGBColor(red: 66, green: 133, blue: 244),
                    destinationModeAccent: action == .openWebsites
                        ? ChromeWebsitesMode.accent
                        : nil
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

public enum ChromeWebsiteAction: String, CaseIterable, Equatable, Sendable {
    case youtube
    case x
    case facebook
    case github
    case linkedin
    case gemini
    case grok

    public var cell: PhysicalCell {
        switch self {
        case .youtube: return PhysicalCell(rawValue: 1)!
        case .x: return PhysicalCell(rawValue: 3)!
        case .facebook: return PhysicalCell(rawValue: 4)!
        case .github: return PhysicalCell(rawValue: 5)!
        case .linkedin: return PhysicalCell(rawValue: 6)!
        case .gemini: return PhysicalCell(rawValue: 7)!
        case .grok: return PhysicalCell(rawValue: 9)!
        }
    }

    public var title: String {
        switch self {
        case .youtube: return "YouTube"
        case .x: return "X"
        case .facebook: return "Facebook"
        case .github: return "GitHub"
        case .linkedin: return "LinkedIn"
        case .gemini: return "Gemini"
        case .grok: return "Grok"
        }
    }

    public static func action(for cell: PhysicalCell) -> ChromeWebsiteAction? {
        allCases.first { $0.cell == cell }
    }
}

public enum ChromeWebsitesMode {
    public static let accent = ChromeMode.accent
    public static let parentCell = PhysicalCell(rawValue: 8)!

    public static let definition = AppSpecificModeDefinition(
        title: "Chrome websites",
        footerTitle: "Chrome websites",
        accent: accent,
        legend: PhysicalCell.all.map { cell in
            if cell.isAppSpecificModeExit {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Exit Chrome mode",
                    accent: accent
                )
            }
            if cell == parentCell {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Back to Chrome",
                    accent: accent,
                    destinationModeAccent: ChromeMode.accent
                )
            }
            if let action = ChromeWebsiteAction.action(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.title,
                    accent: ModeHUDActionFamilyPalette.browserTabs
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
