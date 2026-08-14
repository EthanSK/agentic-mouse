import AppKit
import ScimitarKit

@MainActor
protocol SessionActivityObserving: AnyObject {
    var onSessionBecameActive: (() -> Void)? { get set }
    var onSessionResignedActive: (() -> Void)? { get set }
    func start()
    func stop()
}

/// Observes only public NSWorkspace user-session and sleep notifications.
///
/// Apple guarantees that an app launched into an inactive session receives
/// `sessionDidResignActiveNotification` between will-finish and did-finish
/// launching. AppDelegate therefore starts this observer in will-finish and
/// confirms the session only after did-finish.
@MainActor
final class WorkspaceSessionActivityObserver: NSObject, SessionActivityObserving {
    var onSessionBecameActive: (() -> Void)?
    var onSessionResignedActive: (() -> Void)?

    private let center: NotificationCenter
    private var isStarted = false
    private var sessionIsActive = true

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.center = center
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        sessionIsActive = true
        center.addObserver(
            self,
            selector: #selector(sessionBecameActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionResignedActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.addObserver(
                self,
                selector: #selector(systemBecameUnavailable),
                name: name,
                object: nil
            )
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(
                self,
                selector: #selector(systemBecameAvailable),
                name: name,
                object: nil
            )
        }
    }

    func stop() {
        guard isStarted else { return }
        center.removeObserver(self)
        isStarted = false
    }

    @objc private func sessionBecameActive(_ notification: Notification) {
        sessionIsActive = true
        onSessionBecameActive?()
    }

    @objc private func sessionResignedActive(_ notification: Notification) {
        sessionIsActive = false
        onSessionResignedActive?()
    }

    @objc private func systemBecameUnavailable(_ notification: Notification) {
        onSessionResignedActive?()
    }

    @objc private func systemBecameAvailable(_ notification: Notification) {
        // Display/system sleep is a temporary fail-closed boundary. Restore
        // only when no real session-resign event occurred; a locked or
        // switched-out session must wait for sessionDidBecomeActive.
        if sessionIsActive {
            onSessionBecameActive?()
        }
    }

    deinit { center.removeObserver(self) }
}

/// Owns the fail-closed permission for every Agentic Mouse command.
///
/// Karabiner receives an absolute three-second lease, renewed every second only
/// while the macOS user session is active. Lock/switch-out clears it
/// immediately. A crash, kill, missing CLI, or stalled writer lets it expire,
/// so the generated locked-session sink consumes the exact mouse transports.
@MainActor
final class SessionSecurityController {
    static let variableName = "agentic_mouse_session_unlocked_expires_at"

    enum State: Equatable {
        case awaitingLaunchConfirmation
        case unlocked
        case locked
    }

    private let observer: SessionActivityObserving
    private let lease: ColorProofLeaseControlling
    private let scheduler: TickScheduler
    private let heartbeatInterval: TimeInterval
    private let log: Log
    private(set) var state: State = .awaitingLaunchConfirmation
    private var started = false

    var onLockdown: (() -> Void)?
    var onUnlock: (() -> Void)?
    var isUnlocked: Bool { state == .unlocked }

    init(
        observer: SessionActivityObserving,
        lease: ColorProofLeaseControlling,
        scheduler: TickScheduler,
        log: Log,
        heartbeatInterval: TimeInterval = 1
    ) {
        self.observer = observer
        self.lease = lease
        self.scheduler = scheduler
        self.log = log
        self.heartbeatInterval = heartbeatInterval
    }

    func start() {
        guard !started else { return }
        started = true
        state = .awaitingLaunchConfirmation
        scheduler.stop()
        lease.deactivate()
        observer.onSessionBecameActive = { [weak self] in self?.markUnlocked() }
        observer.onSessionResignedActive = { [weak self] in self?.markLocked() }
        observer.start()
        log.info("mouse command security boundary awaiting session confirmation")
    }

    /// Call from applicationDidFinishLaunching. If the session were inactive,
    /// NSWorkspace would already have delivered its documented resign event.
    func confirmActiveSessionAfterLaunch() {
        guard state == .awaitingLaunchConfirmation else { return }
        markUnlocked()
    }

    func markUnlocked() {
        guard started else { return }
        do {
            try lease.activate()
        } catch {
            failClosed(error)
            return
        }
        let changed = state != .unlocked
        state = .unlocked
        scheduler.start(interval: heartbeatInterval) { [weak self] in self?.renew() }
        if changed {
            log.info("macOS user session active; mouse commands enabled")
            onUnlock?()
        }
    }

    func markLocked() {
        guard started else { return }
        let changed = state != .locked
        state = .locked
        scheduler.stop()
        lease.deactivate()
        if changed {
            log.notice("macOS user session inactive; mouse commands disabled")
            onLockdown?()
        }
    }

    func handleLeaseFailure(_ error: Error) {
        failClosed(error)
    }

    func stop() {
        guard started else { return }
        started = false
        state = .locked
        scheduler.stop()
        lease.deactivate()
        observer.stop()
        observer.onSessionBecameActive = nil
        observer.onSessionResignedActive = nil
    }

    private func renew() {
        guard state == .unlocked else { return }
        do {
            try lease.renew()
        } catch {
            failClosed(error)
        }
    }

    private func failClosed(_ error: Error) {
        let changed = state != .locked
        state = .locked
        scheduler.stop()
        lease.deactivate()
        log.error("mouse command security lease failed closed: \(error)")
        if changed { onLockdown?() }
    }
}
