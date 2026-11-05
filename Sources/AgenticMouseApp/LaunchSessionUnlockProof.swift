import AppKit

@MainActor
protocol LaunchSessionUnlockProofObserving: AnyObject {
    var onUnlockedInput: (() -> Void)? { get set }
    @discardableResult func start() -> Bool
    func stop()
}

/// A supervised relaunch can occur while loginwindow owns a locked session.
/// NSWorkspace does not publish a synchronous lock-state query, so launch stays
/// fail closed until macOS delivers real global user input to this logged-in
/// session. Loginwindow-owned events are not delivered to a global monitor.
@MainActor
final class GlobalInputLaunchSessionUnlockProof: LaunchSessionUnlockProofObserving {
    var onUnlockedInput: (() -> Void)?

    private var monitor: Any?
    private var localMonitor: Any?
    private let frontmostBundleIdentifier: () -> String?

    init(
        frontmostBundleIdentifier: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
    ) {
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
    }

    nonisolated static func blocksSession(_ bundleIdentifier: String?) -> Bool {
        switch bundleIdentifier {
        case "com.apple.loginwindow", "com.apple.ScreenSaver.Engine", "com.apple.ScreenSaver":
            return true
        case nil:
            return true
        default:
            return false
        }
    }

    @discardableResult
    func start() -> Bool {
        guard monitor == nil && localMonitor == nil else { return true }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .scrollWheel,
            .keyDown,
            .flagsChanged,
        ]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.observeUnlockedInput()
            }
        }
        // A normal Dock app also receives real input in its own settings
        // window. Global monitors exclude that input; use the same blocked-
        // session check locally, without consuming or synthesizing events.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.observeUnlockedInput() }
            return event
        }
        return monitor != nil || localMonitor != nil
    }

    private func observeUnlockedInput() {
        guard !Self.blocksSession(frontmostBundleIdentifier()) else { return }
        stop()
        onUnlockedInput?()
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        self.monitor = nil
        self.localMonitor = nil
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
