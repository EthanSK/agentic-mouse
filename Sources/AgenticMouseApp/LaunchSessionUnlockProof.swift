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
        guard monitor == nil else { return true }
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
                guard let self else { return }
                guard !Self.blocksSession(self.frontmostBundleIdentifier()) else { return }
                self.stop()
                self.onUnlockedInput?()
            }
        }
        return monitor != nil
    }

    func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
