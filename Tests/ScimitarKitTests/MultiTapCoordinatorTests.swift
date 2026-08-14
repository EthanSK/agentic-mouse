import XCTest
@testable import ScimitarKit

/// Mode lifecycle: button-12 enter/exit, fail-closed entry, and the guarantee
/// that every ending path returns the mouse to normal.
final class MultiTapCoordinatorTests: XCTestCase {

    private var clock: ManualClock!
    private var scheduler: ManualTickScheduler!
    private var keyControl: FakeICUEKeyControl!
    private var transport: ICUEMacroKeyTransport!
    private var textOutput: RecordingTextOutput!
    private var resolver: StubTextTargetResolver!
    private var permission: StubAccessibilityPermission!
    private var hud: RecordingHUDPresenter!
    private var engine: MultiTapEngine!
    private var coordinator: MultiTapCoordinator!
    private var modeChanges: [Bool] = []
    private var exits: [ModeExitReason] = []

    override func setUp() {
        super.setUp()
        clock = ManualClock()
        scheduler = ManualTickScheduler()
        keyControl = FakeICUEKeyControl()
        transport = ICUEMacroKeyTransport(
            session: keyControl,
            deviceIdentifier: keyControl.deviceIdentifier,
            clock: clock,
            log: Log(category: "test", sink: NullLogSink())
        )
        textOutput = RecordingTextOutput()
        resolver = StubTextTargetResolver()
        permission = StubAccessibilityPermission(isTrusted: true)
        hud = RecordingHUDPresenter()
        engine = MultiTapEngine(configuration: MultiTapConfiguration(initialShiftState: .lower))
        modeChanges = []
        exits = []

        coordinator = MultiTapCoordinator(
            engine: engine,
            transport: transport,
            textOutput: textOutput,
            targetResolver: resolver,
            permission: permission,
            hud: hud,
            clock: clock,
            scheduler: scheduler,
            log: Log(category: "test", sink: NullLogSink()),
            autoExitAfterIdle: 10
        )
        transport.delegate = coordinator
        coordinator.onModeChange = { [weak self] in self?.modeChanges.append($0) }
        coordinator.onExit = { [weak self] in self?.exits.append($0) }
        try? transport.start()
    }

    // MARK: - Helpers

    private func pressButton(_ key: Int) {
        keyControl.emit(macroKeyId: key, isPressed: true)
        clock.advance(by: 0.05)
        keyControl.emit(macroKeyId: key, isPressed: false)
        clock.advance(by: 0.05)
    }

    private func settle() {
        clock.advance(by: 1.2)
        scheduler.fire()
    }

    // MARK: - Button 12 lifecycle

    func testButtonTwelveEntersTheMode() {
        pressButton(12)

        XCTAssertTrue(coordinator.isActive)
        XCTAssertTrue(hud.isVisible)
        XCTAssertEqual(modeChanges, [true])
        XCTAssertEqual(keyControl.interceptedKeys, Set(1...12))
        XCTAssertTrue(scheduler.isRunning)
    }

    func testInactiveToggleClassifierCanOwnThePressWithoutEntering() {
        var classifications = 0
        coordinator.onInactiveTogglePress = {
            classifications += 1
            return true
        }

        pressButton(12)

        XCTAssertEqual(classifications, 1)
        XCTAssertFalse(coordinator.isActive)
        XCTAssertFalse(hud.isVisible)
        XCTAssertTrue(keyControl.interceptedKeys.isEmpty)
    }

    func testButtonTwelveExitsTheMode() {
        pressButton(12)
        clock.advance(by: 0.5)
        pressButton(12)

        XCTAssertFalse(coordinator.isActive)
        XCTAssertFalse(hud.isVisible)
        XCTAssertEqual(modeChanges, [true, false])
        XCTAssertTrue(keyControl.isFullyReleased)
        XCTAssertFalse(scheduler.isRunning)
    }

    func testLostToggleReleaseCannotPermanentlyBlockPhysicalExit() {
        keyControl.emit(macroKeyId: 12, isPressed: true)
        XCTAssertTrue(coordinator.isActive)

        // No release arrives. A genuinely later physical press is admitted by
        // the transport as an implicit release + new press and must still exit.
        clock.advance(by: 2)
        keyControl.emit(macroKeyId: 12, isPressed: true)

        XCTAssertFalse(coordinator.isActive)
        XCTAssertTrue(keyControl.isFullyReleased)
        XCTAssertEqual(modeChanges, [true, false])
    }

    func testTheSameButtonTogglesRepeatedly() {
        for _ in 0..<3 {
            clock.advance(by: 0.5)
            pressButton(12)
            XCTAssertTrue(coordinator.isActive)
            clock.advance(by: 0.5)
            pressButton(12)
            XCTAssertFalse(coordinator.isActive)
            XCTAssertTrue(keyControl.isFullyReleased)
        }
    }

    func testAToggleBounceIsIgnored() {
        pressButton(12)
        XCTAssertTrue(coordinator.isActive)

        // A second press inside the debounce window must not immediately exit.
        keyControl.emit(macroKeyId: 12, isPressed: true)
        XCTAssertTrue(coordinator.isActive)
    }

    func testAnotherRuntimeModeCanSuppressEntryWithoutSideEffects() {
        coordinator = MultiTapCoordinator(
            engine: engine,
            transport: transport,
            textOutput: textOutput,
            targetResolver: resolver,
            permission: permission,
            hud: hud,
            clock: clock,
            scheduler: scheduler,
            log: Log(category: "test", sink: NullLogSink()),
            entryAllowed: { false },
            autoExitAfterIdle: 10
        )
        transport.delegate = coordinator

        pressButton(12)

        XCTAssertFalse(coordinator.isActive)
        XCTAssertFalse(hud.isVisible)
        XCTAssertTrue(keyControl.interceptedKeys.isEmpty)
        XCTAssertEqual(keyControl.currentAccessLevel, .shared)
    }

    // MARK: - Typing while active

    func testTypingWhileActiveReachesTheAnchoredTarget() {
        pressButton(12)
        pressButton(4)
        pressButton(4)      // g → h
        settle()

        XCTAssertEqual(textOutput.buffer, "h")
        XCTAssertEqual(textOutput.deliveries.first?.target, resolver.resolution.target)
    }

    func testNoTextIsProducedWhenTheModeIsOff() {
        pressButton(4)
        pressButton(4)
        settle()
        XCTAssertTrue(textOutput.deliveries.isEmpty, "the grid must do nothing at all until the mode is entered")
    }

    // MARK: - Fail-closed entry

    func testEntryIsRefusedWithoutAccessibilityPermission() {
        permission.isTrusted = false
        pressButton(12)

        XCTAssertFalse(coordinator.isActive)
        XCTAssertFalse(hud.isVisible, "a refused entry must not show the HUD")
        XCTAssertTrue(modeChanges.isEmpty, "no lighting change either")
        XCTAssertEqual(keyControl.currentAccessLevel, .shared, "and no interception")
        XCTAssertFalse(hud.problems.isEmpty, "but the user is told why")
    }

    func testEntryIsRefusedWhenTheMouseDoesNotReportAllTwelveButtons() {
        keyControl.macroKeys = Array(1...10)
        pressButton(12)

        XCTAssertFalse(coordinator.isActive)
        XCTAssertFalse(hud.isVisible)
        XCTAssertTrue(keyControl.interceptedKeys.isEmpty)
    }

    func testEntryIsRefusedWhenICUERefusesKeyControl() {
        keyControl.requestControlCode = 7
        pressButton(12)

        XCTAssertFalse(coordinator.isActive)
        XCTAssertFalse(hud.isVisible)
        XCTAssertTrue(keyControl.isFullyReleased)
        XCTAssertTrue(
            hud.problems.contains { $0.contains("key interception") },
            "the message should name the actual iCUE setting"
        )
    }

    func testEntryIsRefusedWhenInterceptionCannotBeCompleted() {
        keyControl.configureCodes[9] = 4
        pressButton(12)

        XCTAssertFalse(coordinator.isActive)
        XCTAssertFalse(hud.isVisible)
        XCTAssertTrue(keyControl.isFullyReleased, "the partial transaction is rolled back")
    }

    func testModeCanEnterWithoutATextFieldAndHudExplainsWhyTypingIsBlocked() {
        resolver.resolution = .refused(.secureField)

        pressButton(12)

        XCTAssertTrue(coordinator.isActive)
        XCTAssertTrue(hud.isVisible)
        XCTAssertEqual(hud.lastSnapshot?.state.targetRefusal, .secureField)
        pressButton(2)
        settle()
        XCTAssertTrue(textOutput.deliveries.isEmpty)
    }

    func testARefusedEntryLeavesTheMouseCompletelyNormal() {
        keyControl.requestControlCode = 2  // CE_NoControl
        pressButton(12)

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(keyControl.currentAccessLevel, .shared)
        XCTAssertTrue(keyControl.interceptedKeys.isEmpty)
        XCTAssertFalse(scheduler.isRunning)
    }

    // MARK: - Failure exits

    func testTransportFailureExitsAndRestoresTheMouse() {
        pressButton(12)
        coordinator.handleTransportFailure(InputTransportError.notAvailable("tap disabled"))

        XCTAssertFalse(coordinator.isActive)
        XCTAssertTrue(keyControl.isFullyReleased)
        XCTAssertFalse(hud.isVisible)
        XCTAssertEqual(exits.count, 1)
        XCTAssertTrue(exits[0].isFailure)
    }

    func testSessionLossExitsAndRestoresTheMouse() {
        pressButton(12)
        coordinator.handleSessionLost()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(exits, [.sessionLost])
        XCTAssertTrue(keyControl.isFullyReleased)
    }

    func testDeviceLossExitsAndRestoresTheMouse() {
        pressButton(12)
        coordinator.handleDeviceLost()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(exits, [.deviceLost])
        XCTAssertTrue(keyControl.isFullyReleased)
    }

    func testPermissionRevokedMidSessionExits() {
        pressButton(12)
        permission.isTrusted = false
        scheduler.fire()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(exits, [.permissionLost])
        XCTAssertTrue(keyControl.isFullyReleased)
    }

    func testIdleTimeoutExits() {
        pressButton(12)
        clock.advance(by: 11)
        scheduler.fire()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(exits, [.idleTimeout])
        XCTAssertTrue(keyControl.isFullyReleased)
    }

    func testAFailureExitHidesTheHudBeforeExplainingItself() {
        pressButton(12)
        XCTAssertTrue(hud.isVisible)

        coordinator.handleSessionLost()

        // Order matters for the real AppKit presenter: `hide()` marks the HUD
        // inactive, and the problem message that follows is what re-shows it
        // briefly and then dismisses itself. If `hide()` were skipped the
        // message would have nothing to dismiss it.
        XCTAssertEqual(hud.hideCount, 1)
        XCTAssertFalse(hud.isVisible)
        XCTAssertEqual(hud.problems.last, ModeExitReason.sessionLost.explanation)
    }

    func testACleanExitDoesNotNagWithAProblemMessage() {
        pressButton(12)
        clock.advance(by: 0.5)
        pressButton(12)

        XCTAssertEqual(hud.hideCount, 1)
        XCTAssertTrue(hud.problems.isEmpty, "pressing 12 to leave is not a failure")
    }

    func testShutdownExitsAndStopsTheTransport() {
        pressButton(12)
        coordinator.shutdown()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertTrue(keyControl.isFullyReleased)
        XCTAssertFalse(transport.isRunning)
    }

    // MARK: - Reconnect must not silently re-enter

    func testAReconnectDoesNotSilentlyReEnterTheMode() throws {
        pressButton(12)
        XCTAssertTrue(coordinator.isActive)

        coordinator.handleSessionLost()
        XCTAssertFalse(coordinator.isActive)

        // iCUE comes back and the transport restarts.
        transport.handleSessionLoss()
        keyControl.isSessionUsable = true
        try transport.start()

        XCTAssertFalse(
            coordinator.isActive,
            "coming back online must never put the mouse into a modal state the user did not ask for"
        )
        XCTAssertTrue(keyControl.interceptedKeys.isEmpty)
    }

    // MARK: - Stale timers

    func testATickScheduledBeforeAnExitCannotResurrectTheMode() {
        pressButton(12)
        _ = engine.press(.k2, at: clock.now, target: resolver.resolveCurrentTarget())

        coordinator.exit(reason: .userRequested)
        XCTAssertFalse(coordinator.isActive)

        // The scheduler was stopped, but fire it anyway to model a callback
        // already in flight.
        scheduler.fire()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertTrue(textOutput.deliveries.isEmpty, "a stale tick must not flush a dead pending character")
    }

    func testPendingTextIsDiscardedOnExitRatherThanFlushed() {
        pressButton(12)
        keyControl.emit(macroKeyId: 2, isPressed: true)   // pending `a`
        clock.advance(by: 0.05)
        keyControl.emit(macroKeyId: 2, isPressed: false)

        coordinator.exit(reason: .sessionLost)

        XCTAssertTrue(
            textOutput.deliveries.isEmpty,
            "a teardown must not type into whatever happens to be in front"
        )
        XCTAssertNil(engine.state.pendingCharacter)
    }

    // MARK: - Focus

    func testFocusChangeCancelsPendingTextWithoutTyping() {
        pressButton(12)
        keyControl.emit(macroKeyId: 2, isPressed: true)
        clock.advance(by: 0.05)
        keyControl.emit(macroKeyId: 2, isPressed: false)

        resolver.moveToApplication(pid: 999)
        coordinator.handleFocusChange()

        XCTAssertTrue(textOutput.deliveries.isEmpty)
        XCTAssertTrue(coordinator.isActive, "the default policy cancels the letter but stays in the mode")
    }

    func testPolledSameAppFieldChangeExitsWhenConfigured() {
        engine = MultiTapEngine(
            configuration: MultiTapConfiguration(
                focusChangePolicy: .cancelPendingAndExit,
                initialShiftState: .lower
            )
        )
        coordinator = MultiTapCoordinator(
            engine: engine,
            transport: transport,
            textOutput: textOutput,
            targetResolver: resolver,
            permission: permission,
            hud: hud,
            clock: clock,
            scheduler: scheduler,
            log: Log(category: "test", sink: NullLogSink()),
            autoExitAfterIdle: 10
        )
        transport.delegate = coordinator
        coordinator.onExit = { [weak self] in self?.exits.append($0) }

        pressButton(12)
        pressButton(2)
        resolver.moveToElement("field-b")
        scheduler.fire()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(exits, [.focusPolicy])
        XCTAssertTrue(textOutput.deliveries.isEmpty)
        XCTAssertTrue(keyControl.isFullyReleased)
    }

    func testTargetMovingDuringFinalDeliveryExitsWithoutTyping() {
        pressButton(12)
        pressButton(2)
        textOutput.errorToThrow = .targetChanged

        settle()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(exits, [.focusPolicy])
        XCTAssertTrue(textOutput.deliveries.isEmpty)
        XCTAssertTrue(keyControl.isFullyReleased)
    }

    // MARK: - Preflight

    func testPreflightAggregatesEveryReason() {
        permission.isTrusted = false
        keyControl.macroKeys = Array(1...5)

        let readiness = coordinator.preflight()
        XCTAssertFalse(readiness.isReady)
        XCTAssertGreaterThanOrEqual(readiness.reasons.count, 2, "the user should see all of it at once")
    }
}
