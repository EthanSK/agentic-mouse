import XCTest
@testable import ScimitarKit

/// Fresh-session Switch App and the wheel-adjustment feedback contract,
/// driven through the real coordinator exactly as the receiver drives it.
final class WandSwitchAppAndAdjustTests: XCTestCase {
    private var clock: ManualClock!
    private var watchdog: ManualTickScheduler!
    private var hud: RecordingModeHUDPresenter!
    private var coordinator: ModePickerCoordinator!
    private var controller: WandSelectionController!
    private var homeActions: [PhysicalCell] = []
    private var appInputs: [PhysicalCell] = []
    private var sentDirections: [WheelChordDirection] = []
    private var wheelReleases: [WheelChordControl] = []
    private var dispatcherAccepts = true
    private var frontmost: AppSpecificTarget = .chrome
    private var gestureCounter = 0
    private var sequence = 0
    private var origin: (x: Double, y: Double) = (0, 0)

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
                target: frontmost,
                displayName: frontmost.displayName,
                bundleIdentifier: frontmost.bundleIdentifier
            )
        }
        coordinator.onWandHomeInput = { [unowned self] cell in homeActions.append(cell); return true }
        coordinator.onAppSpecificInput = { [unowned self] _, _, cell, _, _ in appInputs.append(cell); return true }
        coordinator.onWheelControlRelease = { [unowned self] _, control in wheelReleases.append(control) }
        controller = WandSelectionController(
            target: coordinator,
            scheduler: watchdog,
            clock: clock,
            log: Log(category: "test", sink: NullLogSink()),
            inputTime: { [unowned self] in clock.now }
        )
        controller.onAdjustStep = { [unowned self] direction in
            sentDirections.append(direction)
            return dispatcherAccepts
        }
    }

    // MARK: Helpers

    private var gestureID: String { "gesture-\(gestureCounter)" }

    private func cell(_ raw: Int) -> PhysicalCell { PhysicalCell(rawValue: raw)! }

    /// Resting stick position of a card on the wheel the HUD is drawing.
    private func wheel(_ target: PhysicalCell) -> (x: Double, y: Double) {
        let layout = coordinator.wandRadialLayout
        precondition(layout.contains(target), "cell is not on the wheel")
        return WandRadialNavigator.restingPosition(of: target, in: layout)
    }

    private func hold() {
        gestureCounter += 1
        sequence = 0
        controller.handle(.init(phase: .begin, gestureID: gestureID, sequence: 0))
        origin = wheel(controller.focusedCell ?? WandSelectionController.homeStartCell)
    }

    private func offset(_ x: Double, _ y: Double) {
        sequence += 1
        clock.advance(by: 0.03)
        controller.handle(.init(phase: .update, gestureID: gestureID, sequence: sequence, offset: .init(x: x, y: y)))
    }

    private func walk(to target: Int) {
        let destination = wheel(cell(target))
        offset(destination.x - origin.x, destination.y - origin.y)
        XCTAssertEqual(controller.focusedCell?.rawValue, target)
    }

    private func release() {
        sequence += 1
        clock.advance(by: 0.03)
        controller.handle(.init(phase: .end, gestureID: gestureID, sequence: sequence))
    }

    private func tap() {
        hold()
        release()
    }

    private var adjustment: ModeHUDWheelAdjustment? { coordinator.pointerFocus?.adjustment }

    /// Opens Codex directly and arms Reasoning Effort + Wheel (cell 4).
    private func armReasoningEffort() {
        frontmost = .codex
        coordinator.enterAppSpecific(source: .wand)
        hold()
        walk(to: 4)
        release()
        XCTAssertEqual(controller.phase, .armed)
        XCTAssertEqual(coordinator.activeWheelControl, .codexReasoningEffort)
    }

    // MARK: Fresh-session Switch App

    func testFreshTapRunsSwitchAppExactlyOnceAndEachLaterTapOnceMore() {
        tap()
        XCTAssertEqual(homeActions, [.switchApp])
        XCTAssertEqual(controller.phase, .lingering)
        tap() // during the short linger
        XCTAssertEqual(homeActions, [.switchApp, .switchApp], "one switch per tap, never a burst")
        clock.advance(by: 2.1)
        watchdog.fire()
        XCTAssertFalse(coordinator.isActive)
        tap()
        XCTAssertEqual(homeActions, [.switchApp, .switchApp, .switchApp])
        XCTAssertEqual(appInputs, [])
    }

    func testHoldingAndMovingSelectsAnotherCardInstead() {
        hold()
        walk(to: 9)
        release()
        XCTAssertEqual(coordinator.page, .keys)
        XCTAssertEqual(homeActions, [], "leaving Switch App never also switches app")

        select(10) // back to Default on the Keys card
        hold()
        walk(to: 11)
        walk(to: 8)
        walk(to: 11) // off and back again
        release()
        XCTAssertEqual(homeActions, [.switchApp])
    }

    func testBackToDefaultRestoresTheParentCardRatherThanSwitchApp() {
        hold()
        walk(to: 2)
        release() // into the current app's mode
        XCTAssertEqual(coordinator.page, .appSpecific)
        select(2) // the wheel's centre, Exit Chrome mode → Default
        XCTAssertTrue(coordinator.isWandHome)
        XCTAssertEqual(coordinator.pointerFocus?.cell, .frontmostAppModeSelector)
        tap()
        XCTAssertEqual(coordinator.page, .appSpecific, "a tap selects the restored card")
        XCTAssertEqual(homeActions, [])
    }

    func testCancelLockAndLostReleaseNeverSwitchApp() {
        hold()
        controller.handle(.init(phase: .cancel, gestureID: gestureID, sequence: 9, cancelReason: .user))
        XCTAssertFalse(coordinator.isActive)
        hold()
        controller.reset(reason: .systemSleep)
        XCTAssertFalse(coordinator.isActive)
        hold()
        clock.advance(by: 1.1)
        watchdog.fire()
        XCTAssertFalse(coordinator.isActive)
        release()
        XCTAssertEqual(homeActions, [], "only a real release on Switch App switches")
    }

    func testDefaultsOwnExitStillClosesDeliberately() {
        hold()
        walk(to: 10)
        release()
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(homeActions, [])
    }

    func testSwitchingAppRefreshesTheVisibleCurrentAppCard() {
        tap()
        XCTAssertEqual(hud.snapshots.last?.legend.first { $0.cell == .frontmostAppModeSelector }?.actionTitle, "Chrome mode")
        frontmost = .codex
        coordinator.updateFrontmostApp(coordinator.resolveFrontmostApp!())
        XCTAssertEqual(hud.snapshots.last?.legend.first { $0.cell == .frontmostAppModeSelector }?.actionTitle,
                       "Codex mode", "the lingering Default page shows the app it switched to")
    }

    func testTheWandSwitchAppCardIsTheSameCardTheMiceSee() {
        tap()
        let wandCard = hud.snapshots.last?.legend.first { $0.cell == .switchApp }
        for source in [MouseSource.corsair, .razer] {
            let mouseCard = DefaultMapLegend.snapshot(source: source).legend.first { $0.cell == .switchApp }
            XCTAssertEqual(wandCard?.gesture?.click, mouseCard?.actionTitle)
            XCTAssertEqual(wandCard?.gesture?.motion, .leftRight)
            XCTAssertEqual(wandCard?.accent, mouseCard?.accent)
        }
    }

    // MARK: Wheel adjustment feedback

    func testArmedCardShowsNoAdjustmentUntilTheAdjustingHoldBegins() {
        armReasoningEffort()
        XCTAssertEqual(coordinator.pointerFocus?.isArmed, true)
        XCTAssertNil(adjustment, "armed and waiting is the plain dashed ring")
        hold()
        XCTAssertEqual(controller.phase, .adjusting)
        XCTAssertEqual(adjustment, ModeHUDWheelAdjustment())
    }

    func testProgressFollowsTiltSeparatelyFromNavigationPull() {
        armReasoningEffort()
        hold()
        offset(0, -3) // tilt up, short of a detent
        XCTAssertEqual(adjustment?.pull ?? 0, -3.0 / 7 / 0.68, accuracy: 0.001)
        XCTAssertEqual(adjustment?.sentSteps, 0)
        XCTAssertEqual(coordinator.pointerFocus?.pullX, 0)
        XCTAssertEqual(coordinator.pointerFocus?.pullY, 0, "navigation residuals never mix with adjustment")
        offset(20, -3) // sideways travel changes nothing
        XCTAssertEqual(adjustment?.pull ?? 0, -3.0 / 7 / 0.68, accuracy: 0.001)
    }

    func testEverySentDetentStepsOnceAndProgressRestartsFromTheResidual() {
        armReasoningEffort()
        hold()
        offset(0, -5) // one physical-up detent
        XCTAssertEqual(sentDirections, [.down])
        XCTAssertEqual(adjustment?.sentSteps, 1)
        XCTAssertEqual(adjustment?.netSteps, 1)
        XCTAssertEqual(adjustment?.lastStepWasUp, true)
        // Like the navigation outline after a snap, progress restarts from the
        // true residual: just past an up detent it leans back toward down.
        XCTAssertGreaterThan(adjustment?.pull ?? -1, 0)
        XCTAssertLessThan(adjustment?.pull ?? 1, 0.5)
        offset(0, 9.5) // two physical-down detents
        XCTAssertEqual(adjustment?.sentSteps, 3)
        XCTAssertEqual(adjustment?.netSteps, -1)
        XCTAssertEqual(adjustment?.lastStepWasUp, false)
        release()
        XCTAssertEqual(wheelReleases, [.codexReasoningEffort])
        XCTAssertNil(coordinator.pointerFocus, "release clears the adjustment outline")
    }

    func testConsumedDetentsNeverPulse() {
        armReasoningEffort()
        dispatcherAccepts = false
        hold()
        offset(0, -5)
        XCTAssertEqual(sentDirections.count, 1, "the detent was offered to the dispatcher")
        XCTAssertEqual(adjustment?.sentSteps, 0, "but it was not sent, so nothing steps")
        XCTAssertEqual(adjustment?.netSteps, 0)
        XCTAssertNil(adjustment?.lastStepWasUp)
    }

    func testAdjustmentResetsOnCancelRetargetAndTheNextHold() {
        armReasoningEffort()
        hold()
        offset(0, -5)
        XCTAssertEqual(adjustment?.sentSteps, 1)
        release()
        hold() // a fresh navigation hold, not an adjustment
        XCTAssertNil(adjustment)
        walk(to: 4)
        release()
        hold()
        XCTAssertEqual(adjustment, ModeHUDWheelAdjustment(), "each adjusting hold starts from zero")
        controller.handle(.init(phase: .cancel, gestureID: gestureID, sequence: 9, cancelReason: .user))
        XCTAssertFalse(coordinator.isActive)
        XCTAssertNil(coordinator.pointerFocus)

        armReasoningEffort()
        hold()
        offset(0, -3)
        XCTAssertNotNil(adjustment)
        frontmost = .chrome
        coordinator.updateFrontmostApp(coordinator.resolveFrontmostApp!())
        offset(0, -6)
        XCTAssertNil(adjustment, "a vanished card never keeps drawing adjustment")
    }

    // MARK: Helpers that need the harness

    private func select(_ target: Int) {
        hold()
        walk(to: target)
        release()
    }
}
