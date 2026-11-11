import AppKit
import ApplicationServices
import ScimitarKit

/// Routes Claude's verified menu accelerators and exact Accessibility buttons.
/// Use exact enabled menu items for pane commands to avoid closing the window.
@MainActor
final class ClaudeModeActionExecutor {
    typealias ActionError = ApplicationShortcutDispatcher.DispatchError
    typealias AccessibilityActionPerformer = @MainActor (_ action: ClaudeModeAction) -> Bool

    private let shortcutDispatcher: ApplicationShortcutDispatcher
    private let performAccessibilityAction: AccessibilityActionPerformer
    private let accessibilityTrusted: ApplicationShortcutDispatcher.AccessibilityTrustProvider
    private let inputAllowed: ApplicationShortcutDispatcher.InputAllowedProvider

    init(
        shortcutDispatcher: ApplicationShortcutDispatcher? = nil,
        accessibilityTrusted: @escaping ApplicationShortcutDispatcher.AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping ApplicationShortcutDispatcher.InputAllowedProvider = { true },
        performAccessibilityAction: AccessibilityActionPerformer? = nil
    ) {
        self.shortcutDispatcher = shortcutDispatcher ?? ApplicationShortcutDispatcher(
            accessibilityTrusted: accessibilityTrusted,
            inputAllowed: inputAllowed
        )
        self.performAccessibilityAction = performAccessibilityAction ?? Self.pressClaudeControl
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
    }

    func perform(_ action: ClaudeModeAction) -> Result<Void, ActionError> {
        let shortcut = Self.shortcut(for: action)
        if let shortcut {
            return shortcutDispatcher.perform(
                shortcut,
                targetBundleIdentifier: ClaudeMode.bundleIdentifier,
                targetDisplayName: "Claude"
            )
        }
        guard inputAllowed() else {
            return .failure(ActionError(
                description: "Mouse commands are disabled while macOS is locked"
            ))
        }
        guard accessibilityTrusted() else {
            return .failure(ActionError(
                description: "Accessibility permission is required for Claude shortcuts"
            ))
        }
        guard performAccessibilityAction(action) else {
            return .failure(ActionError(
                description: "Claude does not currently expose the \(action.title) control"
            ))
        }
        return .success(())
    }

    func performTabStep(_ direction: WheelChordDirection) -> Result<Void, ActionError> {
        shortcutDispatcher.perform(
            Self.tabShortcut(for: direction),
            targetBundleIdentifier: ClaudeMode.bundleIdentifier,
            targetDisplayName: "Claude"
        )
    }

    func performTogglePin() -> Result<Void, ActionError> {
        shortcutDispatcher.perform(
            Self.togglePinShortcut,
            targetBundleIdentifier: ClaudeMode.bundleIdentifier,
            targetDisplayName: "Claude"
        )
    }

    // Claude matches these commands by character. A bare ANSI key code sent
    // to its renderer can carry the Dvorak letter instead.
    static let togglePinShortcut = ApplicationShortcutDispatcher.Shortcut(
        keyCode: 35, flags: [.maskCommand, .maskAlternate], character: "p"
    )

    static func tabShortcut(for direction: WheelChordDirection) -> ApplicationShortcutDispatcher.Shortcut {
        // Match Codex's held-wheel navigation: up advances, down goes back.
        .init(keyCode: direction == .up ? 30 : 33,
              flags: [.maskCommand, .maskShift])
    }

    static func shortcut(for action: ClaudeModeAction) -> ApplicationShortcutDispatcher.Shortcut? {
        switch action {
        case .newChat: return .init(keyCode: 45, flags: .maskCommand)
        case .pressEnter: return .init(keyCode: 36, flags: [])
        case .toggleFastMode: return .init(keyCode: 3, flags: [.maskCommand, .maskAlternate])
        case .chooseEffort: return .init(keyCode: 14, flags: [.maskCommand, .maskShift], character: "e")
        case .toggleDictation: return .init(keyCode: 2, flags: .maskCommand, character: "d")
        case .openSideChat, .closePane:
            return nil
        }
    }

    private static func pressClaudeControl(_ action: ClaudeModeAction) -> Bool {
        switch action {
        case .openSideChat:
            return pressMenuItem("New Side Chat", in: "File")
        case .closePane:
            return pressMenuItem("Close Pane", in: "View")
        default:
            return false
        }
    }

    private static func pressMenuItem(_ title: String, in menuTitle: String) -> Bool {
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: ClaudeMode.bundleIdentifier
        ).first(where: { $0.isActive }) else { return false }
        let root = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.08)
        guard let window = focusedWindow(of: root),
              let menuBar = elementAttribute(kAXMenuBarAttribute as CFString, of: root)
        else { return false }

        // Claude's Close Window is always available. Only use the exact
        // session/pane command, and only when Claude has enabled it.
        let menus = children(of: menuBar).filter {
            stringAttribute(kAXTitleAttribute as CFString, of: $0) == menuTitle
        }
        guard menus.count == 1 else { return false }
        let matching = children(of: menus[0]).flatMap { children(of: $0) }.filter {
            role(of: $0) == kAXMenuItemRole as String
                && stringAttribute(kAXTitleAttribute as CFString, of: $0) == title
        }
        guard matching.count == 1, isEnabled(matching[0]), supportsPress(matching[0]),
              application.isActive, let current = focusedWindow(of: root), CFEqual(window, current)
        else { return false }
        return AXUIElementPerformAction(matching[0], kAXPressAction as CFString) == .success
    }

    private static func focusedWindow(of application: AXUIElement) -> AXUIElement? {
        elementAttribute(kAXFocusedWindowAttribute as CFString, of: application)
    }

    private static func elementAttribute(_ name: CFString, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func role(of element: AXUIElement) -> String? {
        stringAttribute(kAXRoleAttribute as CFString, of: element)
    }

    private static func stringAttribute(_ name: CFString, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value as? String
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func isEnabled(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXEnabledAttribute as CFString,
            &value
        ) == .success else { return false }
        return (value as? Bool) == true
    }

    private static func supportsPress(_ element: AXUIElement) -> Bool {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success,
              let actionNames = actions as? [String]
        else { return false }
        return actionNames.contains(kAXPressAction as String)
    }
}
