import ApplicationServices
import CoreGraphics

enum ForwardNavigationActionError: Error, Equatable {
    case inputBlocked
    case accessibilityPermissionMissing
    case eventCreationFailed
}

/// Emits the ordinary auxiliary mouse-button Forward click after physical
/// cell 5 is released without using the YouTube volume chord.
@MainActor
struct ForwardNavigationActionExecutor {
    typealias Poster = @MainActor () -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool
    typealias InputAllowedProvider = @MainActor () -> Bool

    private let post: Poster
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider

    init(
        post: @escaping Poster = Self.postForwardClick,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping InputAllowedProvider = { true }
    ) {
        self.post = post
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
    }

    func perform() -> Result<Void, ForwardNavigationActionError> {
        guard inputAllowed() else { return .failure(.inputBlocked) }
        guard accessibilityTrusted() else {
            return .failure(.accessibilityPermissionMissing)
        }
        return post() ? .success(()) : .failure(.eventCreationFailed)
    }

    private static func postForwardClick() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let forwardButton = CGMouseButton(rawValue: 4),
              let location = CGEvent(source: source)?.location,
              let down = CGEvent(
                mouseEventSource: source,
                mouseType: .otherMouseDown,
                mouseCursorPosition: location,
                mouseButton: forwardButton
              ),
              let up = CGEvent(
                mouseEventSource: source,
                mouseType: .otherMouseUp,
                mouseCursorPosition: location,
                mouseButton: forwardButton
              )
        else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
