import XCTest
@testable import ScimitarKit

// MARK: - Wire contract

final class WandSelectionCommandTests: XCTestCase {
    func testLiquidProgressShowsHalfwayAndReversesAfterSnap() throws {
        var nav = try XCTUnwrap(WandGridNavigator(rows: PhysicalCell.displayRowsTopToBottom(for: .wand), start: .frontmostAppModeSelector))
        let initial = nav.focusedCell
        nav.apply(deltaX: 2.72, deltaY: 0)
        XCTAssertEqual(nav.focusedCell, initial)
        XCTAssertEqual(nav.pointerFocus.pullX, 0.5, accuracy: 0.001)
        nav.apply(deltaX: 3, deltaY: 0)
        XCTAssertNotEqual(nav.focusedCell, initial)
        XCTAssertLessThan(nav.pointerFocus.pullX, 0)
    }

    private func decode(_ json: String) throws -> WandSelectionCommand? {
        try WandSelectionCommand.decodeIfPresent(Data(json.utf8))
    }

    private func assertRejects(
        _ json: String,
        _ expected: WandSelectionCommandError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try decode(json), file: file, line: line) { error in
            XCTAssertEqual(error as? WandSelectionCommandError, expected, file: file, line: line)
        }
    }

    func testDocumentedContractExamplesDecode() throws {
        let begin = try XCTUnwrap(decode(
            #"{"command":"agentic_mouse_wand_selection","version":1,"phase":"begin","gesture_id":"9F2C4A10-wand","seq":0}"#
        ))
        XCTAssertEqual(begin, WandSelectionCommand(phase: .begin, gestureID: "9F2C4A10-wand", sequence: 0))

        let update = try XCTUnwrap(decode(
            #"{"command":"agentic_mouse_wand_selection","version":1,"phase":"update","gesture_id":"9F2C4A10-wand","seq":7,"x_deg":-3.25,"y_deg":1.5}"#
        ))
        XCTAssertEqual(update.offset, WandAngularOffset(x: -3.25, y: 1.5))

        let end = try XCTUnwrap(decode(
            #"{"command":"agentic_mouse_wand_selection","version":1,"phase":"end","gesture_id":"9F2C4A10-wand","seq":8,"x_deg":-3.5,"y_deg":1.5}"#
        ))
        XCTAssertEqual(end.phase, .end)
        XCTAssertEqual(end.sequence, 8)

        let bareEnd = try XCTUnwrap(decode(
            #"{"command":"agentic_mouse_wand_selection","version":1,"phase":"end","gesture_id":"9F2C4A10-wand","seq":9}"#
        ))
        XCTAssertNil(bareEnd.offset)

        let cancel = try XCTUnwrap(decode(
            #"{"command":"agentic_mouse_wand_selection","version":1,"phase":"cancel","gesture_id":"9F2C4A10-wand","seq":10,"reason":"disconnect"}"#
        ))
        XCTAssertEqual(cancel.cancelReason, .disconnect)

        let defaultCancel = try XCTUnwrap(decode(
            #"{"command":"agentic_mouse_wand_selection","version":1,"phase":"cancel","gesture_id":"9F2C4A10-wand","seq":10}"#
        ))
        XCTAssertEqual(defaultCancel.cancelReason, .user)
    }

    func testOtherNamespacesAreNotWandCommands() throws {
        XCTAssertNil(try decode(
            #"{"command":"agentic_mouse_mode_picker","action":"open","source":"corsair","physical_cell":12,"phase":"press"}"#
        ))
        XCTAssertNil(try decode("not json"))
        XCTAssertNil(try decode(String(repeating: "x", count: 4_096)))
    }

    func testStrictSchemaRejectsMalformedWandPayloads() {
        let prefix = #"{"command":"agentic_mouse_wand_selection","#
        assertRejects(prefix + #""version":2,"phase":"begin","gesture_id":"abcdefgh","seq":0}"#, .unsupportedVersion)
        assertRejects(prefix + #""version":true,"phase":"begin","gesture_id":"abcdefgh","seq":0}"#, .invalidField("version"))
        assertRejects(prefix + #""phase":"begin","gesture_id":"abcdefgh","seq":0}"#, .missingField("version"))
        assertRejects(prefix + #""version":1,"phase":"press","gesture_id":"abcdefgh","seq":0}"#, .invalidField("phase"))
        assertRejects(prefix + #""version":1,"phase":"begin","gesture_id":"short","seq":0}"#, .invalidField("gesture_id"))
        assertRejects(prefix + #""version":1,"phase":"begin","gesture_id":"has space!","seq":0}"#, .invalidField("gesture_id"))
        assertRejects(prefix + #""version":1,"phase":"begin","gesture_id":"abcdefgh","seq":true}"#, .invalidField("seq"))
        assertRejects(prefix + #""version":1,"phase":"begin","gesture_id":"abcdefgh","seq":1.5}"#, .invalidField("seq"))
        assertRejects(prefix + #""version":1,"phase":"begin","gesture_id":"abcdefgh","seq":-1}"#, .invalidField("seq"))
        assertRejects(prefix + #""version":1,"phase":"begin","gesture_id":"abcdefgh","seq":0,"source":"corsair"}"#, .unexpectedKey("source"))
        assertRejects(prefix + #""version":1,"phase":"begin","gesture_id":"abcdefgh","seq":0,"x_deg":0,"y_deg":0}"#, .unexpectedKey("x_deg"))
        assertRejects(prefix + #""version":1,"phase":"update","gesture_id":"abcdefgh","seq":1}"#, .missingField("x_deg"))
        assertRejects(prefix + #""version":1,"phase":"update","gesture_id":"abcdefgh","seq":1,"x_deg":1}"#, .missingField("y_deg"))
        assertRejects(prefix + #""version":1,"phase":"update","gesture_id":"abcdefgh","seq":1,"x_deg":"1","y_deg":0}"#, .invalidField("x_deg"))
        assertRejects(prefix + #""version":1,"phase":"update","gesture_id":"abcdefgh","seq":1,"x_deg":7201,"y_deg":0}"#, .invalidField("x_deg"))
        assertRejects(prefix + #""version":1,"phase":"update","gesture_id":"abcdefgh","seq":1,"x_deg":0,"y_deg":false}"#, .invalidField("y_deg"))
        assertRejects(prefix + #""version":1,"phase":"end","gesture_id":"abcdefgh","seq":1,"reason":"user"}"#, .unexpectedKey("reason"))
        assertRejects(prefix + #""version":1,"phase":"cancel","gesture_id":"abcdefgh","seq":1,"reason":"lost"}"#, .invalidField("reason"))
        let padded = prefix + #""version":1,"phase":"begin","gesture_id":"abcdefgh","seq":0}"#
            + String(repeating: " ", count: WandSelectionCommand.maximumPayloadBytes)
        assertRejects(padded, .payloadTooLarge)
        assertRejects(#"["agentic_mouse_wand_selection"]"#, .notAnObject)
    }

    func testWandIdentityCannotBeDecodedFromAnyMouseNamespace() {
        XCTAssertEqual(MouseSource.allCases, [.corsair, .razer])
        let forged = #"{"command":"agentic_mouse_mode_picker","action":"openAppSpecific","source":"wand","physical_cell":2,"phase":"press"}"#
        XCTAssertThrowsError(try ModePickerCommand.decode(Data(forged.utf8)))
        let corsair = #"{"command":"agentic_mouse_mode_picker","action":"openAppSpecific","source":"corsair","physical_cell":2,"phase":"press"}"#
        XCTAssertEqual(try ModePickerCommand.decode(Data(corsair.utf8)).source, .corsair)
    }

    func testWandPresentsWithUnchangedCorsairCardsAndItsOwnCentredPanel() {
        XCTAssertEqual(
            PhysicalCell.displayRowsTopToBottom(for: .wand),
            PhysicalCell.displayRowsTopToBottom(for: .corsair)
        )
        for cell in PhysicalCell.all {
            XCTAssertEqual(cell.displayLabel(on: .wand), cell.displayLabel(on: .corsair))
            XCTAssertEqual(cell.printedSide(on: .wand), cell.printedSide(on: .corsair))
        }
        XCTAssertEqual(PhysicalCell(rawValue: 10)!.displayLabel(on: .razer), "Razer 12")
        XCTAssertEqual(AppConfiguration.HUDConfiguration.sourceCorner(for: .wand), .bottomCenter)
        XCTAssertEqual(AppConfiguration.HUDConfiguration.sourceCorner(for: .corsair), .bottomRight)
        XCTAssertEqual(AppConfiguration.HUDConfiguration.sourceCorner(for: .razer), .bottomLeft)
        XCTAssertFalse(MouseSource.wand.isPhysicalAdapter)
        XCTAssertEqual(MouseSource.wand.presentationSource, .corsair)
    }
}

// MARK: - Navigation tolerance

final class WandGridNavigatorTests: XCTestCase {
    private let rows = PhysicalCell.displayRowsTopToBottom(for: .wand)

    private func navigator(start: Int = 2) -> WandGridNavigator {
        WandGridNavigator(rows: rows, start: PhysicalCell(rawValue: start)!)!
    }

    func testStartsOnRequestedCardAndRejectsRaggedGrids() {
        XCTAssertEqual(navigator().focusedCell.rawValue, 2)
        XCTAssertNil(WandGridNavigator(rows: [], start: .modeExit))
        XCTAssertNil(WandGridNavigator(rows: [[.modeExit], []], start: .modeExit))
    }

    func testFirstStepNeedsHalfACardPlusHysteresis() {
        var grid = navigator()
        XCTAssertFalse(grid.apply(deltaX: 5.3, deltaY: 0)) // 0.66 of an 8° column
        XCTAssertEqual(grid.focusedCell.rawValue, 2)
        XCTAssertTrue(grid.apply(deltaX: 0.2, deltaY: 0))  // crosses 0.68
        XCTAssertEqual(grid.focusedCell.rawValue, 5)
    }

    func testOneFastSweepCrossesSeveralCards() {
        var grid = navigator()
        XCTAssertTrue(grid.apply(deltaX: 17, deltaY: 0))
        XCTAssertEqual(grid.focusedCell.rawValue, 8)
        XCTAssertTrue(grid.apply(deltaX: 9, deltaY: 0))
        XCTAssertEqual(grid.focusedCell.rawValue, 11)
    }

    func testHysteresisBandPreventsBoundaryFlicker() {
        var grid = navigator()
        grid.apply(deltaX: 5.6, deltaY: 0) // position 0.70 → cell 5
        XCTAssertEqual(grid.focusedCell.rawValue, 5)
        XCTAssertFalse(grid.apply(deltaX: -1.6, deltaY: 0)) // 0.50, inside the band
        XCTAssertFalse(grid.apply(deltaX: 1.2, deltaY: 0))  // 0.65, still inside
        XCTAssertFalse(grid.apply(deltaX: -2.4, deltaY: 0)) // 0.35, still inside
        XCTAssertTrue(grid.apply(deltaX: -0.4, deltaY: 0))  // 0.30 leaves the band
        XCTAssertEqual(grid.focusedCell.rawValue, 2)
    }

    func testOutwardTravelDoesNotWindUp() {
        var grid = navigator()
        XCTAssertFalse(grid.apply(deltaX: -64, deltaY: 0))
        XCTAssertEqual(grid.focusedCell.rawValue, 2)
        XCTAssertTrue(grid.apply(deltaX: 5.6, deltaY: 0))
        XCTAssertEqual(grid.focusedCell.rawValue, 5)
        XCTAssertTrue(grid.apply(deltaX: 0, deltaY: -63)) // reaches top edge
        XCTAssertFalse(grid.apply(deltaX: 0, deltaY: -5)) // stays at top row
        XCTAssertEqual(grid.focusedCell.rawValue, 6)
        XCTAssertTrue(grid.apply(deltaX: 0, deltaY: 4.9))   // straight back down
        XCTAssertEqual(grid.focusedCell.rawValue, 5)
    }

    func testRowsFollowTheDrawnGridFromTopToDesk() {
        var up = navigator()
        up.apply(deltaX: 0, deltaY: -5)
        XCTAssertEqual(up.focusedCell.rawValue, 3)
        var down = navigator()
        down.apply(deltaX: 0, deltaY: 5)
        XCTAssertEqual(down.focusedCell.rawValue, 1)
        var diagonal = navigator()
        diagonal.apply(deltaX: 6, deltaY: 5)
        XCTAssertEqual(diagonal.focusedCell.rawValue, 4)
    }

    func testDominantHorizontalSweepDoesNotSlipARow() {
        var attenuated = navigator()
        attenuated.apply(deltaX: 20, deltaY: 5)
        XCTAssertEqual(attenuated.focusedCell.rawValue, 8)
        var unattenuated = WandGridNavigator(
            rows: rows,
            start: .frontmostAppModeSelector,
            tuning: WandNavigationTuning(minorAxisAttenuation: 0)
        )!
        unattenuated.apply(deltaX: 20, deltaY: 5)
        XCTAssertEqual(unattenuated.focusedCell.rawValue, 7)
    }

    func testInvalidTuningIsBoundedAndNonFiniteMotionIsIgnored() {
        var grid = WandGridNavigator(
            rows: rows,
            start: .frontmostAppModeSelector,
            tuning: WandNavigationTuning(degreesPerColumn: 0, degreesPerRow: .nan, hysteresis: 9)
        )!
        XCTAssertFalse(grid.apply(deltaX: .infinity, deltaY: 0))
        XCTAssertFalse(grid.apply(deltaX: 0.5, deltaY: 0))
        XCTAssertEqual(grid.focusedCell.rawValue, 2)
    }
}

// MARK: - Wheel-card adjustment

final class WandAdjustmentTests: XCTestCase {
    func testTiltUpIsAPhysicalWheelUpInTheSharedResolverConvention() {
        XCTAssertEqual(WandAdjustStep.physicalUp.wheelDirection, .down)
        XCTAssertEqual(WandAdjustStep.physicalDown.wheelDirection, .up)
        // Physical wheel up already means increase / forward for these cards.
        XCTAssertEqual(
            WheelChordControl.codexReasoningEffort.codexReasoningEffortAction(
                for: WandAdjustStep.physicalUp.wheelDirection
            ),
            .increase
        )
    }

    func testDetentsUseHysteresisAndBoundBursts() {
        var tracker = WandAdjustDetentTracker(degreesPerStep: 7, hysteresis: 0.18)
        XCTAssertEqual(tracker.apply(deltaY: -4.6), [])
        XCTAssertEqual(tracker.apply(deltaY: -0.3), [.physicalUp])
        XCTAssertEqual(tracker.apply(deltaY: -7), [.physicalUp]) // position −1.70
        XCTAssertEqual(tracker.apply(deltaY: 2), [])             // −1.41: inside the band
        XCTAssertEqual(tracker.apply(deltaY: 1), [.physicalDown]) // −1.27 leaves it
        XCTAssertEqual(tracker.apply(deltaY: .nan), [])
        var burst = WandAdjustDetentTracker()
        XCTAssertEqual(burst.apply(deltaY: 500).count, WandAdjustDetentTracker.maximumStepsPerUpdate)
        XCTAssertEqual(burst.apply(deltaY: 1), [], "surplus travel must not replay later")
    }

    func testOnlySideEffectFreeCardsAreAdjustable() {
        let adjustable = Set(WheelChordControl.allCases.filter(\.supportsWandAdjustment))
        XCTAssertEqual(adjustable, [
            .codexPin, .codexReasoningEffort, .codexResponseSpeed, .codexChatHistory,
            .claudePin, .claudeTabs,
            .chromeTabs, .spotifyVolume, .vsCodeCursorHistory,
            .horizontalScroll, .clipboard, .brightness, .zoom, .systemOverview,
            .applicationWindows, .magnetWindow, .spaces, .mediaTracks,
        ])
    }

    func testVirtualWheelKeepsEachControlsOwnDispatchPolicy() {
        let clock = ManualClock()
        let wheel = WandVirtualWheel(clock: clock)
        XCTAssertNil(wheel.step(.down), "unarmed tilt never dispatches")

        wheel.setActive(.codexPin)
        XCTAssertEqual(wheel.step(.down)?.control, .codexPin)
        XCTAssertNil(wheel.step(.up), "Pin/Unpin acts once per hold")
        let release = wheel.release(.codexPin)
        XCTAssertEqual(release?.didObserveWheelInput, true)
        XCTAssertNil(wheel.activeControl)

        wheel.setActive(.codexChatHistory)
        XCTAssertNotNil(wheel.step(.up))
        XCTAssertNil(wheel.step(.up), "duplicate inside the 80 ms filter")
        XCTAssertNotNil(wheel.step(.down), "an immediate reversal is intentional")
        clock.advance(by: 0.1)
        XCTAssertNotNil(wheel.step(.down))
        wheel.setActive(nil)
        XCTAssertNil(wheel.release(.codexChatHistory), "clear never produces a click release")
    }
}

// MARK: - Gesture controller

final class WandSelectionControllerTests: XCTestCase {
    private struct AppInput: Equatable {
        let source: MouseSource
        let target: AppSpecificTarget
        let cell: Int
        let phase: ModePickerCommand.Phase
    }

    private var clock: ManualClock!
    private var watchdog: ManualTickScheduler!
    private var hud: RecordingModeHUDPresenter!
    private var coordinator: ModePickerCoordinator!
    private var controller: WandSelectionController!
    private var appInputs: [AppInput] = []
    private var wheelChanges: [WheelChordControl?] = []
    private var wheelReleases: [WheelChordControl] = []
    private var adjustSteps: [WheelChordDirection] = []
    private var frontmost: AppSpecificTarget? = .chrome
    private var allowed = true
    private var gestureCounter = 0

    override func setUp() {
        super.setUp()
        clock = ManualClock(now: 100)
        watchdog = ManualTickScheduler()
        hud = RecordingModeHUDPresenter()
        coordinator = ModePickerCoordinator(
            lease: WandModeLease(),
            hud: hud,
            scheduler: ManualTickScheduler(),
            log: Log(category: "test", sink: NullLogSink())
        )
        coordinator.resolveFrontmostApp = { [unowned self] in
            FrontmostAppModeContext(
                target: self.frontmost,
                displayName: self.frontmost?.displayName ?? "None",
                bundleIdentifier: self.frontmost?.bundleIdentifier
            )
        }
        coordinator.onAppSpecificInput = { [unowned self] source, target, cell, phase, _ in
            self.appInputs.append(AppInput(source: source, target: target, cell: cell.rawValue, phase: phase))
            return true
        }
        coordinator.onWheelControlChange = { [unowned self] _, control in self.wheelChanges.append(control) }
        coordinator.onWheelControlRelease = { [unowned self] _, control in self.wheelReleases.append(control) }
        controller = WandSelectionController(
            target: coordinator,
            scheduler: watchdog,
            clock: clock,
            log: Log(category: "test", sink: NullLogSink()),
            inputTime: { [unowned self] in self.clock.now },
            inputAllowed: { [unowned self] in self.allowed }
        )
        controller.onAdjustStep = { [unowned self] direction in
            self.adjustSteps.append(direction)
            return true
        }
    }

    // MARK: Helpers

    private var gestureID: String { "gesture-\(gestureCounter)" }

    private func begin(home: Bool = false) {
        if !home && !coordinator.isActive { coordinator.enterAppSpecific(source: .wand) }
        gestureCounter += 1
        controller.handle(.init(phase: .begin, gestureID: gestureID, sequence: 0))
        holdStart = controller.focusedCell ?? .switchApp
    }

    private func move(_ x: Double, _ y: Double, seq: Int) {
        clock.advance(by: 0.02)
        controller.handle(.init(phase: .update, gestureID: gestureID, sequence: seq, offset: .init(x: x, y: y)))
    }

    /// Cumulative offset that points the wheel's virtual stick at `raw`
    /// from where this hold started, using the HUD's own radial layout.
    /// `scale` > 1 overshoots, as a large sweep would.
    private func offset(toward raw: Int, scale: Double = 1) -> (x: Double, y: Double) {
        let layout = coordinator.wandRadialLayout
        let start = WandRadialNavigator.restingPosition(of: holdStart, in: layout)
        let goal = WandRadialNavigator.restingPosition(of: PhysicalCell(rawValue: raw)!, in: layout)
        return (goal.x * scale - start.x, goal.y * scale - start.y)
    }

    private func aim(at raw: Int, seq: Int, scale: Double = 1) {
        let value = offset(toward: raw, scale: scale)
        move(value.x, value.y, seq: seq)
    }

    private var holdStart: PhysicalCell = .switchApp

    private func end(seq: Int = 99) {
        clock.advance(by: 0.02)
        controller.handle(.init(phase: .end, gestureID: gestureID, sequence: seq))
    }

    private func tickAfter(_ seconds: TimeInterval) {
        clock.advance(by: seconds)
        watchdog.fire()
    }

    // MARK: Tests

    func testFreshHoldStartsOnSwitchAppAndATapSwitchesAppExactlyOnce() {
        var selected: [PhysicalCell] = []
        coordinator.onWandHomeInput = { selected.append($0); return true }
        begin(home: true)
        XCTAssertTrue(coordinator.isWandHome)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Default mode")
        XCTAssertEqual(controller.focusedCell, .switchApp)
        XCTAssertEqual(hud.snapshots.first?.pointerFocus?.cell, .switchApp, "outlined from the first frame")
        XCTAssertEqual(hud.snapshots.last?.legend.first { $0.cell == .frontmostAppModeSelector }?.actionTitle, "Chrome mode")
        end()
        XCTAssertEqual(selected, [.switchApp], "a no-movement tap runs Switch App once")
        XCTAssertTrue(coordinator.isWandHome, "Switch App never enters the outlined app's mode")
        XCTAssertEqual(appInputs, [])
        tickAfter(2.1)
        XCTAssertFalse(coordinator.isActive, "the HUD lingers briefly, then closes")
        XCTAssertEqual(selected, [.switchApp], "linger and close never repeat it")
    }

    func testSelectingTheCurrentAppCardEntersItsMode() {
        begin(home: true)
        aim(at: 2, seq: 1) // Switch App → current app card
        XCTAssertEqual(controller.focusedCell, .frontmostAppModeSelector)
        end()
        XCTAssertFalse(coordinator.isWandHome)
        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .chrome)
        XCTAssertTrue(appInputs.isEmpty, "Entering the mode must not run a child action")
    }

    func testDefaultScreenshotSelectionCallsTheExistingActionOnce() {
        var selected: [PhysicalCell] = []
        coordinator.onWandHomeInput = { selected.append($0); return true }
        begin(home: true)
        aim(at: 4, seq: 1)
        aim(at: 3, seq: 2)
        XCTAssertEqual(controller.focusedCell, .screenshotToggle)
        end()
        XCTAssertEqual(selected, [], "screenshot now uses the native held-wheel release route")
        XCTAssertEqual(wheelReleases, [.screenshotPaste])
    }

    func testExistingAppModeKeepsTheOutlineOnExit() {
        begin()
        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(coordinator.source, .wand)
        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .chrome)
        XCTAssertTrue(coordinator.followsFrontmostApp)
        XCTAssertEqual(controller.phase, .navigating)
        XCTAssertEqual(hud.snapshots.last?.pointerFocus, ModeHUDPointerFocus(cell: .frontmostAppModeSelector))
        XCTAssertEqual(hud.snapshots.last?.source, .wand)
        XCTAssertTrue(watchdog.isRunning)
    }

    func testWandCardsAreTheSameCardsAPhysicalMouseSees() {
        begin()
        let mouseHUD = RecordingModeHUDPresenter()
        let mouse = ModePickerCoordinator(
            lease: WandModeLease(),
            hud: mouseHUD,
            scheduler: ManualTickScheduler(),
            log: Log(category: "test", sink: NullLogSink())
        )
        mouse.resolveFrontmostApp = coordinator.resolveFrontmostApp
        mouse.enterAppSpecific(source: .corsair)
        XCTAssertEqual(hud.snapshots.last?.legend, mouseHUD.snapshots.last?.legend)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, mouseHUD.snapshots.last?.modeTitle)
        XCTAssertNil(mouseHUD.snapshots.last?.pointerFocus, "mice never draw the wand outline")
    }

    func testTapWithoutMovementOnlyClosesTheHUD() {
        begin()
        end()
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(appInputs, [])
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertFalse(watchdog.isRunning)
    }

    func testReleaseSelectsExactlyTheOutlinedCardThroughTheSharedCoordinator() {
        begin()
        aim(at: 5, seq: 1) // cell 5: Chrome New tab
        XCTAssertEqual(hud.snapshots.last?.pointerFocus?.cell.rawValue, 5)
        end()
        XCTAssertEqual(appInputs, [
            AppInput(source: .wand, target: .chrome, cell: 5, phase: .press),
            AppInput(source: .wand, target: .chrome, cell: 5, phase: .release),
        ])
        XCTAssertEqual(controller.phase, .lingering)
        XCTAssertNil(coordinator.pointerFocus)
        XCTAssertTrue(coordinator.isActive, "linger lets bounded follow-up work finish")
        tickAfter(1)
        XCTAssertTrue(coordinator.isActive)
        tickAfter(1.1)
        XCTAssertFalse(coordinator.isActive)
        XCTAssertFalse(watchdog.isRunning)
    }

    func testOneSweepCanTraverseSeveralCardsBeforeRelease() {
        begin()
        aim(at: 8, seq: 1, scale: 4) // overshoots: the stick saturates, no wind-up
        XCTAssertEqual(controller.focusedCell?.rawValue, 8)
        // The stick saturated on the rim, so from there one update sweeps
        // round to a card on the far side.
        let layout = coordinator.wandRadialLayout
        let first = offset(toward: 8, scale: 4)
        let rim = WandRadialNavigator.restingPosition(of: PhysicalCell(rawValue: 8)!, in: layout)
        let maximum = WandRadialTuning().maximumDegrees / WandRadialTuning().restingDegrees
        let goal = WandRadialNavigator.restingPosition(of: PhysicalCell(rawValue: 12)!, in: layout)
        move(first.x + goal.x - rim.x * maximum, first.y + goal.y - rim.y * maximum, seq: 2)
        XCTAssertEqual(controller.focusedCell?.rawValue, 12)
    }

    func testSlowCreepBelowTheDriftFloorNeverMovesTheOutline() {
        begin()
        for step in 1...15 {
            clock.advance(by: 1)
            controller.handle(.init(
                phase: .update,
                gestureID: gestureID,
                sequence: step,
                offset: .init(x: -Double(step), y: -Double(step))
            ))
            watchdog.fire()
        }
        XCTAssertEqual(controller.focusedCell?.rawValue, 2, "1.4 dps of residual bias is not intent")
        XCTAssertTrue(coordinator.isActive, "messages kept the gesture alive")
        let toward = offset(toward: 5)
        controller.handle(.init(phase: .update, gestureID: gestureID, sequence: 16, offset: .init(x: -15 + toward.x, y: -15 + toward.y)))
        XCTAssertEqual(controller.focusedCell?.rawValue, 5, "drift is never re-applied as travel")
    }

    func testOutOfOrderAndForeignMessagesAreIgnored() {
        begin()
        aim(at: 5, seq: 3)
        aim(at: 8, seq: 2)
        XCTAssertEqual(controller.focusedCell?.rawValue, 5)
        controller.handle(.init(phase: .update, gestureID: "someone-else", sequence: 10, offset: .init(x: 30, y: 0)))
        controller.handle(.init(phase: .end, gestureID: "someone-else", sequence: 11))
        XCTAssertEqual(controller.focusedCell?.rawValue, 5)
        XCTAssertEqual(appInputs, [])
        end(seq: 3)
        XCTAssertEqual(appInputs, [], "an end must advance the sequence")
        end(seq: 4)
        XCTAssertEqual(appInputs.count, 2)
        end(seq: 5)
        XCTAssertEqual(appInputs.count, 2, "a duplicate end never selects twice")
    }

    func testLostReleaseClosesWithoutSelecting() {
        begin()
        aim(at: 5, seq: 1)
        tickAfter(0.9)
        XCTAssertTrue(coordinator.isActive)
        tickAfter(0.2)
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(appInputs, [])
        end(seq: 2)
        XCTAssertEqual(appInputs, [], "a late end after the stall must not act")
    }

    func testKeepAliveHoldsTheGestureButNotForever() {
        begin()
        for seq in 1...79 {
            clock.advance(by: 0.25)
            controller.handle(.init(phase: .update, gestureID: gestureID, sequence: seq, offset: .zero))
            watchdog.fire()
        }
        XCTAssertTrue(coordinator.isActive)
        clock.advance(by: 0.25)
        controller.handle(.init(phase: .update, gestureID: gestureID, sequence: 80, offset: .zero))
        tickAfter(0.01)
        XCTAssertFalse(coordinator.isActive, "maximum gesture duration")
        XCTAssertEqual(appInputs, [])
    }

    func testNewGestureBeforeTheOldEndClosesTheOldOneUnselected() {
        begin()
        aim(at: 5, seq: 1)
        begin()
        XCTAssertEqual(appInputs, [])
        XCTAssertTrue(coordinator.isActive)
        XCTAssertTrue(coordinator.isWandHome, "the fresh HUD opens on Default")
        XCTAssertEqual(controller.focusedCell, WandSelectionController.homeStartCell)
        XCTAssertEqual(hud.hideCount, 1, "the stale HUD closed before the fresh one opened")
    }

    func testCancelAndDisconnectFailClosed() {
        begin()
        aim(at: 5, seq: 1)
        controller.handle(.init(phase: .cancel, gestureID: gestureID, sequence: 2, cancelReason: .user))
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(appInputs, [])

        begin()
        aim(at: 5, seq: 1)
        end()
        XCTAssertEqual(controller.phase, .lingering)
        controller.handle(.init(phase: .cancel, gestureID: "stale-gesture", sequence: 1, cancelReason: .user))
        XCTAssertTrue(coordinator.isActive, "a stale user cancel is ignored")
        controller.handle(.init(phase: .cancel, gestureID: "stale-gesture", sequence: 1, cancelReason: .disconnect))
        XCTAssertFalse(coordinator.isActive, "disconnect always closes")
    }

    func testLockedSessionAndResetNeverAct() {
        allowed = false
        begin()
        XCTAssertFalse(coordinator.isActive)
        allowed = true
        begin()
        aim(at: 5, seq: 1)
        allowed = false
        watchdog.fire()
        XCTAssertFalse(coordinator.isActive)
        allowed = true
        begin()
        controller.reset(reason: .systemSleep)
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(appInputs, [])
    }

    func testChildPageStaysOpenAndTheNextHoldNavigatesIt() {
        begin()
        aim(at: 8, seq: 1) // Chrome cell 8: Open website
        end()
        XCTAssertEqual(coordinator.page, .chromeWebsites)
        XCTAssertEqual(controller.phase, .lingering)
        tickAfter(7.5)
        XCTAssertTrue(coordinator.isActive, "a child page waits for the next selection")

        begin()
        XCTAssertEqual(coordinator.page, .chromeWebsites, "never restarts on the parent")
        XCTAssertEqual(controller.focusedCell, .frontmostAppModeSelector)
        end()
        XCTAssertTrue(coordinator.isActive, "a wand child's exit goes back, not away")
        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .chrome)
        XCTAssertEqual(coordinator.pointerFocus?.cell.rawValue, 8, "back lands on Open website")

        begin()
        XCTAssertEqual(controller.focusedCell?.rawValue, 8, "the next hold continues from that card")
        aim(at: 2, seq: 1) // back to the centre: Exit Chrome mode
        end()
        XCTAssertFalse(coordinator.isActive, "the journey's root page still closes deliberately")
    }

    func testIdleChildPageClosesItself() {
        begin()
        aim(at: 8, seq: 1)
        end()
        tickAfter(8.1)
        XCTAssertFalse(coordinator.isActive)
    }

    func testWheelCardArmsThenTheNextHoldAdjustsWithTilt() {
        frontmost = .codex
        begin()
        aim(at: 4, seq: 1) // cell 4: Reasoning Effort + Wheel
        XCTAssertEqual(controller.focusedCell?.rawValue, 4)
        end()
        XCTAssertEqual(controller.phase, .armed)
        XCTAssertEqual(coordinator.activeWheelControl, .codexReasoningEffort)
        XCTAssertEqual(wheelChanges.last, .codexReasoningEffort)
        XCTAssertEqual(hud.snapshots.last?.pointerFocus, ModeHUDPointerFocus(cell: PhysicalCell(rawValue: 4)!, isArmed: true))
        XCTAssertEqual(
            hud.snapshots.last?.legend.first { $0.cell.rawValue == 4 }?.actionTitle,
            "Reasoning Effort",
            "wheel hints stay exactly as they are"
        )

        begin()
        XCTAssertEqual(controller.phase, .adjusting)
        move(30, 0, seq: 1)       // sideways travel never adjusts
        XCTAssertEqual(adjustSteps, [])
        move(30, -12.5, seq: 2)   // two upward detents (physical wheel up)
        XCTAssertEqual(adjustSteps, [.down, .down])
        move(30, -10, seq: 3)     // reversal still inside the band
        XCTAssertEqual(adjustSteps, [.down, .down])
        move(30, -8.5, seq: 4)
        XCTAssertEqual(adjustSteps, [.down, .down, .up])
        end(seq: 5)
        XCTAssertEqual(wheelReleases, [.codexReasoningEffort])
        XCTAssertNil(coordinator.activeWheelControl)
        XCTAssertEqual(controller.phase, .lingering)
        XCTAssertEqual(appInputs, [], "the wheel card dispatches only through wheel steps")
    }

    func testArmedCardTimesOutWithoutAClickRelease() {
        frontmost = .codex
        begin()
        aim(at: 4, seq: 1)
        end()
        tickAfter(8.1)
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(wheelReleases, [])
        XCTAssertNil(wheelChanges.last!)
    }

    func testRetargetedFrontmostAppDisarmsTheWandCard() {
        frontmost = .codex
        begin()
        aim(at: 4, seq: 1)
        end()
        XCTAssertEqual(controller.phase, .armed)
        frontmost = .chrome
        coordinator.updateFrontmostApp(coordinator.resolveFrontmostApp!())
        begin()
        XCTAssertEqual(controller.phase, .navigating, "a vanished card is never adjusted")
        XCTAssertEqual(adjustSteps, [])
    }

    func testCommandsArrivingDuringDispatchCannotStartAnotherGesture() {
        coordinator.onAppSpecificInput = { [unowned self] source, target, cell, phase, _ in
            self.appInputs.append(AppInput(source: source, target: target, cell: cell.rawValue, phase: phase))
            if phase == .press {
                self.controller.handle(.init(phase: .begin, gestureID: "nested-gesture", sequence: 0))
            }
            return true
        }
        begin()
        aim(at: 5, seq: 1)
        end()
        XCTAssertEqual(appInputs.count, 2)
        XCTAssertEqual(controller.phase, .lingering)
        controller.handle(.init(phase: .end, gestureID: "nested-gesture", sequence: 1))
        XCTAssertEqual(appInputs.count, 2)
    }

    func testDisconnectDuringDispatchClosesAfterItReturns() {
        coordinator.onAppSpecificInput = { [unowned self] source, target, cell, phase, _ in
            self.appInputs.append(AppInput(source: source, target: target, cell: cell.rawValue, phase: phase))
            if phase == .release {
                self.controller.handle(.init(phase: .cancel, gestureID: "any-gesture", sequence: 0, cancelReason: .disconnect))
            }
            return true
        }
        begin()
        aim(at: 5, seq: 1)
        end()
        XCTAssertEqual(appInputs.count, 2)
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(controller.phase, .idle)
    }

    func testStartCellIsEachPagesExit() {
        XCTAssertEqual(WandSelectionController.startCell(for: .appSpecific), .frontmostAppModeSelector)
        XCTAssertEqual(WandSelectionController.startCell(for: .chromeWebsites), .frontmostAppModeSelector)
        for page in [ModePickerPage.modes, .keys, .appSelector, .keypad, .extraUtilities] {
            XCTAssertEqual(WandSelectionController.startCell(for: page), .modeExit)
        }
    }

    func testPointerFocusIsClearedByEveryModeBoundary() {
        begin()
        XCTAssertNotNil(coordinator.pointerFocus)
        coordinator.exit(reason: .userRequested)
        XCTAssertNil(coordinator.pointerFocus)
        coordinator.setPointerFocus(ModeHUDPointerFocus(cell: .modeExit))
        XCTAssertNil(coordinator.pointerFocus, "an inactive coordinator never draws a cursor")
    }
}
