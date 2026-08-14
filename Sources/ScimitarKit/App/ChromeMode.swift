import Foundation

public enum ChromeModeAction: String, CaseIterable, Equatable, Sendable {
    case closeCurrentWindow

    public var cell: PhysicalCell {
        switch self {
        case .closeCurrentWindow: return PhysicalCell(rawValue: 1)!
        }
    }

    public var title: String {
        switch self {
        case .closeCurrentWindow: return "Close current window"
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
            if let action = ChromeModeAction.action(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.title,
                    accent: RGBColor(red: 66, green: 133, blue: 244)
                )
            }
            if cell == .modeExit {
                return ModeHUDLegendItem(cell: cell, actionTitle: "Exit Chrome mode", accent: accent)
            }
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Spare",
                accent: RGBColor(red: 118, green: 126, blue: 142)
            )
        }
    )
}
