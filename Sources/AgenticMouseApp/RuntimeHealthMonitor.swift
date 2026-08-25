import Foundation
import ScimitarKit

/// Re-checks the two runtime transports that can be absent briefly at login or
/// invalidated later by Karabiner/Accessibility without terminating the app.
@MainActor
final class RuntimeHealthMonitor {
    private let scheduler: TickScheduler
    private let interval: TimeInterval
    private let check: () -> Void
    private(set) var isStarted = false

    init(
        scheduler: TickScheduler,
        interval: TimeInterval = 2,
        check: @escaping () -> Void
    ) {
        self.scheduler = scheduler
        self.interval = interval
        self.check = check
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        check()
        scheduler.start(interval: interval) { [weak self] in
            guard let self, self.isStarted else { return }
            self.check()
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        scheduler.stop()
    }

    deinit { scheduler.stop() }
}
