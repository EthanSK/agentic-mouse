import AppKit
import ApplicationServices
import ScimitarKit

enum ClaudePinMenuAction: String, Equatable {
    case pin = "Pin"
    case unpin = "Unpin"

    var opposite: Self { self == .pin ? .unpin : .pin }
    var confirmation: String { self == .pin ? "Pinned" : "Unpinned" }
}

@MainActor
protocol ClaudePinMenuSession: AnyObject {
    var isCurrent: Bool { get }
    func open() -> Bool
    func availableAction() -> ClaudePinMenuAction?
    func press(_ action: ClaudePinMenuAction) -> Bool
    func dismiss()
}

/// Claude's installed app exposes Pin/Unpin in the current session's title
/// menu. Plain P does nothing in that menu and can type into the composer.
/// Use only the exact current-session menu and verify its opposite state.
@MainActor
final class ClaudePinActionExecutor {
    private let inputAllowed: () -> Bool
    private let makeSession: () -> (any ClaudePinMenuSession)?
    private var task: Task<Void, Never>?
    private var generation = 0

    init(
        inputAllowed: @escaping () -> Bool,
        makeSession: (() -> (any ClaudePinMenuSession)?)? = nil
    ) {
        self.inputAllowed = inputAllowed
        self.makeSession = makeSession ?? { ClaudeAXPinMenuSession(inputAllowed: inputAllowed) }
    }

    @discardableResult
    func toggle(
        requestAllowed: @escaping () -> Bool = { true },
        feedback: @escaping (String, Bool) -> Void
    ) -> Bool {
        guard task == nil, inputAllowed(), requestAllowed() else { return false }
        generation &+= 1
        let request = generation
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == request { self.task = nil } }
            guard self.inputAllowed(), requestAllowed(),
                  let session = self.makeSession(), session.isCurrent else {
                feedback("Current Claude chat is unavailable", true)
                return
            }
            guard session.open() else {
                feedback("Could not read Claude pin state", true)
                return
            }
            defer { session.dismiss() }
            guard let action = await self.awaitAction(in: session, request: request, allowed: requestAllowed) else {
                if self.isAllowed(request: request, session: session, requestAllowed: requestAllowed) {
                    feedback("Could not read Claude pin state", true)
                }
                return
            }
            guard self.isAllowed(request: request, session: session, requestAllowed: requestAllowed),
                  session.press(action) else {
                feedback("Could not change Claude pin state", true)
                return
            }

            // A successful AXPress proves only dispatch. Reopen the same title
            // menu and read the opposite item before calling the change done.
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(50))
                guard self.isAllowed(request: request, session: session, requestAllowed: requestAllowed) else { return }
                if session.open() { break }
            }
            guard let after = await self.awaitAction(in: session, request: request, allowed: requestAllowed) else {
                if self.isAllowed(request: request, session: session, requestAllowed: requestAllowed) {
                    feedback("Claude pin change not confirmed", true)
                }
                return
            }
            feedback(after == action.opposite ? action.confirmation : "Claude pin change not confirmed",
                     after != action.opposite)
        }
        return true
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    private func isAllowed(
        request: Int,
        session: any ClaudePinMenuSession,
        requestAllowed: () -> Bool
    ) -> Bool {
        !Task.isCancelled && generation == request && inputAllowed()
            && requestAllowed() && session.isCurrent
    }

    private func awaitAction(
        in session: any ClaudePinMenuSession,
        request: Int,
        allowed requestAllowed: () -> Bool
    ) async -> ClaudePinMenuAction? {
        for _ in 0..<8 {
            guard isAllowed(request: request, session: session, requestAllowed: requestAllowed) else { return nil }
            if let action = session.availableAction() { return action }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }
}

@MainActor
private final class ClaudeAXPinMenuSession: ClaudePinMenuSession {
    private struct ElementIdentity: Hashable {
        let element: AXUIElement

        static func == (lhs: Self, rhs: Self) -> Bool {
            CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(CFHash(element))
        }
    }

    private let application: NSRunningApplication
    private let root: AXUIElement
    private let window: AXUIElement
    private let titleButton: AXUIElement
    private let opener: AXUIElement
    private let title: String
    private let titleButtonLabel: String
    private let inputAllowed: () -> Bool
    private let deadline = ProcessInfo.processInfo.systemUptime + 2.5

    init?(inputAllowed: @escaping () -> Bool) {
        guard inputAllowed(), AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: ClaudeMode.bundleIdentifier
              ).first(where: { $0.isActive }) else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.06)
        guard let window = Self.element(root, "AXFocusedWindow"),
              let header = Self.currentHeader(in: window) else { return nil }
        self.application = app
        self.root = root
        self.window = window
        self.titleButton = header.titleButton
        self.opener = header.opener
        self.title = header.title
        self.titleButtonLabel = header.titleButtonLabel
        self.inputAllowed = inputAllowed
    }

    var isCurrent: Bool {
        inputAllowed() && AXIsProcessTrusted() && application.isActive
            && ProcessInfo.processInfo.systemUptime < deadline
            && Self.element(root, "AXFocusedWindow").map { CFEqual($0, window) } == true
            && Self.label(titleButton) == titleButtonLabel
            && Self.label(opener) == "More options for " + title
            && Self.element(opener, "AXWindow").map { CFEqual($0, window) } == true
    }

    func open() -> Bool {
        guard isCurrent, menu == nil else { return false }
        return Self.press(opener)
    }

    func availableAction() -> ClaudePinMenuAction? {
        guard isCurrent, let menu else { return nil }
        let items = Self.children(menu).filter { Self.string($0, "AXRole") == "AXMenuItem" }
        let matching = items.compactMap { ClaudePinMenuAction(rawValue: Self.label($0)) }
        return matching.count == 1 ? matching[0] : nil
    }

    func press(_ action: ClaudePinMenuAction) -> Bool {
        guard availableAction() == action, let menu else { return false }
        let items = Self.children(menu).filter {
            Self.string($0, "AXRole") == "AXMenuItem" && Self.label($0) == action.rawValue
        }
        guard items.count == 1 else { return false }
        return Self.press(items[0])
    }

    func dismiss() {
        guard isCurrent, menu != nil else { return }
        _ = Self.press(opener)
    }

    private var menu: AXUIElement? {
        // AXPress on the header popup focuses its first menu item; a direct
        // click may focus the menu itself. In both cases, the exact title menu
        // is an ancestor of the focused element, not a header-group child.
        guard var current = Self.element(root, "AXFocusedUIElement") else { return nil }
        for _ in 0..<8 {
            if Self.string(current, "AXRole") == "AXMenu",
               Self.label(current) == "More options for " + title,
               Self.element(current, "AXWindow").map({ CFEqual($0, window) }) == true {
                return current
            }
            guard let parent = Self.element(current, "AXParent"),
                  !CFEqual(parent, current) else { return nil }
            current = parent
        }
        return nil
    }

    private static func currentHeader(
        in window: AXUIElement
    ) -> (titleButton: AXUIElement, opener: AXUIElement,
          title: String, titleButtonLabel: String)? {
        var queue = [window]
        var seen = Set<ElementIdentity>()
        var cursor = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 0.8
        while cursor < queue.count && cursor < 4_000
                && ProcessInfo.processInfo.systemUptime < deadline {
            let node = queue[cursor]
            cursor += 1
            guard seen.insert(ElementIdentity(element: node)).inserted else { continue }
            let children = children(node)
            let titleButtons = children.filter { node in
                guard string(node, "AXRole") == "AXButton" else { return false }
                let title = label(node)
                return title.hasSuffix(", rename session") || title.hasSuffix(", rename chat")
            }
            if titleButtons.count == 1, let titleButton = titleButtons.first {
                let buttonLabel = label(titleButton)
                let suffix = buttonLabel.hasSuffix(", rename session")
                    ? ", rename session" : ", rename chat"
                let title = String(buttonLabel.dropLast(suffix.count))
                let openers = children.filter {
                    string($0, "AXRole") == "AXPopUpButton"
                        && label($0) == "More options for " + title
                }
                if !title.isEmpty, openers.count == 1, let opener = openers.first {
                    return (titleButton, opener, title, buttonLabel)
                }
            }
            queue += children
        }
        return nil
    }

    private static func label(_ element: AXUIElement) -> String {
        for attribute in ["AXDescription", "AXTitle"] {
            let text = string(element, attribute)
            if !text.isEmpty { return text }
        }
        return ""
    }

    private static func press(_ element: AXUIElement) -> Bool {
        guard (value(element, "AXEnabled") as? Bool) != false,
              supports(element, kAXPressAction as String) else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private static func supports(_ element: AXUIElement, _ action: String) -> Bool {
        var names: CFArray?
        return AXUIElementCopyActionNames(element, &names) == .success
            && ((names as? [String]) ?? []).contains(action)
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success
            ? result : nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String {
        value(element, attribute) as? String ?? ""
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, "AXChildren") as? [AXUIElement] ?? []
    }
}
