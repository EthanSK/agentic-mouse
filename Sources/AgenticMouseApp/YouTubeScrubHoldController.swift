import Foundation
import ScimitarKit

/// Distinguishes a rewind click from a temporary speed hold on the shared scrub button.
@MainActor
final class YouTubeScrubHoldController {
    static let holdThreshold: TimeInterval = 0.35

    private struct Hold {
        let started: TimeInterval
        var speedEligible: Bool
        var speedRequested = false
    }

    private let clock: MonotonicClock
    private let scheduler: TickScheduler
    private let inputAllowed: () -> Bool
    private let beginSpeed: (MouseSource) -> Void
    private let endSpeed: (MouseSource) -> Void
    private var holds: [MouseSource: Hold] = [:]

    init(
        clock: MonotonicClock = SystemMonotonicClock(),
        scheduler: TickScheduler = DispatchTickScheduler(),
        inputAllowed: @escaping () -> Bool,
        beginSpeed: @escaping (MouseSource) -> Void,
        endSpeed: @escaping (MouseSource) -> Void
    ) {
        self.clock = clock
        self.scheduler = scheduler
        self.inputAllowed = inputAllowed
        self.beginSpeed = beginSpeed
        self.endSpeed = endSpeed
    }

    func press(source: MouseSource, volumeModifierActive: Bool) {
        guard inputAllowed(), holds[source] == nil else { return }
        holds[source] = Hold(started: clock.now, speedEligible: !volumeModifierActive)
        if !scheduler.isRunning {
            scheduler.start(interval: 0.025) { [weak self] in self?.tick() }
        }
    }

    /// Wheel or volume input owns the rest of this hold, even after its modifier releases.
    func inhibitSpeed(source: MouseSource) {
        guard var hold = holds[source] else { return }
        hold.speedEligible = false
        let wasRequested = hold.speedRequested
        hold.speedRequested = false
        holds[source] = hold
        if wasRequested { endSpeed(source) }
        stopIfSettled()
    }

    /// Returns whether the ordinary click remains eligible; the wheel monitor also checks scroll use.
    func release(source: MouseSource) -> Bool {
        guard let hold = holds[source] else { return false }
        let isClick = clock.now - hold.started < Self.holdThreshold
        cancel(source: source)
        return isClick // Releasing after the threshold must not seek, even if a busy run loop delayed the timer. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
    }

    func cancel(source: MouseSource) {
        guard let hold = holds.removeValue(forKey: source) else { return }
        if hold.speedRequested { endSpeed(source) }
        stopIfSettled()
    }

    private func tick() {
        guard inputAllowed() else {
            for source in Array(holds.keys) { cancel(source: source) }
            return
        }
        for source in Array(holds.keys) {
            guard var hold = holds[source], hold.speedEligible, !hold.speedRequested,
                  clock.now - hold.started >= Self.holdThreshold else { continue }
            hold.speedRequested = true
            holds[source] = hold
            beginSpeed(source)
        }
        stopIfSettled()
    }

    private func stopIfSettled() {
        if !holds.values.contains(where: { $0.speedEligible && !$0.speedRequested }) {
            scheduler.stop()
        }
    }
}
