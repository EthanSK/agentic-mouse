import Foundation
import ScimitarKit

/// Reacquires the exact Naga lighting transport after a USB reconnect.
///
/// The presence probe is read-only. Stable connected polls do nothing; an
/// absent-to-present transition retries the idle frame until the device is
/// actually writable, then stays quiet until the next physical transition.
@MainActor
final class RazerDeviceRecoveryMonitor {
    private let scheduler: TickScheduler
    private let interval: TimeInterval
    private let probePresence: () -> Bool
    private let recover: () -> Bool
    private let onLost: () -> Void
    private let onRecovered: () -> Void

    private var isPresent: Bool
    private var isRecovered: Bool

    init(
        initiallyPresent: Bool,
        initiallyRecovered: Bool,
        scheduler: TickScheduler,
        interval: TimeInterval = 2,
        probePresence: @escaping () -> Bool,
        recover: @escaping () -> Bool,
        onLost: @escaping () -> Void,
        onRecovered: @escaping () -> Void
    ) {
        self.isPresent = initiallyPresent
        self.isRecovered = initiallyPresent && initiallyRecovered
        self.scheduler = scheduler
        self.interval = interval
        self.probePresence = probePresence
        self.recover = recover
        self.onLost = onLost
        self.onRecovered = onRecovered
    }

    var isRunning: Bool { scheduler.isRunning }

    func start() {
        scheduler.start(interval: interval) { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        scheduler.stop()
    }

    /// Re-seeds the monitor after sleep/wake without manufacturing a second
    /// transition from the explicit wake recovery that just ran.
    func synchronize(present: Bool, recovered: Bool) {
        isPresent = present
        isRecovered = present && recovered
    }

    private func tick() {
        let presentNow = probePresence()
        guard presentNow else {
            if isPresent {
                onLost()
            }
            isPresent = false
            isRecovered = false
            return
        }

        if !isPresent {
            isPresent = true
            isRecovered = false
        }

        guard !isRecovered else { return }
        guard recover() else { return }
        isRecovered = true
        onRecovered()
    }
}
