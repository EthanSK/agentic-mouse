// Owns the wand's "Magnet" Left/Right commands through macOS desktop tiling.
// macOS owns the original size and drag restoration; this worker only composes
// native menu actions and remembers the last accepted half for monitor hops.
import AppKit
import ApplicationServices
import ScimitarKit

protocol WindowSnapAccess {
    /// The frontmost app's focused window and a stable identity for it.
    func focusedWindow(pid: pid_t) -> (target: WindowResizeTarget, key: WindowSnapKey)?
    func nativeWindowIsTiled(_ window: WindowSnapKey, permitted: () -> Bool) -> Bool
    func snapNatively(_ side: WindowSnapDirection, window: WindowSnapKey,
                      target: WindowResizeTarget, plan: WindowSnapPlan,
                      permitted: @escaping () -> Bool) -> CGRect?
}

/// Identity of an Accessibility window for the snap memory. CFEqual on the
/// element is stable for as long as the window exists.
struct WindowSnapKey: Hashable {
    let pid: pid_t
    let element: AXUIElement?
    /// Lets tests use plain identities without AX elements.
    let testID: Int

    init(pid: pid_t, element: AXUIElement) {
        self.pid = pid
        self.element = element
        testID = 0
    }

    init(testID: Int) {
        pid = 0
        element = nil
        self.testID = testID
    }

    static func == (lhs: WindowSnapKey, rhs: WindowSnapKey) -> Bool {
        guard lhs.pid == rhs.pid, lhs.testID == rhs.testID else { return false }
        switch (lhs.element, rhs.element) {
        case let (a?, b?): return CFEqual(a, b)
        case (nil, nil): return true
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(testID)
        if let element { hasher.combine(CFHash(element)) }
    }
}

final class WindowSnapController {
    enum Outcome: Equatable {
        case moved(CGRect)
        case traversed(CGRect)
        /// Already on that half of the outermost display.
        case unchanged
        case noWindow
        case failed
        case cancelled
    }

    private let access: WindowSnapAccess
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var generations: [MouseSource?: UUID] = [:]
    private var globalGeneration = UUID()
    private let memoryLimit = 32
    private var memory: [WindowSnapKey: WindowSnapMemory] = [:] // Worker-owned.
    private var memoryOrder: [WindowSnapKey] = []                // Worker-owned.
    /// Called on the worker after each snap (logging / HUD feedback).
    var onOutcome: ((WindowSnapDirection, Outcome) -> Void)?

    static let shared = WindowSnapController()

    init(access: WindowSnapAccess = AccessibilityWindowSnapAccess(),
         queue: DispatchQueue = DispatchQueue(label: "agentic-mouse.window-snap", qos: .userInitiated)) {
        self.access = access
        self.queue = queue
    }

    /// Main-thread entry point used by `MagnetWindowActionExecutor`. Reads
    /// the display layout and frontmost app on the main thread (NSScreen and
    /// NSWorkspace are AppKit state), then does the Accessibility work on the
    /// worker. Returns false only when there is nothing to act on.
    @MainActor
    func snapFrontmostWindow(_ side: WindowSnapDirection, source: MouseSource? = nil,
                            inputAllowed: @escaping @MainActor () -> Bool = { true }) -> Bool {
        guard inputAllowed(), let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        let displays = Self.currentDisplays()
        guard !displays.isEmpty else { return false }
        enqueue(side, pid: pid, displays: displays, source: source) {
            // AX remains off-main, but permission and AppKit focus are read on
            // their owner. A queued command cannot act after lock or app change.
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    inputAllowed() && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                }
            }
        }
        return true
    }

    func enqueue(_ side: WindowSnapDirection, pid: pid_t, displays: [WindowSnapDisplay],
                 source: MouseSource?, inputAllowed: @escaping () -> Bool) {
        lock.lock()
        let generation = generations[source] ?? UUID()
        generations[source] = generation
        let global = globalGeneration
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            let permitted = { self.isGloballyCurrent(global) && inputAllowed() }
            guard self.isCurrent(source, generation), permitted() else { return }
            // Release cancels queued detents, but finishes a started native
            // transaction. Lock, focus loss and teardown stop each next action.
            let outcome = self.snap(side, pid: pid, displays: displays, source: source,
                                    permitted: permitted)
            if self.isCurrent(source, generation) { self.onOutcome?(side, outcome) }
        }
    }

    func cancel(source: MouseSource) {
        lock.lock(); generations[source] = nil; lock.unlock()
    }

    func cancelAll() {
        lock.lock(); generations.removeAll(); globalGeneration = UUID(); lock.unlock()
        queue.async { [weak self] in
            self?.memory.removeAll()
            self?.memoryOrder.removeAll()
        }
    }

    private func isGloballyCurrent(_ generation: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return globalGeneration == generation
    }

    private func isCurrent(_ source: MouseSource?, _ generation: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generations[source] == generation
    }

    /// Synchronous core (worker thread, or directly in tests).
    func snap(_ side: WindowSnapDirection, pid: pid_t, displays: [WindowSnapDisplay],
              source: MouseSource? = nil, permitted: @escaping () -> Bool = { true }) -> Outcome {
        guard permitted() else { return .cancelled }
        guard let (target, key) = access.focusedWindow(pid: pid) else { return .noWindow }
        guard let current = target.frame() else { return .failed }
        var previous = memory[key]
        // AX can report an animation's near-final frame. Native margins can
        // also differ from an ideal half. Only repair that hop recognition
        // while macOS confirms the window is still tiled; a normal manual
        // move/resize must retain the original strict geometry rules.
        if let remembered = previous, remembered.direction == side,
           let display = WindowSnapGeometry.display(for: current, in: displays),
           remembered.displayID == display.id,
           !WindowSnapGeometry.approximatelyEqual(current, remembered.acceptedFrame, tolerance: 2),
           !WindowSnapGeometry.approximatelyEqual(current, WindowSnapGeometry.half(side, of: display),
               tolerance: WindowSnapGeometry.matchTolerance),
           WindowSnapGeometry.approximatelyEqual(current, WindowSnapGeometry.half(side, of: display), tolerance: 32),
           permitted(), access.nativeWindowIsTiled(key, permitted: permitted) {
            previous = WindowSnapMemory(direction: side, displayID: display.id, acceptedFrame: current)
        }
        guard let plan = WindowSnapGeometry.plan(side, window: current, displays: displays, memory: previous) else {
            return .unchanged
        }

        guard permitted() else { return .cancelled }
        let accepted = access.snapNatively(plan.side, window: key, target: target,
                                          plan: plan, permitted: permitted)
        guard let accepted else { return permitted() ? .failed : .cancelled }
        guard permitted() else { return .cancelled }
        remember(key, WindowSnapMemory(direction: plan.side, displayID: plan.display.id, acceptedFrame: accepted))
        // "Pre-magnet size" belongs to macOS now. Do not recreate the removed
        // WindowSnapDragRestorer's original-size cache or global mouse listener.
        return plan.traversedDisplay ? .traversed(accepted) : .moved(accepted)
    }

    private func remember(_ key: WindowSnapKey, _ entry: WindowSnapMemory) {
        memory[key] = entry
        memoryOrder.removeAll { $0 == key }
        memoryOrder.append(key)
        if memoryOrder.count > memoryLimit { memory[memoryOrder.removeFirst()] = nil }
    }

    @MainActor
    static func currentDisplays() -> [WindowSnapDisplay] {
        let screens = NSScreen.screens
        let primaryHeight = screens.first { $0.frame.origin == .zero }?.frame.height ?? screens.first?.frame.height ?? 0
        return screens.map { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
                ?? screen.localizedName
            return WindowSnapDisplay(
                id: id,
                frame: WindowSnapDisplay.fromCocoa(screen.frame, primaryHeight: primaryHeight),
                visibleFrame: WindowSnapDisplay.fromCocoa(screen.visibleFrame, primaryHeight: primaryHeight),
                name: screen.localizedName)
        }
    }
}

struct AccessibilityWindowSnapAccess: WindowSnapAccess {
    func nativeWindowIsTiled(_ key: WindowSnapKey, permitted: () -> Bool) -> Bool {
        guard permitted(), focusedWindowMatches(key),
              let menu = menuItems(pid: key.pid, open: true) else { return false }
        defer { AXUIElementPerformAction(menu.header, kAXCancelAction as CFString) }
        return permitted() && NativeWindowSnapMenu.index(of: .restore, in: menu.entries.map(\.item)) != nil
    }

    func focusedWindow(pid: pid_t) -> (target: WindowResizeTarget, key: WindowSnapKey)? {
        guard AXIsProcessTrusted(), pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let raw = AccessibilityWindowResizeAccess.attribute(application, attribute),
               CFGetTypeID(raw) == AXUIElementGetTypeID() {
                let window = unsafeBitCast(raw, to: AXUIElement.self)
                AXUIElementSetMessagingTimeout(window, 0.15)
                return (AccessibilityWindowResizeTarget(window: window, application: application),
                        WindowSnapKey(pid: pid, element: window))
            }
        }
        return nil
    }

    func snapNatively(_ side: WindowSnapDirection, window key: WindowSnapKey,
                      target: WindowResizeTarget, plan: WindowSnapPlan,
                      permitted: @escaping () -> Bool) -> CGRect? {
        guard #available(macOS 15, *), let element = key.element,
              !plan.traversedDisplay || plan.display.name != nil,
              focusedWindowMatches(key), permitted(),
              let initial = menuItems(pid: key.pid, open: true)
        else { return nil }
        var currentMenu = initial
        // AXPress on a closed, unvalidated menu can return success without
        // invoking its disabled item. Validate the native Window menu first;
        // cancel that exact menu on every exit, including a failed action.
        defer { AXUIElementPerformAction(currentMenu.header, kAXCancelAction as CFString) }
        guard let commands = NativeWindowSnapMenu.commands(side: side,
            movingTo: plan.traversedDisplay ? plan.display.name : nil, items: initial.entries.map(\.item))
        else { return nil }

        // Native Move to Display clears tiling state. Untile first so its
        // original size, rather than the old half size, seeds the new tile.
        // These are public AXPress operations on observed native menu items,
        // never calls to AppKit's private selector implementation.
        for (offset, command) in commands.enumerated() {
            guard permitted(), focusedWindowMatches(key) else { return nil }
            if offset > 0 {
                guard let refreshed = menuItems(pid: key.pid, open: true) else { return nil }
                currentMenu = refreshed
            }
            let items = currentMenu.entries
            guard let index = NativeWindowSnapMenu.index(of: command, in: items.map(\.item)),
                  let before = target.frame() else { return nil }
            let deadline = ProcessInfo.processInfo.systemUptime + 0.75
            let observer = NativeWindowSnapChangeObserver(pid: key.pid, window: element)
            guard permitted(), focusedWindowMatches(key),
                  AXUIElementPerformAction(items[index].element, kAXPressAction as CFString) == .success
            else { return nil }
            // Wait for actual window change notifications, with no settling
            // sleep or permanent observer. Most native actions read back at once.
            while permitted(), focusedWindowMatches(key) {
                guard let accepted = target.frame() else { return nil }
                let complete: Bool
                switch command {
                case .restore:
                    complete = accepted != before || !restoreEnabled(pid: key.pid)
                case .move:
                    complete = plan.display.frame.contains(CGPoint(x: accepted.midX, y: accepted.midY))
                case .tile:
                    // Native margins and one-point AppKit rounding belong to
                    // macOS. Never "correct" them with AX geometry writes.
                    let exact = WindowSnapGeometry.approximatelyEqual(accepted, plan.frame, tolerance: 2)
                    complete = exact || (observer.didChange &&
                        WindowSnapGeometry.approximatelyEqual(accepted, plan.frame, tolerance: 32))
                }
                if complete { break }
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0, observer.isObserving else { return nil }
                CFRunLoopRunInMode(.defaultMode, remaining, true)
            }
            guard permitted(), focusedWindowMatches(key) else { return nil }
        }
        return permitted() ? target.frame() : nil
    }

    private func focusedWindowMatches(_ key: WindowSnapKey) -> Bool {
        guard let expected = key.element,
              let (_, current) = focusedWindow(pid: key.pid),
              let actual = current.element, CFEqual(expected, actual) else { return false }
        return AccessibilityWindowResizeAccess.attribute(expected, "AXFullScreen") as? Bool != true
    }

    private func restoreEnabled(pid: pid_t) -> Bool {
        guard let items = menuItems(pid: pid) else { return false }
        return NativeWindowSnapMenu.index(of: .restore, in: items.entries.map(\.item)) != nil
    }

    private struct MenuEntry {
        let item: NativeWindowSnapMenu.Item
        let element: AXUIElement
    }
    private struct MenuSnapshot {
        let header: AXUIElement
        let entries: [MenuEntry]
    }

    private func menuItems(pid: pid_t, open: Bool = false) -> MenuSnapshot? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let raw = AccessibilityWindowResizeAccess.attribute(application, kAXMenuBarAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let bar = unsafeBitCast(raw, to: AXUIElement.self)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.6
        var remainingNodes = 512
        func children(_ item: AXUIElement) -> [AXUIElement] {
            AccessibilityWindowResizeAccess.attribute(item, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        func walk(_ item: AXUIElement, depth: Int, into entries: inout [MenuEntry]) {
            guard depth < 7, remainingNodes > 0,
                  ProcessInfo.processInfo.systemUptime < deadline else { return }
            remainingNodes -= 1
            AXUIElementSetMessagingTimeout(item, 0.15)
            let identifier = AccessibilityWindowResizeAccess.attribute(item, kAXIdentifierAttribute) as? String
            if let identifier, NativeWindowSnapMenu.identifiers.contains(identifier) {
                entries.append(MenuEntry(item: .init(
                    identifier: identifier,
                    title: AccessibilityWindowResizeAccess.attribute(item, kAXTitleAttribute) as? String ?? "",
                    enabled: AccessibilityWindowResizeAccess.attribute(item, kAXEnabledAttribute) as? Bool == true),
                    element: item))
            }
            for child in children(item) { walk(child, depth: depth + 1, into: &entries) }
        }
        // Window is near the end in standard AppKit menus. Discover by native
        // action identity, not an English "Window"/"Left" label or key binding.
        for header in children(bar).reversed() {
            var entries: [MenuEntry] = []
            walk(header, depth: 0, into: &entries)
            if entries.contains(where: { $0.item.identifier == "_zoomLeft:" }) {
                if open {
                    guard AXUIElementPerformAction(header, kAXPressAction as CFString) == .success else {
                        AXUIElementPerformAction(header, kAXCancelAction as CFString)
                        return nil
                    }
                    entries.removeAll()
                    remainingNodes = 512
                    walk(header, depth: 0, into: &entries)
                }
                return MenuSnapshot(header: header, entries: entries)
            }
        }
        return nil
    }

}


/// Opaque AX identifiers observed in the native desktop menu on macOS 26/27.
/// Reject changed/unavailable menus rather than guessing a translated label,
/// synthesizing a shortcut, or using Full-Screen Tile's _tile* actions.
enum NativeWindowSnapMenu {
    enum Command: Equatable {
        case tile(WindowSnapDirection)
        case restore
        case move(String)

        var identifier: String {
            switch self {
            case .tile(.left): return "_zoomLeft:"
            case .tile(.right): return "_zoomRight:"
            case .restore: return "_zoomUntile:"
            case .move: return "_moveToDisplay:"
            }
        }
    }
    struct Item {
        let identifier: String
        let title: String
        let enabled: Bool
    }
    static let identifiers: Set<String> = ["_zoomLeft:", "_zoomRight:", "_zoomUntile:", "_moveToDisplay:"]

    static func index(of command: Command, in items: [Item]) -> Int? {
        let matches = items.indices.filter { index in
            let item = items[index]
            guard item.identifier == command.identifier, item.enabled else { return false }
            if case .move(let name) = command { return !name.isEmpty && item.title.hasSuffix(name) }
            return true
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func commands(side: WindowSnapDirection, movingTo name: String?, items: [Item]) -> [Command]? {
        guard index(of: .tile(side), in: items) != nil else { return nil }
        guard let name else { return [.tile(side)] }
        guard index(of: .move(name), in: items) != nil else { return nil }
        var result: [Command] = []
        if index(of: .restore, in: items) != nil { result.append(.restore) }
        result += [.move(name), .tile(side)]
        return result
    }
}

/// Scoped only to an in-flight native command. No input tap, drag tracking,
/// polling timer, original-size cache or idle listener survives the operation.
private final class NativeWindowSnapChangeObserver {
    private var observer: AXObserver?
    private let runLoop = CFRunLoopGetCurrent()
    private(set) var isObserving = false
    private(set) var didChange = false

    init(pid: pid_t, window: AXUIElement) {
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, _, name, context in
            guard let context, name as String == kAXMovedNotification || name as String == kAXResizedNotification else { return }
            Unmanaged<NativeWindowSnapChangeObserver>.fromOpaque(context).takeUnretainedValue().didChange = true
        }, &created) == .success, let created else { return }
        observer = created
        var attached = false
        for name in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
            if AXObserverAddNotification(created, window, name as CFString,
                Unmanaged.passUnretained(self).toOpaque()) == .success { attached = true }
        }
        isObserving = attached
        if attached { CFRunLoopAddSource(runLoop, AXObserverGetRunLoopSource(created), .defaultMode) }
    }
    deinit {
        if let observer, isObserving {
            CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }
}
