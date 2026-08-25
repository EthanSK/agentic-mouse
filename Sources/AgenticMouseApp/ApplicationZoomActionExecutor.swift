import CoreGraphics
import ApplicationServices
import ScimitarKit

enum ApplicationZoomActionError: Error, Equatable {
    case accessibilityPermissionMissing
    case eventCreationFailed
}

/// Sends the standard macOS zoom shortcut to the current frontmost app.
///
/// Zoom In is Command-Plus (the physical equals key with Shift); Zoom Out is
/// Command-Minus. Posting one bounded down/up cycle keeps the Modes menu open
/// and never changes application focus.
@MainActor
struct ApplicationZoomActionExecutor {
    typealias EventPoster = @MainActor (_ keyCode: CGKeyCode, _ flags: CGEventFlags, _ isDown: Bool) -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool

    private static let equalsKeyCode: CGKeyCode = 24
    private static let minusKeyCode: CGKeyCode = 27

    private let postEvent: EventPoster
    private let accessibilityTrusted: AccessibilityTrustProvider

    init(
        postEvent: @escaping EventPoster = Self.postKeyboardEvent,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted
    ) {
        self.postEvent = postEvent
        self.accessibilityTrusted = accessibilityTrusted
    }

    /// Test-only convenience that keeps existing event-recorder call sites
    /// deterministic without depending on the host process's TCC state.
    init(_ postEvent: @escaping EventPoster) {
        self.init(postEvent: postEvent, accessibilityTrusted: { true })
    }

    func perform(_ action: ModeUtilityAction) -> Result<Void, ApplicationZoomActionError> {
        guard accessibilityTrusted() else {
            return .failure(.accessibilityPermissionMissing)
        }
        let keyCode: CGKeyCode
        let flags: CGEventFlags
        switch action {
        case .zoomIn:
            keyCode = Self.equalsKeyCode
            flags = [.maskCommand, .maskShift]
        case .zoomOut:
            keyCode = Self.minusKeyCode
            flags = [.maskCommand]
        case .increaseDisplayBrightness, .decreaseDisplayBrightness,
             .rewindYouTubeFiveSeconds, .openIntelligenceOnDemand,
             .moveToSpaceLeft, .moveToSpaceRight, .copy, .paste,
             .moveWindowLeftWithMagnet, .moveWindowRightWithMagnet,
             .showDesktop, .missionControl, .pasteStoredPassword,
             .showApplicationWindows, .organizeWindows, .quitApp:
            preconditionFailure("ApplicationZoomActionExecutor only owns Zoom In and Zoom Out")
        }

        guard postEvent(keyCode, flags, true), postEvent(keyCode, flags, false) else {
            return .failure(.eventCreationFailed)
        }
        return .success(())
    }

    private static func postKeyboardEvent(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        isDown: Bool
    ) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: isDown
              ) else {
            return false
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        return true
    }
}
