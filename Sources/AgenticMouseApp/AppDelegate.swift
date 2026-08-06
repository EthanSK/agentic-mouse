import AppKit
import ScimitarKit
import ScimitarUI

/// Wires the whole helper together.
///
/// Startup is intentionally forgiving: the app runs with whichever subsystems
/// are available. No iCUE means no lighting and no multi-tap, but the menu bar
/// still explains why. No Hue credentials means no mirroring, but multi-tap
/// still works. Nothing is ever half-enabled silently.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logSink: LogSink
    private var log: Log

    private var configuration: AppConfiguration = .default
    private var configurationWarnings: [String] = []

    private var statusItem: StatusItemController?
    private var hudPresenter: AppKitHUDPresenter?

    private let permission = AccessibilityPermission()
    private var targetResolver: TextTargetResolving?
    private var focusMonitor: FocusMonitoring?

    private var lightingController: ICUELightingController?
    private var lightingCoordinator: LightingCoordinator?
    private var multiTapCoordinator: MultiTapCoordinator?
    private var macroKeyTransport: ICUEMacroKeyTransport?
    private var hueObserver: HueRoomObserver?
    /// Owns the asynchronous handler-install/start sequence so teardown can
    /// cancel it before stopping the observer. Without this, a stale startup
    /// task could resume after reload and restart an otherwise abandoned SSE
    /// loop whose callbacks were merely being ignored.
    private var hueLifecycleTask: Task<Void, Never>?
    /// Invalidates callbacks from an observer that is being replaced during a
    /// configuration reload. All reads and writes happen on the main queue.
    private var hueObserverGeneration: UInt64 = 0
    private var deviceRefreshGeneration: UInt64 = 0

    private var selectedDevice: ICUEDevice?
    private var hueStatusText = "idle"
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory: no Dock icon, and — critically — the app can never become
        // active, which is what keeps the HUD from stealing focus.
        NSApp.setActivationPolicy(.accessory)

        installTerminationHandlers()
        loadConfiguration()

        rebuildHUDPresenter()
        statusItem = StatusItemController()
        statusItem?.onQuit = { [weak self] in self?.quit() }
        statusItem?.onReloadConfiguration = { [weak self] in self?.reload() }
        statusItem?.onToggleMode = { [weak self] in self?.toggleMode() }

        startICUE()
        startMultiTap()
        startHue()
        refreshStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardown()
    }

    /// Runs on every exit path, including signals.
    private func teardown() {
        shouldMaintainICUESession = false
        sessionReconnectGeneration &+= 1
        sessionReconnectAttempt = 0
        multiTapCoordinator?.shutdown()
        macroKeyTransport?.stop()
        lightingCoordinator?.releaseEverything()
        hueObserverGeneration &+= 1
        hueLifecycleTask?.cancel()
        hueLifecycleTask = nil
        deviceRefreshGeneration &+= 1
        let observerToStop = hueObserver
        hueObserver = nil
        Task { await observerToStop?.stop() }
        focusMonitor?.stop()
        ICUESession.shared.disconnect()
        ICUESession.shared.onStateChange = nil
        ICUESession.shared.onDeviceConnectionChange = nil

        hudPresenter?.hide()
        multiTapCoordinator = nil
        macroKeyTransport = nil
        lightingCoordinator = nil
        lightingController = nil
        targetResolver = nil
        focusMonitor = nil
        selectedDevice = nil
        hueStatusText = "idle"
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
                self?.teardown()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private var signalSources: [DispatchSourceSignal] = []

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
        rebuildHUDPresenter()
        startICUE()
        startMultiTap()
        startHue()
        refreshStatus()
    }

    private func rebuildHUDPresenter() {
        hudPresenter?.hide()
        hudPresenter = AppKitHUDPresenter(configuration: configuration.hud)
    }

    private func quit() {
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
                clock: SystemMonotonicClock(),
                log: Log(category: "lighting", sink: logSink),
                pulseScheduler: DispatchTickScheduler(),
                deferredFlushScheduler: DispatchTickScheduler()
            )
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
            // Deliberately does *not* re-enter multi-tap mode: a reconnect must
            // never silently put the mouse back into a modal state the user did
            // not ask for.
            restartMacroKeyTransport()
        case .connectionLost, .closed, .connectionRefused, .timedOut:
            // Invalidate the transport's local SDK ownership first. Coordinator
            // teardown must not try to unconfigure/release through a session
            // that has already gone terminal.
            macroKeyTransport?.handleSessionLoss()
            multiTapCoordinator?.handleSessionLost()
            lightingCoordinator?.handleSessionLost()
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
            multiTapCoordinator?.handleDeviceLost()
        }

        if currentIdentifier != nil {
            lightingCoordinator?.handleSessionRestored()
        } else {
            lightingCoordinator?.handleSessionLost()
        }
        if macroKeyTransport?.isRunning != true || previousIdentifier != currentIdentifier {
            restartMacroKeyTransport(excluding: excluded)
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

    // MARK: - Multi-tap

    private func startMultiTap(excluding excludedIdentifiers: Set<String> = []) {
        guard configuration.multiTap.enabled else {
            log.info("multi-tap is disabled in the configuration")
            return
        }
        guard let hudPresenter else { return }

        let resolver = AccessibilityTextTargetResolver(
            permission: permission,
            log: Log(category: "target", sink: logSink)
        )
        targetResolver = resolver

        let engine = MultiTapEngine(
            keymap: .classic,
            configuration: configuration.multiTap.engineConfiguration
        )

        guard let transport = makeTransport(excluding: excludedIdentifiers) else {
            log.notice("no input transport available; multi-tap stays off until iCUE is reachable")
            return
        }

        let coordinator = MultiTapCoordinator(
            engine: engine,
            transport: transport,
            textOutput: CGEventTextOutput(
                permission: permission,
                targetResolver: resolver,
                log: Log(category: "text", sink: logSink)
            ),
            targetResolver: resolver,
            permission: permission,
            hud: hudPresenter,
            clock: SystemMonotonicClock(),
            scheduler: DispatchTickScheduler(),
            log: Log(category: "multitap", sink: logSink),
            toggleKey: MultiTapKey(rawValue: configuration.input.toggleKey) ?? .k12,
            autoExitAfterIdle: configuration.multiTap.autoExitAfterIdle,
            toggleDebounce: configuration.multiTap.toggleDebounce
        )
        transport.delegate = coordinator

        coordinator.onModeChange = { [weak self] active in
            self?.lightingCoordinator?.setModeActive(active)
            self?.refreshStatus()
        }
        coordinator.onEntryRefused = { [weak self] reasons in
            self?.log.notice("entry refused: \(reasons.joined(separator: " | "))")
            self?.refreshStatus()
        }
        coordinator.onExit = { [weak self] _ in self?.refreshStatus() }

        multiTapCoordinator = coordinator

        // Replace rather than accumulate: `startMultiTap()` runs again on every
        // iCUE reconnect, and a second live observer would deliver every focus
        // change twice.
        focusMonitor?.stop()
        let monitor = WorkspaceFocusMonitor()
        monitor.onFocusChange = { [weak self] in self?.multiTapCoordinator?.handleFocusChange() }
        monitor.start()
        focusMonitor = monitor

        do {
            try transport.start()
            log.info("multi-tap ready — press side button \(configuration.input.toggleKey) to enter")
        } catch {
            log.notice("input transport unavailable: \(MultiTapCoordinator.describe(error))")
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
        guard configuration.multiTap.enabled,
              configuration.input.transport == .icueMacroKey
        else { return }

        // Never rebuild underneath an active mode: that would drop the
        // interception without running the coordinator's teardown. Exit first,
        // so the mouse is handed back cleanly and the user sees it happen.
        if let existing = multiTapCoordinator, existing.isActive {
            existing.exit(reason: .sessionLost)
        }

        // Order matters: the old transport must clear its handler before the
        // new one installs its own, or the new subscription is silently lost.
        macroKeyTransport?.stop()
        macroKeyTransport = nil
        multiTapCoordinator = nil
        startMultiTap(excluding: excludedIdentifiers)
    }

    private func toggleMode() {
        guard let coordinator = multiTapCoordinator else { return }
        if coordinator.isActive {
            coordinator.exit(reason: .userRequested)
        } else {
            _ = coordinator.enter()
        }
    }

    // MARK: - Hue

    private func startHue() {
        guard configuration.lighting.enabled else {
            hueStatusText = "disabled with mouse lighting"
            return
        }
        guard configuration.hue.enabled else {
            hueStatusText = "disabled"
            return
        }
        guard configuration.hue.isConfigured else {
            hueStatusText = "not configured"
            log.notice("Hue mirroring is enabled but not configured; see docs/SETUP.md")
            return
        }

        let resolver = KeychainSecretResolver(log: Log(category: "secrets", sink: logSink))
        guard let key = resolver.resolve(configuration.hue.applicationKeySource) else {
            hueStatusText = "missing application key"
            log.notice("Hue application key could not be read from \(configuration.hue.applicationKeySource.redactedDescription)")
            return
        }

        let transport = HueHTTPTransport(
            credentials: HueBridgeCredentials(host: configuration.hue.bridgeHost, applicationKey: key),
            log: Log(category: "hue", sink: logSink)
        )

        let observer = HueRoomObserver(
            transport: transport,
            configuration: .init(
                assignments: configuration.hue.lights,
                policy: configuration.hue.policy,
                coalescingInterval: configuration.hue.coalescingInterval
            ),
            log: Log(category: "hue", sink: logSink)
        )
        hueObserver = observer
        hueObserverGeneration &+= 1
        let generation = hueObserverGeneration

        let onFrame: @Sendable (LightingFrame?) -> Void = { [weak self] frame in
            Task { @MainActor [weak self] in
                guard let self, self.hueObserverGeneration == generation else { return }
                self.lightingCoordinator?.updateHueFrame(frame)
            }
        }
        let onStatus: @Sendable (HueRoomObserver.Status) -> Void = { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self, self.hueObserverGeneration == generation else { return }
                self.hueStatusText = String(describing: status)
                self.refreshStatus()
            }
        }

        hueLifecycleTask?.cancel()
        hueLifecycleTask = Task { @MainActor [weak self, observer] in
            await observer.setHandlers(
                onFrame: onFrame,
                onStatus: onStatus
            )
            guard !Task.isCancelled,
                  let self,
                  self.hueObserverGeneration == generation,
                  self.hueObserver === observer
            else {
                await observer.stop()
                return
            }
            await observer.start()
            // Cancellation may arrive while the actor hop to `start()` is in
            // flight. Stop again if this startup lost ownership meanwhile.
            guard !Task.isCancelled,
                  self.hueObserverGeneration == generation,
                  self.hueObserver === observer
            else {
                await observer.stop()
                return
            }
        }
    }

    // MARK: - Status

    private func refreshStatus() {
        var warnings = configurationWarnings
        if configuration.multiTap.enabled, !permission.isTrusted {
            warnings.insert("Accessibility permission is required for multi-tap mode.", at: 0)
        }
        if let selection = lightingController?.lastSelection, selection.device == nil {
            warnings.append(selection.explanation)
        }

        statusItem?.update(
            StatusItemController.Status(
                isModeActive: multiTapCoordinator?.isActive ?? false,
                multiTapEnabled: configuration.multiTap.enabled,
                accessibilityGranted: permission.isTrusted,
                icueState: ICUESession.shared.state.explanation,
                deviceDescription: (lightingController?.device ?? selectedDevice?.summary)
                    .map { "\($0.model) · \($0.ledCount) LEDs" },
                hueStatus: hueStatusText,
                warnings: warnings
            )
        )
    }
}
