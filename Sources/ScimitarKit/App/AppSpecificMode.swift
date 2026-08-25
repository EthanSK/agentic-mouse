import Foundation

/// Apps recognized by the shared app-specific mode. Targets with a selector
/// cell can also be locked manually; automatic-only targets follow focus.
public enum AppSpecificTarget: String, CaseIterable, Equatable, Hashable, Sendable {
    case codex
    case chrome
    case vsCode
    case spotify
    case obs
    case claude
    case notion
    case telegram
    case safari
    case firefox
    case opera
    case restreamChat
    case preview
    case mail
    case iCue
    case karabinerSettings
    case systemSettings
    case terminal
    case finder
    case karabinerEventViewer
    case iTerm
    case iPhoneMirroring

    /// The manual selector deliberately exposes only the highest-value apps
    /// that fit its eleven usable cells. Every case remains available through
    /// automatic frontmost-app detection and resolves the same definition.
    public var selectorCell: PhysicalCell? {
        switch self {
        case .codex: return PhysicalCell(rawValue: 1)!
        case .chrome: return PhysicalCell(rawValue: 4)!
        case .vsCode: return PhysicalCell(rawValue: 7)!
        case .terminal: return PhysicalCell(rawValue: 2)!
        case .iTerm: return PhysicalCell(rawValue: 5)!
        case .claude: return PhysicalCell(rawValue: 3)!
        case .spotify: return PhysicalCell(rawValue: 6)!
        case .notion: return PhysicalCell(rawValue: 8)!
        case .obs: return PhysicalCell(rawValue: 9)!
        case .telegram: return PhysicalCell(rawValue: 11)!
        case .safari: return PhysicalCell(rawValue: 12)!
        case .firefox, .opera, .restreamChat, .preview, .mail, .iCue,
             .karabinerSettings, .systemSettings, .finder, .karabinerEventViewer,
             .iPhoneMirroring:
            return nil
        }
    }

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .chrome: return "Chrome"
        case .vsCode: return "VS Code"
        case .spotify: return "Spotify"
        case .obs: return "OBS"
        case .claude: return "Claude"
        case .notion: return "Notion"
        case .telegram: return "Telegram"
        case .safari: return "Safari"
        case .firefox: return "Firefox"
        case .opera: return "Opera"
        case .restreamChat: return "Restream Chat++"
        case .preview: return "Preview"
        case .mail: return "Mail"
        case .iCue: return "iCUE"
        case .karabinerSettings: return "Karabiner-Elements"
        case .systemSettings: return "System Settings"
        case .terminal: return "Terminal"
        case .finder: return "Finder"
        case .karabinerEventViewer: return "Karabiner-EventViewer"
        case .iTerm: return "iTerm"
        case .iPhoneMirroring: return "iPhone Mirroring"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .codex: return CodexMode.bundleIdentifier
        case .chrome: return "com.google.Chrome"
        case .vsCode: return "com.microsoft.VSCode"
        case .spotify: return "com.spotify.client"
        case .obs: return "com.obsproject.obs-studio"
        case .claude: return ClaudeMode.bundleIdentifier
        case .notion: return "notion.id"
        case .telegram: return "ru.keepcoder.Telegram"
        case .safari: return "com.apple.Safari"
        case .firefox: return "org.mozilla.firefox"
        case .opera: return "com.operasoftware.Opera"
        case .restreamChat: return "com.ethansk.restream-chat-plus-plus"
        case .preview: return "com.apple.Preview"
        case .mail: return "com.apple.mail"
        case .iCue: return "com.corsair.cue.main"
        case .karabinerSettings: return "org.pqrs.Karabiner-Elements.Settings"
        case .systemSettings: return "com.apple.systempreferences"
        case .terminal: return "com.apple.Terminal"
        case .finder: return "com.apple.finder"
        case .karabinerEventViewer: return "org.pqrs.Karabiner-EventViewer"
        case .iTerm: return "com.googlecode.iterm2"
        case .iPhoneMirroring: return IPhoneMirroringMode.bundleIdentifier
        }
    }

    public var accent: RGBColor {
        switch self {
        case .codex: return CodexMode.accent
        case .chrome: return ChromeMode.accent
        case .vsCode: return VSCodeMode.accent
        case .spotify: return RGBColor(red: 29, green: 185, blue: 84)
        case .obs: return RGBColor(red: 88, green: 116, blue: 255)
        case .claude: return ClaudeMode.accent
        case .notion: return RGBColor(red: 230, green: 230, blue: 230)
        case .telegram: return RGBColor(red: 42, green: 171, blue: 238)
        case .safari: return RGBColor(red: 0, green: 122, blue: 255)
        case .firefox: return RGBColor(red: 255, green: 104, blue: 48)
        case .opera: return RGBColor(red: 255, green: 27, blue: 68)
        case .restreamChat: return RGBColor(red: 130, green: 72, blue: 255)
        case .preview: return RGBColor(red: 48, green: 153, blue: 255)
        case .mail: return RGBColor(red: 0, green: 132, blue: 255)
        case .iCue: return RGBColor(red: 255, green: 208, blue: 0)
        case .karabinerSettings: return RGBColor(red: 0, green: 188, blue: 212)
        case .systemSettings: return RGBColor(red: 120, green: 142, blue: 255)
        case .terminal: return TerminalMode.terminalAccent
        case .finder: return RGBColor(red: 72, green: 164, blue: 255)
        case .karabinerEventViewer: return RGBColor(red: 0, green: 204, blue: 180)
        case .iTerm: return TerminalMode.iTermAccent
        case .iPhoneMirroring: return IPhoneMirroringMode.accent
        }
    }

    public var definition: AppSpecificModeDefinition {
        switch self {
        case .codex:
            return CodexMode.definition
        case .chrome:
            return ChromeMode.definition
        case .vsCode:
            return VSCodeMode.definition
        case .claude:
            return ClaudeMode.definition
        case .iPhoneMirroring:
            return IPhoneMirroringMode.definition
        case .spotify, .obs, .notion, .telegram, .safari, .firefox,
             .opera, .restreamChat, .preview, .mail, .iCue,
             .karabinerSettings, .systemSettings, .finder, .karabinerEventViewer:
            return StandardAppMode.definition(for: self)
        case .terminal:
            return TerminalMode.definition(
                displayName: displayName,
                accent: TerminalMode.terminalAccent,
                bundleIdentifier: bundleIdentifier
            )
        case .iTerm:
            return TerminalMode.definition(
                displayName: displayName,
                accent: TerminalMode.iTermAccent,
                bundleIdentifier: bundleIdentifier
            )
        }
    }

    public static func target(for cell: PhysicalCell) -> AppSpecificTarget? {
        allCases.first { $0.selectorCell == cell }
    }

    public static var manuallySelectableCases: [AppSpecificTarget] {
        allCases.filter { $0.selectorCell != nil }
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
    public let applicationPath: String?
    /// Optional presentation identity sampled from the real installed icon.
    /// The deterministic app definition remains the fallback when AppKit
    /// cannot resolve or rasterize that icon.
    public let iconAccent: RGBColor?

    public init(
        target: AppSpecificTarget?,
        displayName: String,
        bundleIdentifier: String?,
        applicationPath: String? = nil,
        iconAccent: RGBColor? = nil
    ) {
        self.target = target
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.applicationPath = applicationPath
        self.iconAccent = iconAccent
    }

    public var definition: AppSpecificModeDefinition {
        let base = target?.definition ?? AppSpecificMode.unsupportedDefinition(
            appName: displayName,
            bundleIdentifier: bundleIdentifier
        )
        if let iconAccent {
            return base.replacingIdentityAccent(with: iconAccent)
        }
        return base
    }

}

public enum AppSpecificMode {
    public static let selectorAccent = RGBColor(red: 0, green: 132, blue: 255)

    public static var selectorDefinition: AppSpecificModeDefinition {
        selectorDefinition { $0.accent }
    }

    /// Builds the manual selector from the same per-app identity source as
    /// automatic targeting. The closure is deliberately ephemeral: icon data
    /// and derived colours never enter configuration or generated mappings.
    public static func selectorDefinition(
        accentFor targetAccent: (AppSpecificTarget) -> RGBColor
    ) -> AppSpecificModeDefinition {
        AppSpecificModeDefinition(
            title: "Choose app",
            footerTitle: "App-specific mode",
            accent: selectorAccent,
            legend: PhysicalCell.all.map { cell in
                if let target = AppSpecificTarget.target(for: cell) {
                    let accent = targetAccent(target)
                    return ModeHUDLegendItem(
                        cell: cell,
                        actionTitle: target.displayName,
                        accent: accent,
                        destinationModeAccent: accent,
                        appBackdrop: ModeHUDAppBackdrop(
                            bundleIdentifier: target.bundleIdentifier
                        )
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
                    accent: RGBColor(red: 96, green: 108, blue: 120)
                )
            }
        )
    }

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
                if cell.isAppSpecificModeExit {
                    return ModeHUDLegendItem(
                        cell: cell,
                        actionTitle: "Exit \(name) mode",
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
