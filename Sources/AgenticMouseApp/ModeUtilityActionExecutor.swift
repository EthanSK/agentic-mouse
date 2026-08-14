import Foundation
import ScimitarKit

enum ModeUtilityActionError: Error, Equatable {
    case displayBrightnessEventCreationFailed
    case applicationZoomEventCreationFailed
    case desktopSpaceEventCreationFailed
    case youtubeBridgeNotificationFailed
}

/// Executes the non-modal actions shown directly in the shared Modes menu.
///
/// Display brightness stays a native macOS auxiliary-key action. YouTube seek
/// uses the already-installed VoiceInk YouTube Bridge so Chrome does not need
/// focus and target selection remains owned by that bridge.
@MainActor
struct ModeUtilityActionExecutor {
    static let youtubeSeekBackwardFiveSecondsNotification =
        Notification.Name("com.ethansk.agenticmouse.youtube.seekBackwardFiveSeconds")

    typealias YouTubeNotifier = @MainActor () -> Bool

    private let brightness: DisplayBrightnessActionExecutor
    private let zoom: ApplicationZoomActionExecutor
    private let spaces: DesktopSpaceActionExecutor
    private let notifyYouTube: YouTubeNotifier

    init(
        brightness: DisplayBrightnessActionExecutor? = nil,
        zoom: ApplicationZoomActionExecutor? = nil,
        spaces: DesktopSpaceActionExecutor? = nil,
        notifyYouTube: YouTubeNotifier? = nil
    ) {
        self.brightness = brightness ?? DisplayBrightnessActionExecutor()
        self.zoom = zoom ?? ApplicationZoomActionExecutor()
        self.spaces = spaces ?? DesktopSpaceActionExecutor()
        self.notifyYouTube = notifyYouTube ?? Self.postYouTubeNotification
    }

    func perform(_ action: ModeUtilityAction) -> Result<Void, ModeUtilityActionError> {
        switch action {
        case .increaseDisplayBrightness, .decreaseDisplayBrightness:
            switch brightness.perform(action) {
            case .success:
                return .success(())
            case .failure:
                return .failure(.displayBrightnessEventCreationFailed)
            }
        case .rewindYouTubeFiveSeconds:
            return notifyYouTube()
                ? .success(())
                : .failure(.youtubeBridgeNotificationFailed)
        case .zoomIn, .zoomOut:
            switch zoom.perform(action) {
            case .success:
                return .success(())
            case .failure:
                return .failure(.applicationZoomEventCreationFailed)
            }
        case .moveToSpaceLeft, .moveToSpaceRight:
            switch spaces.perform(action) {
            case .success:
                return .success(())
            case .failure:
                return .failure(.desktopSpaceEventCreationFailed)
            }
        }
    }

    private static func postYouTubeNotification() -> Bool {
        DistributedNotificationCenter.default().postNotificationName(
            youtubeSeekBackwardFiveSecondsNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }
}
