import AppKit
import ApplicationServices
import ScimitarKit

struct ChromeVSCodeLayoutDisplay: Equatable {
    struct Candidate {
        let display: ChromeVSCodeLayoutDisplay
        let isBuiltIn: Bool
        let isMain: Bool
    }

    /// Ethan's "Dell" means the main external workspace display. Follow that
    /// role on every request, independent of dock names, UUIDs and scaling.
    /// With the menu bar on the laptop, only a sole external is unambiguous.
    static func resolve(_ candidates: [Candidate]) -> Self? {
        let external = candidates.filter { !$0.isBuiltIn }
        let main = external.filter(\.isMain)
        let matches = main.isEmpty ? external : main
        guard matches.count == 1, let match = matches.first else { return nil }
        return match.display
    }
    let uuid: String
    let bounds: CGRect
    let visibleFrame: CGRect

    static func current() -> Self? {
        guard let primary = NSScreen.screens.first else { return nil }
        func quartz(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY,
                   width: rect.width, height: rect.height)
        }
        let candidates = NSScreen.screens.compactMap { screen -> Candidate? in
            guard let uuid = identifier(screen),
                  let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { return nil }
            return Candidate(display: Self(uuid: uuid, bounds: quartz(screen.frame),
                                           visibleFrame: quartz(screen.visibleFrame)),
                             isBuiltIn: CGDisplayIsBuiltin(id) != 0, isMain: id == CGMainDisplayID())
        }
        return resolve(candidates)
    }

    private static func identifier(_ screen: NSScreen) -> String? {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    func frames(codeOnRight: Bool) -> (code: CGRect, chrome: CGRect) {
        let split = floor(visibleFrame.width / 2)
        let left = CGRect(x: visibleFrame.minX, y: visibleFrame.minY,
                          width: split, height: visibleFrame.height)
        let right = CGRect(x: left.maxX, y: visibleFrame.minY,
                           width: visibleFrame.width - split, height: visibleFrame.height)
        return codeOnRight ? (right, left) : (left, right)
    }
}

protocol ChromeVSCodeLayoutAccess {
    func window(bundleID: String, on display: CGRect) -> WindowResizeTarget?
}

/// WindowServer gives stacking order; AX supplies writable windows. Geometry
/// alone is not an identity: restored editor windows commonly share a frame.
enum ChromeVSCodeLayoutWindowMatcher {
    struct Candidate {
        let frame: CGRect
        let title: String
        let isMain: Bool
    }

    static func index(frame: CGRect, title: String, candidates: [Candidate]) -> Int? {
        let matchingFrames = candidates.indices.filter {
            WindowResizeGeometry.approximatelyEqual(candidates[$0].frame, frame)
        }
        guard matchingFrames.count != 1 else { return matchingFrames[0] }
        let matchingTitles = title.isEmpty ? matchingFrames : matchingFrames.filter {
            candidates[$0].title == title
        }
        if matchingTitles.count == 1 { return matchingTitles[0] }
        // Browser titles can acquire a profile suffix or change before the
        // WindowServer snapshot catches up. A unique public main-window
        // identity still identifies a same-frame window on this display.
        let main = (matchingTitles.isEmpty ? matchingFrames : matchingTitles)
            .filter { candidates[$0].isMain }
        return main.count == 1 ? main[0] : nil
    }
}

struct AccessibilityChromeVSCodeLayoutAccess: ChromeVSCodeLayoutAccess {
    var diagnostic: (String) -> Void = { message in
        Log(category: "split-layout", sink: OSLogSink()).notice(message)
    }

    func window(bundleID: String, on display: CGRect) -> WindowResizeTarget? {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]]
        else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let axWindows = AccessibilityWindowResizeAccess.attribute(application, kAXWindowsAttribute) as? [AXUIElement]
        else { return nil }
        let mainWindow = AccessibilityWindowResizeAccess.attribute(application, kAXMainWindowAttribute)
        let candidates = axWindows.compactMap { window -> (AccessibilityWindowResizeTarget, ChromeVSCodeLayoutWindowMatcher.Candidate)? in
            AXUIElementSetMessagingTimeout(window, 0.15)
            guard AccessibilityWindowResizeAccess.attribute(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole
            else { return nil }
            let target = AccessibilityWindowResizeTarget(window: window, application: application)
            guard let frame = target.frame() else { return nil }
            return (target, .init(frame: frame,
                title: AccessibilityWindowResizeAccess.attribute(window, kAXTitleAttribute) as? String ?? "",
                isMain: mainWindow.map { CFEqual($0, window) } ?? false))
        }
        diagnostic("\(bundleID): AX windows=\(axWindows.count), resizable=\(candidates.count)")
        // Match the frontmost normal window on this display, without activating
        // the app. A title or main-window match disambiguates restored frames.
        for info in windows {
            guard info[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let raw = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: raw),
                  frame.width >= 120, frame.height >= 80,
                  display.contains(CGPoint(x: frame.midX, y: frame.midY)) else { continue }
            // Normal-layer popovers can precede the real editor/browser. They
            // have no standard AX window; do not report the app as absent.
            guard candidates.contains(where: {
                WindowResizeGeometry.approximatelyEqual($0.1.frame, frame)
            }) else { continue }
            guard let index = ChromeVSCodeLayoutWindowMatcher.index(
                frame: frame, title: info[kCGWindowName as String] as? String ?? "",
                candidates: candidates.map(\.1)) else {
                diagnostic("\(bundleID): unmatched visible frame=\(frame), AX frames=\(candidates.map { $0.1.frame })")
                return nil
            }
            return candidates[index].0
        }
        return nil
    }
}

/// AX writes stay off the input tap. At most one transaction runs and one
/// latest request waits; a rapid reversal cannot build a backlog of swaps.
final class ChromeVSCodeLayoutController {
    private struct Request {
        let source: MouseSource
        let generation: Int
        let codeOnRight: Bool
        let display: ChromeVSCodeLayoutDisplay
    }
    private let access: ChromeVSCodeLayoutAccess
    private let queue: DispatchQueue
    private let allowed: (MouseSource, ChromeVSCodeLayoutDisplay) -> Bool
    private let lock = NSLock()
    private var generations: [MouseSource: Int] = [:]
    private var pending: Request?
    private var running = false
    private struct Targets {
        let generation: Int
        let display: ChromeVSCodeLayoutDisplay
        let chrome: WindowResizeTarget
        let code: WindowResizeTarget
    }
    private var targets: [MouseSource: Targets] = [:] // Worker-owned, bound to one hold.
    var onCompletion: ((MouseSource, Bool, String) -> Void)?

    init(access: ChromeVSCodeLayoutAccess = AccessibilityChromeVSCodeLayoutAccess(),
         queue: DispatchQueue = DispatchQueue(label: "agentic-mouse.chrome-vscode-layout", qos: .userInitiated),
         allowed: @escaping (MouseSource, ChromeVSCodeLayoutDisplay) -> Bool) {
        self.access = access
        self.queue = queue
        self.allowed = allowed
    }

    func request(source: MouseSource, codeOnRight: Bool, display: ChromeVSCodeLayoutDisplay) {
        lock.lock()
        pending = Request(source: source, generation: generations[source, default: 0],
                          codeOnRight: codeOnRight, display: display)
        let start = !running
        running = true
        lock.unlock()
        if start { queue.async { [weak self] in self?.drain() } }
    }

    func cancel(source: MouseSource) {
        lock.lock(); defer { lock.unlock() }
        generations[source, default: 0] += 1
        if pending?.source == source { pending = nil }
    }

    private func current(_ request: Request) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generations[request.source, default: 0] == request.generation
    }

    private func permitted(_ request: Request) -> Bool {
        guard current(request) else { return false }
        return allowed(request.source, request.display)
    }

    private func drain() {
        while true {
            lock.lock()
            guard let request = pending else { running = false; lock.unlock(); return }
            pending = nil
            lock.unlock()
            perform(request)
        }
    }

    private func perform(_ request: Request) {
        guard permitted(request) else { return }
        let pair: Targets
        if let saved = targets[request.source], saved.generation == request.generation,
           saved.display == request.display {
            pair = saved
        } else {
            guard let chrome = access.window(bundleID: "com.google.Chrome", on: request.display.bounds) else {
                finish(request, false, "No Chrome window on Dell"); return
            }
            guard let code = access.window(bundleID: "com.microsoft.VSCode", on: request.display.bounds) else {
                finish(request, false, "No VS Code window on Dell"); return
            }
            pair = Targets(generation: request.generation, display: request.display, chrome: chrome, code: code)
            targets[request.source] = pair
        }
        let chrome = pair.chrome, code = pair.code
        guard let chromeBefore = chrome.frame(), let codeBefore = code.frame(), permitted(request) else { return }
        let desired = request.display.frames(codeOnRight: request.codeOnRight)
        // Both targets are captured and validated before either window moves.
        // A rejected minimum size must not leave the first window half-arranged.
        let succeeded = place(code, at: desired.code, request: request)
            && place(chrome, at: desired.chrome, request: request)
            && matches(code, desired.code) && matches(chrome, desired.chrome)
        if !succeeded, permitted(request) {
            _ = place(code, at: codeBefore, request: request)
            _ = place(chrome, at: chromeBefore, request: request)
        }
        finish(request, succeeded, succeeded
               ? (request.codeOnRight ? "VS Code right, Chrome left on Dell" : "VS Code left, Chrome right on Dell")
               : "Could not move both windows on Dell")
    }

    private func matches(_ target: WindowResizeTarget, _ frame: CGRect) -> Bool {
        guard let actual = target.frame() else { return false }
        return WindowResizeGeometry.approximatelyEqual(actual, frame)
    }

    private func place(_ target: WindowResizeTarget, at frame: CGRect, request: Request) -> Bool {
        guard permitted(request) else { return false }
        if matches(target, frame) { return true }
        return target.withoutAnimation {
            guard self.permitted(request), target.setSize(frame.size),
                  self.permitted(request), target.setPosition(frame.origin),
                  self.permitted(request), target.setSize(frame.size),
                  self.matches(target, frame) else { return nil }
            return frame
        } != nil
    }

    private func finish(_ request: Request, _ success: Bool, _ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.current(request) else { return }
            self.onCompletion?(request.source, success, message)
        }
    }
}
