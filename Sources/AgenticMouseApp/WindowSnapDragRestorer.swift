import AppKit
import ApplicationServices
import ScimitarKit

/// WindowServer identity captured at mouse-down. Unlike a later AX hit test,
/// this still names the grabbed window after a quick drag has already ended.
struct WindowSnapPointerWindow {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect
}

/// Ethan's "pre-magnet" restore: retain the first size and tie restoration to
/// the actual down/drag/up transaction. AX notifications can arrive after up;
/// sampling today's button state then used to discard yesterday's drag.
/// Established pattern: all AX reads/writes stay on the existing serial worker.
/// Capture now runs before mouse dispatch on its own sleeping run loop, so
/// busy HUD work cannot turn mouse-down into a post-drag window lookup.
final class WindowSnapDragRestorer {
    static let shared = WindowSnapDragRestorer()
    let queue: DispatchQueue
    private struct Entry {
        let token: UUID
        let target: WindowResizeTarget
        let original: CGRect
        let accepted: CGRect
        let windowID: CGWindowID?
        let inputAllowed: () -> Bool
    }
    private struct Drag {
        let id = UUID()
        let key: WindowSnapKey
        let entryToken: UUID
        let windowID: CGWindowID
        let startFrame: CGRect
        let downPoint: CGPoint
        let downTime: TimeInterval
        var point: CGPoint
        var moved = false
        var released = false
        var lastInputTime: TimeInterval
    }
    private let lock = NSLock()
    private var entries: [WindowSnapKey: Entry] = [:]
    private var order: [WindowSnapKey] = []
    private var pending: [WindowSnapKey: UUID] = [:]
    private var needsEvaluation: Set<WindowSnapKey> = []
    private var drag: Drag?
    private var epoch = UUID()
    private var observers: [pid_t: AXObserver] = [:] // Main-thread owned.
    private var observed: [WindowSnapKey: UUID] = [:] // Main-thread owned.
    private let mouseObservation = WindowSnapMouseObservation() // Main-thread owned.
    private var preparingSnaps: Set<UUID> = [] // Lock protected.
    private let windows: () -> [WindowSnapPointerWindow]
    private let now: () -> TimeInterval
    var onRestore: ((CGRect) -> Void)? // Worker callback; only verified restores.

    init(queue: DispatchQueue = DispatchQueue(label: "agentic-mouse.window-snap", qos: .userInitiated),
         windows: @escaping () -> [WindowSnapPointerWindow] = WindowSnapDragRestorer.visibleWindows,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.queue = queue
        self.windows = windows
        self.now = now
    }

    /// A new snap invalidates queued restoration, but keeps the first size.
    func snapRequested() {
        lock.lock(); epoch = UUID(); drag = nil; lock.unlock()
    }

    /// Lock/sleep cancels the interaction, not historical window dimensions.
    /// The entry's LIVE input gate is checked again after unlock. Keeping the
    /// old snap-request generation here made restoration permanently unusable.
    func cancelAll() {
        lock.lock(); epoch = UUID(); drag = nil; pending.removeAll(); needsEvaluation.removeAll(); lock.unlock()
    }

    func didSnap(key: WindowSnapKey, target: WindowResizeTarget, preSnap: CGRect, accepted: CGRect,
                 inputAllowed: @escaping () -> Bool = { true }) {
        let token = UUID()
        let matches = windows().filter {
            $0.pid == key.pid && WindowSnapGeometry.approximatelyEqual($0.frame, accepted, tolerance: 3)
        }
        lock.lock()
        let previous = entries[key]
        let original = WindowSnapDragRestore.originalForSnap(preSnap: preSnap,
            previousOriginal: previous?.original, previousAccepted: previous?.accepted)
        // Remember the size before our FIRST resize, not a position-only snap
        // of an already tiled window. Otherwise that half-size can poison every
        // later cycle, including a window first placed by Magnet itself.
        guard previous != nil || WindowSnapDragRestore.sizeChanged(current: original, accepted: accepted) else {
            lock.unlock()
            return
        }
        entries[key] = Entry(token: token, target: target, original: original, accepted: accepted,
                             windowID: matches.count == 1 ? matches[0].id : previous?.windowID,
                             inputAllowed: inputAllowed)
        order.removeAll { $0 == key }; order.append(key)
        if order.count > 32 { entries[order.removeFirst()] = nil }
        pending[key] = nil
        needsEvaluation.remove(key)
        if drag?.key == key { drag = nil }
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pruneObservers()
            if self.isEntry(key, token), let element = key.element {
                _ = self.startMouseObservation()
                self.observe(key, element: element, token: token)
            }
        }
    }

    private func isEntry(_ key: WindowSnapKey, _ token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return entries[key]?.token == token
    }

    private func forget(_ key: WindowSnapKey, token: UUID) {
        lock.lock()
        if entries[key]?.token == token {
            entries[key] = nil; order.removeAll { $0 == key }; pending[key] = nil
            needsEvaluation.remove(key)
            if drag?.key == key { drag = nil }
        }
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.pruneObservers() }
    }

    /// Same entry point for the native listener and deterministic tests.
    /// Mouse-up retains an already observed drag until its final AX move;
    /// the next unrelated input supersedes it. No timer or extra delay is used.
    func mouseEvent(_ type: CGEventType, point: CGPoint, time: TimeInterval? = nil) {
        let inputTime = time ?? now()
        if type == .leftMouseDown {
            lock.lock(); let hasEntries = !entries.isEmpty; lock.unlock()
            guard hasEntries else { return }
            let hit = windows().first { $0.frame.contains(point) }
            lock.lock()
            drag = nil
            if let hit {
                let matches = entries.filter { key, entry in
                    key.pid == hit.pid && (entry.windowID == hit.id ||
                        (entry.windowID == nil && WindowSnapGeometry.approximatelyEqual(entry.accepted, hit.frame, tolerance: 3)))
                }
                if matches.count == 1, let (key, entry) = matches.first {
                    drag = Drag(key: key, entryToken: entry.token, windowID: hit.id, startFrame: hit.frame,
                                downPoint: point, downTime: inputTime, point: point, lastInputTime: inputTime)
                }
            }
            lock.unlock()
            return
        }
        lock.lock()
        guard var active = drag else { lock.unlock(); return }
        // AppKit can deliver an earlier drag/up after the capture thread has
        // already seen a newer mouse-down. Never attach it to the new grab.
        guard inputTime >= active.downTime || type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
        else { lock.unlock(); return }
        switch type {
        case .leftMouseDragged, .leftMouseUp:
            active.point = point
            active.moved = active.moved || abs(point.x - active.downPoint.x) > 3 || abs(point.y - active.downPoint.y) > 3
            active.released = type == .leftMouseUp
            active.lastInputTime = inputTime
            drag = active
        case .keyDown, .rightMouseDown, .otherMouseDown, .tapDisabledByTimeout, .tapDisabledByUserInput:
            drag = nil
            lock.unlock(); return
        default:
            lock.unlock(); return
        }
        lock.unlock()
        if active.moved { changed(active.key) }
    }

    /// AX move/resize is supporting evidence, never proof of a fresh drag.
    /// Transient failed reads, settling sizes and programmatic moves keep the
    /// original. Only a verified restore or window destruction consumes it.
    func changed(_ key: WindowSnapKey, destroyed: Bool = false) {
        lock.lock()
        guard let entry = entries[key] else { lock.unlock(); return }
        if destroyed { lock.unlock(); forget(key, token: entry.token); return }
        guard let active = drag, active.key == key, active.entryToken == entry.token,
              active.moved else { lock.unlock(); return }
        if pending[key] != nil { needsEvaluation.insert(key); lock.unlock(); return }
        let operation = UUID()
        pending[key] = operation
        let generation = epoch
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                var evaluateAgain = false
                if self.pending[key] == operation {
                    self.pending[key] = nil
                    evaluateAgain = self.needsEvaluation.remove(key) != nil
                }
                self.lock.unlock()
                if evaluateAgain { self.changed(key) }
            }
            let current = {
                self.lock.lock(); defer { self.lock.unlock() }
                guard let latest = self.drag, latest.id == active.id else { return false }
                // Freshness limit, not a delay: evaluate immediately, allowing
                // a late final AX move after up without keeping an old gesture
                // eligible for some unrelated programmatic move much later.
                let fresh = !latest.released || self.now() - latest.lastInputTime <= 1
                return fresh && self.entries[key]?.token == entry.token && self.epoch == generation
            }
            let permitted = { current() && entry.inputAllowed() }
            // Electron can keep returning the pre-drag AX position while its
            // real window is already moving. Magnet checks WindowServer here;
            // use the exact ID captured at down, never a fresh pointer hit test.
            guard permitted(), let frame = self.visibleFrame(for: active),
                  let pointer = self.currentPoint(for: active.id) else { return }
            if !WindowSnapGeometry.approximatelyEqual(frame, active.startFrame, tolerance: 3),
               !WindowSnapDragRestore.sizeChanged(current: frame, accepted: active.startFrame),
               !WindowSnapDragRestore.sizeChanged(current: frame, accepted: entry.original) {
                // A drag at the original size also ends the snap cycle. No AX
                // write is necessary, and the next resize gets a new original.
                self.forget(key, token: entry.token)
                return
            }
            guard let restore = WindowSnapDragRestore.restoredFrame(current: frame, accepted: active.startFrame,
                    original: entry.original, pointer: pointer) else { return }
            let restored = entry.target.withoutAnimation { () -> CGRect? in
                // Preserve the native grab for ordinary restores. Like Magnet,
                // correct position only if shrinking leaves the pointer outside.
                guard permitted(), entry.target.setSize(restore.size),
                      permitted(), let actual = entry.target.frame(),
                      abs(actual.width - restore.width) <= 2, abs(actual.height - restore.height) <= 2 else { return nil }
                guard let visible = self.visibleFrame(for: active) else { return nil }
                let resized = CGRect(origin: visible.origin, size: actual.size)
                if let point = self.currentPoint(for: active.id),
                   let origin = WindowSnapDragRestore.correctedOrigin(after: resized,
                       grabFrame: active.startFrame, grabPoint: active.downPoint, pointer: point) {
                    guard permitted(), entry.target.setPosition(origin),
                          permitted(), let corrected = entry.target.frame(),
                          abs(corrected.width - restore.width) <= 2,
                          abs(corrected.height - restore.height) <= 2 else { return nil }
                    return corrected
                }
                return resized
            }
            if let restored, permitted() {
                self.forget(key, token: entry.token)
                self.onRestore?(restored)
            }
        }
    }

    // MARK: Listener setup and main-thread Accessibility observations
    private static let notifications = [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification]
    /// Reserve listener readiness before any window becomes visibly snapped.
    /// A pending request keeps the listener alive even if an older restore's
    /// observer cleanup runs before this request reaches its worker.
    func prepareForSnap() -> UUID? {
        guard startMouseObservation() else { return nil }
        let token = UUID()
        lock.lock(); preparingSnaps.insert(token); lock.unlock()
        return token
    }

    func finishedSnap(_ token: UUID) {
        lock.lock(); preparingSnaps.remove(token); lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.pruneObservers() }
    }

    private func currentPoint(for id: UUID) -> CGPoint? {
        lock.lock(); defer { lock.unlock() }
        guard drag?.id == id else { return nil }
        return drag?.point
    }

    private func visibleFrame(for active: Drag) -> CGRect? {
        windows().first { $0.id == active.windowID && $0.pid == active.key.pid }?.frame
    }

    private func startMouseObservation() -> Bool {
        mouseObservation.start { [weak self] type, point, time in
            self?.mouseEvent(type, point: point, time: time)
        }
    }

    private func observe(_ key: WindowSnapKey, element: AXUIElement, token: UUID) {
        let observer: AXObserver
        if let existing = observers[key.pid] { observer = existing }
        else {
            var created: AXObserver?
            let callback: AXObserverCallback = { _, element, notification, refcon in
                guard let refcon else { return }
                let owner = Unmanaged<WindowSnapDragRestorer>.fromOpaque(refcon).takeUnretainedValue()
                guard let key = owner.observed.keys.first(where: { $0.element.map { CFEqual($0, element) } ?? false }) else { return }
                owner.changed(key, destroyed: notification as String == kAXUIElementDestroyedNotification)
            }
            guard AXObserverCreate(key.pid, callback, &created) == .success, let created else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
            observers[key.pid] = created; observer = created
        }
        observed[key] = token
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.notifications {
            AXObserverAddNotification(observer, element, notification as CFString, refcon)
        }
    }

    private func pruneObservers() {
        for (key, token) in observed where !isEntry(key, token) {
            if let element = key.element, let observer = observers[key.pid] {
                for notification in Self.notifications {
                    AXObserverRemoveNotification(observer, element, notification as CFString)
                }
            }
            observed[key] = nil
        }
        for (pid, observer) in observers where !observed.keys.contains(where: { $0.pid == pid }) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            observers[pid] = nil
        }
        lock.lock(); let empty = entries.isEmpty && preparingSnaps.isEmpty; lock.unlock()
        if empty { mouseObservation.stop() }
    }

    static func visibleWindows() -> [WindowSnapPointerWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let raw = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: raw) else { return nil }
            return WindowSnapPointerWindow(id: id, pid: pid, frame: frame)
        }
    }
}
