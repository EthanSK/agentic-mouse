import Foundation

public enum ModePickerPage: Int, Equatable, Sendable {
    case modes = 1
    case keys = 2
    case appSelector = 3
    case appSpecific = 4
    case keypad = 5
}

public enum ModePickerExitReason: Equatable, Sendable {
    case userRequested
    case leaseFailure
    case deviceLost
    case systemSleep
    case shuttingDown
}

public struct AppSpecificModeDefinition: Equatable, Sendable {
    public let title: String
    public let footerTitle: String
    public let footerHint: String?
    public let accent: RGBColor
    public let legend: [ModeHUDLegendItem]

    public init(
        title: String,
        footerTitle: String,
        footerHint: String? = nil,
        accent: RGBColor,
        legend: [ModeHUDLegendItem]
    ) {
        self.title = title
        self.footerTitle = footerTitle
        self.footerHint = footerHint
        self.accent = accent
        self.legend = legend
    }
}

/// Owns one fail-closed, exact-device Modes lease. AppDelegate creates one
/// instance per mouse so the left and right HUDs can coexist independently.
/// Physical cell 10 is the universal active-mode exit. Active-mode legends stay
/// visible for the lifetime of their mode; no action cell is spent hiding them.
public final class ModePickerCoordinator {
    public static let accent = RGBColor(red: 164, green: 48, blue: 255)
    public static let keypadAccent = RGBColor(red: 255, green: 0, blue: 174)
    public static let appSpecificAccent = RGBColor(red: 0, green: 132, blue: 255)
    public static let keysAccent = RGBColor(red: 255, green: 92, blue: 0)

    public private(set) var isActive = false
    public private(set) var isLegendVisible = false
    public private(set) var source: MouseSource?
    public private(set) var lightingTargets: ModeLightingTargets = []
    public private(set) var page: ModePickerPage = .modes
    public private(set) var navigationPath: [ModePickerPage] = []
    public private(set) var appSpecificDefinition: AppSpecificModeDefinition?
    public private(set) var appSpecificTarget: AppSpecificTarget?

    private let lease: ColorProofLeaseControlling
    private let hud: ModeHUDPresenting
    private let scheduler: TickScheduler
    private let log: Log
    private let heartbeatInterval: TimeInterval

    public var onAppearanceChange: ((RGBColor?, RGBColor?) -> ModeLightingTargets)?
    public var onModeChange: ((Bool) -> Void)?
    public var onKeypadModeRequested: ((MouseSource) -> Bool)?
    public var onKeypadInput: ((MouseSource, PhysicalCell, ModePickerCommand.Phase) -> Void)?
    public var onAppSpecificInput: ((MouseSource, AppSpecificTarget, PhysicalCell) -> Bool)?
    public var resolveFrontmostApp: (() -> FrontmostAppModeContext)?
    public var onUtilityAction: ((MouseSource, ModeUtilityAction) -> Bool)?
    public var onKeysInput: ((MouseSource, KeysModeAction) -> Bool)?
    private var lastSelection: ModeHUDSelection?
    private var followsFrontmostApp = false

    public init(
        lease: ColorProofLeaseControlling,
        hud: ModeHUDPresenting,
        scheduler: TickScheduler,
        reservedHUDScheduler: TickScheduler = DispatchTickScheduler(),
        log: Log,
        heartbeatInterval: TimeInterval = 2
    ) {
        self.lease = lease
        self.hud = hud
        self.scheduler = scheduler
        self.log = log
        self.heartbeatInterval = heartbeatInterval
        _ = reservedHUDScheduler // retained for source compatibility
    }

    public func handle(_ command: ModePickerCommand) {
        switch command.action {
        case .open:
            guard command.phase == .press else { return }
            enter(source: command.source)
        case .openAppSpecific:
            guard command.phase == .press else { return }
            enterAppSpecific(source: command.source)
        case .openKeys:
            guard command.phase == .press else { return }
            enterKeys(source: command.source)
        case .close:
            guard command.phase == .press else { return }
            exit(reason: .userRequested)
        case .select:
            guard isActive else {
                lease.deactivate()
                return
            }
            route(
                source: command.source,
                cell: command.physicalCell,
                phase: command.phase,
                nativeOutputHandled: false
            )
        case .selectNative:
            guard isActive else {
                lease.deactivate()
                return
            }
            route(
                source: command.source,
                cell: command.physicalCell,
                phase: command.phase,
                nativeOutputHandled: true
            )
        }
    }

    public func enter(source: MouseSource) {
        guard !isActive else { return }
        activate(source: source, page: .modes, definition: nil)
    }

    /// Opens the current frontmost app directly from top-level physical cell 11.
    /// The HUD follows later app activations until the user opens the manual selector.
    public func enterAppSpecific(source: MouseSource) {
        guard !isActive else { return }
        let context = resolveFrontmostApp?() ?? FrontmostAppModeContext(
            target: nil,
            displayName: "No frontmost app",
            bundleIdentifier: nil
        )
        activate(source: source, page: .appSpecific, definition: context.definition)
        appSpecificTarget = context.target
        followsFrontmostApp = true
        log.info("Following frontmost app: \(context.displayName)")
    }

    /// Opens the less-common configured-app selector from Utility cell 11. A
    /// selected target stays locked without activation until universal exit.
    public func enterAppSelector(source: MouseSource) {
        guard !isActive else { return }
        activate(source: source, page: .appSelector, definition: AppSpecificMode.selectorDefinition)
        followsFrontmostApp = false
    }

    /// Opens the shared arrow-key child directly from top-level physical cell 9.
    /// Physical cell 10 exits it.
    public func enterKeys(source: MouseSource) {
        guard !isActive else { return }
        activate(source: source, page: .keys, definition: nil)
    }

    private func activate(
        source: MouseSource,
        page: ModePickerPage,
        definition: AppSpecificModeDefinition?
    ) {
        do {
            try lease.activate()
        } catch {
            hud.flashProblem("Modes unavailable: Karabiner routing failed")
            return
        }
        isActive = true
        isLegendVisible = true
        self.source = source
        self.page = page
        navigationPath = [page]
        appSpecificDefinition = definition
        appSpecificTarget = nil
        followsFrontmostApp = false
        lastSelection = nil
        let appearance = definition?.accent ?? (page == .keys ? Self.keysAccent : Self.accent)
        lightingTargets = onAppearanceChange?(appearance, nil) ?? []
        onModeChange?(true)
        hud.show(snapshot())
        scheduler.start(interval: heartbeatInterval) { [weak self] in self?.renew() }
        let title = definition?.title ?? (page == .keys ? "Keys mode" : "Utility modes")
        log.info("\(title) ON from \(source.displayName)")
    }

    public func exit(reason: ModePickerExitReason = .userRequested) {
        scheduler.stop()
        lease.deactivate()
        guard isActive else { return }
        isActive = false
        isLegendVisible = false
        source = nil
        page = .modes
        navigationPath = []
        appSpecificDefinition = nil
        appSpecificTarget = nil
        followsFrontmostApp = false
        lastSelection = nil
        lightingTargets = onAppearanceChange?(nil, nil) ?? []
        hud.hide()
        onModeChange?(false)
        log.info("Modes OFF: \(String(describing: reason))")
    }

    public func handleDeviceLost(_ source: MouseSource) {
        guard isActive, self.source == source else { return }
        exit(reason: .deviceLost)
    }

    public func handleSystemSleep() {
        guard isActive else { return }
        exit(reason: .systemSleep)
    }

    public func shutdown() { exit(reason: .shuttingDown) }

    /// Refreshes only the direct frontmost-app journey. A manually selected
    /// target remains locked until the user exits or chooses another app.
    public func updateFrontmostApp(_ context: FrontmostAppModeContext) {
        guard isActive, page == .appSpecific, followsFrontmostApp else { return }
        let definition = context.definition
        guard appSpecificTarget != context.target || appSpecificDefinition != definition else {
            return
        }
        appSpecificTarget = context.target
        appSpecificDefinition = definition
        lastSelection = nil
        lightingTargets = onAppearanceChange?(definition.accent, nil) ?? []
        if isLegendVisible { hud.update(snapshot()) }
        log.info("Frontmost app mode changed to \(context.displayName)")
    }

    private func route(
        source: MouseSource,
        cell: PhysicalCell,
        phase: ModePickerCommand.Phase,
        nativeOutputHandled: Bool
    ) {
        guard self.source == source else {
            log.debug("ignored a mode event from the other exact-device coordinator")
            return
        }
        if cell == .modeExit, phase == .press {
            exit(reason: .userRequested)
            return
        }
        switch page {
        case .modes:
            guard phase == .press else { return }
            if cell == .keysModeSelector {
                navigate(to: .keys)
                log.info("Keys mode opened from Utility on \(source.displayName)")
            } else if let action = ModeUtilityAction.action(for: cell) {
                if !nativeOutputHandled {
                    guard onUtilityAction?(source, action) == true else {
                        hud.flashProblem("\(action.actionTitle) could not be performed")
                        return
                    }
                }
                recordSelection(cell: cell)
                log.info("\(action.actionTitle) from \(source.displayName)")
            } else if cell == .keypadModeSelector {
                guard onKeypadModeRequested?(source) == true else {
                    hud.flashProblem("Keypad mode could not start")
                    exit(reason: .userRequested)
                    return
                }
                navigate(to: .keypad)
                log.info("Keypad mode selected from \(source.displayName)")
            } else if cell == .appSpecificModeSelector {
                navigate(to: .appSelector)
                log.info("App selector opened from \(source.displayName)")
            }
        case .keypad:
            onKeypadInput?(source, cell, phase)
        case .appSelector:
            guard phase == .press else { return }
            guard let target = AppSpecificTarget.target(for: cell) else { return }
            navigate(to: .appSpecific, definition: target.definition, target: target)
            log.info("\(target.displayName) mode selected from \(source.displayName)")
        case .appSpecific:
            guard phase == .press else { return }
            if let target = appSpecificTarget,
               onAppSpecificInput?(source, target, cell) == true {
                recordSelection(cell: cell)
            }
        case .keys:
            guard phase == .press else { return }
            if cell == .modePickerEntry {
                navigate(to: .modes)
                log.info("Utility modes opened from Keys on \(source.displayName)")
                return
            }
            guard let action = KeysModeAction.action(for: cell, source: source) else { return }
            if !nativeOutputHandled {
                guard onKeysInput?(source, action) == true else {
                    hud.flashProblem("\(action.actionTitle) could not be performed")
                    return
                }
            }
            recordSelection(cell: cell)
            log.info("\(action.actionTitle) from \(source.displayName)")
        }
    }

    /// Move to a child page or reveal an existing ancestor. This keeps every
    /// mouse's journey cycle-free while allowing future menus to nest without
    /// adding one-off back-state booleans.
    private func navigate(
        to destination: ModePickerPage,
        definition: AppSpecificModeDefinition? = nil,
        target: AppSpecificTarget? = nil,
        followsFrontmostApp: Bool = false
    ) {
        if let existingIndex = navigationPath.lastIndex(of: destination) {
            navigationPath = Array(navigationPath.prefix(through: existingIndex))
        } else {
            navigationPath.append(destination)
        }
        page = destination
        lastSelection = nil
        self.followsFrontmostApp = followsFrontmostApp

        switch destination {
        case .appSelector:
            appSpecificDefinition = AppSpecificMode.selectorDefinition
            appSpecificTarget = nil
        case .appSpecific:
            appSpecificDefinition = definition
            appSpecificTarget = target
        default:
            appSpecificDefinition = nil
            appSpecificTarget = nil
        }

        let appearance: RGBColor
        switch destination {
        case .modes: appearance = Self.accent
        case .keys: appearance = Self.keysAccent
        case .keypad: appearance = Self.keypadAccent
        case .appSelector: appearance = AppSpecificMode.selectorAccent
        case .appSpecific: appearance = definition?.accent ?? Self.appSpecificAccent
        }
        lightingTargets = onAppearanceChange?(appearance, nil) ?? []
        isLegendVisible = true
        if destination == .keypad {
            // The dedicated keypad HUD takes over the presentation.
            hud.hide()
        } else {
            hud.show(snapshot())
        }
    }

    private func recordSelection(cell: PhysicalCell) {
        let item: ModeHUDLegendItem?
        switch page {
        case .modes:
            item = Self.modesLegend.first { $0.cell == cell }
        case .appSelector:
            item = AppSpecificMode.selectorDefinition.legend.first { $0.cell == cell }
        case .appSpecific:
            item = appSpecificDefinition?.legend.first { $0.cell == cell }
        case .keys:
            item = Self.keysLegend(for: source ?? .corsair).first { $0.cell == cell }
        case .keypad:
            item = nil
        }
        guard let item else { return }
        lastSelection = ModeHUDSelection(
            cell: item.cell,
            title: item.actionTitle,
            detail: item.detail,
            accent: item.accent
        )
        lightingTargets = onAppearanceChange?(activeAccent, item.accent) ?? []
        if isLegendVisible { hud.update(snapshot()) }
    }

    private var activeAccent: RGBColor {
        if (page == .appSelector || page == .appSpecific), let accent = appSpecificDefinition?.accent {
            return accent
        }
        if page == .keypad { return Self.keypadAccent }
        if page == .keys { return Self.keysAccent }
        return Self.accent
    }

    private func renew() {
        guard isActive else { return }
        do {
            try lease.renew()
            if page != .keypad, isLegendVisible { hud.update(snapshot()) }
        } catch {
            hud.flashProblem("Modes ended: Karabiner routing failed")
            exit(reason: .leaseFailure)
        }
    }

    private func snapshot() -> ModeHUDSnapshot {
        if (page == .appSelector || page == .appSpecific), let definition = appSpecificDefinition {
            return ModeHUDSnapshot(
                isActive: true,
                modeTitle: definition.title,
                source: source ?? .corsair,
                selection: lastSelection,
                legend: definition.legend,
                accent: definition.accent,
                lightingTargets: lightingTargets,
                footerTitle: definition.footerTitle,
                footerHint: nil,
                presentationStyle: .pastel,
                showsOnAllDisplays: true
            )
        }
        if page == .keys {
            return ModeHUDSnapshot(
                isActive: true,
                modeTitle: "Keys mode",
                source: source ?? .corsair,
                selection: lastSelection,
                legend: Self.keysLegend(for: source ?? .corsair),
                accent: Self.keysAccent,
                lightingTargets: lightingTargets,
                footerTitle: "Keys mode",
                footerHint: nil,
                presentationStyle: .boldOpaque,
                showsOnAllDisplays: true
            )
        }
        return ModeHUDSnapshot(
            isActive: true,
            modeTitle: "Utility modes",
            source: source ?? .corsair,
            selection: lastSelection,
            legend: Self.modesLegend,
            accent: Self.accent,
            lightingTargets: lightingTargets,
            footerTitle: "Utility modes",
            footerHint: nil,
            presentationStyle: .boldOpaque,
            showsOnAllDisplays: true
        )
    }

    public static func keysLegend(for source: MouseSource) -> [ModeHUDLegendItem] {
        PhysicalCell.all.map { cell in
            if let action = KeysModeAction.action(for: cell, source: source) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.actionTitle,
                    detail: "Native keyboard key",
                    accent: action.hudAccent
                )
            }
            if cell == .modeExit {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Exit Keys mode",
                    accent: keysAccent
                )
            }
            if cell == .modePickerEntry {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Utility modes",
                    detail: "Open the Utility page",
                    accent: accent
                )
            }
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Spare",
                detail: "Available for another key",
                accent: RGBColor(red: 110, green: 116, blue: 132)
            )
        }
    }

    public static let keysLegend = keysLegend(for: .corsair)

    public static let modesLegend: [ModeHUDLegendItem] = PhysicalCell.all.map { cell in
        if let action = ModeUtilityAction.action(for: cell) {
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: action.actionTitle,
                accent: action.hudAccent
            )
        }
        switch cell {
        case .keypadModeSelector:
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Keypad",
                accent: keypadAccent
            )
        case .appSpecificModeSelector:
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Choose App Specific",
                accent: appSpecificAccent
            )
        case .keysModeSelector:
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Keys mode",
                accent: keysAccent
            )
        case .modeExit:
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Exit Utility modes",
                accent: accent
            )
        default:
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Spare",
                accent: RGBColor(red: 110, green: 116, blue: 132)
            )
        }
    }
}
