import ApplicationServices
import CoreGraphics
import ScimitarKit

enum SystemOverviewActionError: Error, Equatable {
    case accessibilityPermissionMissing
    case eventCreationFailed
}

/// Sends this Mac's enabled symbolic shortcuts for Show Desktop, Mission
/// Control, and Application Windows. Each action is one bounded down/up cycle
/// and preserves app focus.
@MainActor
struct SystemOverviewActionExecutor {
    typealias KeyEvent = SyntheticKeyboardChordPoster.Event
    typealias ChordPoster = @MainActor (_ events: [KeyEvent]) -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool

    private static let f11KeyCode: CGKeyCode = 103
    private static let upArrowKeyCode: CGKeyCode = 126
    private static let downArrowKeyCode: CGKeyCode = 125

    private static let controlKeyCode: CGKeyCode = 59

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

    func perform(_ action: ModeUtilityAction) -> Result<Void, SystemOverviewActionError> {
        guard accessibilityTrusted() else {
            return .failure(.accessibilityPermissionMissing)
        }

        let events: [KeyEvent]
        switch action {
        case .showDesktop:
            // Apple's supported Fn-F11 shortcut and this Mac's enabled
            // symbolic-hotkey configuration both resolve to this exact pair.
            events = [
                .key(keyCode: Self.f11KeyCode, flags: [.maskSecondaryFn], isDown: true, at: 0),
                .key(keyCode: Self.f11KeyCode, flags: [.maskSecondaryFn], isDown: false, at: 0.020),
            ]
        case .missionControl:
            // This Mac's enabled Mission Control symbolic hotkey is
            // Control-Fn-Up (key 126, flags 0x840000). The missing Fn flag was
            // why the prior synthetic Control-Up cycle was ignored.
            let flags: CGEventFlags = [.maskControl, .maskSecondaryFn]
            events = Self.controlledArrowEvents(keyCode: Self.upArrowKeyCode, flags: flags)
        case .showApplicationWindows:
            // Symbolic hotkey 33 is enabled as Control-Fn-Down on this Mac,
            // matching the four-finger swipe-down App Exposé gesture.
            let flags: CGEventFlags = [.maskControl, .maskSecondaryFn]
            events = Self.controlledArrowEvents(keyCode: Self.downArrowKeyCode, flags: flags)
        case .increaseDisplayBrightness, .decreaseDisplayBrightness,
             .rewindYouTubeFiveSeconds, .openIntelligenceOnDemand, .zoomIn, .zoomOut,
             .moveToSpaceLeft, .moveToSpaceRight, .copy, .paste,
             .moveWindowLeftWithMagnet, .moveWindowRightWithMagnet,
             .organizeWindows, .quitApp,
             .pasteStoredPassword:
            preconditionFailure("SystemOverviewActionExecutor only owns macOS overview actions")
        }

        guard postChord(events) else {
            return .failure(.eventCreationFailed)
        }
        return .success(())
    }

    private static func controlledArrowEvents(
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> [KeyEvent] {
        [
            .modifier(keyCode: controlKeyCode, flags: [.maskControl], at: 0),
            .key(keyCode: keyCode, flags: flags, isDown: true, at: 0.006),
            .key(keyCode: keyCode, flags: flags, isDown: false, at: 0.026),
            .modifier(keyCode: controlKeyCode, flags: [], at: 0.032),
        ]
    }
}
