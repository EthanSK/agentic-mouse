import Foundation

/// Watches the four configured Living-room lights and publishes a two-zone
/// frame whenever their combined appearance actually changes.
///
/// Lifecycle:
///
///   1. **Snapshot.** One `GET /clip/v2/resource/light` establishes the full
///      state of every configured lamp. Without this, the first event delta
///      would be merged onto nothing.
///   2. **Stream.** The bridge's local SSE endpoint pushes deltas. Each delta
///      is merged over the cached state — never substituted for it, because a
///      brightness-only event carries no colour and would otherwise wash the
///      mouse white.
///   3. **Coalesce.** A fade produces dozens of events per second. They are
///      collapsed into at most one recomputation per `coalescingInterval`.
///   4. **Deduplicate.** The recomputed frame is compared with the last one
///      published; an identical frame is dropped before it ever reaches iCUE.
///   5. **Reconnect.** A dropped stream backs off and re-snapshots, because
///      state may have changed while disconnected.
///
/// Nothing here can write to a light: the only transport it holds is
/// `HueReadOnlyTransport`, which has no mutating methods.
public actor HueRoomObserver {
    public struct Configuration: Sendable {
        public var assignments: [HueLightAssignment]
        public var policy: HueMirrorPolicy
        /// Burst window for collapsing rapid fade events.
        public var coalescingInterval: TimeInterval
        /// Backoff bounds for stream reconnection.
        public var minimumReconnectDelay: TimeInterval
        public var maximumReconnectDelay: TimeInterval
        /// Safety net if the stream silently stalls.
        public var resnapshotInterval: TimeInterval

        public init(
            assignments: [HueLightAssignment],
            policy: HueMirrorPolicy = .default,
            coalescingInterval: TimeInterval = 0.08,
            minimumReconnectDelay: TimeInterval = 1,
            maximumReconnectDelay: TimeInterval = 60,
            resnapshotInterval: TimeInterval = 300
        ) {
            self.assignments = assignments
            self.policy = policy
            self.coalescingInterval = coalescingInterval
            self.minimumReconnectDelay = minimumReconnectDelay
            self.maximumReconnectDelay = maximumReconnectDelay
            self.resnapshotInterval = resnapshotInterval
        }
    }

    public enum Status: Equatable, Sendable {
        case idle
        case notConfigured
        case connecting
        case streaming
        case degradedPolling(reason: String)
        case failed(reason: String)

        public var isLive: Bool { self == .streaming }
    }

    private let transport: HueReadOnlyTransport
    private let configuration: Configuration
    private let log: Log

    private var states: [String: HueLightState] = [:]
    private var lastPublishedFrame: LightingFrame?
    private var status: Status = .idle
    private var runTask: Task<Void, Never>?
    private var coalesceTask: Task<Void, Never>?
    private var resnapshotTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval
    private var lastLitColors: [HueCluster: RGBColor] = [:]
    private var lifecycleGeneration: UInt64 = 0
    /// Actor methods are re-entrant across `await`. Deltas received while a
    /// snapshot GET is in flight are applied immediately and also replayed over
    /// the returned snapshot, so an older GET response can never erase a newer
    /// stream update.
    private var snapshotInFlight = false
    private var deltasDuringSnapshot: [HueLightDelta] = []

    /// Called on every genuinely new frame. `nil` means "nothing configured —
    /// release the layer".
    private var onFrame: (@Sendable (LightingFrame?) -> Void)?
    private var onStatus: (@Sendable (Status) -> Void)?

    /// Counters exposed for the doctor CLI and tests.
    public private(set) var eventsReceived = 0
    public private(set) var framesPublished = 0
    public private(set) var framesSuppressed = 0

    public init(transport: HueReadOnlyTransport, configuration: Configuration, log: Log) {
        self.transport = transport
        self.configuration = configuration
        self.log = log
        self.reconnectDelay = Self.positiveDelay(configuration.minimumReconnectDelay, fallback: 1)
    }

    // MARK: - Control

    public func setHandlers(
        onFrame: @escaping @Sendable (LightingFrame?) -> Void,
        onStatus: @escaping @Sendable (Status) -> Void
    ) {
        self.onFrame = onFrame
        self.onStatus = onStatus
    }

    public func start() {
        guard runTask == nil else { return }

        let configured = configuration.assignments.filter { !$0.isPlaceholder }
        guard !configured.isEmpty else {
            updateStatus(.notConfigured)
            onFrame?(nil)
            return
        }

        lifecycleGeneration &+= 1
        runTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    public func stop() {
        lifecycleGeneration &+= 1
        runTask?.cancel()
        runTask = nil
        coalesceTask?.cancel()
        coalesceTask = nil
        resnapshotTask?.cancel()
        resnapshotTask = nil
        updateStatus(.idle)
        // Releasing the layer on stop is what makes "quit the helper" and
        // "unplug the bridge" produce the same, predictable mouse.
        publish(nil, force: true)
        states.removeAll()
        lastLitColors.removeAll()
        snapshotInFlight = false
        deltasDuringSnapshot.removeAll()
    }

    public var currentStatus: Status { status }
    public var currentFrame: LightingFrame? { lastPublishedFrame }
    public var currentStates: [String: HueLightState] { states }

    // MARK: - Main loop

    private func runLoop() async {
        while !Task.isCancelled {
            updateStatus(.connecting)

            do {
                try await refreshSnapshot()
                reconnectDelay = Self.positiveDelay(configuration.minimumReconnectDelay, fallback: 1)
                updateStatus(.streaming)

                startResnapshotLoop()
                defer {
                    resnapshotTask?.cancel()
                    resnapshotTask = nil
                }

                for try await payload in transport.eventStream() {
                    if Task.isCancelled { return }
                    ingest(payload)
                }
                // A clean end of stream is still a disconnect.
                throw HueTransportError.streamEnded
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                let description = Self.describe(error)
                updateStatus(.failed(reason: description))
                log.notice("Hue stream unavailable (\(description)); retrying in \(Int(reconnectDelay))s")

                // While the bridge is unreachable the mouse must not keep
                // showing a stale room. Invalidate before cancelling: an
                // already-awake coalescing task may be queued on this actor and
                // must not repaint its cached frame after the release.
                lifecycleGeneration &+= 1
                coalesceTask?.cancel()
                coalesceTask = nil
                publish(nil, force: true)

                try? await Task.sleep(nanoseconds: Self.nanoseconds(reconnectDelay))
                let maximum = Self.positiveDelay(configuration.maximumReconnectDelay, fallback: 60)
                reconnectDelay = min(maximum, max(0.05, reconnectDelay * 2))
            }
        }
    }

    /// Full read of every configured lamp.
    private func refreshSnapshot() async throws {
        guard !snapshotInFlight else { return }
        snapshotInFlight = true
        deltasDuringSnapshot.removeAll(keepingCapacity: true)

        do {
            let data = try await transport.get(resourcePath: "light")
            try Task.checkCancellation()
            let parsed = try HueWireFormat.parseLightStates(data)

            let wanted = configuredIdentifiers
            var snapshot: [String: HueLightState] = [:]
            for state in parsed where wanted.contains(state.identifier) {
                snapshot[state.identifier] = state
            }

            let missing = wanted.subtracting(snapshot.keys)
            if !missing.isEmpty {
                log.notice("\(missing.count) configured light(s) were not found on the bridge; those zones stay dark")
            }

            // Capture and clear before assigning. No other actor-isolated code
            // can interleave until the next await, so this replacement plus
            // replay is atomic with respect to `ingest`.
            let newerDeltas = deltasDuringSnapshot
            deltasDuringSnapshot.removeAll(keepingCapacity: true)
            snapshotInFlight = false
            states = snapshot
            merge(newerDeltas, countEvents: false)
            recompute(immediately: true)
        } catch {
            snapshotInFlight = false
            deltasDuringSnapshot.removeAll(keepingCapacity: true)
            throw error
        }
    }

    /// Merges one SSE payload.
    private func ingest(_ payload: Data) {
        let deltas = HueWireFormat.parseEventDeltas(payload)
        guard !deltas.isEmpty else { return }

        let relevant = deltas.filter { configuredIdentifiers.contains($0.identifier) }
        guard !relevant.isEmpty else { return }
        if snapshotInFlight {
            deltasDuringSnapshot.append(contentsOf: relevant)
        }
        merge(relevant, countEvents: true)
    }

    private var configuredIdentifiers: Set<String> {
        Set(configuration.assignments.filter { !$0.isPlaceholder }.map(\.resourceIdentifier))
    }

    /// Applies already-filtered stream deltas. Replayed snapshot-race deltas
    /// are not counted twice.
    private func merge(_ deltas: [HueLightDelta], countEvents: Bool) {
        var touched = false
        for delta in deltas {
            let baseline = states[delta.identifier] ?? HueLightState(
                identifier: delta.identifier,
                // Missing snapshot data fails dark. A later on-state delta or
                // periodic snapshot fills in the authoritative value.
                isOn: false
            )
            let merged = baseline.merging(delta)
            if merged != states[delta.identifier] {
                states[delta.identifier] = merged
                touched = true
            }
            if countEvents { eventsReceived += 1 }
        }

        guard touched else { return }
        recompute(immediately: false)
    }

    /// Recomputes the two-zone frame, optionally after a short coalescing
    /// window so a fade does not produce one iCUE write per event.
    private func recompute(immediately: Bool) {
        guard !immediately else {
            publish(currentComputedFrame(), force: false)
            return
        }

        guard coalesceTask == nil else { return }
        let interval = configuration.coalescingInterval
        guard interval.isFinite, interval > 0 else {
            flushCoalesced()
            return
        }
        let generation = lifecycleGeneration
        coalesceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.nanoseconds(interval))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.flushCoalesced(generation: generation)
        }
    }

    private func flushCoalesced(generation: UInt64? = nil) {
        if let generation, generation != lifecycleGeneration { return }
        coalesceTask = nil
        publish(currentComputedFrame(), force: false)
    }

    private func currentComputedFrame() -> LightingFrame? {
        for cluster in HueCluster.allCases {
            if let color = HueClusterAggregator.color(
                for: cluster,
                assignments: configuration.assignments,
                states: states,
                policy: configuration.policy
            ) {
                lastLitColors[cluster] = color
            }
        }
        return HueClusterAggregator.frame(
            assignments: configuration.assignments,
            states: states,
            policy: configuration.policy,
            lastLitColors: lastLitColors
        )
    }

    private func startResnapshotLoop() {
        let interval = configuration.resnapshotInterval
        guard interval.isFinite, interval > 0 else { return }
        resnapshotTask?.cancel()
        resnapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.nanoseconds(interval))
                guard !Task.isCancelled, let self else { return }
                do {
                    try await self.refreshSnapshot()
                } catch is CancellationError {
                    return
                } catch {
                    await self.logResnapshotFailure(error)
                }
            }
        }
    }

    private func logResnapshotFailure(_ error: Error) {
        log.notice("periodic Hue snapshot failed (\(Self.describe(error))); keeping the event stream alive")
    }

    private static func positiveDelay(_ value: TimeInterval, fallback: TimeInterval) -> TimeInterval {
        value.isFinite && value > 0 ? value : fallback
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return UInt64(min(seconds * 1_000_000_000, Double(UInt64.max)))
    }

    /// Publishes only when the frame is genuinely different.
    private func publish(_ frame: LightingFrame?, force: Bool) {
        if !force, frame == lastPublishedFrame {
            framesSuppressed += 1
            return
        }
        lastPublishedFrame = frame
        framesPublished += 1
        onFrame?(frame)
    }

    private func updateStatus(_ newStatus: Status) {
        guard newStatus != status else { return }
        status = newStatus
        onStatus?(newStatus)
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case HueTransportError.unauthorised:
            return "the bridge rejected the application key"
        case HueTransportError.notConfigured(let reason):
            return reason
        case HueTransportError.http(let code):
            return "HTTP \(code)"
        case HueTransportError.streamEnded:
            return "the event stream closed"
        case HueTransportError.network(let reason):
            return reason
        default:
            return "unexpected error"
        }
    }
}
