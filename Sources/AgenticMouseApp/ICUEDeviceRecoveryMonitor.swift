import Foundation
import ScimitarKit

/// Polls the already-connected iCUE session for device-presence transitions.
///
/// iCUE's device callback is the fast path, but some Slipstream receiver
/// re-plugs do not produce one. This monitor is the bounded fallback: it emits
/// only real state transitions, so idle white is reasserted once after recovery
/// rather than repainting the mouse on every poll.
struct ICUEDevicePresenceSnapshot: Equatable {
    var identifier: String?
    var lightingAvailable: Bool

    static let absent = ICUEDevicePresenceSnapshot(identifier: nil, lightingAvailable: false)
}

enum ICUEDevicePresenceTransition: Equatable {
    case lost(previousIdentifier: String)
    case recovered(ICUEDevicePresenceSnapshot)
    case replaced(previousIdentifier: String, current: ICUEDevicePresenceSnapshot)
    case lightingUnavailable(ICUEDevicePresenceSnapshot)
}

@MainActor
final class ICUEDeviceRecoveryMonitor {
    private let scheduler: TickScheduler
    private let interval: TimeInterval
    private let probe: () -> ICUEDevicePresenceSnapshot
    private let onTransition: (ICUEDevicePresenceTransition) -> Void
    private var snapshot: ICUEDevicePresenceSnapshot

    init(
        initialSnapshot: ICUEDevicePresenceSnapshot,
        scheduler: TickScheduler,
        interval: TimeInterval = 2,
        probe: @escaping () -> ICUEDevicePresenceSnapshot,
        onTransition: @escaping (ICUEDevicePresenceTransition) -> Void
    ) {
        self.snapshot = initialSnapshot
        self.scheduler = scheduler
        self.interval = interval
        self.probe = probe
        self.onTransition = onTransition
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

    /// Keeps the fallback poller aligned with a real iCUE callback so the same
    /// transition is not processed twice.
    func synchronize(_ current: ICUEDevicePresenceSnapshot) {
        snapshot = current
    }

    private func tick() {
        let previous = snapshot
        let current = probe()
        guard current != previous else { return }
        snapshot = current

        switch (previous.identifier, current.identifier) {
        case let (.some(old), .none):
            onTransition(.lost(previousIdentifier: old))
        case (.none, .some):
            onTransition(.recovered(current))
        case let (.some(old), .some(new)) where old != new:
            onTransition(.replaced(previousIdentifier: old, current: current))
        case (.some, .some) where !previous.lightingAvailable && current.lightingAvailable:
            onTransition(.recovered(current))
        case (.some, .some) where previous.lightingAvailable && !current.lightingAvailable:
            onTransition(.lightingUnavailable(current))
        default:
            break
        }
    }
}
