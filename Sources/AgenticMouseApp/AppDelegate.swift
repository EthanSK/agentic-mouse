import AppKit
import ScimitarKit
import ScimitarUI

/// Wires the whole helper together.
///
/// Startup is intentionally forgiving: the app runs with whichever subsystems
/// are available. No iCUE means no lighting and no multi-tap, but the menu bar
/// still explains why. Nothing is ever half-enabled silently.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logSink: LogSink
    private var log: Log

    private var configuration: AppConfiguration = .default
    private var configurationWarnings: [String] = []

    private var statusItem: StatusItemController?
    private let launchAtLoginController = LaunchAtLoginController()
    private var launchAtLoginState = "unknown"
    private var keypadHUDPresenters: [MouseSource: AppKitHUDPresenter] = [:]
    private var modeHUDPresenters: [MouseSource: AppKitModeHUDPresenter] = [:]

    private let permission = AccessibilityPermission()
    private var targetResolvers: [MouseSource: TextTargetResolving] = [:]
    private var focusMonitor: FocusMonitoring?

    private var lightingController: ICUELightingController?
    private var lightingCoordinator: LightingCoordinator?
    private var razerLightingController: RazerVendorLightingController?
    private var multiTapCoordinators: [MouseSource: MultiTapCoordinator] = [:]
    private var colorProofCoordinator: ColorProofCoordinator?
    private var modePickerCoordinators: [MouseSource: ModePickerCoordinator] = [:]
    private var defaultMapHintCoordinators: [MouseSource: DefaultMapHintCoordinator] = [:]
    private var sessionSecurityController: SessionSecurityController?
    private var userCommandReceiver: KarabinerUserCommandReceiver?
    private var modeInputTransports: [MouseSource: KarabinerModeInputTransport] = [:]
    private lazy var codexModeActionExecutor = CodexModeActionExecutor(
        inputAllowed: { [weak self] in self?.mouseCommandsAllowed == true }
    )
    private lazy var applicationShortcutDispatcher = ApplicationShortcutDispatcher(
        inputAllowed: { [weak self] in self?.mouseCommandsAllowed == true }
    )
    private lazy var selectedAreaScreenshotController: SelectedAreaScreenshotController = {
        let controller = SelectedAreaScreenshotController(
            inputAllowed: { [weak self] in self?.mouseCommandsAllowed == true }
        )
        controller.onCapturingChange = { [weak self] _ in
            self?.defaultMapHintCoordinators.values.forEach { $0.refresh() }
        }
        return controller
    }()
    private let modeUtilityActionExecutor = ModeUtilityActionExecutor()
    private lazy var keysModeActionExecutor = KeysModeActionExecutor(
        inputAllowed: { [weak self] in self?.mouseCommandsAllowed == true }
    )
    private var suspendedDefaultMapSources: Set<MouseSource> = []
    private var macroKeyTransport: ICUEMacroKeyTransport?
    private var corsairRecoveryMonitor: ICUEDeviceRecoveryMonitor?
    private var deviceRefreshGeneration: UInt64 = 0

    private var selectedDevice: ICUEDevice?
    private var shouldMaintainICUESession = false
    private var sessionReconnectGeneration: UInt64 = 0
    private var sessionReconnectAttempt = 0

    override init() {
        let sink = CompositeLogSink([OSLogSink(), StandardErrorLogSink(minimumLevel: .info)])
        self.logSink = sink
        self.log = Log(category: "app", sink: sink)
        super.init()
    }

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        startSessionSecurityBoundary()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory: no Dock icon, and — critically — the app can never become
        // active, which is what keeps the HUD from stealing focus.
        NSApp.setActivationPolicy(.accessory)

        installTerminationHandlers()
        installWorkspaceObservers()
        sessionSecurityController?.confirmActiveSessionAfterLaunch()
        loadConfiguration()
        launchAtLoginState = launchAtLoginController.ensureRegistered(log: log)

        rebuildHUDPresenters()
        statusItem = StatusItemController()
        statusItem?.onQuit = { [weak self] in self?.quit() }
        statusItem?.onReloadConfiguration = { [weak self] in self?.reload() }
        statusItem?.onToggleMode = { [weak self] in self?.toggleMode() }
        statusItem?.onSetKeysPassword = { [weak self] in self?.promptToStoreKeysPassword() }
        statusItem?.onClearKeysPassword = { [weak self] in self?.confirmClearKeysPassword() }

        startDefaultMapHint()
        startRazerLighting()
        startModePicker()
        startKarabinerUserCommands()
        startICUE()
        startMultiTap()
        startFocusMonitoring()
        log.info("Accessibility trusted: \(permission.isTrusted)")
        refreshStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionSecurityController?.stop()
        teardown()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Runs on every exit path, including signals.
    private func teardown() {
        shouldMaintainICUESession = false
        sessionReconnectGeneration &+= 1
        sessionReconnectAttempt = 0
        defaultMapHintCoordinators.values.forEach { $0.shutdown() }
        modePickerCoordinators.values.forEach { $0.shutdown() }
        colorProofCoordinator?.shutdown()
        userCommandReceiver?.stop()
        selectedAreaScreenshotController.cancel()
        multiTapCoordinators.values.forEach { $0.shutdown() }
        modeInputTransports.values.forEach { $0.stop() }
        macroKeyTransport?.stop()
        corsairRecoveryMonitor?.stop()
        lightingCoordinator?.releaseEverything()
        razerLightingController?.release()
        deviceRefreshGeneration &+= 1
        focusMonitor?.stop()
        ICUESession.shared.disconnect()
        ICUESession.shared.onStateChange = nil
        ICUESession.shared.onDeviceConnectionChange = nil

        keypadHUDPresenters.values.forEach { $0.hide() }
        modeHUDPresenters.values.forEach { $0.hide() }
        keypadHUDPresenters.removeAll()
        multiTapCoordinators.removeAll()
        colorProofCoordinator = nil
        modePickerCoordinators.removeAll()
        defaultMapHintCoordinators.removeAll()
        userCommandReceiver = nil
        modeInputTransports.removeAll()
        suspendedDefaultMapSources.removeAll()
        macroKeyTransport = nil
        corsairRecoveryMonitor = nil
        lightingCoordinator = nil
        razerLightingController = nil
        lightingController = nil
        targetResolvers.removeAll()
        focusMonitor = nil
        selectedDevice = nil
        log.info("shutdown complete; mouse returned to iCUE")
    }

    private func installTerminationHandlers() {
        // A crash or a kill already restores everything (iCUE drops the client
        // and the OS tears down any tap), but a clean signal path means the
        // lighting layer is released immediately rather than a moment later.
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { [weak self] in
                self?.sessionSecurityController?.stop()
                self?.teardown()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private var signalSources: [DispatchSourceSignal] = []

    private var mouseCommandsAllowed: Bool {
        sessionSecurityController?.isUnlocked == true
    }

    private func startSessionSecurityBoundary() {
        let lease = KarabinerCLIModeLease(
            leaseDuration: 3,
            variableName: SessionSecurityController.variableName
        )
        let controller = SessionSecurityController(
            observer: WorkspaceSessionActivityObserver(),
            lease: lease,
            scheduler: DispatchTickScheduler(),
            log: Log(category: "session-security", sink: logSink)
        )
        controller.onLockdown = { [weak self] in self?.handleSessionLocked() }
        controller.onUnlock = { [weak self] in self?.handleSessionUnlocked() }
        lease.onFailure = { [weak controller] error in
            controller?.handleLeaseFailure(error)
        }
        sessionSecurityController = controller
        controller.start()
    }

    private func handleSessionLocked() {
        modePickerCoordinators.values.forEach { $0.handleSystemSleep() }
        colorProofCoordinator?.handleSystemSleep()
        multiTapCoordinators.values.forEach { $0.exit(reason: .shuttingDown) }
        defaultMapHintCoordinators.values.forEach { $0.shutdown() }
        selectedAreaScreenshotController.cancel()
        suspendedDefaultMapSources.removeAll()
        refreshStatus()
    }

    private func handleSessionUnlocked() {
        // Never restore a mode, page, legend, selection, or pending text after
        // authentication. A fresh short lease enables only the ordinary map.
        refreshStatus()
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        modePickerCoordinators.values.forEach { $0.handleSystemSleep() }
        colorProofCoordinator?.handleSystemSleep()
        multiTapCoordinators.values.forEach { $0.exit(reason: .shuttingDown) }
        lightingCoordinator?.releaseEverything()
        razerLightingController?.release()
        refreshStatus()
    }

    @objc private func systemDidWake(_ notification: Notification) {
        if ICUESession.shared.state.isUsable, selectedDevice != nil {
            lightingCoordinator?.handleSessionRestored()
        }
        _ = razerLightingController?.restoreIdle()
        refreshStatus()
    }

    // MARK: - Configuration

    private func loadConfiguration() {
        let (loaded, warnings) = ConfigurationLoader.load(log: log)
        configuration = loaded
        configurationWarnings = warnings
        warnings.forEach { log.notice($0) }
    }

    private func reload() {
        log.info("reloading configuration")
        teardown()
        loadConfiguration()
        rebuildHUDPresenters()
        startDefaultMapHint()
        startRazerLighting()
        startModePicker()
        startKarabinerUserCommands()
        startICUE()
        startMultiTap()
        refreshStatus()
    }

    private func rebuildHUDPresenters() {
        keypadHUDPresenters.values.forEach { $0.hide() }
        modeHUDPresenters.values.forEach { $0.hide() }
        keypadHUDPresenters = Dictionary(
            uniqueKeysWithValues: MouseSource.allCases.map { source in
                (source, AppKitHUDPresenter(source: source, configuration: configuration.hud))
            }
        )
        modeHUDPresenters = Dictionary(
            uniqueKeysWithValues: MouseSource.allCases.map { source in
                (source, AppKitModeHUDPresenter(source: source, configuration: configuration.hud))
            }
        )
    }

    private func quit() {
        sessionSecurityController?.stop()
        teardown()
        NSApp.terminate(nil)
    }

    // MARK: - iCUE

    private func startICUE() {
        guard configuration.lighting.enabled || configuration.multiTap.enabled else {
            shouldMaintainICUESession = false
            return
        }
        shouldMaintainICUESession = true

        let session = ICUESession.shared
        session.configure(log: Log(category: "icue", sink: logSink))

        let searchPaths = configuration.lighting.sdkSearchPaths
            + ICUESession.defaultLibrarySearchPaths(bundlePath: Bundle.main.bundlePath)

        guard case .success = session.loadLibrary(searchPaths: searchPaths) else {
            log.notice("iCUE SDK not found. Lighting and multi-tap are unavailable; see docs/SETUP.md.")
            return
        }

        session.onStateChange = { [weak self] state in
            self?.handleSessionState(state)
        }
        session.onDeviceConnectionChange = { [weak self] identifier, connected in
            self?.handleDeviceConnectionChange(identifier: identifier, connected: connected)
        }

        if case .failure(let error) = session.connect() {
            log.notice("iCUE connection start failed: \(error)")
            scheduleSessionReconnect()
        }

        if configuration.lighting.enabled {
            let controller = ICUELightingController(
                session: session,
                matcher: configuration.lighting.device,
                layerPriority: configuration.lighting.layerPriority,
                log: Log(category: "lighting", sink: logSink)
            )
            lightingController = controller

            let throttled = ThrottlingLightingController(
                wrapping: controller,
                minimumInterval: 1.0 / max(1, configuration.lighting.maximumWritesPerSecond)
            )
            lightingCoordinator = LightingCoordinator(
                controller: throttled,
                modeStyle: configuration.lighting.modeIndicatorStyle,
                idleColor: .white,
                clock: SystemMonotonicClock(),
                log: Log(category: "lighting", sink: logSink),
                pulseScheduler: DispatchTickScheduler(),
                deferredFlushScheduler: DispatchTickScheduler()
            )
            colorProofCoordinator?.refreshLightingAvailability()
        }
    }

    private func handleSessionState(_ state: ICUESessionState) {
        log.info("iCUE session \(state.explanation)")
        switch state {
        case .connected:
            sessionReconnectGeneration &+= 1
            sessionReconnectAttempt = 0
            // Device connection events belong to the app/session lifecycle,
            // not to a macro transport that cannot exist until a device has
            // already been selected. This is what makes wake-after-launch and
            // lighting-only configurations recover.
            if case .failure(let error) = ICUESession.shared.subscribeToEvents() {
                log.error("could not subscribe to iCUE device events: \(error); reconnecting the SDK session")
                // Without this subscription, a mouse that is asleep/absent at
                // connect has no event path that can ever bootstrap selection.
                // Fail the whole client session and let the bounded reconnect
                // lifecycle retry instead of pretending this is usable.
                ICUESession.shared.disconnectForRollbackSafety()
                refreshStatus()
                return
            }
            _ = lightingController?.refreshDevice()
            _ = refreshSelectedDevice()
            lightingCoordinator?.handleSessionRestored()
            colorProofCoordinator?.refreshLightingAvailability()
            // Deliberately does *not* re-enter multi-tap mode: a reconnect must
            // never silently put the mouse back into a modal state the user did
            // not ask for.
            restartMacroKeyTransport()
            startCorsairRecoveryMonitor()
        case .connectionLost, .closed, .connectionRefused, .timedOut:
            // Invalidate the transport's local SDK ownership first. Coordinator
            // teardown must not try to unconfigure/release through a session
            // that has already gone terminal.
            macroKeyTransport?.handleSessionLoss()
            multiTapCoordinators[.corsair]?.handleSessionLost()
            lightingCoordinator?.handleSessionLost()
            colorProofCoordinator?.handleLightingUnavailable(.corsair)
            modePickerCoordinators[.corsair]?.handleDeviceLost(.corsair)
            corsairRecoveryMonitor?.stop()
            corsairRecoveryMonitor = nil
            selectedDevice = nil
            scheduleSessionReconnect()
        case .connecting:
            break
        }
        refreshStatus()
    }

    /// Re-establishes a session after connection loss or a rollback fail-safe
    /// disconnect. Reconnect never re-enters multi-tap mode; it only rebuilds
    /// the normal ready state once iCUE reports `.connected` again.
    private func scheduleSessionReconnect() {
        guard shouldMaintainICUESession else { return }
        sessionReconnectGeneration &+= 1
        let generation = sessionReconnectGeneration
        let exponent = min(sessionReconnectAttempt, 6)
        let delay = min(30.0, 0.5 * pow(2.0, Double(exponent)))
        sessionReconnectAttempt += 1

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self,
                  self.shouldMaintainICUESession,
                  generation == self.sessionReconnectGeneration,
                  !ICUESession.shared.state.isUsable
            else { return }

            if case .failure(let error) = ICUESession.shared.connect() {
                self.log.notice("iCUE reconnect failed: \(error)")
                self.scheduleSessionReconnect()
            }
        }
    }

    private func handleDeviceConnectionChange(identifier: String, connected: Bool) {
        deviceRefreshGeneration &+= 1
        let generation = deviceRefreshGeneration
        let previousIdentifier = selectedDevice?.identifier

        // Every disconnect event is authoritative even if enumeration is
        // stale. Always exclude that id: a delayed disconnect for old device A
        // must not make the current replacement B ambiguous with stale A.
        let excluded: Set<String> = connected ? [] : [identifier]
        _ = refreshSelectedDevice(excluding: excluded)
        _ = lightingController?.refreshDevice(excluding: excluded)

        let currentIdentifier = selectedDevice?.identifier
        if connected, currentIdentifier == nil {
            scheduleOneDeviceRefreshRetry(generation: generation)
        }
        if connected, currentIdentifier != nil {
            // Refresh even when the identifier is unchanged. The lighting
            // controller may have forgotten that same device after a transient
            // CE_DeviceNotFound write.
            lightingCoordinator?.handleSessionRestored()
            if currentIdentifier == previousIdentifier,
               macroKeyTransport?.isRunning != true {
                restartMacroKeyTransport(excluding: excluded)
            }
            refreshStatus()
        }

        guard currentIdentifier != previousIdentifier else { return }

        if previousIdentifier != nil {
            log.notice("the selected Scimitar changed or disconnected")
            // Mark the transport's SDK state dead before the coordinator exits;
            // otherwise teardown would try to unconfigure a device that has
            // already disappeared and unnecessarily trigger a safety session
            // disconnect.
            macroKeyTransport?.handleSessionLoss()
            multiTapCoordinators[.corsair]?.handleDeviceLost()
            colorProofCoordinator?.handleDeviceLost(.corsair)
            modePickerCoordinators[.corsair]?.handleDeviceLost(.corsair)
        }

        if currentIdentifier != nil {
            lightingCoordinator?.handleSessionRestored()
        } else {
            lightingCoordinator?.handleSessionLost()
        }
        if macroKeyTransport?.isRunning != true || previousIdentifier != currentIdentifier {
            restartMacroKeyTransport(excluding: excluded)
        }
        corsairRecoveryMonitor?.synchronize(currentCorsairPresence())
        refreshStatus()
    }

    /// Uses read-only device enumeration as a fallback for the Slipstream
    /// receiver re-plug path where iCUE occasionally omits its device callback.
    /// Stable polls are no-ops; only a real transition reasserts idle white or
    /// rebuilds the input transport.
    private func startCorsairRecoveryMonitor() {
        corsairRecoveryMonitor?.stop()
        let monitor = ICUEDeviceRecoveryMonitor(
            initialSnapshot: currentCorsairPresence(),
            scheduler: DispatchTickScheduler(),
            probe: { [weak self] in self?.probeCorsairPresence() ?? .absent },
            onTransition: { [weak self] transition in
                self?.handlePolledCorsairTransition(transition)
            }
        )
        monitor.start()
        corsairRecoveryMonitor = monitor
    }

    private func currentCorsairPresence() -> ICUEDevicePresenceSnapshot {
        ICUEDevicePresenceSnapshot(
            identifier: selectedDevice?.identifier,
            lightingAvailable: lightingController?.isAvailable == true
        )
    }

    private func probeCorsairPresence() -> ICUEDevicePresenceSnapshot {
        guard ICUESession.shared.state.isUsable else { return .absent }
        _ = refreshSelectedDevice()
        _ = lightingController?.refreshDevice()
        return currentCorsairPresence()
    }

    private func handlePolledCorsairTransition(_ transition: ICUEDevicePresenceTransition) {
        switch transition {
        case .lost:
            log.notice("Slipstream recovery monitor observed the Scimitar disconnect")
            macroKeyTransport?.handleSessionLoss()
            multiTapCoordinators[.corsair]?.handleDeviceLost()
            colorProofCoordinator?.handleDeviceLost(.corsair)
            modePickerCoordinators[.corsair]?.handleDeviceLost(.corsair)
            lightingCoordinator?.handleSessionLost()

        case .lightingUnavailable:
            log.notice("Slipstream recovery monitor observed unavailable Scimitar lighting")
            colorProofCoordinator?.handleLightingUnavailable(.corsair)
            lightingCoordinator?.handleSessionLost()

        case .recovered, .replaced:
            log.info("Slipstream recovery monitor restored the Scimitar")
            lightingCoordinator?.handleSessionRestored()
            colorProofCoordinator?.refreshLightingAvailability()
            restartMacroKeyTransport()
        }
        refreshStatus()
    }

    @discardableResult
    private func refreshSelectedDevice(excluding excludedIdentifiers: Set<String> = []) -> DeviceSelectionResult {
        let selection = DeviceSelector.select(
            from: ICUESession.shared.devices(),
            excluding: excludedIdentifiers,
            using: configuration.lighting.device
        )
        selectedDevice = selection.device
        if selection.device == nil { log.notice(selection.explanation) }
        return selection
    }

    /// iCUE can deliver a connection event just before the device appears in
    /// enumeration. Retry once after a short delay; never spin indefinitely and
    /// never guess between multiple matching mice.
    private func scheduleOneDeviceRefreshRetry(generation: UInt64) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self,
                  generation == self.deviceRefreshGeneration,
                  self.selectedDevice == nil,
                  ICUESession.shared.state.isUsable
            else { return }

            let selection = self.refreshSelectedDevice()
            _ = self.lightingController?.refreshDevice()
            guard selection.device != nil else {
                self.refreshStatus()
                return
            }
            self.lightingCoordinator?.handleSessionRestored()
            self.restartMacroKeyTransport()
            self.refreshStatus()
        }
    }

    // MARK: - Reusable mode HUD

    private func startDefaultMapHint() {
        guard configuration.defaultMapHint.enabled else {
            log.info("default-map reminder is compiled but not enabled")
            return
        }
        for source in MouseSource.allCases {
            guard let hud = modeHUDPresenters[source] else { continue }
            defaultMapHintCoordinators[source] = DefaultMapHintCoordinator(
                hud: hud,
                dismissScheduler: DispatchTickScheduler(),
                log: Log(category: "default-map-hint-\(source.rawValue)", sink: logSink),
                source: source,
                isAvailable: { [weak self] in
                    guard let self else { return false }
                    let keypadOwnsSource = self.multiTapCoordinators[source]?.isActive == true
                    return self.colorProofCoordinator?.isActive != true
                        && self.modePickerCoordinators[source]?.isActive != true
                        && !keypadOwnsSource
                },
                isScreenshotCapturing: { [weak self] in
                    self?.selectedAreaScreenshotController.isCapturing == true
                },
                frontmostAppContext: { [weak self] in
                    self?.currentFrontmostAppModeContext()
                },
                displayDuration: configuration.defaultMapHint.displayDuration
            )
        }
    }

    // MARK: - Colour proof

    private func startRazerLighting() {
        let controller = RazerVendorLightingController(
            transport: RazerVendorUSBTransport(),
            idleColor: .white,
            // Equal device bytes look slightly pink beside the Scimitar.
            // Correct only the idle white point; mode colours keep their exact
            // proportions and use the strong full-scale mode output below.
            idleOutputColor: RGBColor(red: 124, green: 129, blue: 130),
            // Idle white is already calibrated above. Runtime mode colours use
            // full strength so modes are unmistakable on the physical mouse.
            brightnessScale: 1.00,
            log: Log(category: "razer-vendor", sink: logSink)
        )
        controller.onProblem = { [weak self] message in
            self?.modeHUDPresenters[.razer]?.flashProblem(message)
        }
        razerLightingController = controller
        _ = controller.restoreIdle()
    }

    private func startColorProof() {
        guard configuration.colorProof.enabled else {
            log.info("colour proof is disabled in the configuration")
            return
        }
        guard let modeHUDPresenter = modeHUDPresenters[.corsair] else { return }

        let lease = KarabinerCLIModeLease(leaseDuration: configuration.colorProof.leaseDuration)
        let coordinator = ColorProofCoordinator(
            lease: lease,
            hud: modeHUDPresenter,
            clock: SystemMonotonicClock(),
            scheduler: DispatchTickScheduler(),
            log: Log(category: "colour-proof", sink: logSink),
            idleTimeout: configuration.colorProof.autoExitAfterIdle,
            absoluteTimeout: configuration.colorProof.absoluteTimeout,
            heartbeatInterval: configuration.colorProof.heartbeatInterval
        )
        coordinator.onColorChange = { [weak self] color in
            guard let self else { return [] }
            var targets: ModeLightingTargets = []
            if self.lightingCoordinator?.setColorProofColor(color) == true {
                targets.insert(.corsair)
            }
            if self.razerLightingController?.setColor(color) == true {
                targets.insert(.razer)
            }
            return targets
        }
        coordinator.onModeChange = { [weak self] active in
            guard let self else { return }
            if active {
                self.defaultMapHintCoordinators.values.forEach { $0.cancel() }
                self.multiTapCoordinators.values.forEach { $0.exit(reason: .userRequested) }
            }
            self.refreshStatus()
        }
        coordinator.onExit = { [weak self] _ in self?.refreshStatus() }
        lease.onFailure = { [weak coordinator] error in
            coordinator?.exit(reason: .leaseFailure("Karabiner variable update failed: \(error)"))
        }
        colorProofCoordinator = coordinator

    }

    // MARK: - Shared mode picker

    private func startModePicker() {
        for source in MouseSource.allCases {
            guard let hud = modeHUDPresenters[source] else { continue }
            let lease = KarabinerCLIModeLease(
                leaseDuration: configuration.colorProof.leaseDuration,
                variableName: "agentic_mouse_mode_picker_\(source.rawValue)_expires_at"
            )
            let coordinator = ModePickerCoordinator(
                lease: lease,
                hud: hud,
                scheduler: DispatchTickScheduler(),
                log: Log(category: "mode-picker-\(source.rawValue)", sink: logSink),
                heartbeatInterval: configuration.colorProof.heartbeatInterval
            )
            coordinator.onAppearanceChange = { [weak self] modeColor, actionColor in
                guard let self else { return [] }
                switch source {
                case .corsair:
                    return self.lightingCoordinator?.setModeAppearance(
                        modeColor: modeColor,
                        actionColor: actionColor
                    ) == true ? [.corsair] : []
                case .razer:
                    return self.razerLightingController?.setModeAppearance(
                        modeColor: modeColor,
                        actionColor: actionColor
                    ) == true ? [.razer] : []
                }
            }
            coordinator.onModeChange = { [weak self] active in
                guard let self else { return }
                if active {
                    if self.defaultMapHintCoordinators[source]?.suspendForMode() != nil {
                        self.suspendedDefaultMapSources.insert(source)
                    }
                    self.colorProofCoordinator?.exit(reason: .userRequested)
                    self.multiTapCoordinators[source]?.exit(reason: .userRequested)
                } else {
                    self.multiTapCoordinators[source]?.exit(reason: .userRequested)
                    if self.mouseCommandsAllowed,
                       self.suspendedDefaultMapSources.remove(source) != nil {
                        self.defaultMapHintCoordinators[source]?.restoreAfterMode(source: source)
                    } else if !self.mouseCommandsAllowed {
                        self.suspendedDefaultMapSources.remove(source)
                    }
                }
                self.refreshStatus()
            }
            coordinator.onKeypadModeRequested = { [weak self] requestedSource in
                guard let self, requestedSource == source else { return false }
                if self.multiTapCoordinators[source]?.isActive == true { return true }
                return self.multiTapCoordinators[source]?.enter(source: source) == true
            }
            coordinator.onKeypadInput = { [weak self] requestedSource, cell, phase in
                guard requestedSource == source else { return }
                self?.modeInputTransports[source]?.deliver(source: source, cell: cell, phase: phase)
            }
            coordinator.resolveFrontmostApp = { [weak self] in
                self?.currentFrontmostAppModeContext() ?? FrontmostAppModeContext(
                    target: nil,
                    displayName: "No frontmost app",
                    bundleIdentifier: nil
                )
            }
            coordinator.onAppSpecificInput = { [weak self] requestedSource, target, cell in
                guard let self, requestedSource == source else { return false }
                let result: Result<Void, ApplicationShortcutDispatcher.DispatchError>
                switch target {
                case .codex:
                    guard let action = CodexModeAction.action(for: cell) else { return false }
                    result = self.codexModeActionExecutor.perform(action)
                case .chrome:
                    guard ChromeModeAction.action(for: cell) == .closeCurrentWindow else {
                        return false
                    }
                    result = self.applicationShortcutDispatcher.perform(
                        .init(keyCode: 13, flags: .maskCommand),
                        targetBundleIdentifier: target.bundleIdentifier,
                        targetDisplayName: target.displayName
                    )
                case .vsCode:
                    return false
                }
                switch result {
                case .success: return true
                case .failure(let error):
                    self.modeHUDPresenters[source]?.flashProblem(error.description)
                    return false
                }
            }
            coordinator.onUtilityAction = { [weak self] requestedSource, action in
                guard let self, requestedSource == source else { return false }
                guard action == .rewindYouTubeFiveSeconds else {
                    // Deterministic native Utility outputs are emitted by the
                    // exact-device Karabiner rule. Reaching this closure for
                    // one of them would risk a duplicate synthetic key cycle.
                    return false
                }
                if case .success = self.modeUtilityActionExecutor.perform(action) { return true }
                return false
            }
            coordinator.onKeysInput = { [weak self] requestedSource, action in
                guard let self, requestedSource == source else { return false }
                switch self.keysModeActionExecutor.perform(action) {
                case .success:
                    return true
                case .failure(.accessibilityPermissionMissing):
                    self.modeHUDPresenters[source]?.flashProblem(
                        "Accessibility permission is required for native Keys-mode actions"
                    )
                    return false
                case .failure(.passwordNotConfigured):
                    self.modeHUDPresenters[source]?.flashProblem(
                        "Set the Keys Mode password from the Agentic Mouse menu"
                    )
                    return false
                case .failure(.inputBlocked):
                    self.modeHUDPresenters[source]?.flashProblem(
                        "Mouse commands are disabled while macOS is locked"
                    )
                    return false
                case .failure:
                    return false
                }
            }
            lease.onFailure = { [weak coordinator] _ in
                coordinator?.exit(reason: .leaseFailure)
            }
            modePickerCoordinators[source] = coordinator
        }
    }

    // MARK: - Karabiner commands

    private func startKarabinerUserCommands() {
        let receiver = KarabinerUserCommandReceiver()
        do {
            try receiver.start { [weak self] data in
                guard let self, self.mouseCommandsAllowed else {
                    self?.log.notice("ignored a mouse command while the macOS session was inactive")
                    return
                }
                if let command = try? ModePickerCommand.decode(data) {
                    self.modePickerCoordinators[command.source]?.handle(command)
                    return
                }
                if let command = try? DefaultMapHintCommand.decode(data) {
                    self.defaultMapHintCoordinators[command.source]?.handleToggle(source: command.source)
                    return
                }
                if let command = try? SelectedAreaScreenshotCommand.decode(data) {
                    switch self.selectedAreaScreenshotController.toggle() {
                    case .started:
                        self.log.info("selected-area screenshot started from \(command.source.displayName)")
                    case .cancelled:
                        self.log.info("selected-area screenshot cancelled from \(command.source.displayName)")
                    case .blocked:
                        self.log.notice("selected-area screenshot rejected while the session was inactive")
                    case .failed(let message):
                        self.log.notice("selected-area screenshot unavailable: \(message)")
                    }
                    return
                }
                self.log.debug("ignored unrelated or malformed Karabiner user command")
            }
            userCommandReceiver = receiver
            log.info("Karabiner user-command receiver ready")
        } catch {
            log.notice("Karabiner user-command receiver unavailable: \(error)")
            modeHUDPresenters.values.forEach {
                $0.flashProblem("Mouse commands unavailable: \(error)")
            }
        }
    }

    // MARK: - Multi-tap

    private func startMultiTap(excluding excludedIdentifiers: Set<String> = []) {
        guard configuration.multiTap.enabled else {
            log.info("multi-tap is disabled in the configuration")
            return
        }
        for source in MouseSource.allCases {
            guard let hud = keypadHUDPresenters[source] else { continue }

            let resolver = AccessibilityTextTargetResolver(
                permission: permission,
                log: Log(category: "target-\(source.rawValue)", sink: logSink)
            )
            targetResolvers[source] = resolver

            let engine = MultiTapEngine(
                keymap: .modesKeypad,
                configuration: configuration.multiTap.engineConfiguration
            )
            let transport = KarabinerModeInputTransport()
            modeInputTransports[source] = transport

            let coordinator = MultiTapCoordinator(
                engine: engine,
                transport: transport,
                textOutput: CGEventTextOutput(
                    permission: permission,
                    targetResolver: resolver,
                    log: Log(category: "text-\(source.rawValue)", sink: logSink)
                ),
                targetResolver: resolver,
                permission: permission,
                hud: hud,
                clock: SystemMonotonicClock(),
                scheduler: DispatchTickScheduler(),
                log: Log(category: "multitap-\(source.rawValue)", sink: logSink),
                entryAllowed: { [weak self] in
                    guard let picker = self?.modePickerCoordinators[source] else { return false }
                    return picker.isActive && (picker.page == .modes || picker.page == .keypad)
                },
                // Runtime Keypad enters through the Modes journey but always exits
                // on the shared physical cell 10. Keep the text engine's safety
                // toggle aligned with that generated universal exit.
                toggleKey: .k10,
                autoExitAfterIdle: configuration.multiTap.autoExitAfterIdle,
                toggleDebounce: configuration.multiTap.toggleDebounce
            )
            transport.delegate = coordinator

            coordinator.onModeChange = { [weak self] _ in self?.refreshStatus() }
            coordinator.onEntryRefused = { [weak self] reasons in
                self?.log.notice(
                    "\(source.displayName) entry refused: \(reasons.joined(separator: " | "))"
                )
                self?.refreshStatus()
            }
            coordinator.onExit = { [weak self] _ in
                guard let self else { return }
                if self.modePickerCoordinators[source]?.isActive == true,
                   self.modePickerCoordinators[source]?.page == .keypad {
                    self.modePickerCoordinators[source]?.exit(reason: .userRequested)
                }
                self.refreshStatus()
            }

            multiTapCoordinators[source] = coordinator
            do {
                try transport.start()
                log.info("\(source.displayName) keypad mode ready — open Utility and choose cell 7")
            } catch {
                log.notice(
                    "\(source.displayName) input transport unavailable: "
                        + MultiTapCoordinator.describe(error)
                )
            }
        }

    }

    private func startFocusMonitoring() {
        // One observer serves both target-anchored Keypad safety and the live
        // frontmost-app HUD. Replacing it avoids duplicate app-change delivery.
        focusMonitor?.stop()
        let monitor = WorkspaceFocusMonitor()
        monitor.onFocusChange = { [weak self] in
            guard let self else { return }
            self.multiTapCoordinators.values.forEach { $0.handleFocusChange() }
            let context = self.currentFrontmostAppModeContext()
            self.modePickerCoordinators.values.forEach { $0.updateFrontmostApp(context) }
            self.defaultMapHintCoordinators.values.forEach { $0.refresh() }
        }
        monitor.start()
        focusMonitor = monitor
    }

    private func currentFrontmostAppModeContext() -> FrontmostAppModeContext {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
            return FrontmostAppModeContext(
                target: nil,
                displayName: "No frontmost app",
                bundleIdentifier: nil
            )
        }
        let bundleIdentifier = application.bundleIdentifier
        return FrontmostAppModeContext(
            target: AppSpecificTarget.target(forBundleIdentifier: bundleIdentifier),
            displayName: application.localizedName ?? bundleIdentifier ?? "Current app",
            bundleIdentifier: bundleIdentifier
        )
    }

    private func makeTransport(excluding excludedIdentifiers: Set<String> = []) -> InputTransport? {
        switch configuration.input.transport {
        case .icueMacroKey:
            let selection = refreshSelectedDevice(excluding: excludedIdentifiers)
            guard let device = selection.device else {
                log.notice(selection.explanation)
                return nil
            }
            selectedDevice = device
            let transport = ICUEMacroKeyTransport(
                session: ICUESession.shared,
                deviceIdentifier: device.identifier,
                expectedMacroKeys: configuration.input.gridMacroKeys,
                log: Log(category: "input", sink: logSink)
            )
            macroKeyTransport = transport
            return transport

        case .cgEventTap:
            guard let bindings = configuration.input.fallbackLogicalBindings,
                  let toggleKey = MultiTapKey(rawValue: configuration.input.toggleKey),
                  let toggleBinding = bindings.first(where: { $0.value == toggleKey })?.key
            else {
                log.error("cgEventTap transport selected but fallbackBindings is not an exact, unique k1...k12 map")
                return nil
            }
            return CGEventTapInputTransport(
                logicalKeyByBinding: bindings,
                alwaysInterceptedBindings: [toggleBinding],
                permission: permission,
                log: Log(category: "input", sink: logSink)
            )
        }
    }

    /// (Re)builds the input stack against the device iCUE has just told us about.
    ///
    /// This is also the *first* time the stack can be built on a cold launch:
    /// `applicationDidFinishLaunching` runs before `CorsairConnect` has
    /// completed, so no device is selectable yet and `startMultiTap()` bails out
    /// early. The session-connected callback is what actually gets multi-tap
    /// running, so this must not require a coordinator to already exist.
    private func restartMacroKeyTransport(excluding excludedIdentifiers: Set<String> = []) {
        // Multi-tap now receives both mice through the exact-device Karabiner
        // mode stream. iCUE reconnects must not rebuild or duplicate it.
        _ = excludedIdentifiers
    }

    private func toggleMode() {
        guard mouseCommandsAllowed else { return }
        let active = modePickerCoordinators.filter { $0.value.isActive }
        if !active.isEmpty {
            active.values.forEach { $0.exit(reason: .userRequested) }
            return
        }
        modePickerCoordinators[.corsair]?.enter(source: .corsair)
    }

    // MARK: - Stored Keys password

    private func promptToStoreKeysPassword() {
        guard mouseCommandsAllowed else { return }
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Password"

        let alert = NSAlert()
        alert.messageText = "Set Keys Mode password"
        alert.informativeText = "Stored only in this Mac's Keychain. Keys Mode cell 2 types it directly without using the clipboard."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            field.stringValue = ""
            return
        }
        let password = field.stringValue
        field.stringValue = ""
        guard !password.isEmpty else {
            showPasswordStorageProblem("The password was empty.")
            return
        }
        if case .failure(let error) = StoredPasswordKeychain.save(password) {
            showPasswordStorageProblem("Keychain could not save the password (\(error)).")
        }
        refreshStatus()
    }

    private func confirmClearKeysPassword() {
        guard mouseCommandsAllowed else { return }
        let alert = NSAlert()
        alert.messageText = "Clear Keys Mode password?"
        alert.informativeText = "This removes the device-local Keychain item."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if case .failure(let error) = StoredPasswordKeychain.clear() {
            showPasswordStorageProblem("Keychain could not clear the password (\(error)).")
        }
        refreshStatus()
    }

    private func showPasswordStorageProblem(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Keys Mode password unavailable"
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: - Status

    private func refreshStatus() {
        var warnings = configurationWarnings
        if !mouseCommandsAllowed {
            warnings.insert(
                "Mouse commands are disabled until the macOS user session is active.",
                at: 0
            )
        }
        if configuration.multiTap.enabled, !permission.isTrusted {
            warnings.insert("Accessibility permission is required for multi-tap mode.", at: 0)
        }
        if let selection = lightingController?.lastSelection, selection.device == nil {
            warnings.append(selection.explanation)
        }

        statusItem?.update(
            StatusItemController.Status(
                isModeActive: multiTapCoordinators.values.contains(where: { $0.isActive })
                    || (colorProofCoordinator?.isActive ?? false)
                    || modePickerCoordinators.values.contains(where: { $0.isActive }),
                activeModeName: activeModeSummary(),
                multiTapEnabled: configuration.multiTap.enabled,
                accessibilityGranted: permission.isTrusted,
                keysPasswordConfigured: StoredPasswordKeychain.isConfigured,
                launchAtLoginState: launchAtLoginState,
                icueState: ICUESession.shared.state.explanation,
                deviceDescription: (lightingController?.device ?? selectedDevice?.summary)
                    .map { "\($0.model) · \($0.ledCount) LEDs" },
                warnings: warnings
            )
        )
    }

    private func activeModeSummary() -> String? {
        let active = MouseSource.allCases.compactMap { source -> String? in
            guard let coordinator = modePickerCoordinators[source], coordinator.isActive else {
                return nil
            }
            let name: String
            switch coordinator.page {
            case .modes: name = "Utility"
            case .keypad: name = "Keypad"
            case .appSelector: name = "Choose app"
            case .appSpecific: name = "App-specific"
            case .keys: name = "Keys"
            }
            return "\(source.displayName) \(name)"
        }
        if !active.isEmpty { return active.joined(separator: " + ") }
        if colorProofCoordinator?.isActive == true { return "Colour proof" }
        if multiTapCoordinators.values.contains(where: { $0.isActive }) { return "Keypad mode" }
        return nil
    }
}
