import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Notifies when the frontmost application changes.
///
/// This is a *hint*, not the safety mechanism. The authoritative check is
/// `MultiTapEngine.reconcileTarget`, which compares the anchored `TextTarget`
/// against a freshly resolved one on every press, release and tick — that also
/// catches focus moving between two fields inside a single app, which produces
/// no workspace notification at all.
///
/// The observer exists so the HUD can react promptly rather than waiting for
/// the next tick.
public protocol FocusMonitoring: AnyObject {
    var onFocusChange: (() -> Void)? { get set }
    func start()
    func stop()
}

#if canImport(AppKit)
public final class WorkspaceFocusMonitor: FocusMonitoring {
    public var onFocusChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []
    private let workspace: NSWorkspace
    private let ownProcessIdentifier: pid_t

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        self.ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    }

    public func start() {
        stop()
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification
        ] {
            let observer = workspace.notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                // The HUD never activates, so we should never see ourselves
                // here; if we do, it is not a real focus change.
                if let app, app.processIdentifier == self.ownProcessIdentifier { return }
                self.onFocusChange?()
            }
            observers.append(observer)
        }
    }

    public func stop() {
        observers.forEach { workspace.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    deinit { stop() }
}
#endif

public final class StubFocusMonitor: FocusMonitoring {
    public var onFocusChange: (() -> Void)?
    public private(set) var isRunning = false

    public init() {}

    public func start() { isRunning = true }
    public func stop() { isRunning = false }
    public func simulateFocusChange() { onFocusChange?() }
}
