import AppKit
import ApplicationServices
import ScimitarKit

/// Built-in Left/Right window snapping for the Magic Wand's "Magnet wedge"
/// and the mice's Magnet + Wheel card (Ethan's term "Magnet" = these two
/// actions). Added 2026-10-31 at Ethan's request to do it "via the inbuilt
/// thing" inside Agentic Mouse while the third-party Magnet app stays
/// installed and running for his keyboard shortcuts.
///
/// Established pattern: this reuses `AccessibilityWindowResizeTarget` (the
/// hovered-window resize feature's AX wrapper: frame/size/position writes,
/// AXEnhancedUserInterface suppression, 150 ms messaging timeout) and, like
/// `WindowResizeController`, runs Accessibility on one serial worker — never
/// inside the wheel tap or on the main thread.
///
/// Why built-in instead of synthesizing Magnet's ⌃⌥←/→: Magnet animates each
/// placement and decides the next press from the window's committed frame,
/// so quick presses across monitors could race and land oddly. Here every
/// placement is written synchronously, read back, corrected onto the target
/// display, and remembered, before the next queued press runs.
protocol WindowSnapAccess {
    /// The frontmost app's focused window and a stable identity for it.
    func focusedWindow(pid: pid_t) -> (target: WindowResizeTarget, key: WindowSnapKey)?
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
    private let restorer: WindowSnapDragRestorer
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
         queue: DispatchQueue? = nil,
         restorer: WindowSnapDragRestorer = .shared) {
        self.access = access
        self.queue = queue ?? restorer.queue
        self.restorer = restorer
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
        guard !displays.isEmpty, let observation = restorer.prepareForSnap() else { return false }
        enqueue(side, pid: pid, displays: displays, source: source, observation: observation) {
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
                 source: MouseSource?, observation: UUID? = nil, inputAllowed: @escaping () -> Bool) {
        restorer.snapRequested()
        lock.lock()
        let generation = generations[source] ?? UUID()
        generations[source] = generation
        let global = globalGeneration
        lock.unlock()
        let restorer = self.restorer
        queue.async { [weak self] in
            defer { if let observation { restorer.finishedSnap(observation) } }
            guard let self else { return }
            let permitted = { self.isGloballyCurrent(global) && inputAllowed() }
            guard self.isCurrent(source, generation), permitted() else { return }
            // Match WindowResizeController: release cancels queued detents, but
            // finishes an already-started frame transaction. Lock, focus change
            // and global teardown still stop before each subsequent AX write.
            let outcome = self.snap(side, pid: pid, displays: displays, source: source,
                                    permitted: permitted, restorationAllowed: inputAllowed)
            if self.isCurrent(source, generation) { self.onOutcome?(side, outcome) }
        }
    }

    func cancel(source: MouseSource) {
        // Mode release cancels queued snaps. The independently grabbed window
        // owns restoration; a late mode-clear must not cancel its new drag.
        lock.lock(); generations[source] = nil; lock.unlock()
    }

    func cancelAll() {
        restorer.cancelAll()
        lock.lock(); generations.removeAll(); globalGeneration = UUID(); lock.unlock()
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
              source: MouseSource? = nil, permitted: @escaping () -> Bool = { true },
              restorationAllowed: (() -> Bool)? = nil) -> Outcome {
        guard permitted() else { return .cancelled }
        guard let (target, key) = access.focusedWindow(pid: pid) else { return .noWindow }
        guard let current = target.frame() else { return .failed }
        guard let plan = WindowSnapGeometry.plan(side, window: current, displays: displays, memory: memory[key]) else {
            return .unchanged
        }

        guard permitted() else { return .cancelled }
        let accepted = target.withoutAnimation { () -> CGRect? in
            func needsResize(_ frame: CGRect) -> Bool {
                abs(frame.width - plan.frame.width) > 1 || abs(frame.height - plan.frame.height) > 1
            }
            // Move between equal-sized halves without resizing. Retry size
            // after moving ONLY when the app actually clamped the first write
            // at its old display/position. Accepted sizes need no repeat.
            if needsResize(current) {
                guard permitted(), target.setSize(plan.frame.size) else { return nil }
            }
            guard permitted(), target.setPosition(plan.frame.origin),
                  let placed = target.frame() else { return nil }
            let frame: CGRect
            if needsResize(placed) {
                guard permitted(), target.setSize(plan.frame.size),
                      let resized = target.frame() else { return nil }
                frame = resized
            } else {
                frame = placed
            }
            var acceptedFrame = frame
            // If the app kept a different size (minimum width etc.), slide
            // the window back flush to its side and fully onto the display.
            if let fixed = WindowSnapGeometry.correction(accepted: frame, plan: plan) {
                guard permitted(), target.setPosition(fixed.origin),
                      let corrected = target.frame(),
                      WindowSnapGeometry.approximatelyEqual(corrected, fixed, tolerance: 1) else { return nil }
                acceptedFrame = corrected
            }
            return acceptedFrame
        }
        guard let accepted else { return permitted() ? .failed : .cancelled }
        guard permitted() else { return .cancelled }
        remember(key, WindowSnapMemory(direction: plan.side, displayID: plan.display.id, acceptedFrame: accepted))
        // Restoration belongs to a later physical drag. Keep its live session/
        // focus gate, not this one snap request's permanently invalidated token.
        restorer.didSnap(key: key, target: target, preSnap: current, accepted: accepted,
                         inputAllowed: restorationAllowed ?? permitted)
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
                visibleFrame: WindowSnapDisplay.fromCocoa(screen.visibleFrame, primaryHeight: primaryHeight))
        }
    }
}

struct AccessibilityWindowSnapAccess: WindowSnapAccess {
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
}
