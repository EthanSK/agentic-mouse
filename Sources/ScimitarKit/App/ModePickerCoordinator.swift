import Foundation

public enum ModePickerPage: Int, Equatable, Sendable {
    case modes = 1
    case keys = 2
    case appSelector = 3
    case appSpecific = 4
    case keypad = 5
    case extraUtilities = 6
}

public enum ModePickerExitReason: Equatable, Sendable {
    case userRequested
    case leaseFailure
    case deviceLost
    case systemSleep
    case shuttingDown
}

public enum ModeUtilityActionOutcome: Equatable, Sendable {
    case performed
    case failed(message: String?)
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

    /// Re-colours only app-identity roles while preserving semantic action
    /// fills. One icon-derived accent can therefore drive the page perimeter,
    /// navigation cards, exit cards, and mouse lighting without flattening
    /// the action-family palette.
    public func replacingIdentityAccent(with replacement: RGBColor) -> Self {
        guard replacement != accent else { return self }
        return Self(
            title: title,
            footerTitle: footerTitle,
            footerHint: footerHint,
            accent: replacement,
            legend: legend.map { item in
                ModeHUDLegendItem(
                    cell: item.cell,
                    actionTitle: item.actionTitle,
                    accent: item.accent == accent ? replacement : item.accent,
                    destinationModeAccent: item.destinationModeAccent == accent
                        ? replacement
                        : item.destinationModeAccent,
                    appBackdrop: item.appBackdrop,
                    controlStatus: item.controlStatus
                )
            }
        )
    }
}

/// Owns one fail-closed, exact-device Modes lease. AppDelegate creates one
/// instance per mouse so the left and right HUDs can coexist independently.
/// Physical cell 10 is the universal active-mode exit. App-specific child pages
/// additionally reuse their top-level entry cell 2 as an exit. Active-mode
/// legends stay visible for the lifetime of their mode; no action cell is spent
/// hiding them.
public final class ModePickerCoordinator {
    /// Strong electric purple for Utility, kept deliberately near full device
    /// output so the mode is obvious on both the HUD and physical mouse.
    public static let accent = RGBColor(red: 200, green: 0, blue: 255)
    public static let keypadAccent = RGBColor(red: 255, green: 0, blue: 174)
    public static let appSpecificAccent = RGBColor(red: 0, green: 132, blue: 255)
    /// Strong saturated orange for Keys, distinct from Utility at a glance.
    public static let keysAccent = RGBColor(red: 255, green: 104, blue: 0)
    /// Saturated teal for the less-frequent nested utility page.
    public static let extraUtilitiesAccent = RGBColor(red: 0, green: 229, blue: 168)

    public private(set) var isActive = false
    public private(set) var isLegendVisible = false
    public private(set) var source: MouseSource?
    public private(set) var lightingTargets: ModeLightingTargets = []
    public private(set) var page: ModePickerPage = .modes
    public private(set) var navigationPath: [ModePickerPage] = []
    public private(set) var appSpecificDefinition: AppSpecificModeDefinition?
    public private(set) var appSpecificTarget: AppSpecificTarget?
    public private(set) var activeWheelControl: WheelChordControl?
    public private(set) var followsFrontmostApp = false

    private let lease: ColorProofLeaseControlling
    private let hud: ModeHUDPresenting
    private let scheduler: TickScheduler
    private let log: Log
    private let heartbeatInterval: TimeInterval

    public var onAppearanceChange: ((RGBColor?, RGBColor?) -> ModeLightingTargets)?
    public var onModeChange: ((Bool) -> Void)?
    public var onKeypadModeRequested: ((MouseSource) -> Bool)?
    public var onKeypadInput: ((MouseSource, PhysicalCell, ModePickerCommand.Phase) -> Void)?
    public var onAppSpecificInput: ((MouseSource, AppSpecificTarget, PhysicalCell, ModePickerCommand.Phase) -> Bool)?
    public var onNativeAppSpecificInput: ((MouseSource, AppSpecificTarget, PhysicalCell, ModePickerCommand.Phase) -> Bool)?
    public var resolveFrontmostApp: (() -> FrontmostAppModeContext)?
    public var resolveAppSpecificDefinition: ((AppSpecificTarget) -> AppSpecificModeDefinition)?
    public var resolveAppSelectorDefinition: (() -> AppSpecificModeDefinition)?
    public var onUtilityAction: ((MouseSource, ModeUtilityAction) -> ModeUtilityActionOutcome)?
    public var onWheelControlChange: ((MouseSource, WheelChordControl?) -> Void)?
    public var onWheelControlRelease: ((MouseSource, WheelChordControl) -> Void)?
    public var onKeysInput: ((MouseSource, KeysModeAction) -> Bool)?
    private var lastSelection: ModeHUDSelection?
    /// Stay can take several seconds to restore a multi-display layout. Treat
    /// Organize Windows as one request per Extra Utilities visit so uncertainty
    /// cannot turn repeated physical presses into a queue of Stay restores.
    private var organizeWindowsRequested = false
    /// A repeated press must not quit whichever app becomes frontmost after
    /// the first target closes. Require leaving and re-entering Extra
    /// Utilities before another graceful Quit request can be dispatched.
    private var quitAppRequested = false

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

    /// Opens the current frontmost app directly from top-level physical cell 2.
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

    /// Opens the less-common configured-app selector from Utility cell 2. A
    /// selected target stays locked without activation until universal exit.
    public func enterAppSelector(source: MouseSource) {
        guard !isActive else { return }
        activate(
            source: source,
            page: .appSelector,
            definition: resolveAppSelectorDefinition?() ?? AppSpecificMode.selectorDefinition
        )
        followsFrontmostApp = false
    }

    /// Opens the shared native-key child directly from top-level physical cell 9.
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
        organizeWindowsRequested = false
        quitAppRequested = false
        let appearance: RGBColor
        if let definition {
            appearance = definition.accent
        } else {
            switch page {
            case .modes: appearance = Self.accent
            case .keys: appearance = Self.keysAccent
            case .extraUtilities: appearance = Self.extraUtilitiesAccent
            case .keypad: appearance = Self.keypadAccent
            case .appSelector: appearance = AppSpecificMode.selectorAccent
            case .appSpecific: appearance = Self.appSpecificAccent
            }
        }
        lightingTargets = onAppearanceChange?(appearance, nil) ?? []
        onModeChange?(true)
        hud.show(snapshot())
        scheduler.start(interval: heartbeatInterval) { [weak self] in self?.renew() }
        let title: String
        if let definition {
            title = definition.title
        } else {
            switch page {
            case .modes: title = "Utility modes"
            case .keys: title = "Keys mode"
            case .extraUtilities: title = "Extra Utilities"
            case .keypad: title = "Keypad mode"
            case .appSelector: title = "Choose app"
            case .appSpecific: title = "App mode"
            }
        }
        log.info("\(title) ON from \(source.displayName)")
    }

    public func exit(reason: ModePickerExitReason = .userRequested) {
        scheduler.stop()
        lease.deactivate()
        guard isActive else { return }
        clearWheelControl()
        isActive = false
        isLegendVisible = false
        source = nil
        page = .modes
        navigationPath = []
        appSpecificDefinition = nil
        appSpecificTarget = nil
        followsFrontmostApp = false
        lastSelection = nil
        organizeWindowsRequested = false
        quitAppRequested = false
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
        // A frontmost-app journey may retarget while the physical button is
        // still held. Disarm before changing definitions so a later wheel
        // event cannot run the prior app's command and a release cannot be
        // stranded on a target that no longer owns the control.
        clearWheelControl()
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
        let isExitCell = cell == .modeExit
            || (page == .appSpecific && cell == .frontmostAppModeSelector)
        if isExitCell {
            if phase == .press {
                exit(reason: .userRequested)
            }
            return
        }
        switch page {
        case .modes:
            if let control = WheelChordControl.utilityControl(for: cell) {
                switch phase {
                case .press:
                    activeWheelControl = control
                    onWheelControlChange?(source, control)
                    recordSelection(cell: cell)
                    log.info("\(control.actionTitle) wheel control held on \(source.displayName)")
                case .release:
                    guard activeWheelControl == control else { return }
                    onWheelControlRelease?(source, control)
                    clearWheelControl()
                }
                return
            }
            guard phase == .press else { return }
            if cell == .keysModeSelector {
                navigate(to: .keys)
                log.info("Keys mode opened from Utility on \(source.displayName)")
            } else if cell == .extraUtilitiesSelector {
                navigate(to: .extraUtilities)
                log.info("Extra Utilities opened from Utility on \(source.displayName)")
            } else if let action = ModeUtilityAction.directAction(for: cell) {
                guard !nativeOutputHandled else {
                    hud.flashProblem("Unexpected native route for \(action.actionTitle)")
                    return
                }
                let outcome = onUtilityAction?(source, action)
                    ?? .failed(message: nil)
                guard case .performed = outcome else {
                    if case .failed(let message) = outcome {
                        hud.flashProblem(
                            message ?? "\(action.actionTitle) could not be performed"
                        )
                    }
                    return
                }
                recordSelection(cell: cell)
                log.info("\(action.actionTitle) from \(source.displayName)")
            } else if cell == .appSpecificModeSelector {
                navigate(to: .appSelector)
                log.info("App selector opened from \(source.displayName)")
            }
        case .extraUtilities:
            guard phase == .press,
                  let action = ModeUtilityAction.extraUtilitiesAction(for: cell)
            else { return }
            if action == .organizeWindows, organizeWindowsRequested {
                hud.flashFeedback(ModeHUDFeedback(
                    message: "Stay restore already requested",
                    tone: .informational
                ))
                log.info("Ignored repeated Organize Windows request on \(source.displayName)")
                return
            }
            if action == .quitApp, quitAppRequested {
                hud.flashFeedback(ModeHUDFeedback(
                    message: "Quit App already sent",
                    tone: .informational
                ))
                log.info("Ignored repeated Quit App request on \(source.displayName)")
                return
            }
            guard !nativeOutputHandled else {
                hud.flashProblem("Unexpected native route for \(action.actionTitle)")
                return
            }
            let outcome = onUtilityAction?(source, action) ?? .failed(message: nil)
            guard case .performed = outcome else {
                if case .failed(let message) = outcome {
                    hud.flashProblem(
                        message ?? "\(action.actionTitle) could not be performed"
                    )
                }
                return
            }
            if action == .organizeWindows {
                organizeWindowsRequested = true
                hud.flashFeedback(ModeHUDFeedback(
                    message: "Stay restore requested",
                    tone: .informational
                ))
            } else if action == .quitApp {
                quitAppRequested = true
                hud.flashFeedback(ModeHUDFeedback(
                    message: "Quit App sent",
                    tone: .informational
                ))
            }
            recordSelection(cell: cell)
            log.info("\(action.actionTitle) from Extra Utilities on \(source.displayName)")
        case .keypad:
            onKeypadInput?(source, cell, phase)
        case .appSelector:
            guard phase == .press else { return }
            guard let target = AppSpecificTarget.target(for: cell) else { return }
            navigate(
                to: .appSpecific,
                definition: resolveAppSpecificDefinition?(target) ?? target.definition,
                target: target
            )
            log.info("\(target.displayName) mode selected from \(source.displayName)")
        case .appSpecific:
            if let target = appSpecificTarget,
               let control = WheelChordControl.appSpecificControl(for: target, cell: cell) {
                switch phase {
                case .press:
                    activeWheelControl = control
                    onWheelControlChange?(source, control)
                    recordSelection(cell: cell)
                    log.info("\(control.actionTitle) wheel control held on \(source.displayName)")
                case .release:
                    guard activeWheelControl == control else { return }
                    onWheelControlRelease?(source, control)
                    clearWheelControl()
                }
                return
            }
            let appSpecificInput = nativeOutputHandled
                ? onNativeAppSpecificInput
                : onAppSpecificInput
            if let target = appSpecificTarget,
               appSpecificInput?(source, target, cell, phase) == true,
               phase == .press {
                recordSelection(cell: cell)
            }
        case .keys:
            if let control = WheelChordControl.keysControl(for: cell) {
                switch phase {
                case .press:
                    activeWheelControl = control
                    onWheelControlChange?(source, control)
                    recordSelection(cell: cell)
                    log.info("\(control.actionTitle) wheel control held on \(source.displayName)")
                case .release:
                    guard activeWheelControl == control else { return }
                    onWheelControlRelease?(source, control)
                    clearWheelControl()
                }
                return
            }
            guard phase == .press else { return }
            if cell == .keypadModeSelector {
                guard onKeypadModeRequested?(source) == true else {
                    hud.flashProblem("Keypad mode could not start")
                    exit(reason: .userRequested)
                    return
                }
                navigate(to: .keypad)
                log.info("Keypad mode selected from Keys on \(source.displayName)")
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
        clearWheelControl()
        if let existingIndex = navigationPath.lastIndex(of: destination) {
            navigationPath = Array(navigationPath.prefix(through: existingIndex))
        } else {
            navigationPath.append(destination)
        }
        page = destination
        lastSelection = nil
        organizeWindowsRequested = false
        quitAppRequested = false
        self.followsFrontmostApp = followsFrontmostApp

        switch destination {
        case .appSelector:
            appSpecificDefinition = resolveAppSelectorDefinition?()
                ?? AppSpecificMode.selectorDefinition
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
        case .extraUtilities: appearance = Self.extraUtilitiesAccent
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
            item = Self.modesLegend(for: source ?? .corsair).first { $0.cell == cell }
        case .extraUtilities:
            item = Self.extraUtilitiesLegend(for: source ?? .corsair).first { $0.cell == cell }
        case .appSelector:
            item = appSpecificDefinition?.legend.first { $0.cell == cell }
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
            accent: item.accent
        )
        lightingTargets = onAppearanceChange?(activeAccent, item.accent) ?? []
        if isLegendVisible { hud.update(snapshot()) }
    }

    private func clearWheelControl() {
        guard let source, activeWheelControl != nil else {
            activeWheelControl = nil
            return
        }
        activeWheelControl = nil
        onWheelControlChange?(source, nil)
    }

    private var activeAccent: RGBColor {
        if (page == .appSelector || page == .appSpecific), let accent = appSpecificDefinition?.accent {
            return accent
        }
        if page == .keypad { return Self.keypadAccent }
        if page == .keys { return Self.keysAccent }
        if page == .extraUtilities { return Self.extraUtilitiesAccent }
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
                presentationStyle: .boldOpaque,
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
        if page == .extraUtilities {
            return ModeHUDSnapshot(
                isActive: true,
                modeTitle: "Extra Utilities",
                source: source ?? .corsair,
                selection: lastSelection,
                legend: Self.extraUtilitiesLegend(for: source ?? .corsair),
                accent: Self.extraUtilitiesAccent,
                lightingTargets: lightingTargets,
                footerTitle: "Extra Utilities",
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
            legend: Self.modesLegend(for: source ?? .corsair),
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
            if let control = WheelChordControl.keysControl(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "\(control.actionTitle) + Wheel",
                    accent: control.hudAccent,
                    controlStatus: control.hudControlStatus
                )
            }
            if cell == .keypadModeSelector {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Keypad",
                    accent: keypadAccent,
                    destinationModeAccent: keypadAccent,
                    controlStatus: .normal
                )
            }
            if let action = KeysModeAction.action(for: cell, source: source) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.actionTitle,
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
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Spare",
                accent: RGBColor(red: 110, green: 116, blue: 132)
            )
        }
    }

    public static let keysLegend = keysLegend(for: .corsair)

    public static func extraUtilitiesLegend(for source: MouseSource) -> [ModeHUDLegendItem] {
        PhysicalCell.all.map { cell in
            if let action = ModeUtilityAction.extraUtilitiesAction(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.actionTitle,
                    accent: action.hudAccent
                )
            }
            if cell == .modeExit {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: "Exit Extra Utilities",
                    accent: extraUtilitiesAccent
                )
            }
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Spare",
                accent: RGBColor(red: 110, green: 116, blue: 132)
            )
        }
    }

    public static let extraUtilitiesLegend = extraUtilitiesLegend(for: .corsair)

    public static func modesLegend(for source: MouseSource) -> [ModeHUDLegendItem] {
        PhysicalCell.all.map { cell in
        if let control = WheelChordControl.utilityControl(for: cell) {
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "\(control.actionTitle) + Wheel",
                accent: control.hudAccent,
                controlStatus: control.hudControlStatus
            )
        }
        if let action = ModeUtilityAction.directAction(for: cell) {
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: action.actionTitle,
                accent: action.hudAccent
            )
        }
        switch cell {
        case .appSpecificModeSelector:
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Choose App Specific",
                accent: appSpecificAccent,
                destinationModeAccent: appSpecificAccent
            )
        case .keysModeSelector:
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Keys mode",
                accent: keysAccent,
                destinationModeAccent: keysAccent
            )
        case .modeExit:
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Exit Utility modes",
                accent: accent
            )
        case .extraUtilitiesSelector:
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: "Extra Utilities",
                accent: extraUtilitiesAccent,
                destinationModeAccent: extraUtilitiesAccent
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

    public static let modesLegend = modesLegend(for: .corsair)
}
