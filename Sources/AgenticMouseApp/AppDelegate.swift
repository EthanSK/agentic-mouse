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
    nonisolated static let wakeNotifications = [
        NSWorkspace.didWakeNotification,
        NSWorkspace.screensDidWakeNotification,
    ]

    private struct PendingSpaceDiagnostic {
        let source: MouseSource
        let actionTitle: String
        let detentCount: Int
        let sentAt: TimeInterval
        let generation: UInt64
    }

    private let logSink: LogSink
    private var log: Log
    private var runtimeRetention = ApplicationRuntimeRetention()

    private var configuration: AppConfiguration = .default
    private var configurationWarnings: [String] = []

    private var statusItem: StatusItemController?
    private let launchAtLoginController = LaunchAtLoginController()
    private var launchAtLoginState = "unknown"
    private var isQuitInProgress = false
    private var keypadHUDPresenters: [MouseSource: AppKitHUDPresenter] = [:]
    private var modeHUDPresenters: [MouseSource: AppKitModeHUDPresenter] = [:]
    /// Shared across both source HUDs and app-mode resolution so an installed
    /// app icon is loaded and sampled only once per process lifetime.
    private let appIconProvider = WorkspaceModeHUDAppIconProvider()

    private let permission = AccessibilityPermission()
    private var targetResolvers: [MouseSource: TextTargetResolving] = [:]
    private var focusMonitor: FocusMonitoring?
    private var runtimeHealthMonitor: RuntimeHealthMonitor?
    private var wheelChordLastProblem: String?
    private var karabinerReceiverLastProblem: String?

    private var lightingController: ICUELightingController?
    private var lightingCoordinator: LightingCoordinator?
    private var razerLightingController: RazerVendorLightingController?
    private var razerRecoveryMonitor: RazerDeviceRecoveryMonitor?
    private var multiTapCoordinators: [MouseSource: MultiTapCoordinator] = [:]
    private var colorProofCoordinator: ColorProofCoordinator?
    private var modePickerCoordinators: [MouseSource: ModePickerCoordinator] = [:]
    private var vsCodeModeGestureClassifiers: [MouseSource: VSCodeModeGestureClassifier] = [:]
    private var defaultMapHintCoordinators: [MouseSource: DefaultMapHintCoordinator] = [:]
    private var sessionSecurityController: SessionSecurityController?
    private var userCommandReceiver: KarabinerUserCommandReceiver?
    private var modeInputTransports: [MouseSource: KarabinerModeInputTransport] = [:]
    private var wheelChordMonitor: ScrollWheelChordMonitor?
    private var pendingSpaceDiagnostic: PendingSpaceDiagnostic?
    private var spaceDiagnosticGeneration: UInt64 = 0
    private var wakeRecoveryGate = WakeRecoveryGate()
    private lazy var magnetWheelActionSequencer = MagnetWheelActionSequencer(
        perform: { [weak self] request in
            self?.performSequencedMagnetAction(request)
        },
        inputAllowed: { [weak self] in self?.mouseCommandsAllowed == true }
    )
    private lazy var codexModeActionExecutor = CodexModeActionExecutor(
        inputAllowed: { [weak self] in self?.mouseCommandsAllowed == true }
    )
    private var codexEditOwner: MouseSource?
    private lazy var applicationShortcutDispatcher = ApplicationShortcutDispatcher(
        inputAllowed: { [weak self] in self?.mouseCommandsAllowed == true }
    )
    private lazy var vsCodeCommandBridge = VSCodeCommandBridge(
        inputAllowed: { [weak self] in self?.mouseCommandsAllowed == true }
    )
    private let notificationCenterToggleVerifier = NotificationCenterToggleVerifier()
    private lazy var chromeYouTubeSpeedHoldController: ChromeYouTubeSpeedHoldController = {
        let controller = ChromeYouTubeSpeedHoldController(
            inputAllowed: { [weak self] in self?.mouseCommandsAllowed == true }
        )
        controller.onStickyLockChange = { [weak self] source, locked in
            self?.modeHUDPresenters[source]?.flashFeedback(ModeHUDFeedback(
                message: locked ? "2× lock requested" : "1× speed requested",
                tone: .informational
            ))
        }
        return controller
    }()
    private lazy var selectedAreaScreenshotController: SelectedAreaScreenshotController = {
        let controller = SelectedAreaScreenshotController(
            inputAllowed: { [weak self] in self?.mouseCommandsAllowed == true }
        )
        controller.onStateChange = { [weak self] in
            self?.defaultMapHintCoordinators.values.forEach { $0.refresh() }
        }
        controller.onAsynchronousResult = { [weak self] source, result in
            self?.handleScreenshotTriggerResult(result, source: source)
        }
        controller.onClipboardCopy = { [weak self] source, result in
            switch result {
            case .success(let url):
                self?.log.info("selected-area screenshot copied from \(url.lastPathComponent)")
                self?.modeHUDPresenters[source]?.flashFeedback(ModeHUDFeedback(
                    message: "Screenshot copied",
                    tone: .confirmed
                ))
            case .failure(let error):
                self?.log.notice("selected-area screenshot copy failed: \(error.localizedDescription)")
                self?.modeHUDPresenters[source]?.flashProblem(error.localizedDescription)
            }
        }
        controller.onCompletion = { [weak self] result in
            switch result {
            case .completed:
                self?.log.info("native selected-area screenshot interaction completed")
            case .cancelled:
                self?.log.info("selected-area screenshot selection cancelled")
            case .failed(let message):
                self?.log.notice("selected-area screenshot failed: \(message)")
            }
        }
        return controller
    }()
    private lazy var modeUtilityActionExecutor = ModeUtilityActionExecutor(
        inputAllowed: { [weak self] in self?.mouseCommandsAllowed == true },
        typeStoredPassword: { [weak self] in
            self?.keysModeActionExecutor.performStoredPassword() ?? .failure(.inputBlocked)
        }
    )
    private lazy var claudeModeActionExecutor = ClaudeModeActionExecutor(
        shortcutDispatcher: applicationShortcutDispatcher,
        inputAllowed: { [weak self] in self?.mouseCommandsAllowed == true }
    )
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

        // Take AppKit's supported process-lifetime automatic-termination
        // opt-out as soon as did-finish begins. The signed login helper is the
        // recovery layer, but there is no reason to leave a launch-time gap.
        runtimeRetention.retain()
        installTerminationHandlers()
        installWorkspaceObservers()
        sessionSecurityController?.confirmActiveSessionAfterLaunch()
        loadConfiguration()
        launchAtLoginState = launchAtLoginController.ensureRegistered(
            revision: runtimeSupervisorRevision(),
            log: log,
            onStatusChange: { [weak self] state in
                guard let self else { return }
                self.launchAtLoginState = state
                self.refreshStatus()
            }
        )

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
        startWheelChordMonitor()
        startKarabinerUserCommands()
        startICUE()
        startMultiTap()
        startFocusMonitoring()
        startRuntimeHealthMonitor()
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
        runtimeHealthMonitor?.stop()
        runtimeHealthMonitor = nil
        notificationCenterToggleVerifier.cancel()
        codexModeActionExecutor.cancelPendingActions()
        codexEditOwner = nil
        sessionReconnectGeneration &+= 1
        sessionReconnectAttempt = 0
        defaultMapHintCoordinators.values.forEach { $0.shutdown() }
        modePickerCoordinators.values.forEach { $0.shutdown() }
        vsCodeModeGestureClassifiers.values.forEach { $0.cancel() }
        colorProofCoordinator?.shutdown()
        userCommandReceiver?.stop()
        wheelChordMonitor?.stop()
        magnetWheelActionSequencer.cancelAll()
        chromeYouTubeSpeedHoldController.cancelAll()
        pendingSpaceDiagnostic = nil
        spaceDiagnosticGeneration &+= 1
        selectedAreaScreenshotController.cancel()
        multiTapCoordinators.values.forEach { $0.shutdown() }
        modeInputTransports.values.forEach { $0.stop() }
        macroKeyTransport?.stop()
        corsairRecoveryMonitor?.stop()
        razerRecoveryMonitor?.stop()
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
        vsCodeModeGestureClassifiers.removeAll()
        defaultMapHintCoordinators.removeAll()
        userCommandReceiver = nil
        wheelChordMonitor = nil
        modeInputTransports.removeAll()
        suspendedDefaultMapSources.removeAll()
        macroKeyTransport = nil
        corsairRecoveryMonitor = nil
        razerRecoveryMonitor = nil
        lightingCoordinator = nil
        razerLightingController = nil
        lightingController = nil
        targetResolvers.removeAll()
        focusMonitor = nil
        wheelChordLastProblem = nil
        karabinerReceiverLastProblem = nil
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
        codexModeActionExecutor.cancelPendingActions()
        codexEditOwner = nil
        wheelChordMonitor?.clearAll()
        magnetWheelActionSequencer.cancelAll()
        chromeYouTubeSpeedHoldController.cancelAll()
        pendingSpaceDiagnostic = nil
        spaceDiagnosticGeneration &+= 1
        modePickerCoordinators.values.forEach { $0.handleSystemSleep() }
        colorProofCoordinator?.handleSystemSleep()
        multiTapCoordinators.values.forEach { $0.exit(reason: .shuttingDown) }
        defaultMapHintCoordinators.values.forEach { $0.shutdown() }
        selectedAreaScreenshotController.cancel()
        suspendedDefaultMapSources.removeAll()
        SessionLockHUDHider.hideAll(
            modeHUDs: modeHUDPresenters.values,
            keypadHUDs: keypadHUDPresenters.values
        )
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
        for name in Self.wakeNotifications {
            center.addObserver(
                self,
                selector: #selector(systemDidWake),
                name: name,
                object: nil
            )
        }
        center.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        codexModeActionExecutor.cancelPendingActions()
        codexEditOwner = nil
        wheelChordMonitor?.clearAll()
        magnetWheelActionSequencer.cancelAll()
        chromeYouTubeSpeedHoldController.cancelAll()
        notificationCenterToggleVerifier.cancel()
        pendingSpaceDiagnostic = nil
        spaceDiagnosticGeneration &+= 1
        selectedAreaScreenshotController.cancel()
        modePickerCoordinators.values.forEach { $0.handleSystemSleep() }
        colorProofCoordinator?.handleSystemSleep()
        multiTapCoordinators.values.forEach { $0.exit(reason: .shuttingDown) }
        lightingCoordinator?.releaseEverything()
        razerRecoveryMonitor?.stop()
        razerLightingController?.release()
        refreshStatus()
    }

    @objc private func systemDidWake(_ notification: Notification) {
        let now = ProcessInfo.processInfo.systemUptime
        guard wakeRecoveryGate.shouldRecover(at: now) else {
            log.debug("coalesced duplicate screen/system wake recovery")
            return
        }
        if ICUESession.shared.state.isUsable, selectedDevice != nil {
            lightingCoordinator?.handleSessionRestored()
        }
        let razerPresent = RazerVendorUSBTransport.exactDeviceIsPresent()
        let razerRecovered = razerPresent && (razerLightingController?.restoreIdle() == true)
        razerRecoveryMonitor?.synchronize(
            present: razerPresent,
            recovered: razerRecovered
        )
        razerRecoveryMonitor?.start()
        refreshStatus()
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        guard let pending = pendingSpaceDiagnostic else { return }
        pendingSpaceDiagnostic = nil
        let elapsedMilliseconds = max(
            0,
            Int((ProcessInfo.processInfo.systemUptime - pending.sentAt) * 1_000)
        )
        let message = "\(pending.actionTitle) observed · \(pending.detentCount) "
            + "\(Self.ratchetNoun(pending.detentCount).lowercased()) · "
            + "\(elapsedMilliseconds) ms"
        log.info("wheel diagnostic: \(pending.source.displayName): \(message)")
        guard modePickerCoordinators[pending.source]?.isActive == true else { return }
        modeHUDPresenters[pending.source]?.flashFeedback(
            ModeHUDFeedback(message: message, tone: .confirmed)
        )
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
        startWheelChordMonitor()
        startKarabinerUserCommands()
        startICUE()
        startMultiTap()
        startFocusMonitoring()
        startRuntimeHealthMonitor()
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
                (
                    source,
                    AppKitModeHUDPresenter(
                        source: source,
                        configuration: configuration.hud,
                        appIconProvider: appIconProvider
                    )
                )
            }
        )
    }

    private func quit() {
        guard !isQuitInProgress else { return }
        isQuitInProgress = true
        launchAtLoginState = "disarming for Quit"
        refreshStatus()
        launchAtLoginController.disableForIntentionalQuit(log: log) { [weak self] result in
            guard let self else { return }
            self.isQuitInProgress = false
            switch result {
            case .success:
                self.sessionSecurityController?.stop()
                self.teardown()
                NSApp.terminate(nil)
            case .failure:
                self.launchAtLoginState = "Quit cancelled — recovery was not safely disarmed"
                if !self.configurationWarnings.contains(where: { $0.hasPrefix("Quit cancelled:") }) {
                    self.configurationWarnings.append(
                        "Quit cancelled: Agentic Mouse could not safely disable runtime self-recovery"
                    )
                }
                self.refreshStatus()
            }
        }
    }

    private func runtimeSupervisorRevision() -> String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "unknown"
        return "\(version)-\(build)-\(Bundle.main.bundleURL.resolvingSymlinksInPath().path)"
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
                screenshotActionState: { [weak self] in
                    self?.selectedAreaScreenshotController.presentationState ?? .idle
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
        razerRecoveryMonitor?.stop()
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
        let initiallyPresent = RazerVendorUSBTransport.exactDeviceIsPresent()
        let initiallyRecovered = controller.restoreIdle()
        let monitor = RazerDeviceRecoveryMonitor(
            initiallyPresent: initiallyPresent,
            initiallyRecovered: initiallyRecovered,
            scheduler: DispatchTickScheduler(),
            probePresence: { RazerVendorUSBTransport.exactDeviceIsPresent() },
            recover: { [weak controller] in controller?.restoreIdle() == true },
            onLost: { [weak self, weak controller] in
                self?.log.notice("Razer recovery monitor observed the Naga disconnect")
                controller?.handleDeviceLost()
                self?.colorProofCoordinator?.handleDeviceLost(.razer)
                self?.modePickerCoordinators[.razer]?.handleDeviceLost(.razer)
                self?.refreshStatus()
            },
            onRecovered: { [weak self] in
                self?.log.info("Razer recovery monitor restored idle white")
                self?.colorProofCoordinator?.refreshLightingAvailability()
                self?.refreshStatus()
            }
        )
        monitor.start()
        razerRecoveryMonitor = monitor
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
            let vsCodeGestures = VSCodeModeGestureClassifier(
                clock: SystemMonotonicClock(),
                scheduler: DispatchTickScheduler()
            )
            vsCodeModeGestureClassifiers[source] = vsCodeGestures
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
                self.wheelChordMonitor?.clear(source: source)
                self.magnetWheelActionSequencer.cancel(source: source)
                if active {
                    if self.defaultMapHintCoordinators[source]?.suspendForMode() != nil {
                        self.suspendedDefaultMapSources.insert(source)
                    }
                    self.colorProofCoordinator?.exit(reason: .userRequested)
                    self.multiTapCoordinators[source]?.exit(reason: .userRequested)
                } else {
                    self.chromeYouTubeSpeedHoldController.cancel(source: source)
                    // An exit can be user-driven, but it can also be lock,
                    // sleep, device loss, or lease failure. Drop any bounded
                    // click still awaiting classification so a teardown can
                    // never emit a late Better Git command.
                    self.vsCodeModeGestureClassifiers[source]?.cancel()
                    self.multiTapCoordinators[source]?.exit(reason: .userRequested)
                    if self.mouseCommandsAllowed,
                       self.suspendedDefaultMapSources.remove(source) != nil {
                        self.defaultMapHintCoordinators[source]?.restoreAfterMode(source: source)
                    } else if !self.mouseCommandsAllowed {
                        self.suspendedDefaultMapSources.remove(source)
                    }
                    if self.codexEditOwner == source {
                        self.codexModeActionExecutor.cancelQueuedMessageEdit()
                    }
                    let anotherCodexModeIsActive = self.modePickerCoordinators.values.contains {
                        $0.isActive && $0.page == .appSpecific && $0.appSpecificTarget == .codex
                    }
                    if !anotherCodexModeIsActive {
                        self.codexModeActionExecutor.cancelPendingVerifications()
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
            coordinator.resolveAppSpecificDefinition = { [weak self] target in
                self?.appSpecificDefinition(for: target) ?? target.definition
            }
            coordinator.resolveAppSelectorDefinition = { [weak self] in
                self?.appSelectorDefinition() ?? AppSpecificMode.selectorDefinition
            }
            coordinator.onAppSpecificInput = { [weak self] requestedSource, target, cell, phase in
                guard let self, requestedSource == source else { return false }
                let result: Result<Void, ApplicationShortcutDispatcher.DispatchError>
                switch target {
                case .codex:
                    guard phase == .press else { return true }
                    guard let action = CodexModeAction.action(for: cell) else { return false }
                    let previousEditOwner = self.codexEditOwner
                    if action == .editQueuedMessage {
                        self.codexEditOwner = source
                    }
                    defer {
                        if action == .editQueuedMessage {
                            self.codexEditOwner = previousEditOwner
                        }
                    }
                    result = self.codexModeActionExecutor.perform(action) { [weak self] feedback in
                        guard let self,
                              self.modePickerCoordinators[source]?.isActive == true,
                              self.modePickerCoordinators[source]?.page == .appSpecific,
                              self.modePickerCoordinators[source]?.appSpecificTarget == .codex
                        else { return }
                        let hudFeedback: ModeHUDFeedback
                        switch feedback {
                        case .checking(let message), .sentUnverified(let message):
                            hudFeedback = ModeHUDFeedback(message: message, tone: .informational)
                        case .confirmed(let message):
                            hudFeedback = ModeHUDFeedback(message: message, tone: .confirmed)
                        case .notConfirmed(let message):
                            hudFeedback = ModeHUDFeedback(message: message, tone: .notConfirmed)
                        }
                        self.modeHUDPresenters[source]?.flashFeedback(hudFeedback)
                    }
                case .chrome:
                    guard let action = ChromeModeAction.action(for: cell) else { return false }
                    switch action {
                    case .closeCurrentTab, .closeCurrentWindow, .openDevTools, .reloadCurrentTab, .newTab,
                         .focusAddress, .reopenClosedTab, .findPage:
                        guard phase == .press else { return true }
                        guard let shortcut = ChromeModeShortcutResolver.shortcut(for: action) else {
                            return false
                        }
                        result = self.applicationShortcutDispatcher.perform(
                            shortcut,
                            targetBundleIdentifier: target.bundleIdentifier,
                            targetDisplayName: target.displayName
                        )
                    case .holdYouTubeDoubleSpeed:
                        return self.chromeYouTubeSpeedHoldController.handle(
                            source: source,
                            phase: phase
                        )
                    case .cycleTabsWithWheel:
                        return false
                    }
                case .vsCode:
                    guard phase == .press else { return true }
                    guard let action = VSCodeModeAction.action(for: cell) else { return false }
                    guard let classifier = self.vsCodeModeGestureClassifiers[source] else {
                        return false
                    }
                    classifier.handlePress(action: action) { [weak self] command in
                        self?.performVSCodeModeCommand(command, source: source)
                    }
                    return true
                case .terminal, .iTerm:
                    guard let action = TerminalModeAction.action(for: cell) else {
                        return false
                    }
                    guard phase == .press else { return true }
                    guard let shortcut = TerminalModeShortcutResolver.shortcut(for: action) else {
                        self.modeHUDPresenters[source]?.flashProblem(
                            "Could not resolve Interrupt terminal for the current keyboard layout"
                        )
                        return false
                    }
                    result = self.applicationShortcutDispatcher.perform(
                        shortcut,
                        targetBundleIdentifier: target.bundleIdentifier,
                        targetDisplayName: target.displayName
                    )
                case .iPhoneMirroring:
                    guard phase == .press else { return true }
                    guard let action = IPhoneMirroringModeAction.action(for: cell) else {
                        return false
                    }
                    guard let shortcut = IPhoneMirroringModeShortcutResolver.shortcut(
                        for: action
                    ) else {
                        self.modeHUDPresenters[source]?.flashProblem(
                            "Could not resolve Notifications for the current keyboard layout"
                        )
                        return false
                    }
                    let previousVisibility = self.notificationCenterToggleVerifier
                        .captureBeforeToggle()
                    result = self.applicationShortcutDispatcher.performForegroundHardwareShortcut(
                        shortcut,
                        targetBundleIdentifier: target.bundleIdentifier,
                        targetDisplayName: target.displayName
                    )
                    if case .success = result {
                        self.modeHUDPresenters[source]?.flashFeedback(ModeHUDFeedback(
                            message: "Checking Notification Centre…",
                            tone: .informational
                        ))
                        self.notificationCenterToggleVerifier.verifyToggle(
                            from: previousVisibility
                        ) { [weak self] outcome in
                            let feedback: ModeHUDFeedback
                            switch outcome {
                            case .opened:
                                feedback = ModeHUDFeedback(
                                    message: "Notification Centre opened",
                                    tone: .confirmed
                                )
                            case .closed:
                                feedback = ModeHUDFeedback(
                                    message: "Notification Centre closed",
                                    tone: .confirmed
                                )
                            case .unchanged:
                                feedback = ModeHUDFeedback(
                                    message: "Notification Centre did not change",
                                    tone: .notConfirmed
                                )
                            case .unavailable:
                                feedback = ModeHUDFeedback(
                                    message: "Shortcut sent — result not confirmed",
                                    tone: .informational
                                )
                            }
                            self?.modeHUDPresenters[source]?.flashFeedback(feedback)
                        }
                    }
                case .claude:
                    guard phase == .press else { return true }
                    guard let action = ClaudeModeAction.action(for: cell) else {
                        return false
                    }
                    result = self.claudeModeActionExecutor.perform(action)
                case .spotify, .obs, .notion, .telegram, .safari,
                     .firefox, .opera, .restreamChat, .preview, .mail, .iCue,
                     .karabinerSettings, .systemSettings, .finder,
                     .karabinerEventViewer:
                    guard phase == .press else { return true }
                    guard let action = StandardAppMode.action(for: target, cell: cell) else {
                        return false
                    }
                    result = self.applicationShortcutDispatcher.perform(
                        StandardAppModeShortcutResolver.shortcut(for: action),
                        targetBundleIdentifier: target.bundleIdentifier,
                        targetDisplayName: target.displayName
                    )
                }
                switch result {
                case .success: return true
                case .failure(let error):
                    self.modeHUDPresenters[source]?.flashProblem(error.description)
                    return false
                }
            }
            coordinator.onUtilityAction = { [weak self] requestedSource, action in
                guard let self, requestedSource == source else {
                    return .failed(message: nil)
                }
                // ModePicker routes only one-press Utility cards here. Keep
                // held-wheel families out so one detent can never double-fire.
                guard action.isDirectAction else { return .failed(message: nil) }
                switch self.modeUtilityActionExecutor.perform(action) {
                case .success:
                    return .performed
                case .failure(.storedPasswordAccessibilityPermissionMissing):
                    return .failed(message:
                        "Accessibility permission is required to paste the stored password"
                    )
                case .failure(.storedPasswordNotConfigured):
                    return .failed(message:
                        "Set the Utility password from the Agentic Mouse menu"
                    )
                case .failure(.storedPasswordInputBlocked):
                    return .failed(message:
                        "Mouse commands are disabled while macOS is locked"
                    )
                case .failure(.clipboardAccessibilityPermissionMissing):
                    return .failed(message:
                        "Accessibility permission is required for Copy and Paste"
                    )
                case .failure(.clipboardInputBlocked):
                    return .failed(message:
                        "Mouse commands are disabled while macOS is locked"
                    )
                case .failure(.organizeWindowsAccessibilityPermissionMissing):
                    return .failed(message:
                        "Accessibility permission is required to organize windows"
                    )
                case .failure(.organizeWindowsInputBlocked):
                    return .failed(message:
                        "Mouse commands are disabled while macOS is locked"
                    )
                case .failure(.quitAppAccessibilityPermissionMissing):
                    return .failed(message:
                        "Accessibility permission is required to quit the current app"
                    )
                case .failure(.quitAppInputBlocked):
                    return .failed(message:
                        "Mouse commands are disabled while macOS is locked"
                    )
                case .failure(.quitAppTargetUnavailable):
                    return .failed(message: "No app is available to quit")
                case .failure(.intelligenceOnDemandAccessibilityPermissionMissing):
                    return .failed(message:
                        "Accessibility permission is required for Intelligence on demand"
                    )
                case .failure(.intelligenceOnDemandInputBlocked):
                    return .failed(message:
                        "Mouse commands are disabled while macOS is locked"
                    )
                case .failure:
                    return .failed(message: nil)
                }
            }
            coordinator.onWheelControlChange = { [weak self] requestedSource, control in
                guard requestedSource == source else { return }
                if control == nil {
                    self?.magnetWheelActionSequencer.cancel(source: source)
                }
                self?.wheelChordMonitor?.setActive(control, for: source)
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

    private func performVSCodeModeCommand(
        _ command: VSCodeModeCommand,
        source: MouseSource
    ) {
        if command == .toggleTerminal {
            vsCodeCommandBridge.perform(.toggleTerminal) { [weak self] result in
                guard case .failure(let error) = result else { return }
                self?.modeHUDPresenters[source]?.flashProblem(error.description)
            }
            return
        }

        guard let shortcut = VSCodeModeShortcutResolver.shortcut(for: command) else {
            modeHUDPresenters[source]?.flashProblem(
                "Could not resolve Interrupt terminal for the current keyboard layout"
            )
            return
        }

        if case .failure(let error) = applicationShortcutDispatcher.perform(
            shortcut,
            targetBundleIdentifier: AppSpecificTarget.vsCode.bundleIdentifier,
            targetDisplayName: AppSpecificTarget.vsCode.displayName
        ) {
            modeHUDPresenters[source]?.flashProblem(error.description)
        }
    }

    // MARK: - Karabiner commands

    private func startWheelChordMonitor() {
        if let wheelChordMonitor {
            attemptToStartWheelChordMonitor(wheelChordMonitor)
            return
        }
        let monitor = ScrollWheelChordMonitor(
            permission: permission,
            inputAllowed: { [weak self] in self?.mouseCommandsAllowed == true },
            log: Log(category: "wheel-chords", sink: logSink)
        )
        monitor.onStep = { [weak self] step in
            guard let self else { return false }
            if step.control == .horizontalScroll {
                self.scheduleHorizontalWheelAction(step)
                return true
            }
            if let action = step.control.youtubeSeekAction(for: step.direction) {
                self.scheduleYouTubeSeekAction(action, step: step)
                return true
            }
            if let tabAction = step.control.chromeTabAction(for: step.direction) {
                guard let coordinator = self.modePickerCoordinators[step.source],
                      coordinator.isActive,
                      coordinator.page == .appSpecific,
                      coordinator.appSpecificTarget == .chrome,
                      coordinator.activeWheelControl == .chromeTabs
                else { return false }
                self.scheduleChromeTabAction(tabAction, step: step)
                return true
            }
            if let action = step.control.spotifyVolumeAction(for: step.direction) {
                guard let coordinator = self.modePickerCoordinators[step.source],
                      coordinator.isActive,
                      coordinator.page == .appSpecific,
                      coordinator.appSpecificTarget == .spotify,
                      coordinator.activeWheelControl == .spotifyVolume
                else { return false }
                self.scheduleSpotifyVolumeAction(action, step: step)
                return true
            }
            if let command = step.control.vsCodeCursorHistoryCommand(for: step.direction) {
                guard let coordinator = self.modePickerCoordinators[step.source],
                      coordinator.isActive,
                      coordinator.page == .appSpecific,
                      coordinator.appSpecificTarget == .vsCode,
                      coordinator.activeWheelControl == .vsCodeCursorHistory
                else { return false }
                self.scheduleVSCodeCursorHistoryAction(command, step: step)
                return true
            }
            if let action = step.control.codexReasoningEffortAction(for: step.direction) {
                guard let coordinator = self.modePickerCoordinators[step.source],
                      coordinator.isActive,
                      coordinator.page == .appSpecific,
                      coordinator.appSpecificTarget == .codex,
                      coordinator.activeWheelControl == .codexReasoningEffort
                else { return false }
                self.scheduleCodexReasoningEffortAction(action, step: step)
                return true
            }
            if let action = step.control.codexChatHistoryAction(for: step.direction) {
                guard let coordinator = self.modePickerCoordinators[step.source],
                      coordinator.isActive,
                      coordinator.page == .appSpecific,
                      coordinator.appSpecificTarget == .codex,
                      coordinator.activeWheelControl == .codexChatHistory
                else { return false }
                self.scheduleCodexChatHistoryAction(action, step: step)
                return true
            }
            if let action = step.control.topLevelSystemAction(for: step.direction) {
                // Return from the Quartz event-tap callback before posting the
                // Copy/Paste shortcut. This prevents synthetic keyboard input
                // from re-entering the callback that is still consuming the
                // source wheel event.
                self.scheduleUtilityWheelAction(action, step: step)
                return true
            }
            guard let coordinator = self.modePickerCoordinators[step.source],
                  coordinator.isActive,
                  coordinator.page == .modes,
                  coordinator.activeWheelControl == step.control,
                  let action = step.control.utilityAction(for: step.direction)
            else {
                return false
            }
            if action == .moveWindowLeftWithMagnet
                || action == .moveWindowRightWithMagnet {
                // Return from the Quartz wheel callback before opening
                // Magnet's global Control-Option-Arrow accelerator. This
                // prevents synthetic keyboard input from re-entering the tap
                // that is still consuming the source wheel event.
                self.scheduleMagnetAction(
                    action,
                    source: step.source,
                    detentCount: step.detentCount
                )
                return true
            }
            if action == .moveToSpaceLeft || action == .moveToSpaceRight {
                self.scheduleSpaceAction(
                    action,
                    source: step.source,
                    detentCount: step.detentCount
                )
                return true
            }
            self.scheduleUtilityWheelAction(action, step: step)
            return true
        }
        monitor.onProblem = { [weak self] message in
            guard let self else { return }
            let activeSources = self.modePickerCoordinators
                .filter { $0.value.activeWheelControl != nil }
                .map(\.key)
            if activeSources.isEmpty {
                self.modeHUDPresenters.values.forEach { $0.flashProblem(message) }
            } else {
                activeSources.forEach { self.modeHUDPresenters[$0]?.flashProblem(message) }
            }
        }
        monitor.onDiagnostic = { [weak self] source, message in
            self?.defaultMapHintCoordinators[source]?.flashWheelDiagnostic(
                source: source,
                message: message
            )
        }
        wheelChordMonitor = monitor
        attemptToStartWheelChordMonitor(monitor)
    }

    private func attemptToStartWheelChordMonitor(_ monitor: ScrollWheelChordMonitor) {
        guard !monitor.isRunning else { return }
        do {
            try monitor.start()
            if wheelChordLastProblem != nil {
                log.info("wheel-chord event tap recovered")
            }
            wheelChordLastProblem = nil
        } catch {
            let problem = String(describing: error)
            guard wheelChordLastProblem != problem else { return }
            wheelChordLastProblem = problem
            log.notice("wheel-chord event tap unavailable: \(problem)")
            modeHUDPresenters.values.forEach {
                $0.flashProblem("Wheel controls unavailable: \(problem)")
            }
        }
    }

    private func scheduleHorizontalWheelAction(_ step: WheelChordStateMachine.Step) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mouseCommandsAllowed else { return }
            let linesPerRatchet = self.configuration.input.horizontalScrollLinesPerRatchet
            guard ScrollWheelChordMonitor.postHorizontalWheel(
                step.direction,
                linesPerRatchet: linesPerRatchet
            ) else {
                self.modeHUDPresenters[step.source]?.flashProblem(
                    "Horizontal Scroll could not be posted"
                )
                self.flashWheelActionFeedback(
                    step,
                    outcome: .couldNotBeSent
                )
                return
            }
            self.log.info(
                "Horizontal Scroll ratchet \(step.detentCount) posted from "
                    + "\(step.source.displayName) wheel chord at \(linesPerRatchet) lines/ratchet"
            )
            self.flashWheelActionFeedback(step)
        }
    }

    private func scheduleYouTubeSeekAction(
        _ action: YouTubeSeekAction,
        step: WheelChordStateMachine.Step
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.mouseCommandsAllowed,
                  self.wheelChordMonitor?.activeControl(for: step.source) == .youtubeScrub
            else { return }
            switch self.modeUtilityActionExecutor.performYouTubeSeek(action) {
            case .success:
                self.log.info(
                    "YouTube \(action.seconds > 0 ? "+5" : "−5") sec ratchet "
                        + "\(step.detentCount) requested through the VoiceInk bridge from "
                        + step.source.displayName
                )
                self.flashWheelActionFeedback(step)
            case .failure:
                self.flashWheelActionFeedback(step, outcome: .couldNotBeSent)
            }
        }
    }

    private func scheduleChromeTabAction(
        _ tabAction: ChromeTabNavigationAction,
        step: WheelChordStateMachine.Step
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mouseCommandsAllowed else { return }
            let keyCode: CGKeyCode = tabAction == .nextTab ? 124 : 123
            let result = self.applicationShortcutDispatcher.perform(
                .init(
                    keyCode: keyCode,
                    flags: .maskCommand.union(.maskAlternate)
                ),
                targetBundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier,
                targetDisplayName: AppSpecificTarget.chrome.displayName
            )
            switch result {
            case .success:
                let direction = tabAction == .nextTab ? "right" : "left"
                self.log.info(
                    "Chrome tab \(direction) ratchet \(step.detentCount) posted from "
                        + "\(step.source.displayName) wheel chord"
                )
                self.flashWheelActionFeedback(step)
            case .failure(let error):
                self.modeHUDPresenters[step.source]?.flashProblem(error.description)
                self.flashWheelActionFeedback(
                    step,
                    outcome: .couldNotBeSent
                )
            }
        }
    }

    private func scheduleSpotifyVolumeAction(
        _ action: StandardAppModeAction,
        step: WheelChordStateMachine.Step
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mouseCommandsAllowed else { return }
            let result = self.applicationShortcutDispatcher.perform(
                StandardAppModeShortcutResolver.shortcut(for: action),
                targetBundleIdentifier: AppSpecificTarget.spotify.bundleIdentifier,
                targetDisplayName: AppSpecificTarget.spotify.displayName
            )
            switch result {
            case .success:
                self.log.info(
                    "Spotify \(action.title.lowercased()) ratchet \(step.detentCount) posted from "
                        + "\(step.source.displayName) wheel chord"
                )
                self.flashWheelActionFeedback(step)
            case .failure(let error):
                self.modeHUDPresenters[step.source]?.flashProblem(error.description)
                self.flashWheelActionFeedback(
                    step,
                    outcome: .couldNotBeSent
                )
            }
        }
    }

    private func scheduleVSCodeCursorHistoryAction(
        _ command: VSCodeModeCommand,
        step: WheelChordStateMachine.Step
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.mouseCommandsAllowed,
                  self.wheelChordMonitor?.activeControl(for: step.source)
                    == .vsCodeCursorHistory
            else { return }
            let action: VSCodeCommandBridge.Action = command == .navigateForward
                ? .cursorHistoryForward
                : .cursorHistoryBack
            self.vsCodeCommandBridge.perform(action) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    let direction = command == .navigateForward ? "forward" : "back"
                    self.log.info(
                        "VS Code cursor history \(direction) ratchet \(step.detentCount) "
                            + "requested through the direct VS Code bridge from "
                            + "\(step.source.displayName)"
                    )
                    self.flashWheelActionFeedback(step)
                case .failure(let error):
                    self.modeHUDPresenters[step.source]?.flashProblem(error.description)
                    self.flashWheelActionFeedback(
                        step,
                        outcome: .couldNotBeSent
                    )
                }
            }
        }
    }

    private func scheduleCodexReasoningEffortAction(
        _ action: CodexReasoningEffortAction,
        step: WheelChordStateMachine.Step
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.mouseCommandsAllowed,
                  self.wheelChordMonitor?.activeControl(for: step.source)
                    == .codexReasoningEffort
            else { return }
            switch self.codexModeActionExecutor.performReasoningEffort(action) {
            case .success:
                self.log.info(
                    "Codex reasoning effort \(action == .increase ? "up" : "down") "
                        + "ratchet \(step.detentCount) posted from "
                        + "\(step.source.displayName) wheel chord"
                )
                self.flashWheelActionFeedback(step)
            case .failure(let error):
                self.modeHUDPresenters[step.source]?.flashProblem(error.description)
                self.flashWheelActionFeedback(step, outcome: .couldNotBeSent)
            }
        }
    }

    private func scheduleCodexChatHistoryAction(
        _ action: CodexChatHistoryAction,
        step: WheelChordStateMachine.Step
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.mouseCommandsAllowed,
                  self.wheelChordMonitor?.activeControl(for: step.source)
                    == .codexChatHistory
            else { return }
            switch self.codexModeActionExecutor.performChatHistory(action) {
            case .success:
                self.log.info(
                    "Codex chat \(action == .forward ? "forward" : "back") "
                        + "ratchet \(step.detentCount) posted from "
                        + "\(step.source.displayName) wheel chord"
                )
                self.flashWheelActionFeedback(step)
            case .failure(let error):
                self.modeHUDPresenters[step.source]?.flashProblem(error.description)
                self.flashWheelActionFeedback(step, outcome: .couldNotBeSent)
            }
        }
    }

    private func scheduleUtilityWheelAction(
        _ action: ModeUtilityAction,
        step: WheelChordStateMachine.Step
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mouseCommandsAllowed else { return }
            switch self.modeUtilityActionExecutor.perform(action) {
            case .success:
                self.log.info(
                    "\(action.actionTitle) ratchet \(step.detentCount) posted from "
                        + "\(step.source.displayName) wheel chord"
                )
                self.flashWheelActionFeedback(step)
            case .failure:
                if step.control.topLevelCell == nil {
                    self.modeHUDPresenters[step.source]?.flashProblem(
                        "\(action.actionTitle) could not be performed"
                    )
                }
                self.flashWheelActionFeedback(
                    step,
                    outcome: .couldNotBeSent
                )
            }
        }
    }

    private func scheduleSpaceAction(
        _ action: ModeUtilityAction,
        source: MouseSource,
        detentCount: Int
    ) {
        let shortcutName: String
        switch action {
        case .moveToSpaceLeft:
            shortcutName = "CTRL-FN-LEFT"
        case .moveToSpaceRight:
            shortcutName = "CTRL-FN-RIGHT"
        default:
            modeHUDPresenters[source]?.flashProblem("Unexpected top-level Space action")
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.mouseCommandsAllowed else { return }
            switch self.modeUtilityActionExecutor.perform(action) {
            case .success:
                let direction: WheelChordDirection = action == .moveToSpaceRight ? .up : .down
                self.flashWheelActionFeedback(.init(
                    source: source,
                    control: .spaces,
                    direction: direction,
                    detentCount: detentCount
                ))
                self.spaceDiagnosticGeneration &+= 1
                let generation = self.spaceDiagnosticGeneration
                self.pendingSpaceDiagnostic = PendingSpaceDiagnostic(
                    source: source,
                    actionTitle: action.actionTitle,
                    detentCount: detentCount,
                    sentAt: ProcessInfo.processInfo.systemUptime,
                    generation: generation
                )
                self.log.info(
                    "\(shortcutName) posted from \(source.displayName) Utility wheel chord"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    guard let self,
                          self.pendingSpaceDiagnostic?.generation == generation
                    else { return }
                    self.pendingSpaceDiagnostic = nil
                    let message = "\(action.actionTitle) sent · \(detentCount) "
                        + "\(Self.ratchetNoun(detentCount).lowercased()) · "
                        + "no Space change observed"
                    self.log.notice("wheel diagnostic: \(source.displayName): \(message)")
                    guard self.modePickerCoordinators[source]?.isActive == true else { return }
                    self.modeHUDPresenters[source]?.flashFeedback(
                        ModeHUDFeedback(message: message, tone: .notConfirmed)
                    )
                }
            case .failure(let error):
                self.pendingSpaceDiagnostic = nil
                self.log.notice(
                    "\(shortcutName) failed from \(source.displayName) wheel chord: \(error)"
                )
                self.modeHUDPresenters[source]?.flashProblem(
                    "\(shortcutName) could not be posted: \(error)"
                )
                let direction: WheelChordDirection = action == .moveToSpaceRight ? .up : .down
                self.flashWheelActionFeedback(
                    .init(
                        source: source,
                        control: .spaces,
                        direction: direction,
                        detentCount: detentCount
                    ),
                    outcome: .couldNotBeSent
                )
            }
        }
    }

    private func scheduleMagnetAction(
        _ action: ModeUtilityAction,
        source: MouseSource,
        detentCount: Int
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.mouseCommandsAllowed,
                  self.wheelChordMonitor?.activeControl(for: source) == .magnetWindow
            else {
                return
            }
            let accepted = self.magnetWheelActionSequencer.enqueue(.init(
                action: action,
                source: source,
                detentCount: detentCount
            ))
            guard accepted else {
                self.log.notice(
                    "\(action.actionTitle) ratchet \(detentCount) rejected because the "
                        + "bounded Magnet queue is full or input became inactive"
                )
                let direction: WheelChordDirection = action == .moveWindowLeftWithMagnet
                    ? .up
                    : .down
                self.flashWheelActionFeedback(
                    .init(
                        source: source,
                        control: .magnetWindow,
                        direction: direction,
                        detentCount: detentCount
                    ),
                    outcome: .couldNotBeQueued
                )
                return
            }
            self.log.info(
                "\(action.actionTitle) ratchet \(detentCount) queued from "
                    + "\(source.displayName); pending "
                    + "\(self.magnetWheelActionSequencer.pendingCount)"
            )
        }
    }

    private func performSequencedMagnetAction(
        _ request: MagnetWheelActionSequencer.Request
    ) {
        switch modeUtilityActionExecutor.perform(request.action) {
        case .success:
            log.info(
                "\(request.action.actionTitle) ratchet \(request.detentCount) posted from "
                    + "\(request.source.displayName) wheel chord"
            )
            let direction: WheelChordDirection = request.action == .moveWindowLeftWithMagnet
                ? .up
                : .down
            flashWheelActionFeedback(.init(
                source: request.source,
                control: .magnetWindow,
                direction: direction,
                detentCount: request.detentCount
            ))
        case .failure(let error):
            log.notice(
                "\(request.action.actionTitle) ratchet \(request.detentCount) failed from "
                    + "\(request.source.displayName) wheel chord: \(error)"
            )
            modeHUDPresenters[request.source]?.flashProblem(
                "\(request.action.actionTitle) could not be posted: \(error)"
            )
            let direction: WheelChordDirection = request.action == .moveWindowLeftWithMagnet
                ? .up
                : .down
            flashWheelActionFeedback(
                .init(
                    source: request.source,
                    control: .magnetWindow,
                    direction: direction,
                    detentCount: request.detentCount
                ),
                outcome: .couldNotBeSent
            )
        }
    }

    /// Presents one uniform, source-specific result after a held-wheel output
    /// route accepts or rejects the action. Runtime pages already own a visible
    /// HUD; top-level actions may update only an already-open Default legend.
    private func flashWheelActionFeedback(
        _ step: WheelChordStateMachine.Step,
        outcome: WheelChordActionOutcome = .sent
    ) {
        guard let feedback = step.control.hudFeedback(
            for: step.direction,
            detentCount: step.detentCount,
            outcome: outcome
        ) else { return }
        if step.control.topLevelCell != nil {
            defaultMapHintCoordinators[step.source]?.flashWheelFeedback(
                source: step.source,
                feedback: feedback
            )
            return
        }
        guard modePickerCoordinators[step.source]?.isActive == true else { return }
        modeHUDPresenters[step.source]?.flashFeedback(feedback)
    }

    private static func ratchetNoun(_ count: Int) -> String {
        count == 1 ? "RATCHET" : "RATCHETS"
    }

    private func startKarabinerUserCommands() {
        if let userCommandReceiver {
            guard !userCommandReceiver.isHealthy else { return }
            log.notice("Karabiner user-command socket disappeared; rebinding")
            userCommandReceiver.stop()
            self.userCommandReceiver = nil
        }
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
                if let command = try? WheelChordCommand.decodeTopLevel(data) {
                    self.wheelChordMonitor?.setActive(
                        command.phase == .press ? command.control : nil,
                        for: command.source
                    )
                    return
                }
                if let command = try? DefaultMapHintCommand.decode(data) {
                    self.defaultMapHintCoordinators[command.source]?.handleToggle(source: command.source)
                    return
                }
                if let command = try? SelectedAreaScreenshotCommand.decode(data) {
                    let result = self.selectedAreaScreenshotController.handlePress(
                        from: command.source
                    )
                    self.handleScreenshotTriggerResult(result, source: command.source)
                    return
                }
                if let command = try? YouTubeRewindCommand.decode(data) {
                    guard self.modePickerCoordinators[command.source]?.isActive != true else {
                        self.log.notice("ignored delayed top-level YouTube rewind during a mode")
                        return
                    }
                    let feedback: ModeHUDFeedback
                    switch self.modeUtilityActionExecutor.perform(.rewindYouTubeFiveSeconds) {
                    case .success:
                        feedback = ModeHUDFeedback(
                            message: "YouTube −5 sec requested",
                            tone: .informational
                        )
                        self.log.info(
                            "YouTube −5 sec requested from top-level "
                                + command.source.displayName
                        )
                    case .failure:
                        feedback = ModeHUDFeedback(
                            message: "YouTube −5 sec could not be requested",
                            tone: .notConfirmed
                        )
                    }
                    self.defaultMapHintCoordinators[command.source]?.flashActionFeedback(
                        source: command.source,
                        feedback: feedback
                    )
                    return
                }
                self.log.debug("ignored unrelated or malformed Karabiner user command")
            }
            userCommandReceiver = receiver
            if karabinerReceiverLastProblem != nil {
                log.info("Karabiner user-command receiver recovered")
            }
            karabinerReceiverLastProblem = nil
            log.info("Karabiner user-command receiver ready")
        } catch {
            let problem = String(describing: error)
            guard karabinerReceiverLastProblem != problem else { return }
            karabinerReceiverLastProblem = problem
            log.notice("Karabiner user-command receiver unavailable: \(problem)")
            modeHUDPresenters.values.forEach {
                $0.flashProblem("Mouse commands unavailable: \(problem)")
            }
        }
    }

    private func handleScreenshotTriggerResult(
        _ result: SelectedAreaScreenshotController.TriggerResult,
        source: MouseSource
    ) {
        switch result {
        case .awaitingSinglePress:
            log.debug("classifying screenshot press from \(source.displayName)")
        case .started:
            log.info("selected-area screenshot started from \(source.displayName)")
        case .cancelled:
            log.info("selected-area screenshot cancelled from \(source.displayName)")
        case .pasteQueued:
            log.info("screenshot paste queued until the saved image is available")
            modeHUDPresenters[source]?.flashFeedback(ModeHUDFeedback(
                message: "Paste queued",
                tone: .informational
            ))
        case .pasted:
            log.info("screenshot paste shortcut sent from \(source.displayName)")
            modeHUDPresenters[source]?.flashFeedback(ModeHUDFeedback(
                message: "Paste screenshot sent",
                tone: .informational
            ))
        case .blocked:
            log.notice("selected-area screenshot rejected while the session was inactive")
        case .failed(let message):
            log.notice("selected-area screenshot unavailable: \(message)")
            modeHUDPresenters[source]?.flashProblem(message)
        }
    }

    private func startRuntimeHealthMonitor() {
        runtimeHealthMonitor?.stop()
        let monitor = RuntimeHealthMonitor(
            scheduler: DispatchTickScheduler(),
            interval: 2
        ) { [weak self] in
            guard let self else { return }
            if self.userCommandReceiver?.isHealthy != true {
                self.startKarabinerUserCommands()
            }
            if self.wheelChordMonitor?.isRunning != true {
                self.startWheelChordMonitor()
            }
            self.sessionSecurityController?.ensureUnlockProofMonitoring()
        }
        runtimeHealthMonitor = monitor
        monitor.start()
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
                    return picker.isActive && (picker.page == .keys || picker.page == .keypad)
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
                log.info("\(source.displayName) keypad mode ready — open Keys and choose cell 6")
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
            for (source, coordinator) in self.modePickerCoordinators {
                if coordinator.followsFrontmostApp,
                   coordinator.appSpecificTarget == .chrome,
                   context.target != .chrome {
                    self.chromeYouTubeSpeedHoldController.cancel(source: source)
                }
                coordinator.updateFrontmostApp(context)
            }
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
        let backdrop = ModeHUDAppBackdrop(
            bundleIdentifier: bundleIdentifier,
            applicationPath: application.bundleURL?.path
        )
        return FrontmostAppModeContext(
            target: AppSpecificTarget.target(forBundleIdentifier: bundleIdentifier),
            displayName: application.localizedName ?? bundleIdentifier ?? "Current app",
            bundleIdentifier: bundleIdentifier,
            applicationPath: application.bundleURL?.path,
            iconAccent: backdrop.flatMap { appIconProvider.accent(for: $0) }
        )
    }

    private func appSpecificDefinition(
        for target: AppSpecificTarget
    ) -> AppSpecificModeDefinition {
        let accent = ModeHUDAppBackdrop(bundleIdentifier: target.bundleIdentifier)
            .flatMap { appIconProvider.accent(for: $0) }
        guard let accent else { return target.definition }
        return target.definition.replacingIdentityAccent(with: accent)
    }

    private func appSelectorDefinition() -> AppSpecificModeDefinition {
        AppSpecificMode.selectorDefinition { [weak self] target in
            self?.appSpecificDefinition(for: target).accent ?? target.accent
        }
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
        alert.messageText = "Set Utility password"
        alert.informativeText = "Stored only in this Mac's Keychain. Utility cell 7 types it directly without using the clipboard."
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
        alert.messageText = "Clear Utility password?"
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
        alert.messageText = "Utility password unavailable"
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
            case .extraUtilities: name = "Extra Utilities"
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
