import Foundation

/// Stateless system actions exposed directly from the shared Modes menu.
///
/// These actions do not enter a child mode. Their physical-cell identity is
/// shared across both exact-device adapters; only the printed number differs.
public enum ModeUtilityAction: Equatable, Sendable {
    case increaseDisplayBrightness
    case decreaseDisplayBrightness
    case rewindYouTubeFiveSeconds
    case zoomIn
    case zoomOut
    case moveToSpaceLeft
    case moveToSpaceRight

    public var cell: PhysicalCell {
        switch self {
        case .increaseDisplayBrightness: return .brightnessIncrease
        case .decreaseDisplayBrightness: return .brightnessDecrease
        case .rewindYouTubeFiveSeconds: return .youtubeBackFiveSeconds
        case .zoomIn: return .applicationZoomIn
        case .zoomOut: return .applicationZoomOut
        case .moveToSpaceLeft: return .desktopSpaceLeft
        case .moveToSpaceRight: return .desktopSpaceRight
        }
    }

    public var actionTitle: String {
        switch self {
        case .increaseDisplayBrightness: return "Brightness Up"
        case .decreaseDisplayBrightness: return "Brightness Down"
        case .rewindYouTubeFiveSeconds: return "YouTube −5 sec"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .moveToSpaceLeft: return "Space Left"
        case .moveToSpaceRight: return "Space Right"
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
        case .rewindYouTubeFiveSeconds:
            return RGBColor(red: 255, green: 72, blue: 72)
        }
    }

    public static func action(for cell: PhysicalCell) -> ModeUtilityAction? {
        switch cell {
        case .brightnessIncrease: return .increaseDisplayBrightness
        case .brightnessDecrease: return .decreaseDisplayBrightness
        case .youtubeBackFiveSeconds: return .rewindYouTubeFiveSeconds
        case .applicationZoomIn: return .zoomIn
        case .applicationZoomOut: return .zoomOut
        case .desktopSpaceLeft: return .moveToSpaceLeft
        case .desktopSpaceRight: return .moveToSpaceRight
        default: return nil
        }
    }
}
