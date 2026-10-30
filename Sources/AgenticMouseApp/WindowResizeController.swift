import AppKit
import ApplicationServices
import ScimitarKit

protocol WindowResizeTarget: AnyObject {
    func frame() -> CGRect?
    func setSize(_ size: CGSize) -> Bool
    func setPosition(_ point: CGPoint) -> Bool
    func withoutAnimation(_ operation: () -> CGRect?) -> CGRect?
}

extension WindowResizeTarget {
    func withoutAnimation(_ operation: () -> CGRect?) -> CGRect? { operation() }
}

protocol WindowResizeAccess {
    func window(at point: CGPoint) -> WindowResizeTarget?
}

/// Accessibility runs on one worker, never inside the wheel tap or on the main
/// thread. A generation per physical hold invalidates queued work on release.
final class WindowResizeController {
    private struct Session {
        let target: WindowResizeTarget
        let geometry: WindowResizeGeometry
        let axis: WindowResizeAxis
        var lastFrame: CGRect
    }
    private let access: WindowResizeAccess
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var generations: [MouseSource: UUID] = [:]
    private var sessions: [MouseSource: Session] = [:] // Worker-owned.
    var onProblem: ((MouseSource, String) -> Void)?
    var onResize: ((MouseSource, WindowResizeAxis, CGRect) -> Void)?

    init(access: WindowResizeAccess = AccessibilityWindowResizeAccess(),
         queue: DispatchQueue = DispatchQueue(label: "agentic-mouse.window-resize", qos: .userInitiated)) {
        self.access = access
        self.queue = queue
    }

    func begin(source: MouseSource, axis: WindowResizeAxis, pointer: CGPoint, bounds: CGRect) {
        let generation = UUID()
        lock.lock(); generations[source] = generation; lock.unlock()
        queue.async { [weak self] in
            guard let self, self.isCurrent(source, generation) else { return }
            self.sessions[source] = nil
            guard let target = self.access.window(at: pointer), let frame = target.frame(),
                  let geometry = WindowResizeGeometry(frame: frame, pointer: pointer, bounds: bounds)
            else {
                self.fail(source, generation, "No resizable window under pointer")
                return
            }
            guard self.isCurrent(source, generation) else { return }
            self.sessions[source] = Session(target: target, geometry: geometry, axis: axis, lastFrame: frame)
        }
    }

    func step(source: MouseSource, grow: Bool) {
        lock.lock(); let generation = generations[source]; lock.unlock()
        guard let generation else { return }
        queue.async { [weak self] in
            guard let self, self.isCurrent(source, generation), var session = self.sessions[source] else { return }
            guard let current = session.target.frame() else {
                self.fail(source, generation, "This window cannot be resized"); return
            }
            guard WindowResizeGeometry.approximatelyEqual(current, session.lastFrame) else {
                self.fail(source, generation, "Window moved or resized somewhere else, so resizing stopped"); return
            }
            guard let desired = session.geometry.frame(from: current, axis: session.axis, delta: grow ? 120 : -120),
                  self.isCurrent(source, generation) else { return }
            if WindowResizeGeometry.approximatelyEqual(desired, current) { return }
            // Complete an already-started frame transaction; release cancels
            // queued detents, not the anchor correction halfway through a write.
            let final = session.target.withoutAnimation {
                // Size/position/size handles macOS constraining the initial size
                // at the old position (especially height growth near an edge).
                guard session.target.setSize(desired.size),
                      session.target.setPosition(desired.origin),
                      session.target.setSize(desired.size),
                      let resized = session.target.frame() else { return nil }
                var accepted = desired
                accepted.size = resized.size
                let anchored = session.geometry.anchored(accepted, axis: session.axis)
                if !WindowResizeGeometry.approximatelyEqual(resized, anchored) {
                    guard session.target.setPosition(anchored.origin) else { return nil }
                }
                guard let final = session.target.frame(),
                      WindowResizeGeometry.approximatelyEqual(final, anchored) else { return nil }
                return final
            }
            guard let final else {
                self.fail(source, generation, "Could not resize window"); return
            }
            session.lastFrame = final
            self.sessions[source] = session
            self.deliver(source, generation) { $0.onResize?(source, session.axis, final) }
        }
    }

    func cancel(source: MouseSource) {
        lock.lock(); generations[source] = nil; lock.unlock()
        queue.async { [weak self] in self?.sessions[source] = nil }
    }

    private func isCurrent(_ source: MouseSource, _ generation: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generations[source] == generation
    }

    private func deliver(_ source: MouseSource, _ generation: UUID,
                         _ body: @escaping (WindowResizeController) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(source, generation) else { return }
            body(self)
        }
    }

    private func fail(_ source: MouseSource, _ generation: UUID, _ message: String) {
        sessions[source] = nil
        deliver(source, generation) { $0.onProblem?(source, message) }
    }
}

struct AccessibilityWindowResizeAccess: WindowResizeAccess {
    func window(at point: CGPoint) -> WindowResizeTarget? {
        guard AXIsProcessTrusted() else { return nil }
        // WindowServer order is independent of keyboard focus. Some apps'
        // system-wide AX hit tests return an application or web element without
        // AXWindow when inactive, so resolve only this visible window's owner.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let visible = windows.first(where: { info in
                  guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                        let pid = info[kCGWindowOwnerPID as String] as? Int32,
                        pid != ProcessInfo.processInfo.processIdentifier,
                        let raw = info[kCGWindowBounds as String] as? NSDictionary,
                        let frame = CGRect(dictionaryRepresentation: raw) else { return false }
                  return frame.contains(point)
              }),
              let pid = visible[kCGWindowOwnerPID as String] as? Int32,
              let raw = visible[kCGWindowBounds as String] as? NSDictionary,
              let visibleFrame = CGRect(dictionaryRepresentation: raw) else { return nil }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let candidates = Self.attribute(application, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        let matches = candidates.compactMap { window -> AccessibilityWindowResizeTarget? in
            AXUIElementSetMessagingTimeout(window, 0.15)
            guard Self.attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole else { return nil }
            let target = AccessibilityWindowResizeTarget(window: window, application: application)
            guard let frame = target.frame(), WindowResizeGeometry.approximatelyEqual(frame, visibleFrame) else { return nil }
            return target
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
}

final class AccessibilityWindowResizeTarget: WindowResizeTarget {
    let window: AXUIElement
    let application: AXUIElement
    init(window: AXUIElement, application: AXUIElement) {
        self.window = window
        self.application = application
    }

    func withoutAnimation(_ operation: () -> CGRect?) -> CGRect? {
        // Enhanced UI enables animated AX frame writes in Chrome/Electron.
        // Restore the original app attribute even on failure or cancellation.
        let name = "AXEnhancedUserInterface" as CFString
        let enhanced = AccessibilityWindowResizeAccess.attribute(application, name as String) as? Bool == true
        let changed = enhanced && AXUIElementSetAttributeValue(application, name, kCFBooleanFalse) == .success
        defer {
            if changed { AXUIElementSetAttributeValue(application, name, kCFBooleanTrue) }
        }
        return operation()
    }

    func frame() -> CGRect? {
        guard AccessibilityWindowResizeAccess.attribute(window, "AXFullScreen") as? Bool != true,
              AccessibilityWindowResizeAccess.attribute(window, kAXMinimizedAttribute) as? Bool != true,
              settable(kAXSizeAttribute), settable(kAXPositionAttribute),
              let position = AccessibilityWindowResizeAccess.attribute(window, kAXPositionAttribute),
              let size = AccessibilityWindowResizeAccess.attribute(window, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    func setSize(_ size: CGSize) -> Bool {
        var value = size
        guard let packed = AXValueCreate(.cgSize, &value) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, packed) == .success
    }

    func setPosition(_ point: CGPoint) -> Bool {
        var value = point
        guard let packed = AXValueCreate(.cgPoint, &value) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, packed) == .success
    }

    private func settable(_ name: String) -> Bool {
        var value: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(window, name as CFString, &value) == .success && value.boolValue
    }
}
