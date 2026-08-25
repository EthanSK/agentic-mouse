import CoreGraphics
import ApplicationServices
import ScimitarKit

enum DesktopSpaceActionError: Error, Equatable {
    case accessibilityPermissionMissing
    case eventCreationFailed
}

/// Sends the standard macOS Space-navigation shortcuts without changing app
/// focus. This Mac stores them as Control-Fn-Arrow. Emit a real modifier
/// lifecycle rather than relying on flags attached to the arrow alone.
@MainActor
struct DesktopSpaceActionExecutor {
    typealias KeyEvent = SyntheticKeyboardChordPoster.Event

    typealias ChordPoster = @MainActor (_ events: [KeyEvent]) -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool

    private static let controlKeyCode: CGKeyCode = 59
    private static let leftArrowKeyCode: CGKeyCode = 123
    private static let rightArrowKeyCode: CGKeyCode = 124

    private let postChord: ChordPoster
    private let accessibilityTrusted: AccessibilityTrustProvider

    init(
        postChord: @escaping ChordPoster = SyntheticKeyboardChordPoster.shared.post,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted
    ) {
        self.postChord = postChord
        self.accessibilityTrusted = accessibilityTrusted
    }

    /// Test-only convenience that avoids coupling event-recorder tests to TCC.
    init(_ postChord: @escaping ChordPoster) {
        self.init(postChord: postChord, accessibilityTrusted: { true })
    }

    func perform(_ action: ModeUtilityAction) -> Result<Void, DesktopSpaceActionError> {
        guard accessibilityTrusted() else {
            return .failure(.accessibilityPermissionMissing)
        }
        let keyCode: CGKeyCode
        switch action {
        case .moveToSpaceLeft:
            keyCode = Self.leftArrowKeyCode
        case .moveToSpaceRight:
            keyCode = Self.rightArrowKeyCode
        case .increaseDisplayBrightness, .decreaseDisplayBrightness,
             .rewindYouTubeFiveSeconds, .openIntelligenceOnDemand, .zoomIn, .zoomOut,
             .copy, .paste, .showDesktop, .missionControl,
             .moveWindowLeftWithMagnet, .moveWindowRightWithMagnet,
             .pasteStoredPassword, .showApplicationWindows, .organizeWindows, .quitApp:
            preconditionFailure("DesktopSpaceActionExecutor only owns Space Left and Space Right")
        }

        let shortcutFlags: CGEventFlags = [.maskControl, .maskSecondaryFn]
        let events = [
            KeyEvent.modifier(keyCode: Self.controlKeyCode, flags: [.maskControl], at: 0),
            KeyEvent.key(keyCode: keyCode, flags: shortcutFlags, isDown: true, at: 0.006),
            KeyEvent.key(keyCode: keyCode, flags: shortcutFlags, isDown: false, at: 0.026),
            KeyEvent.modifier(keyCode: Self.controlKeyCode, flags: [], at: 0.032),
        ]
        guard postChord(events) else {
            return .failure(.eventCreationFailed)
        }
        return .success(())
    }

}
