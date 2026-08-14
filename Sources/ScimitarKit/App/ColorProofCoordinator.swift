import Foundation

public protocol ColorProofLeaseControlling: AnyObject {
    func activate() throws
    func renew() throws
    func deactivate()
}

public enum ColorProofExitReason: Equatable, Sendable {
    case userRequested
    case idleTimeout
    case absoluteTimeout
    case leaseFailure(String)
    case deviceLost
    case systemSleep
    case shuttingDown

    public var isFailure: Bool {
        switch self {
        case .userRequested, .idleTimeout, .absoluteTimeout, .shuttingDown: return false
        case .leaseFailure, .deviceLost, .systemSleep: return true
        }
    }

    public var explanation: String {
        switch self {
        case .userRequested: return "Colour proof off."
        case .idleTimeout: return "Colour proof timed out."
        case .absoluteTimeout: return "Colour proof reached its safety limit."
        case .leaseFailure(let detail): return "Colour proof ended: \(detail)"
        case .deviceLost: return "Colour proof ended: the active mouse disconnected."
        case .systemSleep: return "Colour proof ended before sleep."
        case .shuttingDown: return "Colour proof ended: quitting."
        }
    }
}

/// Owns the small twelve-colour demonstration without changing multi-tap.
///
/// Karabiner holds only an expiring routing lease. This coordinator renews it
/// while the HUD is alive and clears it through one teardown path. If the app
/// dies, the absolute Karabiner expiry restores the ordinary base mappings.
public final class ColorProofCoordinator {
    public private(set) var isActive = false
    public private(set) var source: MouseSource?
    public private(set) var selection: ColorProofSwatch?
    public private(set) var lightingTargets: ModeLightingTargets = []
    public private(set) var isHUDVisible = false
    public var reservedHUDPendingSource: MouseSource? { reservedHUDGesture.pendingSource }

    public var lightingAvailable: Bool { !lightingTargets.isEmpty }

    private let lease: ColorProofLeaseControlling
    private let hud: ModeHUDPresenting
    private let clock: MonotonicClock
    private let scheduler: TickScheduler
    private let reservedHUDGesture: ReservedModeHUDGesture
    private let log: Log
    private let idleTimeout: TimeInterval
    private let absoluteTimeout: TimeInterval
    private let heartbeatInterval: TimeInterval

    private var enteredAt: TimeInterval = 0
    private var lastInputAt: TimeInterval = 0
    private var activationGeneration: UInt64 = 0

    /// Returns every RGB adapter that accepted the colour. An empty result
    /// means the universal HUD remains the sole indicator.
    public var onColorChange: ((RGBColor?) -> ModeLightingTargets)?
    public var onModeChange: ((Bool) -> Void)?
    public var onExit: ((ColorProofExitReason) -> Void)?

    public init(
        lease: ColorProofLeaseControlling,
        hud: ModeHUDPresenting,
        clock: MonotonicClock,
        scheduler: TickScheduler,
        reservedHUDScheduler: TickScheduler = DispatchTickScheduler(),
        log: Log,
        idleTimeout: TimeInterval = 0,
        absoluteTimeout: TimeInterval = 0,
        heartbeatInterval: TimeInterval = 2
    ) {
        self.lease = lease
        self.hud = hud
        self.clock = clock
        self.scheduler = scheduler
        self.reservedHUDGesture = ReservedModeHUDGesture(
            clock: clock,
            scheduler: reservedHUDScheduler
        )
        self.log = log
        self.idleTimeout = idleTimeout
        self.absoluteTimeout = absoluteTimeout
        self.heartbeatInterval = heartbeatInterval
    }

    deinit {
        if isActive { forceExit(reason: .shuttingDown) }
    }

    public func handle(_ command: ColorProofCommand) {
        switch command.action {
        case .enter:
            guard !isActive else { return }
            enter(source: command.source, cell: command.physicalCell)
        case .select:
            guard isActive else {
                // A delayed select from an old Karabiner lease must shorten,
                // never extend, a hidden routing state after app restart.
                lease.deactivate()
                return
            }
            if command.physicalCell == .modeHUDToggle {
                handleReservedHUDPress(source: command.source, cell: command.physicalCell)
            } else {
                reservedHUDGesture.commitPendingSinglePress()
                guard isActive else { return }
                select(source: command.source, cell: command.physicalCell)
            }
        case .exit:
            guard isActive else {
                lease.deactivate()
                return
            }
            forceExit(reason: .userRequested)
        }
    }

    @discardableResult
    public func enter(source: MouseSource, cell: PhysicalCell) -> Bool {
        guard !isActive else { return true }
        do {
            try lease.activate()
        } catch {
            let message = "Karabiner mode lease unavailable: \(error)"
            log.notice(message)
            hud.flashProblem(message)
            return false
        }

        activationGeneration &+= 1
        isActive = true
        enteredAt = clock.now
        lastInputAt = clock.now
        self.source = source
        selection = ColorProofPalette.swatch(for: cell)
        // Clear another runtime mode before painting the first proof colour;
        // otherwise its lighting teardown can erase a successfully written
        // entry colour while the HUD claims RGB is active.
        onModeChange?(true)
        lightingTargets = onColorChange?(selection?.color) ?? []

        isHUDVisible = true
        hud.show(snapshot())
        scheduler.start(interval: heartbeatInterval) { [weak self] in self?.tick() }
        log.info("colour proof ON from \(source.displayName) cell \(cell.rawValue)")
        return true
    }

    public func select(source: MouseSource, cell: PhysicalCell) {
        guard isActive else { return }
        lastInputAt = clock.now
        self.source = source
        selection = ColorProofPalette.swatch(for: cell)
        lightingTargets = onColorChange?(selection?.color) ?? []
        if isHUDVisible { hud.update(snapshot()) }
    }

    public func exit(reason: ColorProofExitReason = .userRequested) {
        guard isActive else {
            lease.deactivate()
            return
        }
        forceExit(reason: reason)
    }

    public func handleDeviceLost(_ source: MouseSource) {
        guard isActive, self.source == source else { return }
        forceExit(reason: .deviceLost)
    }

    public func handleSystemSleep() {
        guard isActive else { return }
        forceExit(reason: .systemSleep)
    }

    public func refreshLightingAvailability() {
        guard isActive, let selection else { return }
        lightingTargets = onColorChange?(selection.color) ?? []
        if isHUDVisible { hud.update(snapshot()) }
    }

    public func handleLightingUnavailable(_ targets: ModeLightingTargets) {
        guard isActive else { return }
        lightingTargets.subtract(targets)
        if isHUDVisible { hud.update(snapshot()) }
    }

    public func shutdown() {
        forceExit(reason: .shuttingDown)
    }

    private func tick() {
        guard isActive else { return }
        let generation = activationGeneration
        let now = clock.now

        if idleTimeout > 0, now - lastInputAt >= idleTimeout {
            forceExit(reason: .idleTimeout)
            return
        }
        if absoluteTimeout > 0, now - enteredAt >= absoluteTimeout {
            forceExit(reason: .absoluteTimeout)
            return
        }

        do {
            try lease.renew()
        } catch {
            forceExit(reason: .leaseFailure("could not renew Karabiner routing"))
            return
        }

        guard generation == activationGeneration, isActive else { return }
        if isHUDVisible { hud.update(snapshot()) }
    }

    /// Physical cell 3 is reserved across mode legends: one press
    /// keeps the mode action, while two same-mouse presses show or hide the HUD.
    public func handleReservedHUDPress(source: MouseSource, cell: PhysicalCell) {
        guard isActive, cell == .modeHUDToggle else { return }
        reservedHUDGesture.handlePress(
            source: source,
            singlePress: { [weak self] in self?.select(source: source, cell: cell) },
            doublePress: { [weak self] in self?.toggleHUD(source: source) }
        )
    }

    private func toggleHUD(source: MouseSource) {
        guard isActive else { return }
        self.source = source
        if isHUDVisible {
            isHUDVisible = false
            hud.hide()
            log.info("colour proof legend hidden from \(source.displayName) top-left double-click")
        } else {
            isHUDVisible = true
            hud.show(snapshot())
            log.info("colour proof legend shown from \(source.displayName) top-left double-click")
        }
    }

    private func forceExit(reason: ColorProofExitReason) {
        let wasActive = isActive
        isActive = false
        activationGeneration &+= 1
        scheduler.stop()
        reservedHUDGesture.cancel()
        lease.deactivate()
        _ = onColorChange?(nil)
        hud.hide()
        isHUDVisible = false
        source = nil
        selection = nil
        lightingTargets = []

        guard wasActive else { return }
        onModeChange?(false)
        onExit?(reason)
        if reason.isFailure {
            log.notice(reason.explanation)
            hud.flashProblem(reason.explanation)
        } else {
            log.info(reason.explanation)
        }
    }

    private func snapshot(problem: String? = nil) -> ModeHUDSnapshot {
        let swatch = selection ?? ColorProofPalette.swatch(for: PhysicalCell(rawValue: 1)!)
        return ModeHUDSnapshot(
            isActive: isActive,
            modeTitle: "Colour Proof",
            source: source ?? .corsair,
            selection: ModeHUDSelection(
                cell: swatch.cell,
                title: swatch.name,
                detail: swatch.color.hexString,
                accent: swatch.color
            ),
            legend: ColorProofPalette.legend,
            accent: swatch.color,
            lightingTargets: lightingTargets,
            footerTitle: "\(swatch.name) · \(swatch.color.hexString)",
            footerHint: "Double-click C12 or R10 to hide/show · press C\(PhysicalCell.colorProofEntry.printedSide(on: .corsair)!) or R\(PhysicalCell.colorProofEntry.printedSide(on: .razer)!) to exit",
            problem: problem,
            showsOnAllDisplays: true
        )
    }
}
