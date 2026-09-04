import Foundation
import ScimitarKit

/// Owns the physical lifetime of Chrome mode's YouTube 2× hold and sticky lock.
///
/// Agentic Mouse renews a short browser-side lease while either exact mouse is
/// physically held or a same-source double-click has locked the rate. Ordinary
/// release and teardown restore the exact prior rate. A second same-source
/// double-click explicitly requests 1×. If any end is lost, the extension's
/// lease still restores the exact prior rate.
@MainActor
final class ChromeYouTubeSpeedHoldController {
    enum Event: Equatable {
        case begin
        case renew
        case end
    }

    static let beginNotification = Notification.Name(
        "com.ethansk.agenticmouse.youtube.doubleSpeedHoldBegan"
    )
    static let renewNotification = Notification.Name(
        "com.ethansk.agenticmouse.youtube.doubleSpeedHoldRenewed"
    )
    static let endNotification = Notification.Name(
        "com.ethansk.agenticmouse.youtube.doubleSpeedHoldEnded"
    )
    static let tokenKey = "holdToken"
    static let restorePlaybackRateKey = "restorePlaybackRate"
    static let normalPlaybackRate = 1.0

    typealias Notifier = @MainActor (Notification.Name, String, Double?) -> Bool
    typealias InputAllowedProvider = @MainActor () -> Bool
    typealias TokenProvider = @MainActor () -> String
    typealias StickyLockChangeHandler = @MainActor (MouseSource, Bool) -> Void

    private let scheduler: TickScheduler
    private let notify: Notifier
    private let inputAllowed: InputAllowedProvider
    private let makeToken: TokenProvider
    private let clock: MonotonicClock
    private let renewalInterval: TimeInterval
    private let doubleClickInterval: TimeInterval
    private var heldSources: Set<MouseSource> = []
    private var pressStartedAt: [MouseSource: TimeInterval] = [:]
    private var lastShortReleaseAt: [MouseSource: TimeInterval] = [:]
    private var suppressedDoubleClickReleases: Set<MouseSource> = []
    private var token: String?
    private var stickyLockSource: MouseSource?

    var onStickyLockChange: StickyLockChangeHandler?

    var isStickyLocked: Bool { stickyLockSource != nil }

    init(
        scheduler: TickScheduler = DispatchTickScheduler(),
        clock: MonotonicClock = SystemMonotonicClock(),
        renewalInterval: TimeInterval = 0.75,
        doubleClickInterval: TimeInterval = 0.34,
        notify: @escaping Notifier = ChromeYouTubeSpeedHoldController.post,
        inputAllowed: @escaping InputAllowedProvider = { true },
        makeToken: @escaping TokenProvider = { UUID().uuidString }
    ) {
        self.scheduler = scheduler
        self.clock = clock
        self.renewalInterval = renewalInterval
        self.doubleClickInterval = max(0.15, doubleClickInterval)
        self.notify = notify
        self.inputAllowed = inputAllowed
        self.makeToken = makeToken
    }

    @discardableResult
    func handle(source: MouseSource, phase: ModePickerCommand.Phase) -> Bool {
        switch phase {
        case .press:
            return press(source: source)
        case .release:
            release(source: source)
            return true
        }
    }

    @discardableResult
    func press(source: MouseSource) -> Bool {
        guard inputAllowed() else { return false }
        guard pressStartedAt[source] == nil else { return true }

        let now = clock.now
        pressStartedAt[source] = now

        if let previousRelease = lastShortReleaseAt[source],
           now - previousRelease <= doubleClickInterval {
            lastShortReleaseAt[source] = nil
            suppressedDoubleClickReleases.insert(source)

            if isStickyLocked {
                end(restorePlaybackRate: Self.normalPlaybackRate)
                onStickyLockChange?(source, false)
                return true
            }

            guard token == nil, heldSources.isEmpty else {
                suppressedDoubleClickReleases.remove(source)
                return beginMomentaryHold(source: source)
            }
            guard beginLease() else {
                return false
            }
            stickyLockSource = source
            onStickyLockChange?(source, true)
            return true
        }

        lastShortReleaseAt[source] = nil
        if isStickyLocked {
            return true
        }

        return beginMomentaryHold(source: source)
    }

    /// Shares the lease with Default's long hold without seeding Chrome's sticky double-click.
    func beginMomentaryHold(source: MouseSource) -> Bool {
        guard inputAllowed() else { return false }
        guard heldSources.insert(source).inserted else { return true }
        guard token == nil else { return true }

        guard beginLease() else {
            heldSources.remove(source)
            return false
        }
        return true
    }

    func release(source: MouseSource) {
        let releasedAt = clock.now
        let startedAt = pressStartedAt.removeValue(forKey: source)

        if suppressedDoubleClickReleases.remove(source) != nil {
            return
        }

        if let startedAt, releasedAt - startedAt <= doubleClickInterval {
            lastShortReleaseAt[source] = releasedAt
        } else {
            lastShortReleaseAt[source] = nil
        }

        if isStickyLocked {
            return
        }

        heldSources.remove(source)
        guard heldSources.isEmpty else { return }
        end()
    }

    func cancel(source: MouseSource) {
        pressStartedAt[source] = nil
        lastShortReleaseAt[source] = nil
        suppressedDoubleClickReleases.remove(source)
        heldSources.remove(source)

        if stickyLockSource == source {
            end()
        } else if heldSources.isEmpty, !isStickyLocked {
            end()
        }
    }

    func cancelAll() {
        pressStartedAt.removeAll()
        lastShortReleaseAt.removeAll()
        suppressedDoubleClickReleases.removeAll()
        heldSources.removeAll()
        end()
    }

    private func beginLease() -> Bool {
        let token = makeToken()
        self.token = token
        guard notify(Self.beginNotification, token, nil) else {
            self.token = nil
            return false
        }
        scheduler.start(interval: renewalInterval) { [weak self] in
            self?.renew()
        }
        return true
    }

    private func renew() {
        guard inputAllowed(), (!heldSources.isEmpty || isStickyLocked), let token else {
            cancelAll()
            return
        }
        _ = notify(Self.renewNotification, token, nil)
    }

    private func end(restorePlaybackRate: Double? = nil) {
        scheduler.stop()
        guard let token else { return }
        self.token = nil
        stickyLockSource = nil
        heldSources.removeAll()
        _ = notify(Self.endNotification, token, restorePlaybackRate)
    }

    private static func post(
        name: Notification.Name,
        token: String,
        restorePlaybackRate: Double?
    ) -> Bool {
        var userInfo: [String: Any] = [tokenKey: token]
        if let restorePlaybackRate {
            userInfo[restorePlaybackRateKey] = restorePlaybackRate
        }
        DistributedNotificationCenter.default().postNotificationName(
            name,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
        return true
    }
}
