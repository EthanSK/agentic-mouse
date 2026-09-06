import AppKit
import ApplicationServices
import ScimitarKit

/// A directional pin gesture never sends the toggle shortcut. The current
/// chat's own menu offers exactly one explicit state change; its opposite
/// means the requested state already holds. Missing/ambiguous menus fail closed.
@MainActor
protocol CodexPinMenuSession: AnyObject {
    var isCurrent: Bool { get }
    func open() -> Bool
    func readItems() -> [String]?
    func press(_ label: String) -> Bool
    func dismiss()
}

@MainActor
final class CodexPinActionExecutor {
    enum Decision: Equatable {
        case press(String)
        case already
        case unavailable
    }

    static func decision(_ action: CodexPinAction, labels: [String]) -> Decision {
        let pin = labels.filter { $0 == "Pin" || $0 == "Pin chat" }
        let unpin = labels.filter { $0 == "Unpin" || $0 == "Unpin chat" }
        guard pin.count + unpin.count == 1 else { return .unavailable }
        let desired = action == .pin ? pin : unpin
        return desired.first.map(Decision.press) ?? .already
    }

    private let makeSession: () -> (any CodexPinMenuSession)?
    private let inputAllowed: () -> Bool
    private var task: Task<Void, Never>?
    private var generation = 0

    init(
        inputAllowed: @escaping () -> Bool,
        makeSession: (() -> (any CodexPinMenuSession)?)? = nil
    ) {
        self.inputAllowed = inputAllowed
        self.makeSession = makeSession ?? { CodexAXPinMenuSession(inputAllowed: inputAllowed) }
    }

    func perform(
        _ action: CodexPinAction,
        requestAllowed: @escaping () -> Bool = { true },
        feedback: @escaping (String, Bool) -> Void
    ) {
        guard task == nil, inputAllowed(), requestAllowed() else { return }
        generation &+= 1
        let request = generation
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == request { self.task = nil } }
            guard self.inputAllowed(), requestAllowed(), !Task.isCancelled,
                  let session = self.makeSession(), session.isCurrent else {
                feedback("Main Codex window is not active", true)
                return
            }
            guard session.open() else {
                feedback("Could not read the pin state", true)
                return
            }
            defer { if session.isCurrent { session.dismiss() } }
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, self.generation == request,
                      self.inputAllowed(), requestAllowed(), session.isCurrent else { return }
                guard let labels = session.readItems() else { continue }
                switch Self.decision(action, labels: labels) {
                case .already:
                    feedback(action == .pin ? "Already pinned" : "Already unpinned", false)
                    return
                case .press(let label):
                    guard session.isCurrent, self.inputAllowed(), requestAllowed(), session.press(label) else {
                        feedback("Could not read the pin state", true)
                        return
                    }
                    feedback(action == .pin
                        ? "Pin requested. Check the window to confirm."
                        : "Unpin requested. Check the window to confirm.", false)
                    return
                case .unavailable:
                    feedback("Could not read the pin state", true)
                    return
                }
            }
            feedback("Could not read the pin state", true)
        }
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
    }
}

/// Uses only advertised Accessibility controls in the foreground Codex window.
/// It never activates Codex, edits its state files, searches conversation text,
/// guesses a sidebar title, or sends a blind pin-toggle shortcut.
@MainActor
private final class CodexAXPinMenuSession: CodexPinMenuSession {
    private let application: NSRunningApplication
    private let root: AXUIElement
    private let window: AXUIElement
    private let opener: AXUIElement
    private let titleButton: AXUIElement
    private let title: String
    private let inputAllowed: () -> Bool
    private let deadline = ProcessInfo.processInfo.systemUptime + 1.5
    private var items: [(String, AXUIElement)] = []
    private var ownedMenu: AXUIElement?

    init?(inputAllowed: @escaping () -> Bool) {
        guard inputAllowed(), AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: CodexMode.bundleIdentifier
              ).first(where: { $0.isActive }) else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.04)
        guard let window = Self.element(root, "AXFocusedWindow") else { return nil }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.45
        guard let nodes = Self.nodes(window, deadline: deadline),
              !nodes.contains(where: { Self.string($0, "AXRole") == "AXMenu" }) else { return nil }
        let openers = nodes.filter {
            Self.string($0, "AXRole") == "AXPopUpButton"
                && Self.string($0, "AXDescription") == "Chat actions"
                && Self.isMainHeaderControl($0)
        }
        guard openers.count == 1, let opener = openers.first,
              Self.value(opener, "AXExpanded") as? Bool == false,
              let parent = Self.element(opener, "AXParent"),
              let titleGroup = Self.children(parent).first(where: { Self.string($0, "AXRole") == "AXGroup" }),
              let titleNodes = Self.nodes(titleGroup, deadline: deadline, limit: 50) else { return nil }
        let titleButtons = titleNodes.filter {
            Self.string($0, "AXRole") == "AXButton" && !Self.string($0, "AXTitle").isEmpty
        }
        guard titleButtons.count == 1, let titleButton = titleButtons.first else { return nil }
        self.application = app
        self.root = root
        self.window = window
        self.opener = opener
        self.titleButton = titleButton
        self.title = Self.string(titleButton, "AXTitle")
        self.inputAllowed = inputAllowed
    }

    var isCurrent: Bool {
        inputAllowed() && AXIsProcessTrusted() && application.isActive
            && ProcessInfo.processInfo.systemUptime < deadline
            && Self.element(root, "AXFocusedWindow").map { CFEqual($0, window) } == true
            && Self.string(titleButton, "AXTitle") == title
            && Self.element(opener, "AXWindow").map { CFEqual($0, window) } == true
    }

    func open() -> Bool {
        guard isCurrent, Self.value(opener, "AXExpanded") as? Bool == false else { return false }
        return Self.press(opener)
    }

    func readItems() -> [String]? {
        guard isCurrent, Self.value(opener, "AXExpanded") as? Bool == true,
              let nodes = Self.nodes(window, deadline: min(deadline, ProcessInfo.processInfo.systemUptime + 0.25)) else { return nil }
        let menus = nodes.filter { Self.string($0, "AXRole") == "AXMenu" }
        guard menus.count == 1, let menu = menus.first,
              let menuNodes = Self.nodes(menu, deadline: deadline, limit: 120) else { return nil }
        if let ownedMenu, !CFEqual(ownedMenu, menu) { return nil }
        ownedMenu = menu
        items = menuNodes.compactMap { node in
            guard Self.string(node, "AXRole") == "AXMenuItem" else { return nil }
            let title = Self.string(node, "AXTitle")
            let label = title.isEmpty ? Self.string(node, "AXDescription") : title
            return (label, node)
        }
        return items.map(\.0)
    }

    func press(_ label: String) -> Bool {
        // Re-read the same menu immediately before pressing. A rename, route
        // change, another popup, vanished control or state change cancels it.
        guard isCurrent, let labels = readItems(), labels.filter({ $0 == label }).count == 1,
              let item = items.first(where: { $0.0 == label })?.1 else { return false }
        return Self.press(item)
    }

    func dismiss() {
        guard isCurrent, let ownedMenu,
              Self.value(opener, "AXExpanded") as? Bool == true,
              let nodes = Self.nodes(window, deadline: deadline),
              nodes.contains(where: { CFEqual($0, ownedMenu) }) else { return }
        // Toggle only the menu this gesture opened, never an unrelated popup.
        _ = Self.press(opener)
    }

    private static func isMainHeaderControl(_ control: AXUIElement) -> Bool {
        var parent = element(control, "AXParent")
        for _ in 0..<4 {
            guard let node = parent else { return false }
            let classes = Set(value(node, "AXDOMClassList") as? [String] ?? [])
            if classes.isSuperset(of: ["fixed", "h-toolbar", "top-0"]) { return true }
            parent = element(node, "AXParent")
        }
        return false
    }

    private static func press(_ element: AXUIElement) -> Bool {
        guard value(element, "AXEnabled") as? Bool != false else { return false }
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success,
              (actions as? [String] ?? []).contains(kAXPressAction as String) else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String {
        value(element, attribute) as? String ?? ""
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, "AXChildren") as? [AXUIElement] ?? []
    }

    private static func nodes(_ root: AXUIElement, deadline: TimeInterval, limit: Int = 2200) -> [AXUIElement]? {
        var queue = [(root, 0)]
        var output: [AXUIElement] = []
        var cursor = 0
        while cursor < queue.count {
            guard cursor < limit, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            let (node, depth) = queue[cursor]
            cursor += 1
            let role = string(node, "AXRole")
            if role == "AXWebArea" {
                let url = value(node, "AXURL") as? URL
                guard url?.scheme == "app" else { continue }
            }
            output.append(node)
            // The header and menu are outside the conversation's deep text tree.
            if depth < 25 { queue += children(node).map { ($0, depth + 1) } }
        }
        return output
    }
}
