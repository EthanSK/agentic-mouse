import Foundation

/// The exact place a pending character is allowed to land.
///
/// Two things identify it, and **both** must still hold at commit time:
///
///  * `processIdentifier` — the frontmost application. Guards against the user
///    switching apps mid-character.
///  * `elementIdentity`   — an opaque token for the focused Accessibility
///    element. Guards against tabbing from the "To" field to the "Subject"
///    field *inside the same app*, which a PID check alone would miss.
///
/// If either changes, the pending character is cancelled: nothing is typed into
/// the old field and nothing is typed into the new one.
public struct TextTarget: Equatable, Hashable, Sendable {
    public enum Anchor: String, Equatable, Hashable, Sendable {
        /// Accessibility exposed the exact editable element.
        case focusedElement
        /// The app hid its internal keyboard focus. Delivery is allowed only
        /// while the same application remains frontmost.
        case frontmostApplication
    }

    public let processIdentifier: pid_t
    /// Opaque, stable-for-the-lifetime-of-the-focus identity of the focused AX
    /// element. Never contains the element's *contents*.
    public let elementIdentity: String
    /// Redacted bundle tag, safe for logs.
    public let redactedApplication: String
    public let anchor: Anchor

    public init(
        processIdentifier: pid_t,
        elementIdentity: String,
        redactedApplication: String,
        anchor: Anchor = .focusedElement
    ) {
        self.processIdentifier = processIdentifier
        self.elementIdentity = elementIdentity
        self.redactedApplication = redactedApplication
        self.anchor = anchor
    }

    public var debugDescription: String {
        "pid \(processIdentifier) · \(redactedApplication) · \(anchor.rawValue) · el:\(Redaction.tag(elementIdentity))"
    }
}

/// Why a target was refused. All of these fail **closed**: no text is emitted.
public enum TextTargetRefusal: Equatable, Sendable {
    case accessibilityPermissionMissing
    /// The focused element does not accept text (a button, a list, the desktop).
    case notEditable
    /// Nothing is focused, or Accessibility could not tell us what is.
    case unknown
    case noFrontmostApplication

    public var explanation: String {
        switch self {
        case .accessibilityPermissionMissing:
            return "Accessibility permission is not granted."
        case .notEditable:
            return "The focused element does not accept text."
        case .unknown:
            return "Could not determine what has keyboard focus."
        case .noFrontmostApplication:
            return "No frontmost application."
        }
    }
}

public enum TextTargetResolution: Equatable, Sendable {
    case ready(TextTarget)
    case refused(TextTargetRefusal)

    public var target: TextTarget? {
        if case .ready(let target) = self { return target }
        return nil
    }

    public var refusal: TextTargetRefusal? {
        if case .refused(let reason) = self { return reason }
        return nil
    }
}

/// Resolves the current typing destination. Injected so the state machine can
/// be tested with no Accessibility permission and no foreground app.
public protocol TextTargetResolving: AnyObject {
    func resolveCurrentTarget() -> TextTargetResolution
}

/// Scriptable resolver for tests and simulation.
public final class StubTextTargetResolver: TextTargetResolving {
    public var resolution: TextTargetResolution

    public init(resolution: TextTargetResolution = .ready(
        TextTarget(processIdentifier: 1234, elementIdentity: "field-a", redactedApplication: "app:test")
    )) {
        self.resolution = resolution
    }

    public func resolveCurrentTarget() -> TextTargetResolution { resolution }

    /// Convenience: move focus to a different element in the *same* app.
    public func moveToElement(_ identity: String) {
        guard let current = resolution.target else { return }
        resolution = .ready(
            TextTarget(
                processIdentifier: current.processIdentifier,
                elementIdentity: identity,
                redactedApplication: current.redactedApplication
            )
        )
    }

    /// Convenience: switch to a different application.
    public func moveToApplication(pid: pid_t, elementIdentity: String = "field-a") {
        resolution = .ready(
            TextTarget(
                processIdentifier: pid,
                elementIdentity: elementIdentity,
                redactedApplication: "app:\(pid)"
            )
        )
    }
}
