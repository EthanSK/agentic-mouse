import Foundation

/// System actions exposed directly from the shared Modes menu.
///
/// These actions do not enter a child mode. Their physical-cell identity is
/// shared across both exact-device adapters; only the printed number differs.
public enum ModeUtilityAction: Equatable, Sendable {
    case increaseDisplayBrightness
    case decreaseDisplayBrightness
    case rewindYouTubeFiveSeconds
    case openIntelligenceOnDemand
    case zoomIn
    case zoomOut
    case moveToSpaceLeft
    case moveToSpaceRight
    case copy
    case paste
    case moveWindowLeftWithMagnet
    case moveWindowRightWithMagnet
    case showDesktop
    case missionControl
    case showApplicationWindows
    case organizeWindows
    case spotifySongRadio
    case quitApp
    case pasteStoredPassword

    public var actionTitle: String {
        switch self {
        case .increaseDisplayBrightness: return "Brightness Up"
        case .decreaseDisplayBrightness: return "Brightness Down"
        case .rewindYouTubeFiveSeconds: return "YouTube −5 sec"
        case .openIntelligenceOnDemand: return "Intelligence on demand"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .moveToSpaceLeft: return "Space Left"
        case .moveToSpaceRight: return "Space Right"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .moveWindowLeftWithMagnet: return "Magnet Left"
        case .moveWindowRightWithMagnet: return "Magnet Right"
        case .showDesktop: return "Show Desktop"
        case .missionControl: return "Mission Control"
        case .showApplicationWindows: return "App Exposé"
        case .organizeWindows: return "Organize Windows"
        case .spotifySongRadio: return "Spotify Song Radio"
        case .quitApp: return "Quit App"
        case .pasteStoredPassword: return "PP"
        }
    }

    /// Action-card fill. Both members of a semantic pair share one family
    /// colour; the mode accent is rendered separately as the card border.
    public var hudAccent: RGBColor {
        switch self {
        case .increaseDisplayBrightness, .decreaseDisplayBrightness:
            return ModeHUDActionFamilyPalette.brightness
        case .zoomIn, .zoomOut:
            return ModeHUDActionFamilyPalette.applicationZoom
        case .moveToSpaceLeft, .moveToSpaceRight:
            return ModeHUDActionFamilyPalette.desktopSpaces
        case .copy, .paste:
            return ModeHUDActionFamilyPalette.clipboard
        case .moveWindowLeftWithMagnet, .moveWindowRightWithMagnet:
            return ModeHUDActionFamilyPalette.windowManagement
        case .showDesktop, .missionControl:
            return ModeHUDActionFamilyPalette.systemOverview
        case .showApplicationWindows, .organizeWindows:
            return ModeHUDActionFamilyPalette.windowManagement
        case .quitApp:
            return RGBColor(red: 205, green: 56, blue: 72)
        case .spotifySongRadio:
            return RGBColor(red: 30, green: 215, blue: 96)
        case .pasteStoredPassword:
            return ModeHUDActionFamilyPalette.storedPassword
        case .rewindYouTubeFiveSeconds:
            return RGBColor(red: 255, green: 72, blue: 72)
        case .openIntelligenceOnDemand:
            return RGBColor(red: 126, green: 92, blue: 255)
        }
    }

    public static func directAction(for cell: PhysicalCell) -> ModeUtilityAction? {
        switch cell {
        case .storedPassword:
            return .pasteStoredPassword
        case .intelligenceOnDemand:
            return .openIntelligenceOnDemand
        default:
            return nil
        }
    }

    /// One-press actions on the nested Extra Utilities page. Keep this mapping
    /// separate from Utility so the same canonical cells can own independent
    /// semantics on different pages without changing either mouse transport.
    public static func extraUtilitiesAction(for cell: PhysicalCell) -> ModeUtilityAction? {
        switch cell {
        case .organizeWindows: return .organizeWindows
        case .spotifySongRadio: return .spotifySongRadio
        case .quitApp: return .quitApp
        default: return nil
        }
    }

    /// True for one-shot actions routed through the shared native executor.
    /// `directAction(for:)` separately decides which of them appear as Utility
    /// cards; held-wheel families never enter this path.
    public var isDirectAction: Bool {
        switch self {
        case .rewindYouTubeFiveSeconds, .openIntelligenceOnDemand,
             .organizeWindows, .spotifySongRadio, .quitApp, .pasteStoredPassword:
            return true
        case .increaseDisplayBrightness, .decreaseDisplayBrightness,
             .zoomIn, .zoomOut, .moveToSpaceLeft, .moveToSpaceRight,
             .showDesktop, .missionControl, .showApplicationWindows:
            return false
        case .copy, .paste, .moveWindowLeftWithMagnet, .moveWindowRightWithMagnet:
            return false
        }
    }
}
