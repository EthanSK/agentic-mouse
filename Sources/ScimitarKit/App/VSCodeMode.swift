import Foundation

public enum VSCodeModeAction: String, CaseIterable, Equatable, Sendable {
    case previousChange
    case nextChange
    case stageAndNext
    case toggleTerminal

    public var cell: PhysicalCell {
        switch self {
        case .previousChange: return PhysicalCell(rawValue: 5)!
        case .nextChange: return PhysicalCell(rawValue: 8)!
        case .stageAndNext: return .appShortcut
        case .toggleTerminal: return PhysicalCell(rawValue: 4)!
        }
    }

    public var title: String {
        switch self {
        case .previousChange: return "Previous Change"
        case .nextChange: return "Next Change"
        case .stageAndNext: return "Stage + Next"
        case .toggleTerminal: return "Toggle Terminal"
        }
    }

    public var accent: RGBColor {
        switch self {
        case .previousChange, .nextChange:
            return RGBColor(red: 0, green: 168, blue: 255)
        case .stageAndNext:
            return RGBColor(red: 72, green: 215, blue: 112)
        case .toggleTerminal:
            return RGBColor(red: 183, green: 128, blue: 255)
        }
    }

    public static func action(for cell: PhysicalCell) -> VSCodeModeAction? {
        allCases.first { $0.cell == cell }
    }
}

public enum VSCodeMode {
    public static let accent = RGBColor(red: 0, green: 168, blue: 255)

    public static let definition = AppSpecificModeDefinition(
        title: "VS Code mode",
        footerTitle: "VS Code mode",
        accent: accent,
        legend: PhysicalCell.all.map { cell in
            if let action = VSCodeModeAction.action(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.title,
                    accent: action.accent
                )
            }
            if cell == .modeExit {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Exit VS Code mode",
                    accent: accent
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
