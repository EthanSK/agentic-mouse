// Opens Ethan's Claude Session plugin through Codex's New tab picker when the
// Razer 9 action requests it. Accessibility notifications advance the two
// menu actions without inserting a delay between them.
import AppKit
import ApplicationServices
import ScimitarKit

@MainActor
final class CodexClaudeSessionOpener {
    private var session: PickerSession?

    func open(
        requestAllowed: @escaping () -> Bool,
        feedback: @escaping (CodexActionFeedback) -> Void
    ) -> Result<Void, ApplicationShortcutDispatcher.DispatchError> {
        cancel()
        guard let candidate = PickerSession(requestAllowed: requestAllowed, feedback: feedback) else {
            return .failure(.init(description: "Open the Codex chat first"))
        }
        session = candidate
        guard candidate.observe() else {
            cancel()
            return .failure(.init(description: "Could not watch the Codex tab picker"))
        }
        guard candidate.openNewTab() else {
            cancel()
            return .failure(.init(description: "Could not open the Codex tab picker"))
        }
        candidate.advance()
        return .success(())
    }

    func cancel() {
        session?.cancel()
        session = nil
    }
}

@MainActor
private final class PickerSession {
    private let application: NSRunningApplication
    private let root: AXUIElement
    private let window: AXUIElement
    private let originalTitle: String
    private let requestAllowed: () -> Bool
    private let feedback: (CodexActionFeedback) -> Void
    private var observer: AXObserver?
    private var expiry: DispatchWorkItem?
    private var activationObserver: NSObjectProtocol?
    private var step = 0
    private var advancing = false
    private var finished = false
    private let labels = ["More tools…", "Open Claude session"]

    init?(requestAllowed: @escaping () -> Bool, feedback: @escaping (CodexActionFeedback) -> Void) {
        guard requestAllowed(), AXIsProcessTrusted(),
              let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: CodexMode.bundleIdentifier
              ).first(where: { $0.isActive }) else { return nil }
        let root = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.04)
        guard let windowValue = Self.value(root, kAXFocusedWindowAttribute),
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }
        self.application = application
        self.root = root
        self.window = unsafeBitCast(windowValue, to: AXUIElement.self)
        self.originalTitle = Self.value(self.window, kAXTitleAttribute) as? String ?? ""
        self.requestAllowed = requestAllowed
        self.feedback = feedback
    }

    private var isCurrent: Bool {
        guard !finished, requestAllowed(), AXIsProcessTrusted(), application.isActive,
              let focused = Self.value(root, kAXFocusedWindowAttribute),
              CFEqual(focused, window) else { return false }
        return (Self.value(window, kAXTitleAttribute) as? String ?? "") == originalTitle
    }

    func observe() -> Bool {
        var result: AXObserver?
        guard AXObserverCreate(application.processIdentifier, { _, _, _, context in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<PickerSession>.fromOpaque(context).takeUnretainedValue().advance()
            }
        }, &result) == .success, let result else { return false }
        observer = result
        let context = Unmanaged.passUnretained(self).toOpaque()
        var subscribed = false
        for target in [root, window] {
            for name in [kAXLayoutChangedNotification, kAXFocusedUIElementChangedNotification,
                         kAXFocusedWindowChangedNotification, kAXMenuOpenedNotification] {
                if AXObserverAddNotification(result, target, name as CFString, context) == .success {
                    subscribed = true
                }
            }
        }
        guard subscribed else { cancel(); return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(result), .commonModes)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self,
                      let active = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      active.processIdentifier != self.application.processIdentifier else { return }
                self.cancel()
            }
        }
        let expiry = DispatchWorkItem { [weak self] in
            guard let self, !self.finished else { return }
            if self.isCurrent {
                self.feedback(.notConfirmed("Could not open Claude session. Use New tab → More tools…"))
            }
            self.cancel()
        }
        self.expiry = expiry
        // This bounds the operation if Codex never publishes the next control.
        // It does not defer any menu action or retry a dispatched command.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: expiry)
        return true
    }

    func advance() {
        guard !advancing else { return }
        guard isCurrent else { cancel(); return }
        advancing = true
        defer { advancing = false }
        let expectedRole = step == 0 ? Set(["AXButton", "AXPopUpButton"]) : Set(["AXMenuItem"])
        guard let control = uniqueControl(in: window, label: labels[step], roles: expectedRole), isCurrent else { return }
        // Advance before AXPress because a synchronous layout notification can
        // arrive while Codex changes the menu. Each control is pressed once.
        step += 1
        guard AXUIElementPerformAction(control, kAXPressAction as CFString) == .success else {
            feedback(.notConfirmed("Could not open Claude session"))
            cancel()
            return
        }
        if step == labels.count {
            feedback(.sentUnverified("Claude session requested"))
            cancel()
        } else {
            DispatchQueue.main.async { [weak self] in self?.advance() }
        }
    }

    func openNewTab() -> Bool {
        guard isCurrent, let menuValue = Self.value(root, kAXMenuBarAttribute),
              CFGetTypeID(menuValue) == AXUIElementGetTypeID() else { return false }
        let menu = unsafeBitCast(menuValue, to: AXUIElement.self)
        guard let command = uniqueControl(in: menu, label: "New tab", roles: ["AXMenuItem"]), isCurrent else { return false }
        return AXUIElementPerformAction(command, kAXPressAction as CFString) == .success
    }

    private func uniqueControl(in parent: AXUIElement, label: String, roles: Set<String>) -> AXUIElement? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.25
        var queue = [parent]
        var cursor = 0
        var matches: [AXUIElement] = []
        while cursor < queue.count, cursor < 1800, ProcessInfo.processInfo.systemUptime < deadline {
            let node = queue[cursor]
            cursor += 1
            let role = Self.value(node, kAXRoleAttribute) as? String ?? ""
            if roles.contains(role),
               [kAXTitleAttribute, kAXDescriptionAttribute].contains(where: { Self.value(node, $0) as? String == label }),
               Self.value(node, kAXEnabledAttribute) as? Bool != false {
                matches.append(node)
            }
            let subrole = Self.value(node, kAXSubroleAttribute) as? String ?? ""
            if role != "AXStaticText", role != "AXTextArea", subrole != "AXApplicationLog" {
                queue.append(contentsOf: Self.value(node, kAXChildrenAttribute) as? [AXUIElement] ?? [])
            }
        }
        guard cursor == queue.count, matches.count == 1 else { return nil }
        return matches.first
    }

    func cancel() {
        finished = true
        expiry?.cancel()
        expiry = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
    }

    private static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
    }
}
