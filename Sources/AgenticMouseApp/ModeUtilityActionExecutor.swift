import AppKit
import ApplicationServices
import ScimitarKit

enum ModeUtilityActionError: Error, Equatable {
    case displayBrightnessEventCreationFailed
    case applicationZoomEventCreationFailed
    case desktopSpaceEventCreationFailed
    case clipboardInputBlocked
    case clipboardAccessibilityPermissionMissing
    case clipboardEventCreationFailed
    case magnetInputBlocked
    case magnetAccessibilityPermissionMissing
    case magnetEventCreationFailed
    case systemOverviewEventCreationFailed
    case organizeWindowsInputBlocked
    case organizeWindowsAccessibilityPermissionMissing
    case organizeWindowsEventCreationFailed
    case quitAppInputBlocked
    case quitAppAccessibilityPermissionMissing
    case quitAppTargetUnavailable
    case quitAppEventCreationFailed
    case youtubeBridgeNotificationFailed
    case chromeTabHistoryBridgeNotificationFailed
    case intelligenceOnDemandInputBlocked
    case intelligenceOnDemandAccessibilityPermissionMissing
    case intelligenceOnDemandEventCreationFailed
    case storedPasswordInputBlocked
    case storedPasswordAccessibilityPermissionMissing
    case storedPasswordNotConfigured
    case storedPasswordEventCreationFailed
}

/// Executes non-modal actions requested by the shared map and Modes menu.
///
/// Display brightness stays a native macOS auxiliary-key action. YouTube seek
/// uses the already-installed VoiceInk YouTube Bridge so Chrome does not need
/// focus and target selection remains owned by that bridge.
@MainActor
struct ModeUtilityActionExecutor {
    /// Stay 1.5.1's verified global Restore Windows hotkey for the saved
    /// `Agentic Mouse Layout v1` profile. Stay records physical key code 0 with
    /// Control-Option-Shift-Command. Its Carbon hotkey does not accept a
    /// Quartz-posted F14 even though event creation succeeds, while this
    /// reserved ordinary-key chord is physically equivalent and live-proven.
    /// The action remains manual and never drives Stay through AppleScript or
    /// UI automation.
    static let stayRestoreKeyCode: CGKeyCode = 0
    static let stayRestoreModifierFlags: CGEventFlags = [
        .maskControl, .maskAlternate, .maskShift, .maskCommand,
    ]

    static let youtubeSeekBackwardFiveSecondsNotification =
        Notification.Name("com.ethansk.agenticmouse.youtube.seekBackwardFiveSeconds")
    static let youtubeSeekForwardFiveSecondsNotification =
        Notification.Name("com.ethansk.agenticmouse.youtube.seekForwardFiveSeconds")
    static let youtubeVolumeDecreaseFivePercentNotification =
        Notification.Name("com.ethansk.agenticmouse.youtube.volumeDecreaseFivePercent")
    static let youtubeVolumeIncreaseFivePercentNotification =
        Notification.Name("com.ethansk.agenticmouse.youtube.volumeIncreaseFivePercent")
    static let chromeTabHistoryBackNotification =
        Notification.Name("com.ethansk.agenticmouse.chrome.tabHistoryBack")
    static let chromeTabHistoryForwardNotification =
        Notification.Name("com.ethansk.agenticmouse.chrome.tabHistoryForward")

    typealias YouTubeNotifier = @MainActor (_ action: YouTubeSeekAction) -> Bool
    typealias YouTubeVolumeNotifier = @MainActor (_ action: YouTubeVolumeAction) -> Bool
    typealias ChromeTabHistoryNotifier = @MainActor (_ action: ChromeTabHistoryAction) -> Bool
    typealias KeyboardChordPoster = @MainActor (
        _ events: [SyntheticKeyboardChordPoster.Event]
    ) -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool
    typealias InputAllowedProvider = @MainActor () -> Bool
    typealias StoredPasswordTyper = @MainActor () -> Result<Void, KeysModeActionError>
    struct QuitApplicationTarget: Equatable {
        let processIdentifier: pid_t
        let displayName: String
    }
    typealias QuitApplicationTargetProvider = @MainActor () -> QuitApplicationTarget?
    typealias QuitApplicationPoster = @MainActor (
        _ pid: pid_t,
        _ events: [SyntheticKeyboardChordPoster.Event]
    ) -> Bool

    private let brightness: DisplayBrightnessActionExecutor
    private let zoom: ApplicationZoomActionExecutor
    private let spaces: DesktopSpaceActionExecutor
    private let magnet: MagnetWindowActionExecutor
    private let systemOverview: SystemOverviewActionExecutor
    private let notifyYouTube: YouTubeNotifier
    private let notifyYouTubeVolume: YouTubeVolumeNotifier
    private let notifyChromeTabHistory: ChromeTabHistoryNotifier
    private let postKeyboardChord: KeyboardChordPoster
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider
    private let typeStoredPassword: StoredPasswordTyper
    private let quitApplicationTarget: QuitApplicationTargetProvider
    private let postQuitApplication: QuitApplicationPoster

    init(
        brightness: DisplayBrightnessActionExecutor? = nil,
        zoom: ApplicationZoomActionExecutor? = nil,
        spaces: DesktopSpaceActionExecutor? = nil,
        magnet: MagnetWindowActionExecutor? = nil,
        systemOverview: SystemOverviewActionExecutor? = nil,
        notifyYouTube: YouTubeNotifier? = nil,
        notifyYouTubeVolume: YouTubeVolumeNotifier? = nil,
        notifyChromeTabHistory: ChromeTabHistoryNotifier? = nil,
        postKeyboardChord: @escaping KeyboardChordPoster = SyntheticKeyboardChordPoster.shared.post,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping InputAllowedProvider = { true },
        typeStoredPassword: @escaping StoredPasswordTyper = { .failure(.passwordNotConfigured) },
        quitApplicationTarget: @escaping QuitApplicationTargetProvider = Self.frontmostQuitTarget,
        postQuitApplication: @escaping QuitApplicationPoster = {
            SyntheticKeyboardChordPoster.shared.post($1, to: $0)
        }
    ) {
        self.brightness = brightness ?? DisplayBrightnessActionExecutor()
        self.zoom = zoom ?? ApplicationZoomActionExecutor()
        self.spaces = spaces ?? DesktopSpaceActionExecutor()
        self.magnet = magnet ?? MagnetWindowActionExecutor(
            accessibilityTrusted: accessibilityTrusted,
            inputAllowed: inputAllowed
        )
        self.systemOverview = systemOverview ?? SystemOverviewActionExecutor()
        self.notifyYouTube = notifyYouTube ?? Self.postYouTubeNotification
        self.notifyYouTubeVolume = notifyYouTubeVolume ?? Self.postYouTubeVolumeNotification
        self.notifyChromeTabHistory = notifyChromeTabHistory ?? Self.postChromeTabHistoryNotification
        self.postKeyboardChord = postKeyboardChord
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
        self.typeStoredPassword = typeStoredPassword
        self.quitApplicationTarget = quitApplicationTarget
        self.postQuitApplication = postQuitApplication
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
            return performYouTubeSeek(.backwardFiveSeconds)
        case .openIntelligenceOnDemand:
            guard inputAllowed() else {
                return .failure(.intelligenceOnDemandInputBlocked)
            }
            guard accessibilityTrusted() else {
                return .failure(.intelligenceOnDemandAccessibilityPermissionMissing)
            }
            return postKeyboardChord(Self.intelligenceOnDemandChord())
                ? .success(())
                : .failure(.intelligenceOnDemandEventCreationFailed)
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
        case .copy, .paste:
            guard inputAllowed() else { return .failure(.clipboardInputBlocked) }
            guard accessibilityTrusted() else {
                return .failure(.clipboardAccessibilityPermissionMissing)
            }
            let keyCode: CGKeyCode = action == .copy ? 8 : 9
            let commandKeyCode: CGKeyCode = 55
            let events: [SyntheticKeyboardChordPoster.Event] = [
                .modifier(keyCode: commandKeyCode, flags: [.maskCommand], at: 0),
                .key(keyCode: keyCode, flags: [.maskCommand], isDown: true, at: 0.006),
                .key(keyCode: keyCode, flags: [.maskCommand], isDown: false, at: 0.026),
                .modifier(keyCode: commandKeyCode, flags: [], at: 0.032),
            ]
            return postKeyboardChord(events)
                ? .success(())
                : .failure(.clipboardEventCreationFailed)
        case .moveWindowLeftWithMagnet, .moveWindowRightWithMagnet:
            switch magnet.perform(action) {
            case .success:
                return .success(())
            case .failure(.inputBlocked):
                return .failure(.magnetInputBlocked)
            case .failure(.accessibilityPermissionMissing):
                return .failure(.magnetAccessibilityPermissionMissing)
            case .failure(.eventCreationFailed):
                return .failure(.magnetEventCreationFailed)
            }
        case .showDesktop, .missionControl, .showApplicationWindows:
            switch systemOverview.perform(action) {
            case .success:
                return .success(())
            case .failure:
                return .failure(.systemOverviewEventCreationFailed)
            }
        case .organizeWindows:
            guard inputAllowed() else {
                return .failure(.organizeWindowsInputBlocked)
            }
            guard accessibilityTrusted() else {
                return .failure(.organizeWindowsAccessibilityPermissionMissing)
            }
            let control: CGEventFlags = [.maskControl]
            let controlOption: CGEventFlags = [.maskControl, .maskAlternate]
            let controlOptionShift: CGEventFlags = [
                .maskControl, .maskAlternate, .maskShift,
            ]
            let allModifiers = Self.stayRestoreModifierFlags
            let events: [SyntheticKeyboardChordPoster.Event] = [
                .modifier(keyCode: 59, flags: control, at: 0),
                .modifier(keyCode: 58, flags: controlOption, at: 0.006),
                .modifier(keyCode: 56, flags: controlOptionShift, at: 0.012),
                .modifier(keyCode: 55, flags: allModifiers, at: 0.018),
                .key(
                    keyCode: Self.stayRestoreKeyCode,
                    flags: allModifiers,
                    isDown: true,
                    at: 0.024
                ),
                .key(
                    keyCode: Self.stayRestoreKeyCode,
                    flags: allModifiers,
                    isDown: false,
                    at: 0.050
                ),
                .modifier(keyCode: 55, flags: controlOptionShift, at: 0.056),
                .modifier(keyCode: 56, flags: controlOption, at: 0.062),
                .modifier(keyCode: 58, flags: control, at: 0.068),
                .modifier(keyCode: 59, flags: [], at: 0.074),
            ]
            return postKeyboardChord(events)
                ? .success(())
                : .failure(.organizeWindowsEventCreationFailed)
        case .quitApp:
            guard inputAllowed() else { return .failure(.quitAppInputBlocked) }
            guard accessibilityTrusted() else {
                return .failure(.quitAppAccessibilityPermissionMissing)
            }
            guard let target = quitApplicationTarget() else {
                return .failure(.quitAppTargetUnavailable)
            }
            return postQuitApplication(
                target.processIdentifier,
                Self.quitApplicationChord()
            )
                ? .success(())
                : .failure(.quitAppEventCreationFailed)
        case .pasteStoredPassword:
            switch typeStoredPassword() {
            case .success:
                return .success(())
            case .failure(.inputBlocked):
                return .failure(.storedPasswordInputBlocked)
            case .failure(.accessibilityPermissionMissing):
                return .failure(.storedPasswordAccessibilityPermissionMissing)
            case .failure(.passwordNotConfigured):
                return .failure(.storedPasswordNotConfigured)
            case .failure(.eventCreationFailed):
                return .failure(.storedPasswordEventCreationFailed)
            }
        }
    }

    func performYouTubeSeek(
        _ action: YouTubeSeekAction
    ) -> Result<Void, ModeUtilityActionError> {
        notifyYouTube(action)
            ? .success(())
            : .failure(.youtubeBridgeNotificationFailed)
    }

    func performYouTubeVolume(
        _ action: YouTubeVolumeAction
    ) -> Result<Void, ModeUtilityActionError> {
        notifyYouTubeVolume(action)
            ? .success(())
            : .failure(.youtubeBridgeNotificationFailed)
    }

    func performChromeTabHistory(
        _ action: ChromeTabHistoryAction
    ) -> Result<Void, ModeUtilityActionError> {
        notifyChromeTabHistory(action)
            ? .success(())
            : .failure(.chromeTabHistoryBridgeNotificationFailed)
    }

    private static func postYouTubeNotification(_ action: YouTubeSeekAction) -> Bool {
        let notification = action == .forwardFiveSeconds
            ? youtubeSeekForwardFiveSecondsNotification
            : youtubeSeekBackwardFiveSecondsNotification
        DistributedNotificationCenter.default().postNotificationName(
            notification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }

    private static func postYouTubeVolumeNotification(_ action: YouTubeVolumeAction) -> Bool {
        let notification = action == .increaseFivePercent
            ? youtubeVolumeIncreaseFivePercentNotification
            : youtubeVolumeDecreaseFivePercentNotification
        DistributedNotificationCenter.default().postNotificationName(
            notification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }

    private static func postChromeTabHistoryNotification(
        _ action: ChromeTabHistoryAction
    ) -> Bool {
        let notification = action == .back
            ? chromeTabHistoryBackNotification
            : chromeTabHistoryForwardNotification
        DistributedNotificationCenter.default().postNotificationName(
            notification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }

    /// Codex's global Intelligence on Demand shortcut: one complete physical
    /// left-Option + Space lifecycle, posted only after the Utility command
    /// has passed the session and Accessibility gates.
    static func intelligenceOnDemandChord() -> [SyntheticKeyboardChordPoster.Event] {
        let option: CGEventFlags = [.maskAlternate]
        return [
            .modifier(keyCode: 58, flags: option, at: 0),
            .key(keyCode: 49, flags: option, isDown: true, at: 0.006),
            .key(keyCode: 49, flags: option, isDown: false, at: 0.026),
            .modifier(keyCode: 58, flags: [], at: 0.032),
        ]
    }

    private static func frontmostQuitTarget() -> QuitApplicationTarget? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              !application.isTerminated,
              !isExcludedQuitTarget(
                bundleIdentifier: application.bundleIdentifier,
                processIdentifier: application.processIdentifier,
                currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
                mainBundleIdentifier: Bundle.main.bundleIdentifier
              )
        else { return nil }
        return QuitApplicationTarget(
            processIdentifier: application.processIdentifier,
            displayName: application.localizedName ?? "Current app"
        )
    }

    static func isExcludedQuitTarget(
        bundleIdentifier: String?,
        processIdentifier: pid_t,
        currentProcessIdentifier: pid_t,
        mainBundleIdentifier: String?
    ) -> Bool {
        processIdentifier == currentProcessIdentifier
            || bundleIdentifier == mainBundleIdentifier
            || bundleIdentifier == LaunchAtLoginController.supervisorBundleIdentifier
    }

    /// A normal save-aware Command-Q lifecycle. The target application still
    /// owns confirmation and can refuse or delay termination.
    static func quitApplicationChord() -> [SyntheticKeyboardChordPoster.Event] {
        let command: CGEventFlags = [.maskCommand]
        return [
            .modifier(keyCode: 55, flags: command, at: 0),
            .key(keyCode: 12, flags: command, isDown: true, at: 0.006),
            .key(keyCode: 12, flags: command, isDown: false, at: 0.026),
            .modifier(keyCode: 55, flags: [], at: 0.032),
        ]
    }

}
