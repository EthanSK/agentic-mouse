import Foundation

/// Apps that can be locked as the destination of the shared app-specific mode.
/// Selecting one opens its child legend without activating the application.
public enum AppSpecificTarget: String, CaseIterable, Equatable, Sendable {
    case codex
    case chrome
    case vsCode

    public var selectorCell: PhysicalCell {
        switch self {
        case .codex: return PhysicalCell(rawValue: 1)!
        case .chrome: return PhysicalCell(rawValue: 4)!
        case .vsCode: return PhysicalCell(rawValue: 7)!
        }
    }

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .chrome: return "Chrome"
        case .vsCode: return "VS Code"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .codex: return CodexMode.bundleIdentifier
        case .chrome: return "com.google.Chrome"
        case .vsCode: return "com.microsoft.VSCode"
        }
    }

    public var accent: RGBColor {
        switch self {
        case .codex: return CodexMode.accent
        case .chrome: return ChromeMode.accent
        case .vsCode: return RGBColor(red: 0, green: 168, blue: 255)
        }
    }

    public var definition: AppSpecificModeDefinition {
        switch self {
        case .codex:
            return CodexMode.definition
        case .chrome:
            return ChromeMode.definition
        case .vsCode:
            return AppSpecificModeDefinition(
                title: "\(displayName) mode",
                footerTitle: "\(displayName) mode",
                accent: accent,
                legend: PhysicalCell.all.map { cell in
                    if cell == .modeExit {
                        return ModeHUDLegendItem(
                            cell: cell,
                            actionTitle: "Exit \(displayName) mode",
                            accent: accent
                        )
                    }
                    return ModeHUDLegendItem(
                        cell: cell,
                        actionTitle: "Spare",
                        detail: "No \(displayName) command assigned yet",
                        accent: RGBColor(red: 96, green: 108, blue: 120)
                    )
                }
            )
        }
    }

    public static func target(for cell: PhysicalCell) -> AppSpecificTarget? {
        allCases.first { $0.selectorCell == cell }
    }

    public static func target(forBundleIdentifier bundleIdentifier: String?) -> AppSpecificTarget? {
        guard let bundleIdentifier else { return nil }
        return allCases.first { $0.bundleIdentifier == bundleIdentifier }
    }
}

/// The app observed at the moment a frontmost-app mode is opened or refreshed.
/// Unsupported apps still receive an honest HUD instead of being mistaken for
/// one of the configured manual targets.
public struct FrontmostAppModeContext: Equatable, Sendable {
    public let target: AppSpecificTarget?
    public let displayName: String
    public let bundleIdentifier: String?

    public init(target: AppSpecificTarget?, displayName: String, bundleIdentifier: String?) {
        self.target = target
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
    }

    public var definition: AppSpecificModeDefinition {
        target?.definition ?? AppSpecificMode.unsupportedDefinition(
            appName: displayName,
            bundleIdentifier: bundleIdentifier
        )
    }
}

public enum AppSpecificMode {
    public static let selectorAccent = RGBColor(red: 0, green: 132, blue: 255)

    public static let selectorDefinition = AppSpecificModeDefinition(
        title: "Choose app",
        footerTitle: "App-specific mode",
        accent: selectorAccent,
        legend: PhysicalCell.all.map { cell in
            if let target = AppSpecificTarget.target(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: target.displayName,
                    detail: "Open \(target.displayName) mode",
                    accent: target.accent
                )
            }
            if cell == .modeExit {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Exit app-specific mode",
                    accent: selectorAccent
                )
            }
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Spare",
                detail: "Available for another app",
                accent: RGBColor(red: 96, green: 108, blue: 120)
            )
        }
    )

    /// Returns a stable app identity colour for unconfigured applications.
    /// Swift's `hashValue` is intentionally randomized between launches, so a
    /// small FNV-1a hash keeps TextEdit (for example) the same colour forever.
    public static func identityAccent(appName: String, bundleIdentifier: String?) -> RGBColor {
        let identity = bundleIdentifier?.isEmpty == false ? bundleIdentifier! : appName
        var hash: UInt32 = 2_166_136_261
        for byte in identity.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        let hue = Double(hash % 360) / 360.0
        return hsv(hue: hue, saturation: 0.72, value: 0.95)
    }

    public static func unsupportedDefinition(
        appName: String,
        bundleIdentifier: String? = nil
    ) -> AppSpecificModeDefinition {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Current app"
            : appName
        let accent = identityAccent(appName: name, bundleIdentifier: bundleIdentifier)
        return AppSpecificModeDefinition(
            title: "\(name) mode",
            footerTitle: "App-specific — \(name)",
            accent: accent,
            legend: PhysicalCell.all.map { cell in
                if cell == .modeExit {
                    return ModeHUDLegendItem(
                        cell: cell,
                        actionTitle: "Exit \(name) mode",
                        accent: accent
                    )
                }
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Spare",
                    detail: "No \(name) command assigned yet",
                    accent: RGBColor(red: 118, green: 126, blue: 142)
                )
            }
        )
    }

    private static func hsv(hue: Double, saturation: Double, value: Double) -> RGBColor {
        let h = (hue - floor(hue)) * 6
        let sector = Int(floor(h)) % 6
        let fraction = h - floor(h)
        let p = value * (1 - saturation)
        let q = value * (1 - fraction * saturation)
        let t = value * (1 - (1 - fraction) * saturation)
        let rgb: (Double, Double, Double)
        switch sector {
        case 0: rgb = (value, t, p)
        case 1: rgb = (q, value, p)
        case 2: rgb = (p, value, t)
        case 3: rgb = (p, q, value)
        case 4: rgb = (t, p, value)
        default: rgb = (value, p, q)
        }
        return RGBColor(unitRed: rgb.0, unitGreen: rgb.1, unitBlue: rgb.2)
    }
}
