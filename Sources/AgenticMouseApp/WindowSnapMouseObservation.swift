import AppKit
import ApplicationServices
import Foundation

/// Captures the grabbed window before macOS dispatches mouse-down. The
/// callback always forwards the original event. Its sleeping run loop is
/// separate from HUD/AppKit work: a delayed passive main-thread listener can
/// otherwise inspect the window only after a short drag has already ended.
final class WindowSnapMouseObservation {
    private var capture: Capture?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start(handler: @escaping (CGEventType, CGPoint, TimeInterval) -> Void) -> Bool {
        precondition(Thread.isMainThread)
        if let capture { return capture.isRunning }
        guard let candidate = Capture.make(handler: handler) else { return false }
        let thread = Thread { candidate.run() }
        thread.name = "agentic-mouse.window-snap-input"
        thread.qualityOfService = .userInteractive
        thread.start()
        // Wait for required setup, never for a timed settling interval.
        guard candidate.ready.wait(timeout: .now() + 1) == .success,
              candidate.isRunning else {
            candidate.stop()
            return false
        }
        capture = candidate
        // Magnet separates the pre-dispatch down capture from AppKit's drag
        // delivery. Feeding future drag coordinates straight from a Quartz
        // tap can race the native drag anchor when restoring a narrow window.
        let mask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        let receive: (NSEvent) -> Void = { event in
            let type: CGEventType = event.type == .leftMouseUp ? .leftMouseUp : .leftMouseDragged
            let quartz = event.cgEvent
            let point = quartz?.location ?? CGEvent(source: nil)?.location ?? .zero
            let time = quartz.map { TimeInterval($0.timestamp) / 1_000_000_000 } ?? event.timestamp
            handler(type, point, time)
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: receive)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            receive(event)
            return event
        }
        guard globalMonitor != nil, localMonitor != nil else { stop(); return false }
        return true
    }

    func stop() {
        precondition(Thread.isMainThread)
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        capture?.stop()
        capture = nil
    }

    deinit {
        capture?.stop()
        let global = globalMonitor
        let local = localMonitor
        let remove = {
            if let global { NSEvent.removeMonitor(global) }
            if let local { NSEvent.removeMonitor(local) }
        }
        if Thread.isMainThread { remove() }
        else { DispatchQueue.main.async(execute: remove) }
    }

    private final class Capture {
        let ready = DispatchSemaphore(value: 0)
        // A callback may release the last owner and run stop() on this thread.
        private let lock = NSRecursiveLock()
        private let handler: (CGEventType, CGPoint, TimeInterval) -> Void
        private var stopped = false
        private var loop: CFRunLoop?
        private var tap: CFMachPort!
        private var source: CFRunLoopSource!

        private init(handler: @escaping (CGEventType, CGPoint, TimeInterval) -> Void) {
            self.handler = handler
        }

        static func make(handler: @escaping (CGEventType, CGPoint, TimeInterval) -> Void) -> Capture? {
            let capture = Capture(handler: handler)
            let mask = [CGEventType.leftMouseDown, .keyDown, .rightMouseDown, .otherMouseDown]
                .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
            guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                    options: .defaultTap, eventsOfInterest: mask,
                    callback: { _, type, event, context in
                        if let context {
                            Unmanaged<Capture>.fromOpaque(context).takeUnretainedValue().receive(type, event)
                        }
                        return Unmanaged.passUnretained(event)
                    }, userInfo: Unmanaged.passUnretained(capture).toOpaque()) else { return nil }
            guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
                CFMachPortInvalidate(tap)
                return nil
            }
            capture.tap = tap
            capture.source = source
            return capture
        }

        var isRunning: Bool {
            lock.lock(); defer { lock.unlock() }
            return !stopped && loop != nil && CGEvent.tapIsEnabled(tap: tap)
        }

        func run() {
            let current = CFRunLoopGetCurrent()
            lock.lock()
            guard !stopped else { lock.unlock(); ready.signal(); return }
            loop = current
            CFRunLoopAddSource(current, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            lock.unlock()
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(current, source, .commonModes)
        }

        private func receive(_ type: CGEventType, _ event: CGEvent) {
            lock.lock(); defer { lock.unlock() }
            guard !stopped else { return }
            // stop() waits for this non-AX callback before a new capture can
            // start, so an old tap cannot alter the next snap's interaction.
            let time = event.timestamp > 0 ? TimeInterval(event.timestamp) / 1_000_000_000
                : ProcessInfo.processInfo.systemUptime
            handler(type, event.location, time)
            if !stopped && (type == .tapDisabledByTimeout || type == .tapDisabledByUserInput) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }

        func stop() {
            lock.lock()
            stopped = true
            let current = loop
            lock.unlock()
            CFMachPortInvalidate(tap)
            if let current { CFRunLoopStop(current) }
        }
    }
}
