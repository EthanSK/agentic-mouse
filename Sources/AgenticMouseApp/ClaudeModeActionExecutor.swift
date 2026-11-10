import AppKit
import ApplicationServices
import ScimitarKit

/// Routes Claude's verified menu accelerators and exact Accessibility buttons.
/// AX matching is deliberately exact so a Claude UI change fails closed rather
/// than pressing a similarly named control.
@MainActor
final class ClaudeModeActionExecutor {
    typealias ActionError = ApplicationShortcutDispatcher.DispatchError
    typealias AccessibilityActionPerformer = @MainActor (_ action: ClaudeModeAction) -> Bool

    private struct AXElementIdentity: Hashable {
        let element: AXUIElement

        static func == (lhs: AXElementIdentity, rhs: AXElementIdentity) -> Bool {
            CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(CFHash(element))
        }
    }

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
        case .chooseEffort: return .init(keyCode: 14, flags: [.maskCommand, .maskShift])
        case .toggleVoiceMode, .toggleMicrophoneMute, .openSideChat, .closePane:
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
            return pressExactClaudeButton(action)
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

    private static func pressExactClaudeButton(_ action: ClaudeModeAction) -> Bool {
        let acceptedLabels = acceptedLabels(for: action)
        guard !acceptedLabels.isEmpty else { return false }

        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: ClaudeMode.bundleIdentifier
        )
        guard let application = applications.first(where: { $0.isActive })
                ?? applications.first(where: { !$0.isTerminated })
        else { return false }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(applicationElement, 0.08)
        guard let root = focusedWindow(of: applicationElement) else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.75

        let elements = CodexQueuedMessageSteerer.boundedBreadthFirstTraversal(
            roots: [root],
            limit: 5_000,
            identity: { AXElementIdentity(element: $0) },
            children: children,
            shouldContinue: { ProcessInfo.processInfo.systemUptime < deadline }
        )
        var matches: [AXUIElement] = []
        for element in elements {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            if isExactPressableControl(
                action,
                role: role(of: element),
                labels: labels(of: element),
                isEnabled: isEnabled(element),
                supportsPress: supportsPress(element)
            ) {
                matches.append(element)
            }
        }
        guard matches.count == 1 else { return false }
        return AXUIElementPerformAction(matches[0], kAXPressAction as CFString) == .success
    }

    static func acceptedLabels(for action: ClaudeModeAction) -> Set<String> {
        switch action {
        case .toggleVoiceMode:
            return ["voice mode", "use voice mode", "start voice mode",
                    "end voice mode", "exit voice mode"]
        case .toggleMicrophoneMute:
            return ["mute", "unmute", "mute microphone", "unmute microphone",
                    "turn off microphone", "turn on microphone"]
        default:
            return []
        }
    }

    static func isExactPressableControl(
        _ action: ClaudeModeAction,
        role: String?,
        labels: Set<String>,
        isEnabled: Bool,
        supportsPress: Bool
    ) -> Bool {
        role == kAXButtonRole as String
            && isEnabled
            && supportsPress
            && !acceptedLabels(for: action).isDisjoint(with: labels)
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

    private static func labels(of element: AXUIElement) -> Set<String> {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
            .compactMap { stringAttribute($0 as CFString, of: element) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .reduce(into: Set<String>()) { $0.insert($1) }
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
