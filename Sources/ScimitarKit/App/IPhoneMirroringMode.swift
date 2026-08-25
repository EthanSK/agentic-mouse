import Foundation

public enum IPhoneMirroringModeAction: String, CaseIterable, Equatable, Sendable {
    case notifications

    public var cell: PhysicalCell {
        switch self {
        case .notifications: return PhysicalCell(rawValue: 1)!
        }
    }

    public var title: String {
        switch self {
        case .notifications: return "Notifications"
        }
    }

    public static func action(for cell: PhysicalCell) -> IPhoneMirroringModeAction? {
        allCases.first { $0.cell == cell }
    }
}

/// iPhone Mirroring exposes iPhone notifications through macOS Notification
/// Center rather than through an iPhone-style pull-down gesture. This page is
/// automatic-only and uses Apple's supported Fn-N shortcut.
public enum IPhoneMirroringMode {
    public static let bundleIdentifier = "com.apple.ScreenContinuity"
    public static let accent = RGBColor(red: 55, green: 145, blue: 255)

    public static let definition = AppSpecificModeDefinition(
        title: "iPhone Mirroring mode",
        footerTitle: "iPhone Mirroring mode",
        accent: accent,
        legend: PhysicalCell.all.map { cell in
            if cell.isAppSpecificModeExit {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Exit iPhone Mirroring mode",
                    accent: accent
                )
            }
            if let action = IPhoneMirroringModeAction.action(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.title,
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
