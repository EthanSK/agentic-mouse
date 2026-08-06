import Foundation
#if canImport(ApplicationServices)
import ApplicationServices
#endif

/// Injectable Accessibility-permission probe.
///
/// The project rule is that the permission is *detected and explained*, never
/// worked around. Nothing here prompts, escalates, writes to the TCC database
/// or otherwise tries to grant itself anything: it reports the truth and the
/// UI explains what the user needs to do.
public protocol AccessibilityPermissionChecking: AnyObject {
    var isTrusted: Bool { get }
}

public final class AccessibilityPermission: AccessibilityPermissionChecking {
    public init() {}

    public var isTrusted: Bool {
        #if canImport(ApplicationServices)
        // Explicitly the non-prompting variant. `AXIsProcessTrustedWithOptions`
        // with `kAXTrustedCheckOptionPrompt` would throw a system dialog at the
        // user behind our back; that is the caller's decision, not ours.
        return AXIsProcessTrusted()
        #else
        return false
        #endif
    }

    /// Human-readable explanation shown in the menu, the HUD and the doctor CLI.
    public static let explanation = """
        Agentic Mouse needs Accessibility permission to type the characters \
        you tap out on the mouse and to verify which text field has focus. The \
        production iCUE SDK route sees side-button presses without this grant; \
        the optional CGEvent fallback also depends on Accessibility.

        Grant it in System Settings → Privacy & Security → Accessibility, then \
        quit and relaunch Agentic Mouse.

        Without it, multi-tap mode stays disabled. Hue colour mirroring does not \
        need this permission and keeps working.
        """

    /// Deep link to the right System Settings pane. Opening it is always a
    /// user-initiated action from the menu; the app never opens it by itself.
    public static let settingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
}

public final class StubAccessibilityPermission: AccessibilityPermissionChecking {
    public var isTrusted: Bool

    public init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }
}
