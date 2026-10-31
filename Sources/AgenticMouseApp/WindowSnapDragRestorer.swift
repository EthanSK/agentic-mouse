import AppKit
import ApplicationServices
import ScimitarKit

/// Ethan's "restore windows to original size": a real left-button drag away
/// from our snap restores the first pre-snap size, including after monitor hops.
/// AX work shares the snap worker. Observation stays on the main run loop;
/// generation checks follow WindowSnapController's cancellation pattern.
final class WindowSnapDragRestorer {
    static let shared = WindowSnapDragRestorer()
    let queue: DispatchQueue
    private struct Entry {
        let token: UUID
        let target: WindowResizeTarget
        let original: CGRect
        let accepted: CGRect
        let source: MouseSource?
        let inputAllowed: () -> Bool
    }
    private let lock = NSLock()
    private var entries: [WindowSnapKey: Entry] = [:]
    private var order: [WindowSnapKey] = []
    private var pending: Set<WindowSnapKey> = []
    private var epoch = UUID()
    private var sourceEpochs: [MouseSource?: UUID] = [:]
    private var observers: [pid_t: AXObserver] = [:] // Main-thread owned.
    private var observed: [WindowSnapKey: UUID] = [:] // Main-thread owned.
    private let dragging: () -> Bool
    private let pointer: () -> CGPoint
    var onRestore: ((CGRect) -> Void)? // Worker callback; only verified restores.

    init(queue: DispatchQueue = DispatchQueue(label: "agentic-mouse.window-snap", qos: .userInitiated),
         dragging: @escaping () -> Bool = {
             CGEventSource.buttonState(.hidSystemState, button: .left)
         }, pointer: @escaping () -> CGPoint = { CGEvent(source: nil)?.location ?? .zero }) {
        self.queue = queue
        self.dragging = dragging
        self.pointer = pointer
    }

    /// A newer requested snap invalidates queued restores before it reaches AX.
    func snapRequested() {
        lock.lock(); epoch = UUID(); lock.unlock()
    }

    func cancel(source: MouseSource) {
        lock.lock(); sourceEpochs[source] = UUID(); lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        epoch = UUID(); entries.removeAll(); order.removeAll(); pending.removeAll()
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.pruneObservers() }
    }

    func didSnap(key: WindowSnapKey, target: WindowResizeTarget, preSnap: CGRect, accepted: CGRect,
                 source: MouseSource? = nil, inputAllowed: @escaping () -> Bool = { true }) {
        let token = UUID()
        lock.lock()
        let previous = entries[key]
        let original = WindowSnapDragRestore.originalForSnap(preSnap: preSnap,
            previousOriginal: previous?.original, previousAccepted: previous?.accepted)
        entries[key] = Entry(token: token, target: target, original: original, accepted: accepted,
                             source: source, inputAllowed: inputAllowed)
        order.removeAll { $0 == key }; order.append(key)
        if order.count > 32 { entries[order.removeFirst()] = nil }
        pending.remove(key)
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pruneObservers()
            if self.isEntry(key, token), let element = key.element { self.observe(key, element: element, token: token) }
        }
    }

    private func isEntry(_ key: WindowSnapKey, _ token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return entries[key]?.token == token
    }

    private func forget(_ key: WindowSnapKey, token: UUID) {
        lock.lock()
        if entries[key]?.token == token {
            entries[key] = nil; order.removeAll { $0 == key }; pending.remove(key)
        }
        lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.pruneObservers() }
    }

    /// Injectable notification entry also exercises the real queued controller
    /// in tests without installing AX observers or generating input.
    func changed(_ key: WindowSnapKey, destroyed: Bool = false) {
        lock.lock()
        guard let entry = entries[key] else { lock.unlock(); return }
        if destroyed { lock.unlock(); forget(key, token: entry.token); return }
        guard !pending.contains(key) else { lock.unlock(); return }
        pending.insert(key)
        let generation = epoch
        let sourceGeneration = sourceEpochs[entry.source]
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                if self.entries[key]?.token == entry.token { self.pending.remove(key) }
                self.lock.unlock()
            }
            let current = {
                self.lock.lock(); defer { self.lock.unlock() }
                return self.entries[key]?.token == entry.token && self.epoch == generation &&
                    self.sourceEpochs[entry.source] == sourceGeneration
            }
            guard current(), entry.inputAllowed() else { return }
            guard let frame = entry.target.frame() else { self.forget(key, token: entry.token); return }
            if WindowSnapDragRestore.sizeChanged(current: frame, accepted: entry.accepted) {
                self.forget(key, token: entry.token); return
            }
            guard !WindowSnapGeometry.approximatelyEqual(frame, entry.accepted, tolerance: 3) else { return }
            guard self.dragging() else { self.forget(key, token: entry.token); return }
            guard let restore = WindowSnapDragRestore.restoredFrame(current: frame, accepted: entry.accepted,
                    original: entry.original, pointer: self.pointer()) else { return }
            let permitted = { current() && entry.inputAllowed() && self.dragging() }
            let restored = entry.target.withoutAnimation { () -> CGRect? in
                guard permitted(), entry.target.setSize(restore.size),
                      permitted(), entry.target.setPosition(restore.origin),
                      permitted(), let actual = entry.target.frame(),
                      WindowSnapGeometry.approximatelyEqual(actual, restore, tolerance: 2) else { return nil }
                return actual
            }
            // Never remove a newer snap or claim an ignored/failed AX write.
            if let restored, permitted() {
                self.forget(key, token: entry.token)
                self.onRestore?(restored)
            }
        }
    }

    // MARK: Main-thread Accessibility observations
    private static let notifications = [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification]

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
    }
}
