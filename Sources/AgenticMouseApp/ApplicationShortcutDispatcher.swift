import AppKit
import ApplicationServices

/// Delivers one bounded keyboard shortcut directly to a running application's
/// process without activating it. The transport is generic; each app-specific
/// mode supplies only its bundle identifier and shortcut semantics.
@MainActor
final class ApplicationShortcutDispatcher {
    struct DispatchError: Error, CustomStringConvertible {
        let description: String
    }

    struct Shortcut: Equatable {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    typealias TargetProcessResolver = @MainActor (_ bundleIdentifier: String) -> pid_t?
    typealias EventPoster = @MainActor (
        _ pid: pid_t,
        _ keyCode: CGKeyCode,
        _ flags: CGEventFlags,
        _ isDown: Bool
    ) -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool
    typealias InputAllowedProvider = @MainActor () -> Bool

    private let targetProcessResolver: TargetProcessResolver
    private let postEvent: EventPoster
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider

    init(
        targetProcessResolver: @escaping TargetProcessResolver = { bundleIdentifier in
            let applications = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            )
            return applications.first(where: { $0.isActive })?.processIdentifier
                ?? applications.first(where: { !$0.isTerminated })?.processIdentifier
        },
        postEvent: EventPoster? = nil,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping InputAllowedProvider = { true }
    ) {
        self.targetProcessResolver = targetProcessResolver
        self.postEvent = postEvent ?? Self.postKeyboardEvent
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
    }

    func perform(
        _ shortcut: Shortcut,
        targetBundleIdentifier: String,
        targetDisplayName: String
    ) -> Result<Void, DispatchError> {
        guard inputAllowed() else {
            return .failure(DispatchError(
                description: "Mouse commands are disabled while macOS is locked"
            ))
        }
        guard accessibilityTrusted() else {
            return .failure(DispatchError(
                description: "Accessibility permission is required for \(targetDisplayName) shortcuts"
            ))
        }
        guard let pid = targetProcessResolver(targetBundleIdentifier) else {
            return .failure(DispatchError(description: "\(targetDisplayName) is not running"))
        }

        let downSucceeded = postEvent(pid, shortcut.keyCode, shortcut.flags, true)
        let upSucceeded = postEvent(pid, shortcut.keyCode, shortcut.flags, false)
        guard downSucceeded, upSucceeded else {
            return .failure(DispatchError(
                description: "Could not deliver the \(targetDisplayName) shortcut"
            ))
        }
        return .success(())
    }

    private static func postKeyboardEvent(
        pid: pid_t,
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        isDown: Bool
    ) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: isDown
              )
        else { return false }
        event.flags = flags
        event.postToPid(pid)
        return true
    }
}
