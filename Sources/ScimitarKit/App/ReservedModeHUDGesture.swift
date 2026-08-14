import Foundation

/// Classifies the reserved physical-cell-3 legend gesture for legacy modes.
///
/// A single press keeps the mode's existing cell action after one bounded
/// decision window. Two presses from the same mouse call the HUD toggle
/// instead. Presses from different mice never combine into one gesture.
public final class ReservedModeHUDGesture {
    public private(set) var pendingSource: MouseSource?

    private struct PendingPress {
        let source: MouseSource
        let pressedAt: TimeInterval
        let singlePress: () -> Void
    }

    private let clock: MonotonicClock
    private let scheduler: TickScheduler
    private let doubleClickInterval: TimeInterval
    private var pending: PendingPress?

    public init(
        clock: MonotonicClock,
        scheduler: TickScheduler,
        doubleClickInterval: TimeInterval = 0.34
    ) {
        self.clock = clock
        self.scheduler = scheduler
        self.doubleClickInterval = max(0.15, doubleClickInterval)
    }

    public func handlePress(
        source: MouseSource,
        shouldAcceptNewPress: () -> Bool = { true },
        singlePress: @escaping () -> Void,
        doublePress: @escaping () -> Void
    ) {
        if let pending {
            let withinWindow = clock.now - pending.pressedAt <= doubleClickInterval
            if pending.source == source, withinWindow {
                scheduler.stop()
                self.pending = nil
                pendingSource = nil
                doublePress()
                return
            }

            commitPendingSinglePress()
            guard shouldAcceptNewPress() else { return }
        }

        pending = PendingPress(
            source: source,
            pressedAt: clock.now,
            singlePress: singlePress
        )
        pendingSource = source
        scheduler.start(interval: doubleClickInterval) { [weak self] in
            self?.commitPendingSinglePress()
        }
    }

    /// Runs a pending ordinary cell action before another non-reserved input.
    public func commitPendingSinglePress() {
        scheduler.stop()
        guard let pending else { return }
        self.pending = nil
        pendingSource = nil
        pending.singlePress()
    }

    /// Drops a pending gesture when its owning mode exits or loses the grid.
    public func cancel() {
        scheduler.stop()
        pending = nil
        pendingSource = nil
    }
}
