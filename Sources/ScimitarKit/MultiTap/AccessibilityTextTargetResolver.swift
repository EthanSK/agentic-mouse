#if canImport(ApplicationServices) && canImport(AppKit)
import AppKit
import ApplicationServices
import Foundation

/// Resolves the live typing destination through the Accessibility API.
///
/// It answers three questions on every call:
///
///   1. Which application is frontmost?     → `processIdentifier`
///   2. Which element inside it has focus?  → exact identity when exposed
///   3. Will that element accept text?      → editable, including secure fields
///
/// Some standard inputs, including Spotify's Chromium-backed search field, do
/// not expose `AXFocusedUIElement` even while ordinary keyboard input works.
/// In that case the resolver falls back to the unchanged frontmost application
/// rather than declaring that no focus exists. Delivery still revalidates the
/// PID at every irreversible boundary and never crosses into another app.
///
/// The identity token tracks the actual focused `AXUIElement` using Core
/// Foundation equality. It never reads the field's contents, title, placeholder
/// or window name. A structurally identical replacement field therefore gets a
/// new token instead of being mistaken for the original destination.
public final class AccessibilityTextTargetResolver: TextTargetResolving {
    private let permission: AccessibilityPermissionChecking
    private let workspace: NSWorkspace
    private let ownProcessIdentifier: pid_t
    private let log: Log

    /// Roles that accept typed text.
    private static let editableRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        // Electron editors normally expose AXTextArea or a settable AXValue.
        // A generic AXWebArea alone is not proof that the page is editable.
    ]

    private var lastFocusedElement: AXUIElement?
    private var lastElementToken: UInt64 = 0

    public init(
        permission: AccessibilityPermissionChecking = AccessibilityPermission(),
        workspace: NSWorkspace = .shared,
        log: Log
    ) {
        self.permission = permission
        self.workspace = workspace
        self.ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        self.log = log
    }

    public func resolveCurrentTarget() -> TextTargetResolution {
        guard permission.isTrusted else {
            return .refused(.accessibilityPermissionMissing)
        }
        guard let application = workspace.frontmostApplication,
              application.processIdentifier != ownProcessIdentifier
        else {
            // Our own HUD is a non-activating panel and this process is an
            // accessory, so it should never be frontmost. If it somehow is,
            // there is no user text field to type into.
            return .refused(.noFrontmostApplication)
        }

        let pid = application.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        let fallback = TextTarget(
            processIdentifier: pid,
            elementIdentity: "frontmost:\(pid)",
            redactedApplication: "app:" + Redaction.tag(application.bundleIdentifier ?? "\(pid)"),
            anchor: .frontmostApplication
        )

        guard let focused = copyElement(from: appElement, attribute: kAXFocusedUIElementAttribute) else {
            return .ready(fallback)
        }

        let role = copyString(from: focused, attribute: kAXRoleAttribute) ?? ""
        let subrole = copyString(from: focused, attribute: kAXSubroleAttribute) ?? ""

        // `AXValue` being settable is the most reliable "you can type here"
        // signal across AppKit, Catalyst, Electron and web content. Secure text
        // fields are ordinary editable keyboard targets: the resolver never
        // reads their value and the output path sends process-targeted key
        // events, so refusing them would only break expected mouse typing.
        let isSettable = isAttributeSettable(focused, attribute: kAXValueAttribute)
        let hasEditableRole = Self.acceptsTextEntry(
            role: role,
            subrole: subrole,
            isValueSettable: isSettable
        )

        guard hasEditableRole else { return .ready(fallback) }

        let identity = elementIdentity(for: focused, processIdentifier: pid)
        let target = TextTarget(
            processIdentifier: pid,
            elementIdentity: identity,
            redactedApplication: "app:" + Redaction.tag(application.bundleIdentifier ?? "\(pid)")
        )
        return .ready(target)
    }

    static func acceptsTextEntry(
        role: String,
        subrole: String,
        isValueSettable: Bool
    ) -> Bool {
        isValueSettable || editableRoles.contains(role) || editableRoles.contains(subrole)
    }

    // MARK: - Identity

    /// Opaque identity for the actual focused Accessibility object.
    /// `AXUIElement` is a CF type and explicitly supports `CFEqual`; separate
    /// wrappers for the same remote element compare equal. Retaining only the
    /// most recently seen element is sufficient: once focus moves, every
    /// pending character anchored to the previous token is cancelled.
    private func elementIdentity(for element: AXUIElement, processIdentifier: pid_t) -> String {
        if let previous = lastFocusedElement, CFEqual(previous, element) {
            return "ax:\(processIdentifier):\(lastElementToken)"
        }
        lastFocusedElement = element
        lastElementToken &+= 1
        return "ax:\(processIdentifier):\(lastElementToken)"
    }

    // MARK: - AX helpers

    private func copyElement(from element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private func copyString(from element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let string = value as? String,
              !string.isEmpty
        else { return nil }
        return string
    }

    private func isAttributeSettable(_ element: AXUIElement, attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }
}
#endif
