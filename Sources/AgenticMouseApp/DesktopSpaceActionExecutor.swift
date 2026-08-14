import CoreGraphics
import ApplicationServices
import ScimitarKit

enum DesktopSpaceActionError: Error, Equatable {
    case accessibilityPermissionMissing
    case eventCreationFailed
}

/// Sends the standard macOS Space-navigation shortcuts without changing app
/// focus. Each mouse press produces one bounded Control-Arrow down/up cycle.
@MainActor
struct DesktopSpaceActionExecutor {
    typealias EventPoster = @MainActor (
        _ keyCode: CGKeyCode,
        _ flags: CGEventFlags,
        _ isDown: Bool
    ) -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool

    private static let leftArrowKeyCode: CGKeyCode = 123
    private static let rightArrowKeyCode: CGKeyCode = 124

    private let postEvent: EventPoster
    private let accessibilityTrusted: AccessibilityTrustProvider

    init(
        postEvent: @escaping EventPoster = Self.postKeyboardEvent,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted
    ) {
        self.postEvent = postEvent
        self.accessibilityTrusted = accessibilityTrusted
    }

    /// Test-only convenience that avoids coupling event-recorder tests to TCC.
    init(_ postEvent: @escaping EventPoster) {
        self.init(postEvent: postEvent, accessibilityTrusted: { true })
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
             .rewindYouTubeFiveSeconds, .zoomIn, .zoomOut:
            preconditionFailure("DesktopSpaceActionExecutor only owns Space Left and Space Right")
        }

        let flags: CGEventFlags = [.maskControl]
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
