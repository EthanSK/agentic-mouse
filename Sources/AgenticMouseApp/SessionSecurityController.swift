import AppKit
import ScimitarKit

@MainActor
protocol SessionActivityObserving: AnyObject {
    var onSessionBecameActive: (() -> Void)? { get set }
    var onSessionResignedActive: (() -> Void)? { get set }
    var onSessionMayBeAvailable: (() -> Void)? { get set }
    func start()
    func stop()
}

/// Observes public NSWorkspace user-session, sleep/wake, and application
/// activation notifications. Loginwindow activation is an immediate lockdown;
/// leaving it or waking a display only arms positive user-input proof.
///
/// Apple guarantees that an app launched into an inactive session receives
/// `sessionDidResignActiveNotification` between will-finish and did-finish
/// launching. AppDelegate therefore starts this observer in will-finish and
/// confirms the session only after did-finish.
@MainActor
final class WorkspaceSessionActivityObserver: NSObject, SessionActivityObserving {
    var onSessionBecameActive: (() -> Void)?
    var onSessionResignedActive: (() -> Void)?
    var onSessionMayBeAvailable: (() -> Void)?

    private let center: NotificationCenter
    private var isStarted = false
    private var sessionIsActive = true
    private var loginWindowOwnsSession = false

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
        center.addObserver(
            self,
            selector: #selector(applicationDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func stop() {
        guard isStarted else { return }
        center.removeObserver(self)
        isStarted = false
    }

    @objc private func sessionBecameActive(_ notification: Notification) {
        sessionIsActive = true
        loginWindowOwnsSession = false
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
        if sessionIsActive, !loginWindowOwnsSession {
            onSessionMayBeAvailable?()
        }
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
        else { return }
        handleActivatedBundleIdentifier(application.bundleIdentifier)
    }

    func handleActivatedBundleIdentifier(_ bundleIdentifier: String?) {
        if GlobalInputLaunchSessionUnlockProof.blocksSession(bundleIdentifier) {
            loginWindowOwnsSession = true
            onSessionResignedActive?()
        } else if loginWindowOwnsSession {
            loginWindowOwnsSession = false
            if sessionIsActive { onSessionMayBeAvailable?() }
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
    private let launchUnlockProof: LaunchSessionUnlockProofObserving
    private let heartbeatInterval: TimeInterval
    private let log: Log
    private let recoverableLeaseError: (Error) -> Bool
    private(set) var state: State = .awaitingLaunchConfirmation
    private var started = false
    private var sessionIsActive = false
    private var awaitingInputProof = false
    private var recoveryAttempt = 0

    var onLockdown: (() -> Void)?
    var onUnlock: (() -> Void)?
    var isUnlocked: Bool { state == .unlocked }

    init(
        observer: SessionActivityObserving,
        lease: ColorProofLeaseControlling,
        scheduler: TickScheduler,
        launchUnlockProof: LaunchSessionUnlockProofObserving? = nil,
        log: Log,
        heartbeatInterval: TimeInterval = 1,
        recoverableLeaseError: @escaping (Error) -> Bool = { error in
            guard let error = error as? KarabinerModeBridgeError else { return false }
            switch error {
            case .commandLineUnavailable, .commandLineFailed:
                return true
            case .socketPathOccupied, .systemCall:
                return false
            }
        }
    ) {
        self.observer = observer
        self.lease = lease
        self.scheduler = scheduler
        self.launchUnlockProof = launchUnlockProof ?? GlobalInputLaunchSessionUnlockProof()
        self.log = log
        self.heartbeatInterval = heartbeatInterval
        self.recoverableLeaseError = recoverableLeaseError
    }

    func start() {
        guard !started else { return }
        started = true
        state = .awaitingLaunchConfirmation
        sessionIsActive = false
        awaitingInputProof = false
        recoveryAttempt = 0
        scheduler.stop()
        launchUnlockProof.stop()
        lease.deactivate()
        launchUnlockProof.onUnlockedInput = { [weak self] in
            guard let self,
                  self.awaitingInputProof,
                  self.sessionIsActive
            else { return }
            self.markUnlocked()
        }
        observer.onSessionBecameActive = { [weak self] in self?.markUnlocked() }
        observer.onSessionResignedActive = { [weak self] in self?.markLocked() }
        observer.onSessionMayBeAvailable = { [weak self] in self?.beginUnlockProof() }
        observer.start()
        log.info("mouse command security boundary awaiting session confirmation")
    }

    /// Call from applicationDidFinishLaunching. A supervised relaunch can occur
    /// while loginwindow owns an ordinary locked session without a synchronous
    /// NSWorkspace state query, so launch remains closed until the session
    /// delivers positive global input or an explicit became-active notification.
    func confirmActiveSessionAfterLaunch() {
        guard state == .awaitingLaunchConfirmation else { return }
        beginUnlockProof()
    }

    private func beginUnlockProof() {
        guard started else { return }
        sessionIsActive = true
        awaitingInputProof = true
        guard ensureUnlockProofMonitoring() else {
            state = .locked
            log.error("could not observe unlocked-session input; mouse commands remain disabled")
            onLockdown?()
            return
        }
        log.info("mouse command security boundary awaiting unlocked-session input proof")
    }

    @discardableResult
    func ensureUnlockProofMonitoring() -> Bool {
        guard started, awaitingInputProof, state != .unlocked else { return true }
        return launchUnlockProof.start()
    }

    func markUnlocked() {
        guard started else { return }
        launchUnlockProof.stop()
        awaitingInputProof = false
        sessionIsActive = true
        attemptToUnlock()
    }

    private func attemptToUnlock() {
        guard started, sessionIsActive else { return }
        do {
            try lease.activate()
        } catch {
            failClosed(error, retryIfRecoverable: true)
            return
        }
        recoveryAttempt = 0
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
        launchUnlockProof.stop()
        sessionIsActive = false
        awaitingInputProof = false
        recoveryAttempt = 0
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
        failClosed(error, retryIfRecoverable: true)
    }

    func stop() {
        guard started else { return }
        started = false
        sessionIsActive = false
        awaitingInputProof = false
        recoveryAttempt = 0
        state = .locked
        scheduler.stop()
        launchUnlockProof.stop()
        lease.deactivate()
        observer.stop()
        observer.onSessionBecameActive = nil
        observer.onSessionResignedActive = nil
        observer.onSessionMayBeAvailable = nil
        launchUnlockProof.onUnlockedInput = nil
    }

    private func renew() {
        guard state == .unlocked else { return }
        do {
            try lease.renew()
        } catch {
            failClosed(error, retryIfRecoverable: true)
        }
    }

    private func failClosed(_ error: Error, retryIfRecoverable: Bool) {
        let changed = state != .locked
        state = .locked
        scheduler.stop()
        lease.deactivate()
        log.error("mouse command security lease failed closed: \(error)")
        if changed { onLockdown?() }
        if retryIfRecoverable,
           started,
           sessionIsActive,
           recoverableLeaseError(error) {
            scheduleRecoveryAttempt()
        }
    }

    private func scheduleRecoveryAttempt() {
        let delays: [TimeInterval] = [1, 2, 5, 10, 30]
        let delay = delays[min(recoveryAttempt, delays.count - 1)]
        recoveryAttempt += 1
        log.notice("Karabiner security lease recovery scheduled in \(delay) seconds")
        scheduler.start(interval: delay) { [weak self] in
            self?.attemptToUnlock()
        }
    }
}
