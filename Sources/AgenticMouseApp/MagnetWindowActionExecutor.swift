import ApplicationServices
import ScimitarKit

enum MagnetWindowActionError: Error, Equatable {
    case inputBlocked
    case accessibilityPermissionMissing
    case eventCreationFailed
}

/// Sends Magnet's configured global Control-Option-Arrow accelerator as the
/// same complete modifier/arrow lifecycle produced by a physical keyboard.
/// Magnet remains the placement-policy owner, including display traversal.
@MainActor
struct MagnetWindowActionExecutor {
    typealias KeyEvent = SyntheticKeyboardChordPoster.Event

    typealias ChordPoster = @MainActor (_ events: [KeyEvent]) -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool
    typealias InputAllowedProvider = @MainActor () -> Bool

    static let leftControlKeyCode: CGKeyCode = 59
    static let leftOptionKeyCode: CGKeyCode = 58
    static let leftArrowKeyCode: CGKeyCode = 123
    static let rightArrowKeyCode: CGKeyCode = 124

    private let postChord: ChordPoster
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider

    init(
        postChord: @escaping ChordPoster = SyntheticKeyboardChordPoster.shared.post,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping InputAllowedProvider = { true }
    ) {
        self.postChord = postChord
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
    }

    /// Test-only convenience that avoids coupling command-routing tests to TCC.
    init(_ postChord: @escaping ChordPoster) {
        self.init(
            postChord: postChord,
            accessibilityTrusted: { true },
            inputAllowed: { true }
        )
    }

    func perform(_ action: ModeUtilityAction) -> Result<Void, MagnetWindowActionError> {
        guard inputAllowed() else { return .failure(.inputBlocked) }
        guard accessibilityTrusted() else {
            return .failure(.accessibilityPermissionMissing)
        }

        guard let events = Self.keyEvents(for: action) else {
            preconditionFailure("MagnetWindowActionExecutor only owns Magnet Left and Right")
        }
        return postChord(events)
            ? .success(())
            : .failure(.eventCreationFailed)
    }

    static func keyEvents(for action: ModeUtilityAction) -> [KeyEvent]? {
        let arrowKeyCode: CGKeyCode
        switch action {
        case .moveWindowLeftWithMagnet:
            arrowKeyCode = leftArrowKeyCode
        case .moveWindowRightWithMagnet:
            arrowKeyCode = rightArrowKeyCode
        case .increaseDisplayBrightness, .decreaseDisplayBrightness,
             .rewindYouTubeFiveSeconds, .openIntelligenceOnDemand, .zoomIn, .zoomOut,
             .moveToSpaceLeft, .moveToSpaceRight,
             .copy, .paste, .showDesktop, .missionControl,
             .pasteStoredPassword, .showApplicationWindows, .organizeWindows, .quitApp:
            return nil
        }

        let control: CGEventFlags = .maskControl
        let controlOption: CGEventFlags = [.maskControl, .maskAlternate]
        // Physical arrow keys carry both of these flags. Omitting them turns
        // the chord into an application-level escape sequence that Magnet's
        // global accelerator does not treat as its configured shortcut.
        let arrowFlags: CGEventFlags = [
            .maskControl,
            .maskAlternate,
            .maskSecondaryFn,
            .maskNumericPad,
        ]
        return [
            KeyEvent.modifier(keyCode: leftControlKeyCode, flags: control, at: 0),
            KeyEvent.modifier(keyCode: leftOptionKeyCode, flags: controlOption, at: 0.006),
            KeyEvent.key(keyCode: arrowKeyCode, flags: arrowFlags, isDown: true, at: 0.012),
            KeyEvent.key(keyCode: arrowKeyCode, flags: arrowFlags, isDown: false, at: 0.032),
            KeyEvent.modifier(keyCode: leftOptionKeyCode, flags: control, at: 0.038),
            KeyEvent.modifier(keyCode: leftControlKeyCode, flags: [], at: 0.044),
        ]
    }
}
