import Foundation
import ScimitarKit

/// Routes reconstructed "Magnet" wheel detents without artificial pacing.
/// The built-in WindowSnapController already serializes actual AX work.
/// Ethan accepted restoration on 2026-11-07 and asked to remove obsolete
/// measures: the old 400 ms pause was for third-party Magnet's animations.
/// Explicit timing remains injectable for the legacy shortcut route's tests.
@MainActor
final class MagnetWheelActionSequencer {
    struct Request: Equatable {
        let action: ModeUtilityAction
        let source: MouseSource
        let detentCount: Int
    }

    typealias Performer = @MainActor (Request) -> Void
    typealias InputAllowedProvider = @MainActor () -> Bool
    typealias Scheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @Sendable @MainActor () -> Void
    ) -> Void

    nonisolated static let defaultMinimumInterval: TimeInterval = 0
    nonisolated static let defaultMaximumPendingCount = 3

    private let minimumInterval: TimeInterval
    private let maximumPendingCount: Int
    private let perform: Performer
    private let inputAllowed: InputAllowedProvider
    private let schedule: Scheduler
    private var pending: [Request] = []
    private var isCoolingDown = false
    private var generation: UInt64 = 0

    init(
        minimumInterval: TimeInterval = defaultMinimumInterval,
        maximumPendingCount: Int = defaultMaximumPendingCount,
        perform: @escaping Performer,
        inputAllowed: @escaping InputAllowedProvider = { true },
        schedule: @escaping Scheduler = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    ) {
        self.minimumInterval = max(0, minimumInterval)
        self.maximumPendingCount = max(0, maximumPendingCount)
        self.perform = perform
        self.inputAllowed = inputAllowed
        self.schedule = schedule
    }

    var pendingCount: Int { pending.count }

    @discardableResult
    func enqueue(_ request: Request) -> Bool {
        guard inputAllowed() else {
            cancelAll()
            return false
        }
        guard !isCoolingDown || pending.count < maximumPendingCount else {
            return false
        }
        pending.append(request)
        drainIfReady()
        return true
    }

    func cancel(source: MouseSource) {
        pending.removeAll { $0.source == source }
    }

    func cancelAll() {
        generation &+= 1
        pending.removeAll()
        isCoolingDown = false
    }

    private func drainIfReady() {
        guard !isCoolingDown, !pending.isEmpty else { return }
        guard inputAllowed() else {
            cancelAll()
            return
        }

        let request = pending.removeFirst()
        perform(request)
        // No timer, extra main-queue turn or backlog for the custom backend.
        guard minimumInterval > 0 else { return }
        isCoolingDown = true
        let currentGeneration = generation
        schedule(minimumInterval) { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            self.isCoolingDown = false
            self.drainIfReady()
        }
    }
}
