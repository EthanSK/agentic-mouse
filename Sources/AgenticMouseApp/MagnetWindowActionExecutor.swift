import ApplicationServices
import ScimitarKit

enum MagnetWindowActionError: Error, Equatable {
    case inputBlocked
    case accessibilityPermissionMissing
    case eventCreationFailed
}

/// Runs the wand/mouse "Magnet" Left/Right window commands.
///
/// Ethan's terminology: the Magic Wand's "Magnet wedge" (and the mice's
/// Magnet + Wheel card) means these two actions. Since 2026-10-31 they use
/// Agentic Mouse's BUILT-IN snapping (`WindowSnapController`): Ethan asked for
/// it to be "part of the Agentic Mouse app instead of its own standalone
/// app" and to work "via the inbuilt thing" while the third-party Magnet app
/// stays installed and running for his keyboard shortcuts.
///
///  1. Native desktop route (default): invoke macOS Move & Resize and native
///     Move to Display commands. macOS owns the original size and restores it
///     when the window is dragged away. Never select Full-Screen Tile.
///  2. Magnet route (kept, not the default): Magnet's configured global
///     Control-Option-Arrow accelerator, sent as the complete modifier/arrow
///     lifecycle a physical keyboard produces. Used only when no built-in
///     snapper is injected (tests, or if the built-in route is ever switched
///     off).
@MainActor
struct MagnetWindowActionExecutor {
    typealias KeyEvent = SyntheticKeyboardChordPoster.Event

    typealias ChordPoster = @MainActor (_ events: [KeyEvent]) -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool
    typealias InputAllowedProvider = @MainActor () -> Bool
    /// Starts one built-in snap; returns false when there is nothing to act on.
    typealias WindowSnapper = @MainActor (_ side: WindowSnapDirection, _ source: MouseSource?, _ inputAllowed: @escaping InputAllowedProvider) -> Bool

    static let leftControlKeyCode: CGKeyCode = 59
    static let leftOptionKeyCode: CGKeyCode = 58
    static let leftArrowKeyCode: CGKeyCode = 123
    static let rightArrowKeyCode: CGKeyCode = 124

    private let postChord: ChordPoster
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider
    private let snapWindow: WindowSnapper?

    init(
        postChord: @escaping ChordPoster = SyntheticKeyboardChordPoster.shared.post,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping InputAllowedProvider = { true },
        snapWindow: WindowSnapper? = { side, source, allowed in
            WindowSnapController.shared.snapFrontmostWindow(side, source: source, inputAllowed: allowed)
        }
    ) {
        self.postChord = postChord
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
        self.snapWindow = snapWindow
    }

    /// Test-only convenience that avoids coupling command-routing tests to TCC.
    /// Pins the Magnet keyboard route (no built-in snapper) so the existing
    /// shortcut-lifecycle tests keep exercising that path.
    init(_ postChord: @escaping ChordPoster) {
        self.init(
            postChord: postChord,
            accessibilityTrusted: { true },
            inputAllowed: { true },
            snapWindow: nil
        )
    }

    func perform(_ action: ModeUtilityAction, source: MouseSource? = nil) -> Result<Void, MagnetWindowActionError> {
        guard inputAllowed() else { return .failure(.inputBlocked) }
        guard accessibilityTrusted() else {
            return .failure(.accessibilityPermissionMissing)
        }

        // Built-in route. The lock and Accessibility gates above cover it
        // too (it needs Accessibility to move windows anyway).
        if let snapWindow, let side = Self.snapDirection(for: action) {
            return snapWindow(side, source, inputAllowed) ? .success(()) : .failure(.eventCreationFailed)
        }

        guard let events = Self.keyEvents(for: action) else {
            preconditionFailure("MagnetWindowActionExecutor only owns Magnet Left and Right")
        }
        return postChord(events)
            ? .success(())
            : .failure(.eventCreationFailed)
    }

    /// Which half each wedge direction snaps to.
    static func snapDirection(for action: ModeUtilityAction) -> WindowSnapDirection? {
        switch action {
        case .moveWindowLeftWithMagnet: return .left
        case .moveWindowRightWithMagnet: return .right
        default: return nil
        }
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
             .selectAll, .tab, .save, .copy, .paste, .showDesktop, .missionControl,
             .pasteStoredPassword, .showApplicationWindows, .organizeWindows, .spotifySongRadio, .quitApp:
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
