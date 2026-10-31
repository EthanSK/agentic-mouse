import Foundation

public enum ModePickerPage: Int, Equatable, Sendable {
    case modes = 1
    case keys = 2
    case appSelector = 3
    case appSpecific = 4
    case keypad = 5
    case extraUtilities = 6
    case chromeWebsites = 7
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
    case started(message: String)
    case failed(message: String?)
}

public struct AppSpecificModeDefinition: Equatable, Sendable {
    public let title: String
    public let footerTitle: String
    public let footerHint: String?
    public let accent: RGBColor
    public let outlineWidth: Double?
    public let legend: [ModeHUDLegendItem]

    public init(
        title: String,
        footerTitle: String,
        footerHint: String? = nil,
        accent: RGBColor,
        outlineWidth: Double? = nil,
        legend: [ModeHUDLegendItem]
    ) {
        self.title = title
        self.footerTitle = footerTitle
        self.footerHint = footerHint
        self.accent = accent
        self.outlineWidth = outlineWidth
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
            outlineWidth: outlineWidth,
            legend: legend.map { item in
                if let gesture = item.gesture {
                    return ModeHUDLegendItem(
                        cell: item.cell,
                        gesture: gesture,
                        accent: item.accent == accent ? replacement : item.accent,
                        destinationModeAccent: item.destinationModeAccent == accent
                            ? replacement : item.destinationModeAccent,
                        appBackdrop: item.appBackdrop,
                        controlStatus: item.controlStatus
                    )
                }
                return ModeHUDLegendItem(
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

    public private(set) var isWandHome = false
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
    /// Navigation cursor owned by a pointer-style input (the wand). Mice never
    /// set it; every mode entry and exit clears it, and a wand page change
    /// replaces it atomically with the new page's starting card.
    public private(set) var pointerFocus: ModeHUDPointerFocus?
    /// Advances on every mode entry, page change and exit. The wand uses it to
    /// keep a release on the page where its press happened.
    public private(set) var pageGeneration: UInt64 = 0
    /// Number of wand parent pages that Exit can return to.
    public var wandBackDepth: Int { wandParents.count }

    /// One restorable page in the wand's own journey. Physical mice never push
    /// here: their page lifecycle stays owned by exact-device Karabiner state.
    fileprivate struct WandParentPage {
        let page: ModePickerPage
        let isWandHome: Bool
        let navigationPath: [ModePickerPage]
        let appSpecificDefinition: AppSpecificModeDefinition?
        let appSpecificTarget: AppSpecificTarget?
        let followsFrontmostApp: Bool
        let chromeWebsitesParentDefinition: AppSpecificModeDefinition?
        /// The card on this page that opened the child.
        let openingCell: PhysicalCell
    }

    private var wandParents: [WandParentPage] = []

    private let lease: ColorProofLeaseControlling
    private let hud: ModeHUDPresenting
    private let scheduler: TickScheduler
    private let selectAllGesture: ReservedModeHUDGesture
    private let log: Log
    private let heartbeatInterval: TimeInterval

    public var onAppearanceChange: ((RGBColor?, RGBColor?) -> ModeLightingTargets)?
    public var onModeChange: ((Bool) -> Void)?
    public var onKeypadModeRequested: ((MouseSource) -> Bool)?
    public var onKeypadInput: ((MouseSource, PhysicalCell, ModePickerCommand.Phase) -> Void)?
    public var onAppSpecificInput: ((MouseSource, AppSpecificTarget, PhysicalCell, ModePickerCommand.Phase, TimeInterval) -> Bool)?
    public var onNativeAppSpecificInput: ((MouseSource, AppSpecificTarget, PhysicalCell, ModePickerCommand.Phase, TimeInterval) -> Bool)?
    public var shouldRouteVSCodeCursorHistoryAsButton: ((MouseSource) -> Bool)?
    public var onChromeWebsiteInput: ((MouseSource, ChromeWebsiteAction) -> Bool)?
    public var resolveFrontmostApp: (() -> FrontmostAppModeContext)?
    public var resolveAppSpecificDefinition: ((AppSpecificTarget) -> AppSpecificModeDefinition)?
    public var resolveAppSelectorDefinition: (() -> AppSpecificModeDefinition)?
    public var onWandHomeInput: ((PhysicalCell) -> Bool)?
    public var onWandButtonPhase: ((ModePickerPage, Bool, PhysicalCell, ModePickerCommand.Phase) -> Bool)?
    public var resolveWandHomeSnapshot: (() -> ModeHUDSnapshot)?
    public var onUtilityAction: ((MouseSource, ModeUtilityAction) -> ModeUtilityActionOutcome)?
    public var onWheelControlChange: ((MouseSource, WheelChordControl?) -> Void)?
    public var onWheelControlRelease: ((MouseSource, WheelChordControl) -> Void)?
    public var onKeysInput: ((MouseSource, KeysModeAction) -> Bool)?
    private var lastSelection: ModeHUDSelection?
    private var chromeWebsitesParentDefinition: AppSpecificModeDefinition?
    /// Suppress duplicate presses only while our move-and-dispatch transaction
    /// is running. Completion (including failure) permits a deliberate retry;
    /// it does not prove that Stay finished restoring the external layout.
    private var organizeWindowsRequested = false
    /// A repeated press must not quit whichever app becomes frontmost after
    /// the first target closes. Require leaving and re-entering Extra
    /// Utilities before another graceful Quit request can be dispatched.
    private var quitAppRequested = false
    private var didTogglePinDuringHold = false
    private var codexPinModifierHeld = false
    private var codexPinModifierUsed = false
    private var codexPinModifierOpenedMode = false
    private var codexPinPressed = false

    public init(
        lease: ColorProofLeaseControlling,
        hud: ModeHUDPresenting,
        scheduler: TickScheduler,
        reservedHUDScheduler: TickScheduler = DispatchTickScheduler(),
        reservedHUDClock: MonotonicClock = SystemMonotonicClock(),
        log: Log,
        heartbeatInterval: TimeInterval = 2
    ) {
        self.lease = lease
        self.hud = hud
        self.scheduler = scheduler
        self.selectAllGesture = ReservedModeHUDGesture(
            clock: reservedHUDClock,
            scheduler: reservedHUDScheduler
        )
        self.log = log
        self.heartbeatInterval = heartbeatInterval
    }

    public func handle(_ command: ModePickerCommand, inputTime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        switch command.action {
        case .open:
            guard command.phase == .press else { return }
            enter(source: command.source)
        case .openAppSpecific:
            switch command.phase {
            case .press:
                guard !isActive else { return }
                enterAppSpecific(source: command.source)
                // The physical entry down is already the held modifier. Do
                // not require a second press after the app page appears.
                if isActive, appSpecificTarget == .codex,
                   command.physicalCell == CodexMode.pinModifierCell {
                    codexPinModifierHeld = true
                    codexPinModifierOpenedMode = true
                }
            case .release:
                // An opener's late release must never become a later Exit.
                guard isActive, codexPinModifierOpenedMode,
                      command.physicalCell == CodexMode.pinModifierCell else { return }
                route(source: command.source, cell: command.physicalCell,
                      phase: .release, nativeOutputHandled: false, inputTime: inputTime)
            }
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
                nativeOutputHandled: false,
                inputTime: inputTime
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
                nativeOutputHandled: true,
                inputTime: inputTime
            )
        }
    }

    public func enter(source: MouseSource) {
        guard !isActive else { return }
        activate(source: source, page: .modes, definition: nil)
    }

    public var wandReviewAvailable: Bool { resolveFrontmostApp?().target == .vsCode }
    private var wandReviewSelection: PhysicalCell?
    public func setWandReviewSelection(_ cell: PhysicalCell?) {
        guard wandReviewSelection != cell else { return }
        wandReviewSelection = cell; refreshWandHome()
    }

    public func refreshWandHome() {
        if isActive && isWandHome && isLegendVisible { hud.update(snapshot()) }
    }

    /// Wand only: hides the HUD after a completed action while the mode stays
    /// alive briefly, so bounded follow-up work (Codex Edit, a VS Code
    /// classification) is not cancelled by an immediate exit. Nothing redraws
    /// it again; the wand controller exits the mode shortly afterwards.
    public func concealWandHUD() {
        guard isActive, source == .wand, isLegendVisible else { return }
        isLegendVisible = false
        pointerFocus = nil
        hud.hide()
    }

    /// The first frame already carries `pointerFocus`, so the outline never
    /// appears a frame late or springs in after the panel.
    public func enterWandHome(source: MouseSource, pointerFocus: ModeHUDPointerFocus? = nil) {
        guard source == .wand, !isActive else { return }
        activate(source: source, page: .modes, definition: nil, wandHome: true, pointerFocus: pointerFocus)
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

    public func organizeWindowsRequestDidFinish() {
        organizeWindowsRequested = false
    }

    private func activate(
        source: MouseSource,
        page: ModePickerPage,
        definition: AppSpecificModeDefinition?,
        wandHome: Bool = false,
        pointerFocus initialPointerFocus: ModeHUDPointerFocus? = nil
    ) {
        do {
            try lease.activate()
        } catch {
            hud.flashProblem("Modes unavailable: Karabiner routing failed")
            return
        }
        isWandHome = wandHome
        isActive = true
        isLegendVisible = true
        self.source = source
        self.page = page
        navigationPath = [page]
        wandParents = []
        pageGeneration &+= 1
        appSpecificDefinition = definition
        appSpecificTarget = nil
        followsFrontmostApp = false
        lastSelection = nil
        pointerFocus = source == .wand && page != .keypad ? initialPointerFocus : nil
        chromeWebsitesParentDefinition = nil
        organizeWindowsRequested = false
        quitAppRequested = false
        resetCodexPinChord()
        selectAllGesture.cancel()
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
            case .chromeWebsites: appearance = ChromeWebsitesMode.accent
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
            case .chromeWebsites: title = "Chrome websites"
            }
        }
        log.info("\(title) ON from \(source.displayName)")
    }

    public func exit(reason: ModePickerExitReason = .userRequested) {
        scheduler.stop()
        selectAllGesture.cancel()
        resetCodexPinChord()
        lease.deactivate()
        guard isActive else { return }
        clearWheelControl()
        isWandHome = false
        isActive = false
        isLegendVisible = false
        source = nil
        page = .modes
        navigationPath = []
        wandParents = []
        pageGeneration &+= 1
        appSpecificDefinition = nil
        appSpecificTarget = nil
        followsFrontmostApp = false
        lastSelection = nil
        pointerFocus = nil
        chromeWebsitesParentDefinition = nil
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
        if isActive, isWandHome {
            // Switch App from the wand changes the frontmost app while Default
            // is still showing; redraw its current-app card truthfully.
            if isLegendVisible { hud.update(snapshot()) }
            return
        }
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
        resetCodexPinChord()
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
        nativeOutputHandled: Bool,
        inputTime: TimeInterval
    ) {
        guard self.source == source else {
            log.debug("ignored a mode event from the other exact-device coordinator")
            return
        }
        if source == .wand, onWandButtonPhase?(page, isWandHome, cell, phase) == true {
            if phase == .press { recordSelection(cell: cell) }
            return
        }
        if isWandHome { routeWandHome(cell: cell, phase: phase); return }
        if source == .wand, cell.isWandOnlySlot {
            // Utility's Backspace and Copy outer shortcuts use the existing
            // quick-action callback once on release. Reject stale cards from
            // another page before they can invoke a native action.
            guard pageSnapshot().legend.contains(where: { $0.cell == cell }),
                  phase == .release else { return }
            if onWandHomeInput?(cell) == true { recordSelection(cell: cell) }
            else {
                let title = pageSnapshot().legend.first { $0.cell == cell }?.actionTitle ?? "Action"
                hud.flashProblem("\(title) could not be performed")
            }
            return
        }
        if source.isPhysicalAdapter, page == .appSpecific, appSpecificTarget == .codex,
           cell == CodexMode.pinModifierCell || cell == CodexMode.pinToggleCell {
            guard !nativeOutputHandled else { return }
            routeCodexPinChord(source: source, cell: cell, phase: phase, inputTime: inputTime)
            return
        }
        let isExitCell = cell == .modeExit
            || ((page == .appSpecific || page == .chromeWebsites)
                && cell == .frontmostAppModeSelector)
        if phase == .press, cell != .selectAll, !isExitCell {
            selectAllGesture.commitPendingSinglePress()
        }
        if isExitCell {
            if phase == .press {
                // The wand HUD is a menu: a child page's exit returns to the
                // page that opened it. Only the journey's root page closes.
                if source == .wand, navigateBackForWand() { return }
                if appSpecificTarget == .codex { log.notice("Codex mode exit, source \(source.rawValue), cell \(cell.rawValue)") }
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
                navigate(to: .keys, openingCell: cell)
                log.info("Keys mode opened from Utility on \(source.displayName)")
            } else if cell == .extraUtilitiesSelector {
                navigate(to: .extraUtilities, openingCell: cell)
                log.info("Extra Utilities opened from Utility on \(source.displayName)")
            } else if let action = ModeUtilityAction.directAction(for: cell) {
                guard !nativeOutputHandled else {
                    hud.flashProblem("Unexpected native route for \(action.actionTitle)")
                    return
                }
                if action == .selectAll {
                    selectAllGesture.handlePress(source: source) { [weak self] in
                        self?.performSelectAll(source: source)
                    } doublePress: { [weak self] in
                        guard let self else { return }
                        guard self.onKeysInput?(source, .insertSpace) == true else { return }
                        self.recordSelection(cell: cell)
                        self.log.info("Space from Utility Select All double press on \(source.displayName)")
                    }
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
                if action == .selectAll {
                    hud.flashFeedback(ModeHUDFeedback(message: "Select all sent", tone: .informational))
                }
                recordSelection(cell: cell)
                log.info("\(action.actionTitle) from \(source.displayName)")
            } else if cell == .appSpecificModeSelector {
                navigate(to: .appSelector, openingCell: cell)
                log.info("App selector opened from \(source.displayName)")
            }
        case .extraUtilities:
            if let control = WheelChordControl.extraUtilitiesControl(for: cell) {
                switch phase {
                case .press:
                    guard activeWheelControl != control else { return }
                    activeWheelControl = control
                    onWheelControlChange?(source, control)
                    recordSelection(cell: cell)
                case .release:
                    guard activeWheelControl == control else { return }
                    onWheelControlRelease?(source, control)
                    clearWheelControl()
                }
                return
            }
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
            if case .started(let message) = outcome {
                if action == .organizeWindows { organizeWindowsRequested = true }
                recordSelection(cell: cell)
                hud.flashFeedback(ModeHUDFeedback(message: message, tone: .informational))
                return
            }
            guard case .performed = outcome else {
                if case .failed(let message) = outcome {
                    hud.flashProblem(
                        message ?? "\(action.actionTitle) could not be performed"
                    )
                }
                return
            }
            if action == .organizeWindows {
                hud.flashFeedback(ModeHUDFeedback(
                    message: "Stay restore requested",
                    tone: .informational
                ))
            } else if action == .save {
                hud.flashFeedback(ModeHUDFeedback(message: "Save sent", tone: .informational))
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
                target: target,
                openingCell: cell
            )
            log.info("\(target.displayName) mode selected from \(source.displayName)")
        case .appSpecific:
            if appSpecificTarget == .chrome,
               phase == .press,
               ChromeModeAction.action(for: cell) == .openWebsites {
                chromeWebsitesParentDefinition = appSpecificDefinition
                let websitesDefinition = ChromeWebsitesMode.definition.replacingIdentityAccent(
                    with: appSpecificDefinition?.accent ?? ChromeMode.accent
                )
                navigate(
                    to: .chromeWebsites,
                    definition: websitesDefinition,
                    target: .chrome,
                    followsFrontmostApp: followsFrontmostApp,
                    openingCell: cell
                )
                log.info("Chrome websites opened from \(source.displayName)")
                return
            }
            // VS Code's stage-ready 8+9 / 5+6 preview press takes precedence
            // over cell 6's ordinary Cursor History wheel control.
            if appSpecificTarget == .vsCode,
               shouldRouteVSCodeCursorHistoryAsButton?(source) == true,
               cell == VSCodeMode.cursorHistoryWheelCell {
                let input = nativeOutputHandled
                    ? onNativeAppSpecificInput : onAppSpecificInput
                if input?(source, .vsCode, cell, phase, inputTime) == true {
                    if phase == .press { recordSelection(cell: cell) }
                    return
                }
            }
            if let target = appSpecificTarget,
               let control = WheelChordControl.appSpecificControl(for: target, cell: cell) {
                let pinControl = control == .codexPin || control == .claudePin
                guard !pinControl || !nativeOutputHandled else { return }
                switch phase {
                case .press:
                    guard !pinControl || activeWheelControl != control else { return }
                    activeWheelControl = control
                    onWheelControlChange?(source, control)
                    recordSelection(cell: cell)
                    log.info("\(control.actionTitle) wheel control held on \(source.displayName)")
                case .release:
                    guard activeWheelControl == control else { return }
                    onWheelControlRelease?(source, control)
                    clearWheelControl()
                    if pinControl, isLegendVisible { hud.update(snapshot()) }
                }
                return
            }
            let appSpecificInput = nativeOutputHandled
                ? onNativeAppSpecificInput
                : onAppSpecificInput
            if let target = appSpecificTarget,
               appSpecificInput?(source, target, cell, phase, inputTime) == true,
               phase == .press {
                recordSelection(cell: cell)
                // Ethan's unexpected "New voice chat": retain the requested
                // control/transport for correlation, never prompt or voice text.
                if target == .codex, let action = CodexModeAction.action(for: cell),
                   action == .newTask || action == .toggleVoiceMode {
                    let transport = nativeOutputHandled ? "native" : "app"
                    log.notice("Codex \(action.rawValue) requested via \(transport) route, source \(source.rawValue), cell \(cell.rawValue)")
                }
            }
        case .chromeWebsites:
            guard phase == .press else { return }
            if cell == ChromeWebsitesMode.parentCell {
                let chromeDefinition = chromeWebsitesParentDefinition ?? ChromeMode.definition
                chromeWebsitesParentDefinition = nil
                navigate(
                    to: .appSpecific,
                    definition: chromeDefinition,
                    target: .chrome,
                    followsFrontmostApp: followsFrontmostApp
                )
                log.info("Chrome mode reopened from websites on \(source.displayName)")
                return
            }
            guard let action = ChromeWebsiteAction.action(for: cell),
                  onChromeWebsiteInput?(source, action) == true
            else { return }
            recordSelection(cell: cell)
            log.info("\(action.title) requested from Chrome websites on \(source.displayName)")
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
                    // Keypad needs a mouse's exact press stream. The wand
                    // stays on Keys instead of dismissing its whole menu.
                    if source != .wand { exit(reason: .userRequested) }
                    return
                }
                navigate(to: .keypad, openingCell: cell)
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

    private func routeWandHome(cell: PhysicalCell, phase: ModePickerCommand.Phase) {
        if let control = WheelChordControl.wandHomeControl(for: cell) {
            if phase == .press {
                activeWheelControl = control
                onWheelControlChange?(.wand, control)
                recordSelection(cell: cell)
            } else if activeWheelControl == control {
                onWheelControlRelease?(.wand, control)
                clearWheelControl()
            }
            return
        }
        guard phase == .release else { return }
        switch cell.rawValue {
        case 2:
            let context = resolveFrontmostApp?() ?? FrontmostAppModeContext(target: nil, displayName: "No frontmost app", bundleIdentifier: nil)
            navigate(to: .appSpecific, definition: context.definition, target: context.target,
                     followsFrontmostApp: true, openingCell: cell)
        case 9: navigate(to: .keys, openingCell: cell)
        case 12: navigate(to: .modes, openingCell: cell)
        case 10: exit(reason: .userRequested) // Home is the root: its exit deliberately closes.
        default:
            if onWandHomeInput?(cell) == true { recordSelection(cell: cell) }
            else {
                let title = wandHomeSnapshot().legend.first { $0.cell == cell }?.actionTitle ?? "Action"
                hud.flashProblem("\(title) could not be performed")
            }
        }
    }

    /// The first cell-2 hold opens the page and can immediately protect Pin.
    /// Its release leaves the page open; a later unused click exits on release.
    private func routeCodexPinChord(
        source: MouseSource, cell: PhysicalCell,
        phase: ModePickerCommand.Phase, inputTime: TimeInterval
    ) {
        if cell == CodexMode.pinModifierCell {
            switch phase {
            case .press:
                guard !codexPinModifierHeld else { return }
                codexPinModifierHeld = true
                codexPinModifierUsed = false
                codexPinModifierOpenedMode = false
            case .release:
                guard codexPinModifierHeld else { return }
                let used = codexPinModifierUsed
                let openedMode = codexPinModifierOpenedMode
                codexPinModifierHeld = false
                codexPinModifierUsed = false
                codexPinModifierOpenedMode = false
                if !used, !openedMode { exit(reason: .userRequested) }
            }
            return
        }
        switch phase {
        case .press:
            guard !codexPinPressed else { return }
            codexPinPressed = true
            guard codexPinModifierHeld else { return }
            // Even a failed dispatch consumed this chord; never fall through
            // to Exit when the modifier is released.
            codexPinModifierUsed = true
            if onAppSpecificInput?(source, .codex, cell, .press, inputTime) == true {
                recordSelection(cell: cell)
            }
        case .release:
            codexPinPressed = false
        }
    }

    private func resetCodexPinChord() {
        codexPinModifierHeld = false
        codexPinModifierUsed = false
        codexPinModifierOpenedMode = false
        codexPinPressed = false
    }

    private func performSelectAll(source: MouseSource) {
        guard isActive, self.source == source, page == .modes else { return }
        let outcome = onUtilityAction?(source, .selectAll) ?? .failed(message: nil)
        guard case .performed = outcome else {
            if case .failed(let message) = outcome {
                hud.flashProblem(message ?? "Select all could not be performed")
            }
            return
        }
        hud.flashFeedback(ModeHUDFeedback(message: "Select all sent", tone: .informational))
        recordSelection(cell: .selectAll)
        log.info("Select all from \(source.displayName)")
    }

    /// Move to a child page or reveal an existing ancestor. This keeps every
    /// mouse's journey cycle-free while allowing future menus to nest without
    /// adding one-off back-state booleans.
    private func navigate(
        to destination: ModePickerPage,
        definition: AppSpecificModeDefinition? = nil,
        target: AppSpecificTarget? = nil,
        followsFrontmostApp: Bool = false,
        openingCell: PhysicalCell? = nil
    ) {
        clearWheelControl()
        var wandFocus: ModeHUDPointerFocus?
        if source == .wand, destination != .keypad {
            // An explicit parent control (Chrome websites → Chrome) returns to
            // that ancestor; any other wand navigation records where it came
            // from. Home and Utility share `.modes`, so identity includes the
            // home flag and the app target, never the page value alone.
            if let ancestor = wandParents.lastIndex(where: {
                !$0.isWandHome && $0.page == destination
                    && (destination != .appSpecific || $0.appSpecificTarget == target)
            }) {
                wandFocus = ModeHUDPointerFocus(cell: wandParents[ancestor].openingCell)
                wandParents.removeSubrange(ancestor...)
            } else if let openingCell {
                wandParents.append(currentWandPage(openingCell: openingCell))
                wandFocus = ModeHUDPointerFocus(cell: WandSelectionController.startCell(for: destination))
            }
        }
        pageGeneration &+= 1
        isWandHome = false
        resetCodexPinChord()
        if let existingIndex = navigationPath.lastIndex(of: destination) {
            navigationPath = Array(navigationPath.prefix(through: existingIndex))
        } else {
            navigationPath.append(destination)
        }
        page = destination
        lastSelection = nil
        pointerFocus = wandFocus
        organizeWindowsRequested = false
        quitAppRequested = false
        self.followsFrontmostApp = followsFrontmostApp

        switch destination {
        case .appSelector:
            appSpecificDefinition = resolveAppSelectorDefinition?()
                ?? AppSpecificMode.selectorDefinition
            appSpecificTarget = nil
        case .appSpecific, .chromeWebsites:
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
        case .chromeWebsites: appearance = definition?.accent ?? ChromeWebsitesMode.accent
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

    private func currentWandPage(openingCell: PhysicalCell) -> WandParentPage {
        WandParentPage(
            page: page,
            isWandHome: isWandHome,
            navigationPath: navigationPath,
            appSpecificDefinition: appSpecificDefinition,
            appSpecificTarget: appSpecificTarget,
            followsFrontmostApp: followsFrontmostApp,
            chromeWebsitesParentDefinition: chromeWebsitesParentDefinition,
            openingCell: openingCell
        )
    }

    /// Wand only: where the wand is, so a HUD hidden by an ordinary action can
    /// reopen on the same submenu (Ethan: "when I reopen the HUD, it should
    /// still be in that submenu"). Nil at home or on the separate keypad.
    public func wandJourneyBookmark() -> WandJourneyBookmark? {
        guard isActive, source == .wand, !isWandHome, page != .keypad else { return nil }
        return WandJourneyBookmark(parents: wandParents, current: currentWandPage(openingCell: .switchApp))
    }

    /// Reopens a bookmarked submenu from a freshly opened home, in one HUD
    /// update. Only page state is restored: never a held key, an action or a
    /// wheel press. An automatic app page follows the current frontmost app.
    @discardableResult
    public func restoreWandJourney(_ mark: WandJourneyBookmark) -> Bool {
        guard isActive, source == .wand, isWandHome, wandParents.isEmpty,
              !mark.current.isWandHome, mark.current.page != .keypad else { return false }
        clearWheelControl()
        resetCodexPinChord()
        pageGeneration &+= 1
        wandParents = mark.parents
        isWandHome = false
        page = mark.current.page
        navigationPath = mark.current.navigationPath
        appSpecificDefinition = mark.current.appSpecificDefinition
        appSpecificTarget = mark.current.appSpecificTarget
        followsFrontmostApp = mark.current.followsFrontmostApp
        chromeWebsitesParentDefinition = mark.current.chromeWebsitesParentDefinition
        if page == .appSelector {
            appSpecificDefinition = resolveAppSelectorDefinition?() ?? AppSpecificMode.selectorDefinition
        } else if page == .appSpecific, followsFrontmostApp, let context = resolveFrontmostApp?() {
            appSpecificTarget = context.target
            appSpecificDefinition = context.definition
        }
        lastSelection = nil
        organizeWindowsRequested = false
        quitAppRequested = false
        pointerFocus = ModeHUDPointerFocus(cell: WandSelectionController.startCell(for: page))
        lightingTargets = onAppearanceChange?(activeAccent, nil) ?? []
        isLegendVisible = true
        hud.show(snapshot())
        log.info("Wand reopened its last submenu")
        return true
    }

    /// Wand only: restores the page that opened the current child, with the
    /// outline on the card that opened it, in one HUD update. Returns false at
    /// the journey's root, where the caller keeps its deliberate close.
    @discardableResult
    public func navigateBackForWand() -> Bool {
        guard isActive, source == .wand, let parent = wandParents.popLast() else { return false }
        clearWheelControl()
        pageGeneration &+= 1
        isWandHome = parent.isWandHome
        page = parent.page
        navigationPath = parent.navigationPath
        appSpecificDefinition = parent.appSpecificDefinition
        appSpecificTarget = parent.appSpecificTarget
        followsFrontmostApp = parent.followsFrontmostApp
        chromeWebsitesParentDefinition = parent.chromeWebsitesParentDefinition
        if page == .appSpecific, followsFrontmostApp, let context = resolveFrontmostApp?(),
           context.target != appSpecificTarget {
            // The app may have changed while a child page was open.
            appSpecificTarget = context.target
            appSpecificDefinition = context.definition
        }
        lastSelection = nil
        organizeWindowsRequested = false
        quitAppRequested = false
        pointerFocus = ModeHUDPointerFocus(cell: parent.openingCell)
        lightingTargets = onAppearanceChange?(activeAccent, nil) ?? []
        isLegendVisible = true
        hud.show(snapshot())
        log.info("Wand returned to the parent page")
        return true
    }

    private func recordSelection(cell: PhysicalCell) {
        let item: ModeHUDLegendItem?
        switch page {
        case .modes where isWandHome:
            item = wandHomeSnapshot().legend.first { $0.cell == cell }
        case .modes:
            item = Self.modesLegend(for: source ?? .corsair).first { $0.cell == cell }
        case .extraUtilities:
            item = Self.extraUtilitiesLegend(for: source ?? .corsair).first { $0.cell == cell }
        case .appSelector:
            item = appSpecificDefinition?.legend.first { $0.cell == cell }
        case .appSpecific:
            item = appSpecificDefinition?.legend.first { $0.cell == cell }
        case .chromeWebsites:
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

    /// Reject queued events from the retired Codex pin wheel gesture.
    @discardableResult
    public func toggleCodexPinFromWheel(_ step: WheelChordStateMachine.Step, inputTime: TimeInterval) -> Bool {
        // Reject a stale event from the retired gesture; pinning now requires
        // a fresh same-source cell-2 hold and cell-3 click.
        false
    }

    @discardableResult
    public func toggleClaudePinFromWheel(_ step: WheelChordStateMachine.Step, inputTime: TimeInterval) -> Bool {
        toggleAppPinFromWheel(step, target: .claude, cell: ClaudeMode.pinToggleCell,
                              control: .claudePin, inputTime: inputTime)
    }

    private func toggleAppPinFromWheel(
        _ step: WheelChordStateMachine.Step,
        target: AppSpecificTarget,
        cell: PhysicalCell,
        control: WheelChordControl,
        inputTime: TimeInterval
    ) -> Bool {
        guard isActive, page == .appSpecific, appSpecificTarget == target,
              source == step.source, activeWheelControl == control,
              step.control == control, step.control.accepts(step.direction),
              !didTogglePinDuringHold else { return false }
        didTogglePinDuringHold = true
        let sent = onAppSpecificInput?(step.source, target, cell, .press, inputTime) == true
        if sent { recordSelection(cell: cell) }
        return sent
    }

    /// Moves or clears the wand's navigation outline without performing any
    /// action. Keypad owns a separate HUD, so it never receives a cursor.
    public func setPointerFocus(_ focus: ModeHUDPointerFocus?) {
        var resolved = isActive && page != .keypad ? focus : nil
        if source == .wand, let candidate = resolved {
            // Never outline a card the wheel does not draw (a review card
            // outside VS Code, a Spare, a duplicate exit): use its centre.
            let layout = wandRadialLayout
            if !layout.contains(candidate.cell), let center = layout.center {
                resolved = ModeHUDPointerFocus(cell: center)
            }
        }
        guard resolved != pointerFocus else { return }
        pointerFocus = resolved
        if isLegendVisible, page != .keypad { hud.update(snapshot()) }
    }

    private func clearWheelControl() {
        didTogglePinDuringHold = false
        guard let source, activeWheelControl != nil else {
            activeWheelControl = nil
            return
        }
        activeWheelControl = nil
        onWheelControlChange?(source, nil)
    }

    private var activeAccent: RGBColor {
        if isWandHome { return DefaultMapLegend.accent }
        if (page == .appSelector || page == .appSpecific || page == .chromeWebsites),
           let accent = appSpecificDefinition?.accent {
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
        var value = pageSnapshot()
        value.pointerFocus = pointerFocus
        if source == .wand {
            value.wandRadialLayout = .wandMenu(legend: value.legend, page: page, isHome: isWandHome,
                                               appTarget: appSpecificTarget)
        }
        return value
    }

    private func wandHomeSnapshot() -> ModeHUDSnapshot {
        var value = resolveWandHomeSnapshot?() ?? DefaultMapLegend.snapshot(source: .wand, frontmostAppContext: resolveFrontmostApp?())
        value.source = .wand
        // Ethan (2026-10-30): Screenshot leaves the wand home; its slot holds
        // New Codex chat, and the receiver's mouse button triple-click still takes a
        // screenshot. The physical mice keep their Screenshot card.
        value.legend.removeAll { $0.cell == .screenshotToggle }
        value.legend.append(ModeHUDLegendItem(cell: .wandPlayPause, actionTitle: "Play/Pause", accent: ModeHUDActionFamilyPalette.media))
        // Ethan's outer layer (`WandOuterLayer.home`): Undo beyond Keys, Space
        // beyond Enter and Brightness then Zoom beyond Utility are always present; the review
        // pair joins them beyond the app card only while VS Code is
        // frontmost. New Codex chat is a ring card in Screenshot's old slot.
        value.legend += [
            ModeHUDLegendItem(cell: .wandUndo, actionTitle: "Undo", accent: KeysModeAction.undo.hudAccent),
            ModeHUDLegendItem(cell: .wandSpace, actionTitle: "Space", accent: KeysModeAction.insertSpace.hudAccent),
            ModeHUDLegendItem(cell: .wandCodexNewChat, actionTitle: "New Codex chat", accent: CodexMode.accent),
            // Utility's own Zoom wheel control, one reach beyond Utility.
            ModeHUDLegendItem(cell: .wandZoom, gesture: WheelChordControl.zoom.hudGesture,
                              accent: WheelChordControl.zoom.hudAccent)
        ]
        if resolveFrontmostApp?().target == .vsCode {
            value.legend += [
                ModeHUDLegendItem(cell: .wandReviewChanges, actionTitle: "Review changes", accent: RGBColor(red: 65, green: 201, blue: 122)),
                ModeHUDLegendItem(cell: .wandReviewFiles, actionTitle: "Stage files", accent: RGBColor(red: 180, green: 105, blue: 235))
            ]
        }
        value.selection = lastSelection
        value.wandReviewSelection = wandReviewAvailable ? wandReviewSelection : nil
        return value
    }

    /// The wand's weapon wheel for the page it is showing. The HUD receives
    /// this same layout in every wand snapshot.
    public var wandRadialLayout: WandRadialLayout {
        .wandMenu(legend: pageSnapshot().legend, page: page, isHome: isWandHome, appTarget: appSpecificTarget)
    }

    private func pageSnapshot() -> ModeHUDSnapshot {
        if isWandHome { return wandHomeSnapshot() }
        if (page == .appSelector || page == .appSpecific || page == .chromeWebsites),
           let definition = appSpecificDefinition {
            return ModeHUDSnapshot(
                isActive: true,
                modeTitle: definition.title,
                source: source ?? .corsair,
                selection: lastSelection,
                legend: definition.legend,
                accent: definition.accent,
                outlineWidth: definition.outlineWidth,
                lightingTargets: lightingTargets,
                footerTitle: definition.footerTitle,
                footerHint: appSpecificTarget == .vsCode ? VSCodeMode.undoHint(source: source ?? .corsair) : nil,
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
                    gesture: control.hudGesture,
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
            if let control = WheelChordControl.extraUtilitiesControl(for: cell) {
                return ModeHUDLegendItem(cell: cell, gesture: control.hudGesture,
                                         accent: control.hudAccent)
            }
            if let action = ModeUtilityAction.extraUtilitiesAction(for: cell) {
                return ModeHUDLegendItem(
                    cell: cell,
                    actionTitle: action.actionTitle,
                    accent: action.hudAccent,
                    controlStatus: action == .spotifySongRadio ? .reportedBroken : .normal
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
                gesture: control.hudGesture,
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
        } + (source == .wand ? wandUtilityOuterLegend : [])
    }

    /// Keep the existing action names and palette on Utility's outer bands.
    static let wandUtilityOuterLegend: [ModeHUDLegendItem] = [
        ModeHUDLegendItem(cell: .wandBackspace, actionTitle: KeysModeAction.pressBackspace.actionTitle,
                          accent: KeysModeAction.pressBackspace.hudAccent),
        ModeHUDLegendItem(cell: .wandCopy, actionTitle: ModeUtilityAction.copy.actionTitle,
                          accent: ModeUtilityAction.copy.hudAccent),
    ]


    public static let modesLegend = modesLegend(for: .corsair)
}

/// A wand submenu to reopen after an ordinary action hid the HUD. Opaque:
/// it carries page state only, never a held key, action or wheel press.
public struct WandJourneyBookmark {
    fileprivate let parents: [ModePickerCoordinator.WandParentPage]
    fileprivate let current: ModePickerCoordinator.WandParentPage
    /// The bookmarked page, for tests and logging.
    public var page: ModePickerPage { current.page }
    public var appSpecificTarget: AppSpecificTarget? { current.appSpecificTarget }
}
