import XCTest
@testable import ScimitarKit

/// Ethan's hold-to-show wand HUD, driven through the real coordinator with
/// inert outputs exactly as the receiver drives it: HUD button down `navigate`,
/// held `motion`, HUD button up `park` then `choose` (a held release) or a
/// delayed `activate` (a tap).
final class WandHoldToShowTests: XCTestCase {
    private var clock: ManualClock!
    private var tick: ManualTickScheduler!
    private var hud: RecordingModeHUDPresenter!
    private var target: ModePickerCoordinator!
    private var control: WandPersistentController!
    private var homeActions: [PhysicalCell] = []
    private var buttonPhases: [String] = []
    private var keysActions: [KeysModeAction] = []
    private var wheelChanges: [WheelChordControl?] = []
    private var wheelReleases: [WheelChordControl] = []
    private var adjustSteps: [WheelChordDirection] = []
    private var switchSteps: [WheelChordDirection] = []
    private var frontmost: AppSpecificTarget = .chrome
    private var allowed = true
    private var counter = 0

    override func setUp() {
        super.setUp()
        clock = ManualClock(now: 100)
        tick = ManualTickScheduler()
        hud = RecordingModeHUDPresenter()
        target = ModePickerCoordinator(lease: WandModeLease(), hud: hud, scheduler: ManualTickScheduler(),
                                       log: Log(category: "test", sink: NullLogSink()))
        target.resolveFrontmostApp = { [unowned self] in
            FrontmostAppModeContext(target: frontmost, displayName: frontmost.displayName, bundleIdentifier: frontmost.bundleIdentifier)
        }
        target.onWandHomeInput = { [unowned self] cell in homeActions.append(cell); return true }
        target.onKeysInput = { [unowned self] _, action in keysActions.append(action); return true }
        target.onWheelControlChange = { [unowned self] _, value in wheelChanges.append(value) }
        target.onWheelControlRelease = { [unowned self] _, value in wheelReleases.append(value) }
        // Switch App's held Command belongs to the app's held-key owner.
        target.onWandButtonPhase = { [unowned self] _, home, cell, phase in
            guard home, cell == .switchApp else { return false }
            buttonPhases.append("\(phase)")
            return true
        }
        control = WandPersistentController(target: target, scheduler: tick, clock: clock, allowed: { [unowned self] in allowed })
        control.onAdjustStep = { [unowned self] in adjustSteps.append($0); return true }
        control.onSwitchAppStep = { [unowned self] in switchSteps.append($0); return true }
    }

    // MARK: Receiver-shaped helpers

    private func nextID(_ phase: String) -> String { counter += 1; return "\(phase)-\(counter)-wand" }

    /// HUD button down from closed: open and steer.
    private func holdFromClosed() -> String {
        control.handle(.init(.open, id: nextID("open")))
        return hold()
    }

    /// HUD button down on an open HUD: steer it, or adjust an armed card.
    @discardableResult
    private func hold() -> String {
        let id = nextID("navigate")
        control.handle(.init(.navigate, id: id))
        return id
    }

    private func aim(_ id: String, at cell: PhysicalCell, sequence: Int = 1) {
        let layout = target.wandRadialLayout
        let start = WandRadialNavigator.restingPosition(of: target.pointerFocus?.cell ?? .switchApp, in: layout)
        let goal = WandRadialNavigator.restingPosition(of: cell, in: layout)
        control.handle(.init(.motion, id: id, sequence: sequence, x: goal.x - start.x, y: goal.y - start.y))
        XCTAssertEqual(control.focusedCell, cell, "aimed at the wrong card")
    }

    private func releaseHold(_ id: String, sequence: Int = 9) {
        control.handle(.init(.park, id: id, sequence: sequence))
        control.handle(.init(.choose, id: nextID("choose")))
    }

    private func tap(_ id: String) {
        control.handle(.init(.park, id: id, sequence: 1))
        control.handle(.init(.activate, id: nextID("activate")))
    }

    private func lingerOut() {
        clock.advance(by: WandPersistentController.followUpLinger + 0.1)
        tick.fire()
    }

    // MARK: Ordinary actions close

    func testATapFromClosedSwitchesAppOnceThenHidesTheHUD() {
        tap(holdFromClosed())
        XCTAssertEqual(buttonPhases, ["press", "release"], "one ordinary Switch App press and release")
        XCTAssertFalse(control.isOpen, "the receiver is told the HUD closed")
        XCTAssertTrue(control.isConcealed)
        XCTAssertFalse(hud.isVisible, "the HUD disappears at once")
        XCTAssertTrue(target.isActive, "the mode lingers briefly for follow-up work")
        lingerOut()
        XCTAssertFalse(target.isActive, "then it ends")
    }

    func testHardOpeningTapsIgnoreJoltsAndEachSwitchAppThenClose() {
        // The first repeat reopens during concealment; the next follows its
        // expiry. A release classified as a tap never activates the jolt's card.
        for attempt in 0..<3 {
            let id = holdFromClosed()
            aim(id, at: .wandPlayPause)
            XCTAssertEqual(control.focusedCell, .wandPlayPause, "aim stays immediate")
            control.handle(.init(.park, id: id, sequence: 2))
            control.handle(.init(.activate, id: nextID("activate")))
            XCTAssertTrue(homeActions.isEmpty, "a hard tap must not trigger the neighbouring action")
            XCTAssertEqual(buttonPhases, Array(repeating: ["press", "release"], count: attempt + 1).flatMap { $0 })
            XCTAssertTrue(control.isConcealed)
            XCTAssertFalse(control.isOpen)
            XCTAssertFalse(hud.isVisible)
            clock.advance(by: attempt == 0 ? 0.5 : WandPersistentController.followUpLinger + 0.1)
            tick.fire()
        }
    }

    /// Ethan (2026-10-30): "Single clicking any HUD item, I don't want it to
    /// ever dismiss the HUD ... so then I can just select as many times as I
    /// want." Hold-steer-release acts once and the HUD stays on the card.
    func testHoldingAndReleasingOnAnActionUsesItOnceAndStaysOpen() {
        let id = holdFromClosed()
        aim(id, at: .wandPlayPause)
        releaseHold(id)
        XCTAssertEqual(homeActions, [.wandPlayPause])
        XCTAssertTrue(control.isOpen)
        XCTAssertTrue(hud.isVisible)
        XCTAssertEqual(control.focusedCell, .wandPlayPause, "the outline stays on the card for another click")
        let enter = hold()
        aim(enter, at: PhysicalCell(rawValue: 7)!)
        releaseHold(enter)
        XCTAssertEqual(homeActions, [.wandPlayPause, PhysicalCell(rawValue: 7)!], "Enter is an ordinary action too")
        XCTAssertTrue(control.isOpen)
        tap(hold())
        XCTAssertEqual(homeActions, [.wandPlayPause, PhysicalCell(rawValue: 7)!, PhysicalCell(rawValue: 7)!],
                       "a repeated click acts again, once")
        control.handle(.init(.dismiss, id: nextID("dismiss")))
        XCTAssertFalse(control.isOpen, "only the double click closes it")
    }

    /// YouTube −5 sec's held scrub is mouse-wheel only, so a wand release
    /// is just its click. (Screenshot was this case until it left the wand
    /// home on 2026-10-31.)
    func testANonAdjustableWheelCardClicksOnceAndStaysOpen() {
        let id = holdFromClosed()
        aim(id, at: .youtubeScrubWheelControl)
        releaseHold(id)
        XCTAssertEqual(wheelReleases, [.youtubeScrub], "YouTube keeps its click")
        XCTAssertNil(control.armedCell)
        XCTAssertTrue(control.isOpen)
        XCTAssertTrue(target.acceptsDefaultInput, "the app's Default action guard must admit this wand-home release")
    }

    func testDefaultInputContextKeepsPhysicalModesAndWandChildrenBlocked() {
        XCTAssertTrue(target.acceptsDefaultInput)
        target.enterWandHome(source: .wand)
        XCTAssertTrue(target.acceptsDefaultInput)
        target.handle(.init(action: .select, source: .wand, physicalCell: .modePickerEntry, phase: .press))
        target.handle(.init(action: .select, source: .wand, physicalCell: .modePickerEntry, phase: .release))
        XCTAssertFalse(target.acceptsDefaultInput, "Utility is a child page, not the wand home map")
        target.exit(reason: .userRequested)
        XCTAssertTrue(target.acceptsDefaultInput)
        for source in [MouseSource.corsair, .razer] {
            target.handle(.init(action: .open, source: source, physicalCell: .modePickerEntry, phase: .press))
            XCTAssertFalse(target.acceptsDefaultInput, "a physical mouse mode still blocks delayed Default actions")
            target.exit(reason: .userRequested)
        }
    }

    func testUtilityOuterShortcutsStayOnTheirCardForRepeatedClicks() {
        openUtilities()
        for cell in [PhysicalCell.wandBackspace, .wandCopy] {
            hoverAim(at: cell)
            let before = homeActions.count
            tap(hold())
            XCTAssertEqual(homeActions.count, before + 1)
            XCTAssertEqual(homeActions.last, cell)
            XCTAssertTrue(control.isOpen)
            XCTAssertEqual(target.page, .modes)
            XCTAssertEqual(control.focusedCell, cell)
            XCTAssertNil(control.armedCell, "a shortcut never enters dotted adjustment")
            tap(hold())
            XCTAssertEqual(homeActions.count, before + 2)
            XCTAssertEqual(control.focusedCell, cell)
        }
    }

    // MARK: Pages stay open

    func testReceiverFinalMotionParkChooseOpensUtility() {
        let id = holdFromClosed()
        clock.advance(by: 0.2)
        control.handle(.init(.qualify, id: id, sequence: 1))
        let layout = target.wandRadialLayout
        let goal = WandRadialNavigator.restingPosition(of: PhysicalCell(rawValue: 12)!, in: layout)
        control.handle(.init(.motion, id: id, sequence: 2, x: goal.x, y: goal.y))
        XCTAssertEqual(control.focusedCell?.rawValue, 12)
        // Exact receiver release: final cumulative sample, park, fresh choose ID.
        control.handle(.init(.motion, id: id, sequence: 3, x: goal.x, y: goal.y))
        control.handle(.init(.park, id: id, sequence: 4))
        control.handle(.init(.choose, id: nextID("choose"), sequence: 1))
        XCTAssertFalse(target.isWandHome)
        XCTAssertEqual(target.page, .modes)
        XCTAssertTrue(control.isOpen)
        XCTAssertTrue(homeActions.isEmpty)
    }

    func testASubmenuStaysOpenAndTheNextHoldUsesIt() {
        let id = holdFromClosed()
        aim(id, at: .keysModeSelector)
        releaseHold(id)
        XCTAssertTrue(control.isOpen, "a submenu needs another hold")
        XCTAssertEqual(target.page, .keys)
        XCTAssertEqual(control.focusedCell, .modeExit, "waiting on Keys' centre")
        XCTAssertTrue(hud.isVisible)

        let next = hold()
        let save = target.wandRadialLayout.ring.first { $0.rawValue == 12 }!
        aim(next, at: save)
        releaseHold(next)
        XCTAssertEqual(keysActions.count, 1, "one key, once")
        XCTAssertTrue(control.isOpen, "an ordinary key keeps the HUD open (2026-10-30)")
    }

    func testTheCentreExitGoesBackAndStaysOpen() {
        let id = holdFromClosed()
        aim(id, at: .keysModeSelector)
        releaseHold(id)
        tap(hold())
        XCTAssertTrue(control.isOpen)
        XCTAssertTrue(target.isWandHome, "back to the page that opened Keys")
        XCTAssertEqual(control.focusedCell, .keysModeSelector)
        XCTAssertTrue(keysActions.isEmpty)
    }

    // MARK: Cards that need more motion

    /// Ethan: in dotted mode "it should just be responding to ... wand
    /// movements" without holding the HUD button, "and then I can click to exit".
    func testReleasingOnAWheelCardSelectsItAndOnlyAHoldAdjustsIt() {
        // Held-only rule (Ethan, 2026-10-29 amendment): a release selects the
        // card (dots) without pressing; HUD button up never adjusts; a hold does.
        let id = holdFromClosed()
        let scroll = PhysicalCell(rawValue: 1)!
        aim(id, at: scroll)
        releaseHold(id)
        XCTAssertTrue(control.isOpen)
        XCTAssertEqual(control.armedCell, scroll)
        XCTAssertEqual(target.pointerFocus?.adjustment, ModeHUDWheelAdjustment(isHorizontal: true, isHeld: false), "dots, not listening")
        XCTAssertNil(target.activeWheelControl, "selecting presses nothing")
        let unheld = nextID("hover")
        control.handle(.init(.hover, id: unheld))
        control.handle(.init(.motion, id: unheld, sequence: 1, x: -12.5, y: 0))
        XCTAssertTrue(adjustSteps.isEmpty, "HUD button up never adjusts")
        control.handle(.init(.park, id: unheld, sequence: 2))
        XCTAssertEqual(control.armedCell, scroll, "still selected")
        let held = hold()
        control.handle(.init(.motion, id: held, sequence: 1, x: -12.5, y: 0)) // Horizontal Scroll moves left/right on the wand
        XCTAssertEqual(adjustSteps, [.down, .down], "a hold adjusts")
        XCTAssertEqual(target.pointerFocus?.adjustment?.sentSteps, 2)
        releaseHold(held, sequence: 2)
        XCTAssertEqual(wheelReleases, [.horizontalScroll], "release lets go once")
        XCTAssertEqual(control.armedCell, scroll, "and keeps it selected")
        tap(hold())
        XCTAssertNil(control.armedCell, "a tap deselects")
        XCTAssertTrue(control.isOpen, "back to wedge selection on the same page")
        XCTAssertEqual(control.focusedCell, scroll)
        XCTAssertEqual(adjustSteps.count, 2)
        XCTAssertEqual(wheelReleases.count, 1)
    }

    /// Ethan: after a submenu opens, "it should already be in like a wedge
    /// selection mode. And then when I press the button again, it selects that wedge."
    func testClickingAWheelCardInWedgeSelectionSelectsIt() {
        openKeys()
        tap(hold()) // Keys' centre goes back home, still open
        XCTAssertTrue(target.isWandHome)
        let scroll = PhysicalCell(rawValue: 1)!
        let aiming = nextID("hover")
        control.handle(.init(.hover, id: aiming))
        let layout = target.wandRadialLayout
        let start = WandRadialNavigator.restingPosition(of: control.focusedCell ?? .switchApp, in: layout)
        let goal = WandRadialNavigator.restingPosition(of: scroll, in: layout)
        control.handle(.init(.motion, id: aiming, sequence: 1, x: goal.x - start.x, y: goal.y - start.y))
        XCTAssertEqual(control.focusedCell, scroll, "unheld motion moves the outline")
        XCTAssertNil(control.armedCell, "unheld aiming never operates a card")
        XCTAssertTrue(wheelChanges.compactMap { $0 }.isEmpty)
        control.handle(.init(.park, id: aiming, sequence: 2))
        let click = hold()
        control.handle(.init(.park, id: click, sequence: 1))
        let resumed = nextID("hover") // the stream resumes before the delayed activate
        control.handle(.init(.hover, id: resumed))
        control.handle(.init(.activate, id: nextID("activate")))
        XCTAssertEqual(control.armedCell, scroll, "a click on a wheel card selects it")
        control.handle(.init(.motion, id: resumed, sequence: 1, x: -12.5, y: 0))
        XCTAssertTrue(adjustSteps.isEmpty, "the already-running unheld stream never adjusts")
        XCTAssertTrue(wheelChanges.compactMap { $0 }.isEmpty, "nothing pressed")
    }

    func testAReleaseWithoutItsParkStillUsesTheAimedCardAndNeverExpiresTheNewPage() {
        let id = holdFromClosed()
        aim(id, at: .keysModeSelector)
        control.handle(.init(.choose, id: nextID("choose"))) // the park datagram was lost
        XCTAssertEqual(target.page, .keys)
        clock.advance(by: 1.5)
        tick.fire()
        XCTAssertTrue(control.isOpen, "the released hold cannot later time out and close Keys")
    }

    /// A short tap on Switch App still switches once; a held release enters
    /// dotted app switching with Command down.
    func testReleasingAHoldOnSwitchAppArmsItForTheNextRealHold() {
        let id = holdFromClosed(); releaseHold(id)
        XCTAssertTrue(buttonPhases.isEmpty, "arming does not hold Command")
        XCTAssertEqual(control.armedCell, .switchApp)
        let hover = nextID("hover"); control.handle(.init(.hover, id: hover))
        aim(hover, at: .keysModeSelector)
        XCTAssertEqual(control.focusedCell, .keysModeSelector, "unheld motion still selects other wedges")
        XCTAssertTrue(switchSteps.isEmpty)
        control.handle(.init(.dismiss, id: nextID("dismiss")))
        let fresh = holdFromClosed(); releaseHold(fresh)
        let held = hold()
        XCTAssertTrue(buttonPhases.isEmpty, "Command waits for the first step or the qualified hold")
        control.handle(.init(.motion, id: held, sequence: 1, x: 12.5))
        XCTAssertEqual(buttonPhases, ["press"])
        XCTAssertEqual(switchSteps.count, 1, "two detents right: Command-Tab, then one more")
        releaseHold(held, sequence: 2)
        XCTAssertEqual(buttonPhases, ["press", "release"])
        XCTAssertFalse(control.isOpen)
    }

    func testArmedSwitchAppHoldsNothingSoTimeNeverEndsIt() {
        let id = holdFromClosed()
        releaseHold(id)
        XCTAssertTrue(buttonPhases.isEmpty, "arming presses nothing")
        XCTAssertEqual(control.armedCell, .switchApp)
        XCTAssertEqual(target.pointerFocus?.isArmed, true, "marching outline: armed for the next hold")
        XCTAssertNil(target.pointerFocus?.adjustment, "not dotted mode's locked adjustment ring")
        clock.advance(by: 5)
        tick.fire()
        XCTAssertTrue(control.isOpen, "time alone never ends or operates an armed Switch App")
        XCTAssertEqual(control.armedCell, .switchApp)
        XCTAssertTrue(buttonPhases.isEmpty)
    }

    func testASelectedWheelCardHoldsNothingButAHeldAdjustmentWithoutTelemetryEnds() {
        let id = holdFromClosed()
        aim(id, at: PhysicalCell(rawValue: 1)!)
        releaseHold(id)
        XCTAssertEqual(control.armedCell, PhysicalCell(rawValue: 1)!)
        clock.advance(by: 5)
        tick.fire()
        XCTAssertTrue(control.isOpen, "a selected card presses nothing, so time alone never ends it")
        let held = hold()
        control.handle(.init(.motion, id: held, sequence: 1, x: -7, y: 0))
        XCTAssertEqual(target.activeWheelControl, .horizontalScroll)
        clock.advance(by: 1.1)
        tick.fire()
        XCTAssertFalse(target.isActive, "a held wheel press is never left down without telemetry")
        XCTAssertNil(target.activeWheelControl)
        XCTAssertNil(control.armedCell)
    }

    func testAnArmedCardThatVanishedIsNavigatedNotAdjusted() {
        frontmost = .codex
        let id = holdFromClosed()
        aim(id, at: .frontmostAppModeSelector)
        releaseHold(id)
        XCTAssertEqual(target.page, .appSpecific)
        let effort = hold()
        aim(effort, at: CodexMode.reasoningEffortWheelCell)
        releaseHold(effort)
        XCTAssertEqual(control.armedCell, CodexMode.reasoningEffortWheelCell)
        frontmost = .chrome
        target.updateFrontmostApp(target.resolveFrontmostApp!())
        let next = hold()
        control.handle(.init(.motion, id: next, sequence: 1, x: 0, y: -12))
        XCTAssertTrue(adjustSteps.isEmpty, "a retargeted page never adjusts the old card")
        XCTAssertNil(control.armedCell)
    }

    // MARK: Concealment, review and safety

    func testInputDuringTheFollowUpWaitNeverActsAndANewHoldStartsFresh() {
        tap(holdFromClosed())
        XCTAssertTrue(control.isConcealed)
        control.handle(.init(.dismiss, id: nextID("dismiss")))
        XCTAssertTrue(target.isActive, "the receiver's own close never cuts the follow-up short")
        control.handle(.init(.activate, id: nextID("activate")))
        XCTAssertEqual(buttonPhases.count, 2, "stale taps never act on the hidden HUD")
        let fresh = hold()
        XCTAssertFalse(control.isConcealed)
        XCTAssertTrue(control.isOpen, "a hold that raced the close opens a fresh HUD")
        XCTAssertTrue(target.isWandHome)
        XCTAssertEqual(control.focusedCell, .switchApp)
        aim(fresh, at: .wandPlayPause)
    }

    func testReviewCardsStillPinTheirIndependentLane() {
        frontmost = .vsCode
        let id = holdFromClosed()
        aim(id, at: .wandReviewChanges)
        releaseHold(id)
        XCTAssertEqual(control.selectedReviewMode, "changes")
        XCTAssertFalse(control.isOpen)
        XCTAssertFalse(target.isActive, "review hides the HUD exactly as before")
    }

    func testLockAndLostTelemetryCloseEveryState() {
        let id = holdFromClosed()
        aim(id, at: PhysicalCell(rawValue: 1)!)
        releaseHold(id)
        XCTAssertNotNil(control.armedCell)
        allowed = false
        tick.fire()
        XCTAssertFalse(target.isActive)
        XCTAssertNil(control.armedCell)
        allowed = true
        tap(holdFromClosed())
        allowed = false
        tick.fire()
        XCTAssertFalse(control.isConcealed)
        XCTAssertFalse(target.isActive)
        allowed = true
        _ = holdFromClosed()
        clock.advance(by: 1.1)
        tick.fire()
        XCTAssertFalse(target.isActive, "a hold whose telemetry stops closes")
    }

    func testAStaleOrDuplicateUseActsOnce() {
        let id = holdFromClosed()
        aim(id, at: .wandPlayPause)
        control.handle(.init(.park, id: id, sequence: 9))
        let use = nextID("choose")
        control.handle(.init(.choose, id: use))
        control.handle(.init(.choose, id: use))
        XCTAssertEqual(homeActions, [.wandPlayPause])
    }

    // MARK: Holding the HUD button on a wheel card in wedge selection

    /// Opens Utilities by hold-aim-release, leaving it in wedge selection.
    private func openUtilities() {
        let id = holdFromClosed()
        aim(id, at: PhysicalCell(rawValue: 12)!)
        releaseHold(id)
        XCTAssertEqual(target.page, .modes)
        XCTAssertTrue(control.isOpen)
    }

    /// Unheld aiming, then the receiver parks the stream as the HUD button goes down.
    private func hoverAim(at cell: PhysicalCell) {
        let id = nextID("hover")
        control.handle(.init(.hover, id: id))
        let layout = target.wandRadialLayout
        let start = WandRadialNavigator.restingPosition(of: control.focusedCell ?? .switchApp, in: layout)
        let goal = WandRadialNavigator.restingPosition(of: cell, in: layout)
        control.handle(.init(.motion, id: id, sequence: 1, x: goal.x - start.x, y: goal.y - start.y))
        XCTAssertEqual(control.focusedCell, cell, "unheld motion moves the outline")
        control.handle(.init(.park, id: id, sequence: 2))
    }

    /// Ethan: "when I do press the HUD button down and hold it down and then
    /// drag up and down, it should drag the value up and down like I'm scrolling."
    func testHoldingMiddleOnAWheelCardInWedgeSelectionAdjustsItLikeScrolling() {
        openUtilities()
        let zoom = WheelChordControl.zoom.utilityCell!
        XCTAssertTrue(target.wandRadialLayout.contains(zoom))
        hoverAim(at: zoom)
        XCTAssertTrue(wheelChanges.compactMap { $0 }.isEmpty, "aiming never operates a card")
        let id = hold()
        XCTAssertNil(target.activeWheelControl, "the press waits for the first actual step")
        XCTAssertEqual(target.pointerFocus?.adjustment?.isHeld, true, "the listening outline shows the locked control")
        control.handle(.init(.motion, id: id, sequence: 1, x: 40, y: -12.5))
        XCTAssertEqual(target.activeWheelControl, .zoom, "the first step presses the card")
        XCTAssertEqual(adjustSteps, [.down, .down], "held up/down changes the value")
        XCTAssertEqual(control.focusedCell, zoom, "held motion never slides to a neighbouring wedge")
        control.handle(.init(.motion, id: id, sequence: 2, x: -40, y: -12.5)) // offsets are cumulative
        XCTAssertEqual(adjustSteps.count, 2, "Zoom is vertical: sideways travel does nothing")
        control.handle(.init(.motion, id: id, sequence: 3, x: -40, y: -6))
        XCTAssertEqual(adjustSteps.last, .up, "and back the other way in the same hold")
        let steps = adjustSteps.count
        releaseHold(id, sequence: 4)
        XCTAssertEqual(wheelReleases, [.zoom], "release lets go once")
        XCTAssertNil(target.activeWheelControl)
        XCTAssertNil(control.armedCell, "a held adjustment in wedge selection leaves no selection behind")
        XCTAssertTrue(control.isOpen, "still in wedge selection on Utilities")
        XCTAssertEqual(target.page, .modes)
        XCTAssertEqual(control.focusedCell, zoom)
        XCTAssertEqual(wheelChanges.compactMap { $0 }, [.zoom], "pressed once; the release's choose is consumed")
        XCTAssertEqual(adjustSteps.count, steps)
        hoverAim(at: WheelChordControl.brightness.utilityCell!)
        XCTAssertEqual(adjustSteps.count, steps, "wedge selection continues: unheld motion aims, never adjusts")
        XCTAssertEqual(wheelChanges.compactMap { $0 }, [.zoom])
    }

    /// The same open page and outlined card behave alike however they were
    /// reached: a click still enters dotted mode, and so does a held release
    /// without any adjustment, from the press already down.
    func testAClickOrStillHeldReleaseOnAWheelCardSelectsItWithoutPressing() {
        openUtilities()
        let zoom = WheelChordControl.zoom.utilityCell!
        hoverAim(at: zoom)
        tap(hold())
        XCTAssertEqual(control.armedCell, zoom, "a click selects it")
        XCTAssertTrue(wheelChanges.compactMap { $0 }.isEmpty, "selecting presses nothing")
        tap(hold())
        XCTAssertNil(control.armedCell, "a tap deselects")
        XCTAssertTrue(wheelReleases.isEmpty, "nothing was pressed, so nothing is released")
        XCTAssertTrue(control.isOpen)
        // Outline still on Zoom: hold without moving, release.
        let still = hold()
        XCTAssertNil(target.activeWheelControl, "a still hold presses nothing")
        releaseHold(still, sequence: 1)
        XCTAssertEqual(control.armedCell, zoom, "a still held release selects it")
        XCTAssertTrue(wheelChanges.compactMap { $0 }.isEmpty)
        XCTAssertTrue(adjustSteps.isEmpty)
    }

    /// Never both: a held adjustment of Copy/Paste lets go without its click
    /// action; a plain click on it is one click and closes.
    func testCopyPasteGetsOneActionPerGesture() {
        openUtilities()
        tap(hold()) // Utilities' centre goes back home, still in wedge selection
        XCTAssertTrue(target.isWandHome)
        let clip = PhysicalCell(rawValue: 4)!
        XCTAssertEqual(WheelChordControl.wandHomeControl(for: clip), .clipboard)
        hoverAim(at: clip)
        let held = hold()
        control.handle(.init(.motion, id: held, sequence: 1, x: 0, y: -7))
        XCTAssertEqual(adjustSteps, [.down])
        releaseHold(held, sequence: 2)
        XCTAssertEqual(wheelReleases, [.clipboard])
        XCTAssertTrue(control.isOpen, "after adjusting, wedge selection stays open")
        XCTAssertNil(control.armedCell)
        // Space is its own outer card: a Copy / Paste click selects the card
        // like any other wheel card, and types nothing.
        tap(hold())
        XCTAssertEqual(wheelChanges.compactMap { $0 }, [.clipboard], "the click presses nothing")
        XCTAssertEqual(control.armedCell, clip)
        XCTAssertTrue(control.isOpen)
        tap(hold())
        XCTAssertEqual(wheelReleases, [.clipboard], "deselecting releases nothing")
        XCTAssertEqual(adjustSteps, [.down])
        XCTAssertTrue(control.isOpen, "back to wedge selection")
        XCTAssertNil(control.armedCell)
        XCTAssertTrue(keysActions.isEmpty)
    }

    func testClickUnlocksAdjustedCopyPasteEvenWhenTheClickContainsMovement() {
        openUtilities()
        tap(hold())
        let clip = PhysicalCell(rawValue: 4)!
        hoverAim(at: clip)
        tap(hold())
        let drag = hold()
        control.handle(.init(.motion, id: drag, sequence: 1, y: -7))
        releaseHold(drag, sequence: 2)
        XCTAssertEqual(control.armedCell, clip)
        XCTAssertNil(target.activeWheelControl)

        // The receiver still classifies this as a click by its button timing.
        // A step during that short press must not swallow its unlock intent.
        let click = hold()
        control.handle(.init(.motion, id: click, sequence: 1, y: -7))
        control.handle(.init(.park, id: click, sequence: 2))
        control.handle(.init(.activate, id: nextID("activate")))
        XCTAssertNil(control.armedCell, "one click unlocks the adjusted wedge")
        XCTAssertNil(target.pointerFocus?.adjustment)
        XCTAssertNil(target.activeWheelControl)
        XCTAssertEqual(wheelReleases, [.clipboard, .clipboard], "each actual held step is released once")
        XCTAssertTrue(homeActions.isEmpty, "unlocking never falls through to a click action")

        let enter = PhysicalCell(rawValue: 7)!
        hoverAim(at: enter)
        tap(hold())
        XCTAssertEqual(homeActions, [enter], "Enter is reachable without closing the HUD")
        XCTAssertTrue(control.isOpen)
    }

    func testTerminalOnlyClickUnlocksDottedCardAfterItsNavigationPacketWasLost() {
        openUtilities()
        let zoom = WheelChordControl.zoom.utilityCell!
        hoverAim(at: zoom)
        tap(hold())
        XCTAssertEqual(control.armedCell, zoom)
        control.handle(.init(.activate, id: nextID("activate")))
        XCTAssertNil(control.armedCell, "a delivered click is enough to unlock")
        XCTAssertNil(target.pointerFocus?.adjustment)
        XCTAssertTrue(control.isOpen)
        XCTAssertTrue(wheelChanges.compactMap { $0 }.isEmpty, "unlocking presses nothing")
    }

    func testAHeldAdjustmentWithoutItsParkStillLetsGoOnce() {
        openUtilities()
        let zoom = WheelChordControl.zoom.utilityCell!
        hoverAim(at: zoom)
        let id = hold()
        control.handle(.init(.motion, id: id, sequence: 1, x: 0, y: -12.5))
        control.handle(.init(.choose, id: nextID("choose"))) // the park datagram was lost
        XCTAssertEqual(wheelReleases, [.zoom])
        XCTAssertNil(control.armedCell)
        XCTAssertTrue(control.isOpen)
        control.handle(.init(.park, id: id, sequence: 2)) // late park
        XCTAssertEqual(wheelReleases, [.zoom], "a late park never releases twice")
    }

    func testLostTelemetryOrAMissingClickNeverLeavesAWheelPressHeld() {
        openUtilities()
        let zoom = WheelChordControl.zoom.utilityCell!
        hoverAim(at: zoom)
        let pressed = hold()
        control.handle(.init(.motion, id: pressed, sequence: 1, x: 0, y: -7))
        XCTAssertEqual(target.activeWheelControl, .zoom)
        clock.advance(by: 1.1); tick.fire()
        XCTAssertFalse(control.isOpen, "a held press without telemetry ends")
        XCTAssertNil(target.activeWheelControl)
        XCTAssertTrue(wheelReleases.isEmpty, "ending it is not a release action")

        openUtilities()
        hoverAim(at: zoom)
        control.handle(.init(.park, id: hold(), sequence: 1)) // released, no click or choose follows
        XCTAssertNil(target.activeWheelControl, "a still hold pressed nothing")
        clock.advance(by: 1.1); tick.fire()
        XCTAssertTrue(control.isOpen, "nothing is held, so nothing has to end")
        XCTAssertNil(control.armedCell, "a missing terminal never selects or acts")
        XCTAssertTrue(wheelReleases.isEmpty)
        let next = hold()
        XCTAssertNotNil(target.pointerFocus?.adjustment, "the next press still works")
        releaseHold(next, sequence: 1)
    }

    func testHoldingOnSwitchAppOrAnOrdinaryCardStillAims() {
        openUtilities()
        tap(hold()) // Utilities' centre goes back home, still open
        XCTAssertTrue(target.isWandHome)
        XCTAssertEqual(control.focusedCell, PhysicalCell(rawValue: 12))
        let id = hold()
        XCTAssertNil(target.activeWheelControl, "an ordinary card is not pressed on HUD button down")
        let layout = target.wandRadialLayout
        let start = WandRadialNavigator.restingPosition(of: PhysicalCell(rawValue: 12)!, in: layout)
        aim(id, at: .switchApp)
        clock.advance(by: 2); control.handle(.init(.qualify, id: id, sequence: 2)); tick.fire()
        XCTAssertTrue(switchSteps.isEmpty && buttonPhases.isEmpty, "holding on Switch App aims; time never acts")
        let keys = WandRadialNavigator.restingPosition(of: .keysModeSelector, in: layout)
        control.handle(.init(.motion, id: id, sequence: 3, x: keys.x - start.x, y: keys.y - start.y)) // cumulative from the hold's start
        XCTAssertEqual(control.focusedCell, .keysModeSelector)
        releaseHold(id)
        XCTAssertEqual(target.page, .keys, "release still uses the aimed card")
    }

    // MARK: Repeatable Keys

    private func openKeys() {
        let id = holdFromClosed()
        aim(id, at: .keysModeSelector)
        releaseHold(id)
        XCTAssertEqual(target.page, .keys)
    }

    /// A tap after aiming: park past the aim's sequence, then the delayed tap.
    private func tapAimed(_ id: String) {
        control.handle(.init(.park, id: id, sequence: 9))
        control.handle(.init(.activate, id: nextID("activate")))
    }

    func testOnlyNavigationAndTextKeysRepeatOnTheWand() {
        XCTAssertEqual(KeysModeAction.allCases.filter(\.keepsWandHUDOpen),
                       [.arrowUp, .arrowDown, .arrowLeft, .arrowRight, .insertSpace, .pressBackspace])
    }

    func testArrowTapsAndHeldReleasesRepeatOnTheSameCardWithoutClosing() {
        openKeys()
        XCTAssertFalse(control.repeatKeysHintVisible, "no hint before a key repeats")
        let up = PhysicalCell(rawValue: 5)!
        let first = hold()
        aim(first, at: up)
        tapAimed(first)
        XCTAssertEqual(keysActions, [.arrowUp])
        XCTAssertTrue(control.isOpen)
        XCTAssertFalse(control.isConcealed)
        XCTAssertEqual(target.page, .keys)
        XCTAssertEqual(control.focusedCell, up, "the same card waits for the next click")
        XCTAssertTrue(control.repeatKeysHintVisible)

        tap(hold())
        tap(hold())
        XCTAssertEqual(keysActions, [.arrowUp, .arrowUp, .arrowUp], "click, click, click")
        releaseHold(hold())
        XCTAssertEqual(keysActions.count, 4, "a held release repeats too")
        XCTAssertTrue(control.isOpen)
        XCTAssertEqual(control.focusedCell, up)
        XCTAssertTrue(hud.isVisible)
    }

    func testAOneShotKeyKeepsTheHUDOpenAndEndsTheHint() {
        openKeys()
        let space = hold()
        aim(space, at: PhysicalCell(rawValue: 8)!)
        tapAimed(space)
        XCTAssertEqual(keysActions, [.insertSpace])
        XCTAssertTrue(control.repeatKeysHintVisible)
        let save = hold()
        aim(save, at: PhysicalCell(rawValue: 12)!)
        releaseHold(save)
        XCTAssertEqual(keysActions, [.insertSpace, .save])
        XCTAssertTrue(control.isOpen, "Save acts once; the HUD stays open (2026-10-30)")
        XCTAssertFalse(control.repeatKeysHintVisible, "Save does not repeat, so the repeat hint ends")
    }

    func testDismissExitAndReopenNeverInheritTheHint() {
        openKeys()
        let left = hold()
        aim(left, at: PhysicalCell(rawValue: 1)!)
        tapAimed(left)
        XCTAssertTrue(control.repeatKeysHintVisible)
        control.handle(.init(.dismiss, id: nextID("dismiss")))
        XCTAssertFalse(control.isOpen)
        XCTAssertFalse(control.repeatKeysHintVisible)
        openKeys()
        XCTAssertFalse(control.repeatKeysHintVisible, "a reopened Keys page starts without the hint")
        let down = hold()
        aim(down, at: PhysicalCell(rawValue: 4)!)
        tapAimed(down)
        XCTAssertTrue(control.repeatKeysHintVisible)
        tap(hold()) // still on Down: repeats
        let exit = hold()
        aim(exit, at: .modeExit)
        tapAimed(exit)
        XCTAssertTrue(target.isWandHome, "the centre still goes back")
        XCTAssertFalse(control.repeatKeysHintVisible, "leaving Keys ends the hint")
        allowed = false
        tick.fire()
        XCTAssertFalse(control.repeatKeysHintVisible)
    }

    // MARK: Time alone never acts

    /// Ethan retired the held-centre Switch App dwell: "if you hold it,
    /// nothing happens until you let go or like select one and then let go."

    /// HUD button down from closed, then the receiver's ordinary hold threshold.
    private func qualifiedHoldFromClosed() -> String {
        let id = holdFromClosed()
        clock.advance(by: 0.2)
        control.handle(.init(.qualify, id: id, sequence: 1))
        return id
    }

    /// A healthy held heartbeat: live motion samples and watchdog ticks.
    private func heartbeat(_ id: String, from first: Int, through last: Int, x: Double = 0, y: Double = 0) {
        for sequence in first...last {
            clock.advance(by: 0.25)
            control.handle(.init(.motion, id: id, sequence: sequence, x: x, y: y))
            tick.fire()
        }
    }

    func testHoldingStillOnTheCentreNeverActsUntilRelease() {
        let id = qualifiedHoldFromClosed()
        XCTAssertEqual(target.pointerFocus?.isArmed, false, "freely aiming must not look like locked dotted mode")
        heartbeat(id, from: 2, through: 41) // ten seconds, far past the retired dwell
        XCTAssertTrue(buttonPhases.isEmpty, "holding alone never presses Switch App or Command")
        XCTAssertNil(target.pointerFocus?.adjustment, "holding alone never enters dotted mode")
        XCTAssertNil(control.armedCell, "holding alone never arms")
        XCTAssertTrue(control.isOpen, "a healthy hold has no duration limit")
        XCTAssertEqual(control.focusedCell, .switchApp)
        control.handle(.init(.motion, id: id, sequence: 42, x: 3))
        XCTAssertTrue(switchSteps.isEmpty, "small sideways motion in the centre never switches apps")

        releaseHold(id, sequence: 43)
        XCTAssertTrue(buttonPhases.isEmpty, "release arms without pressing Command")
        XCTAssertEqual(control.armedCell, .switchApp)
        let held = hold()
        control.handle(.init(.motion, id: held, sequence: 1, x: 4.7))
        XCTAssertEqual(buttonPhases, ["press"], "the first step right is Command-Tab itself: the next app")
        XCTAssertTrue(switchSteps.isEmpty)
        control.handle(.init(.motion, id: held, sequence: 2, x: 9.4))
        XCTAssertEqual(switchSteps, [.down], "the next step right moves on one more")
        releaseHold(held, sequence: 3)
        XCTAssertEqual(buttonPhases, ["press", "release"])
        XCTAssertFalse(control.isOpen)
    }

    func testAMotionlessHeldCentreNeverArmsOnTheWatchdog() {
        let id = qualifiedHoldFromClosed()
        heartbeat(id, from: 2, through: 13)
        for _ in 0..<4 { clock.advance(by: 0.2); tick.fire() } // ticks between samples
        XCTAssertTrue(buttonPhases.isEmpty)
        XCTAssertNil(target.pointerFocus?.adjustment)
        XCTAssertTrue(control.isOpen)
    }

    func testWanderingAwayAndBackNeverActsAndReleaseUsesTheOutlinedCard() {
        let id = qualifiedHoldFromClosed()
        let layout = target.wandRadialLayout
        let start = WandRadialNavigator.restingPosition(of: .switchApp, in: layout)
        let goal = WandRadialNavigator.restingPosition(of: .wandPlayPause, in: layout)
        heartbeat(id, from: 2, through: 9, x: goal.x - start.x, y: goal.y - start.y)
        XCTAssertEqual(control.focusedCell, .wandPlayPause)
        heartbeat(id, from: 10, through: 17)
        XCTAssertEqual(control.focusedCell, .switchApp, "back on the centre")
        heartbeat(id, from: 18, through: 25, x: goal.x - start.x, y: goal.y - start.y)
        XCTAssertTrue(buttonPhases.isEmpty);XCTAssertTrue(homeActions.isEmpty)
        releaseHold(id, sequence: 26)
        XCTAssertEqual(homeActions, [.wandPlayPause], "only the release uses the card, once")
        XCTAssertTrue(buttonPhases.isEmpty)
    }

    func testTheFirstHighMouseSampleOfTheHeldChooserOnlyRebases() {
        let id = qualifiedHoldFromClosed(); releaseHold(id, sequence: 2)
        let held = hold()
        control.handle(.init(.motion, id: held, sequence: 1, x: 3, mouseX: 5_000))
        XCTAssertTrue(switchSteps.isEmpty && buttonPhases.isEmpty, "the first cumulative sample only rebases")
        control.handle(.init(.motion, id: held, sequence: 2, x: 3, mouseX: 5_604.8))
        XCTAssertEqual(buttonPhases, ["press"], "one detent right")
        XCTAssertTrue(switchSteps.isEmpty)
        releaseHold(held, sequence: 3)
        XCTAssertFalse(control.isOpen)
        XCTAssertEqual(buttonPhases, ["press", "release"])
    }

    func testSwitchAppUsesFasterHighGainCountsAndImmediateReversal() {
        let held = adjustArmedSwitchApp()
        control.handle(.init(.qualify, id: held, sequence: 1))
        control.handle(.init(.motion, id: held, sequence: 2, mouseX: 1_000))
        // The live HIGH count stream is already scaled by the single receiver
        // sensitivity. 806.4 counts at the reference gain used to make one
        // detent; the 1.5x chooser boost makes exactly two.
        control.handle(.init(.motion, id: held, sequence: 3, mouseX: 1_806.4))
        XCTAssertEqual(switchSteps, [.down, .down])
        control.handle(.init(.motion, id: held, sequence: 4, mouseX: 1_000))
        XCTAssertEqual(switchSteps, [.down, .down, .up, .up], "reverse immediately, without a latch")
        releaseHold(held, sequence: 5)
        XCTAssertEqual(buttonPhases, ["press", "release"])
    }

    func testSwitchAppMetricChangesOnlyRebaseEvenWithFasterSensitivity() {
        let held = adjustArmedSwitchApp()
        control.handle(.init(.qualify, id: held, sequence: 1))
        control.handle(.init(.motion, id: held, sequence: 2, x: 4.7))
        XCTAssertEqual(switchSteps, [.down], "angle fallback receives the same 1.5x boost")
        control.handle(.init(.motion, id: held, sequence: 3, x: 100, mouseX: 5_000))
        XCTAssertEqual(switchSteps, [.down], "first HIGH sample only rebases")
        control.handle(.init(.motion, id: held, sequence: 4, x: 200))
        XCTAssertEqual(switchSteps, [.down], "leaving HIGH also only rebases")
        control.handle(.init(.motion, id: held, sequence: 5, x: 195.3))
        XCTAssertEqual(switchSteps, [.down, .up])
        releaseHold(held, sequence: 6)
    }

    func testChildPagesAndOtherCardsStayOrdinaryHover() {
        openKeys()
        let child = hold()
        clock.advance(by: 0.2)
        control.handle(.init(.qualify, id: child, sequence: 1))
        heartbeat(child, from: 2, through: 13)
        XCTAssertTrue(buttonPhases.isEmpty, "a child page's centre is its exit, never Switch App")
        XCTAssertTrue(keysActions.isEmpty)
        XCTAssertTrue(control.isOpen)
        XCTAssertEqual(target.page, .keys)
    }

    func testLongHeldCentreStillTearsDownOnLockAndLostTelemetry() {
        let locked = qualifiedHoldFromClosed()
        heartbeat(locked, from: 2, through: 9)
        allowed = false
        tick.fire()
        allowed = true
        control.handle(.init(.motion, id: locked, sequence: 10))
        XCTAssertFalse(target.isActive)
        XCTAssertTrue(buttonPhases.isEmpty)

        let silent = qualifiedHoldFromClosed()
        heartbeat(silent, from: 2, through: 9)
        clock.advance(by: 1.1)
        tick.fire()
        XCTAssertFalse(target.isActive, "a hold whose telemetry stops closes")
        control.handle(.init(.motion, id: silent, sequence: 10))
        XCTAssertTrue(buttonPhases.isEmpty)
    }

    // MARK: Receiver circle continuation feedback

    /// Ethan wants the receiver's clockwise/anticlockwise circle to keep the
    /// held Switch App adjustment going. The native flag tells it exactly
    /// when that adjustment is live; the receiver owns the circle itself.

    func testSwitchAppAdjustingIsTrueOnlyWhileTheHeldChooserStreams() {
        let id = qualifiedHoldFromClosed()
        XCTAssertFalse(control.switchAppAdjusting, "the opening hold only aims")
        releaseHold(id, sequence: 2)
        XCTAssertFalse(control.switchAppAdjusting, "armed is not a held chooser")
        let hover = nextID("hover"); control.handle(.init(.hover,id:hover))
        XCTAssertFalse(control.switchAppAdjusting)
        control.handle(.init(.park,id:hover,sequence:1))
        let held = hold()
        XCTAssertTrue(control.switchAppAdjusting)
        control.handle(.init(.motion,id:held,sequence:1,mouseX:1_000))
        control.handle(.init(.motion,id:held,sequence:2,mouseX:1_403.2))
        XCTAssertEqual(buttonPhases,["press"],"one boosted detent right: Command-Tab")
        control.handle(.init(.motion,id:held,sequence:3,mouseX:1_806.4))
        XCTAssertEqual(switchSteps,[.down])
        releaseHold(held,sequence:4)
        XCTAssertFalse(control.switchAppAdjusting)
        XCTAssertEqual(buttonPhases,["press","release"])
    }

    private func adjustArmedSwitchApp() -> String {
        let id = qualifiedHoldFromClosed()
        releaseHold(id, sequence: 2)
        let held = hold()
        XCTAssertTrue(control.switchAppAdjusting)
        return held
    }

    func testSwitchAppAdjustingClearsOnDismissLockAndStaleTelemetry() {
        _ = adjustArmedSwitchApp()
        control.handle(.init(.dismiss, id: nextID("dismiss")))
        XCTAssertFalse(control.switchAppAdjusting)

        _ = adjustArmedSwitchApp()
        allowed = false
        XCTAssertFalse(control.switchAppAdjusting, "a locked session never advertises an adjustment")
        tick.fire()
        allowed = true
        XCTAssertFalse(control.switchAppAdjusting)
        XCTAssertFalse(target.isActive)

        _ = adjustArmedSwitchApp()
        clock.advance(by: 1.1)
        XCTAssertFalse(control.switchAppAdjusting, "stale telemetry stops advertising before the watchdog runs")
        tick.fire()
        XCTAssertFalse(target.isActive)
    }

    func testSwitchAppAdjustingClearsWhenTheModeEnds() {
        _ = adjustArmedSwitchApp()
        target.exit(reason: .userRequested)
        XCTAssertFalse(control.switchAppAdjusting)
    }

    func testOtherAdjustmentsAndChildPagesNeverAdvertiseSwitchApp() {
        let id = holdFromClosed()
        aim(id, at: PhysicalCell(rawValue: 1)!)
        releaseHold(id)
        XCTAssertEqual(control.armedCell, PhysicalCell(rawValue: 1)!)
        let scroll = hold()
        control.handle(.init(.motion, id: scroll, sequence: 1, x: -12.5, y: 0)) // Horizontal Scroll moves left/right on the wand
        XCTAssertEqual(adjustSteps, [.down, .down])
        XCTAssertFalse(control.switchAppAdjusting, "a wheel card's adjustment is not Switch App")
        control.handle(.init(.dismiss, id: nextID("dismiss")))

        openKeys()
        let child = hold()
        clock.advance(by: 0.2)
        control.handle(.init(.qualify, id: child, sequence: 1))
        heartbeat(child, from: 2, through: 5)
        XCTAssertFalse(control.switchAppAdjusting, "a child page has no Switch App")
    }

    func testTheWireAcceptsChoose() throws {
        let json = #"{"command":"agentic_mouse_wand_control","version":1,"phase":"choose","id":"choose-0001","seq":0}"#
        XCTAssertEqual(try WandPersistentCommand.decodeIfPresent(Data(json.utf8))?.phase, .choose)
    }
    func testNewPhysicalHoldRecoversAnOrphanedPreviousHold() {
        // The opening hold's release was lost. A fresh press in the open home
        // HUD on Switch App is the Switch App chooser (Ethan's exception); it
        // must start cleanly and never be swallowed.
        _ = holdFromClosed()
        let fresh = hold()
        XCTAssertTrue(control.isOpen)
        XCTAssertTrue(control.switchAppAdjusting, "the fresh press is live, not swallowed")
        releaseHold(fresh)
        XCTAssertTrue(buttonPhases.isEmpty, "released before any step or qualification: nothing switched")
        // A lost aim on another card: the next press continues on the same page.
        control.handle(.init(.dismiss, id: nextID("dismiss")))
        openKeys()
        let lost = hold()
        aim(lost, at: PhysicalCell(rawValue: 4)!)
        let next = hold()
        aim(next, at: PhysicalCell(rawValue: 4)!)
        XCTAssertEqual(target.page, .keys)
        releaseHold(next)
    }


    // MARK: Switch App exception (Ethan: "that's the exception is the switch
    // app middle button. The behavior was good before")

    func testArmedSwitchAppSurvivesUnheldAimingAwayAndBackThenAHoldChooses() {
        releaseHold(holdFromClosed())
        XCTAssertEqual(control.armedCell, .switchApp)
        hoverAim(at: PhysicalCell(rawValue: 7)!)
        XCTAssertNotEqual(target.pointerFocus?.isArmed, true, "another card looks ordinary")
        hoverAim(at: .switchApp)
        XCTAssertEqual(target.pointerFocus?.isArmed, true, "back on Switch App it still shows armed")
        XCTAssertTrue(homeActions.isEmpty && buttonPhases.isEmpty, "unheld aiming never acts")
        let held = hold()
        XCTAssertTrue(buttonPhases.isEmpty, "Command waits for the first step or the qualified hold")
        XCTAssertTrue(control.switchAppAdjusting)
        control.handle(.init(.motion, id: held, sequence: 1, x: -12.5))
        XCTAssertEqual(buttonPhases, ["press"], "the first step presses Command")
        XCTAssertEqual(switchSteps, [.up, .up, .up], "two steps left of the current app: back past it twice from Command-Tab's next app")
        releaseHold(held, sequence: 2)
        XCTAssertEqual(buttonPhases, ["press", "release"], "release switches")
        XCTAssertFalse(control.isOpen, "and closes")
    }

    func testHoldingAnotherCardWhileSwitchAppIsArmedDisarmsAndAimsNormally() {
        releaseHold(holdFromClosed())
        hoverAim(at: PhysicalCell(rawValue: 7)!)
        let id = hold()
        XCTAssertTrue(buttonPhases.isEmpty, "Command is never pressed away from Switch App")
        XCTAssertNil(control.armedCell)
        aim(id, at: .wandPlayPause)
        releaseHold(id)
        XCTAssertEqual(homeActions, [.wandPlayPause])
        XCTAssertTrue(switchSteps.isEmpty)
    }

    func testCellElevenOnAChildPageIsZoomNotSwitchApp() {
        openUtilities()
        let zoom = WheelChordControl.zoom.utilityCell!
        XCTAssertEqual(zoom, .switchApp, "the same physical cell")
        hoverAim(at: zoom)
        tap(hold())
        XCTAssertTrue(buttonPhases.isEmpty, "Command is never held on a child page")
        XCTAssertEqual(control.armedCell, zoom, "a Zoom click selects Zoom")
        let held = hold()
        XCTAssertFalse(control.switchAppAdjusting, "holding cell 11 on a child page adjusts Zoom")
        control.handle(.init(.motion, id: held, sequence: 1, x: 0, y: -7))
        XCTAssertEqual(wheelChanges.compactMap { $0 }, [.zoom])
        XCTAssertTrue(buttonPhases.isEmpty)
        releaseHold(held, sequence: 2)
    }

    // MARK: Lost and late datagrams

    func testAHeldAdjustmentWhoseParkAndChooseWereLostEndsOnTheNextUnheldStream() {
        openUtilities()
        let zoom = WheelChordControl.zoom.utilityCell!
        hoverAim(at: zoom)
        let id = hold()
        control.handle(.init(.motion, id: id, sequence: 1, x: 0, y: -12.5))
        XCTAssertFalse(adjustSteps.isEmpty)
        // The HUD button went up but its park and choose never arrived; the receiver's
        // next unheld stream proves the release.
        let hover = nextID("hover")
        control.handle(.init(.hover, id: hover))
        XCTAssertEqual(wheelReleases, [.zoom], "the held press is let go once")
        XCTAssertNil(control.armedCell)
        XCTAssertTrue(control.isOpen, "wedge selection stays open")
        control.handle(.init(.motion, id: hover, sequence: 1, x: 6, y: 0))
        clock.advance(by: 3)
        tick.fire()
        XCTAssertTrue(control.isOpen, "an unheld stream never expires on time alone")
        XCTAssertEqual(wheelReleases, [.zoom])
    }

    func testAStaleAimOnAChildPageNeverResetsHomeOnTheNextPress() {
        openKeys()
        let lost = hold()
        aim(lost, at: PhysicalCell(rawValue: 4)!)
        // That hold's park and use were lost. The next physical press continues here.
        let next = hold()
        XCTAssertEqual(target.page, .keys, "the page Ethan was on stays")
        XCTAssertTrue(control.isOpen)
        aim(next, at: PhysicalCell(rawValue: 4)!)
        tapAimed(next)
        XCTAssertEqual(keysActions.count, 1, "the new press acts once")
    }

    // MARK: Release on a submenu from a closed HUD (Ethan, 2026-10-29)

    func testHoldSteerAndReleaseFromClosedEntersAppAndUtilityPages() {
        frontmost = .codex
        let app = holdFromClosed()
        aim(app, at: .frontmostAppModeSelector)
        releaseHold(app)
        XCTAssertEqual(target.page, .appSpecific, "release on the app card enters it at once")
        XCTAssertEqual(target.appSpecificTarget, .codex)
        XCTAssertTrue(control.isOpen)
        XCTAssertNil(control.armedCell, "a submenu card never arms dotted mode")
        control.handle(.init(.dismiss, id: nextID("dismiss")))
        let utility = holdFromClosed()
        aim(utility, at: .modePickerEntry)
        releaseHold(utility)
        XCTAssertEqual(target.page, .modes)
        XCTAssertFalse(target.isWandHome)
        XCTAssertNil(control.armedCell)
    }

    func testAPressWhileTheReceiverThinksAnOldSessionIsOpenStillOpensAndEnters() {
        XCTAssertFalse(control.isOpen)
        let id = hold() // navigate with no open: the receiver still believed a session was open
        XCTAssertTrue(control.isOpen, "a physical press is the hold that shows the HUD")
        aim(id, at: .modePickerEntry)
        releaseHold(id)
        XCTAssertEqual(target.page, .modes)
    }

    // MARK: Codex Speed: hover, then hold and move (Ethan, 2026-10-29)

    func testCodexSpeedHoverThenHeldMovementAdjustsLikeDottedMode() throws {
        frontmost = .codex
        let id = holdFromClosed()
        aim(id, at: .frontmostAppModeSelector)
        releaseHold(id)
        let speed = try XCTUnwrap(PhysicalCell.all.first { WheelChordControl.appSpecificControl(for: .codex, cell: $0) == .codexResponseSpeed })
        hoverAim(at: speed)
        let held = hold()
        XCTAssertTrue(wheelChanges.compactMap { $0 }.isEmpty, "nothing is pressed until the wand actually moves")
        XCTAssertEqual(target.pointerFocus?.adjustment?.isHeld, true, "listening glow while held")
        control.handle(.init(.motion, id: held, sequence: 1, x: 0, y: -12.5))
        XCTAssertEqual(wheelChanges.compactMap { $0 }.last, .codexResponseSpeed, "the first step presses Speed")
        XCTAssertEqual(adjustSteps.count, 2, "held up/down adjusts at once")
        releaseHold(held, sequence: 2)
        XCTAssertTrue(control.isOpen)
        XCTAssertNil(control.armedCell)
        XCTAssertEqual(wheelReleases.last, .codexResponseSpeed)
    }

    // MARK: Semantic axis and swipe actions

    private func stream(_ id: String, from start: Int, steps: Int, dx: Double, dy: Double = 0, every: Double = 0.01,
                        origin: inout (x: Double, y: Double)) -> Int {
        var sequence = start
        for _ in 0..<steps {
            clock.advance(by: every)
            origin.x += dx; origin.y += dy; sequence += 1
            control.handle(.init(.motion, id: id, sequence: sequence, x: origin.x, y: origin.y))
        }
        return sequence
    }

    func testSpacesSwipeLeftAndRightAndRepeatAfterASlowReturn() throws {
        openUtilities()
        let spaces = try XCTUnwrap(WheelChordControl.spaces.utilityCell)
        hoverAim(at: spaces)
        tap(hold())
        XCTAssertEqual(control.armedCell, spaces, "Spaces is selected (dots)")
        var rearms = 0
        control.onAdjustRearm = { rearms += 1 }
        // Ethan: only while the HUD button is held. Unheld motion does nothing.
        let unheld = nextID("hover")
        control.handle(.init(.hover, id: unheld))
        var free = (x: 0.0, y: 0.0)
        _ = stream(unheld, from: 0, steps: 10, dx: 1, origin: &free)
        XCTAssertTrue(adjustSteps.isEmpty, "a dotted card never listens while the HUD button is up")
        control.handle(.init(.park, id: unheld, sequence: 99))
        let hover = hold()
        var at = (x: 0.0, y: 0.0)
        var seq = stream(hover, from: 0, steps: 8, dx: 0, dy: 1, origin: &at)
        XCTAssertTrue(adjustSteps.isEmpty, "Spaces ignores up/down")
        clock.advance(by: 0.3)
        seq = stream(hover, from: seq, steps: 6, dx: 1, origin: &at)
        XCTAssertEqual(adjustSteps, [WheelChordControl.spaces.wandDirection(positive: true)], "one quick drag right: one space left")
        XCTAssertEqual(WheelChordControl.spaces.wandDirection(positive: true), .down)
        XCTAssertEqual(target.pointerFocus?.adjustment?.lastStepWasUp, false, "right drag lights the right arrow despite sending wheel-down")
        seq = stream(hover, from: seq, steps: 100, dx: -0.06, origin: &at)
        XCTAssertEqual(adjustSteps.count, 1, "a slow return never acts")
        seq = stream(hover, from: seq, steps: 6, dx: 1, origin: &at)
        XCTAssertEqual(adjustSteps.count, 2, "the same direction acts again without leaving dotted mode")
        seq = stream(hover, from: seq, steps: 40, dx: 0, origin: &at)
        seq = stream(hover, from: seq, steps: 6, dx: -1, origin: &at)
        XCTAssertEqual(adjustSteps.last, .up, "a quick drag left: one space right")
        XCTAssertEqual(target.pointerFocus?.adjustment?.lastStepWasUp, true, "left drag lights the left arrow")
        XCTAssertEqual(rearms, 3)
        XCTAssertEqual(control.armedCell, spaces, "dotted mode stays until a HUD button click")
        _ = seq
    }

    func testValueControlsKeepContinuousDetentsNotSwipes() throws {
        openUtilities()
        let zoom = try XCTUnwrap(WheelChordControl.zoom.utilityCell)
        XCTAssertFalse(WheelChordControl.zoom.isWandSwipeAction)
        XCTAssertEqual(WheelChordControl.zoom.wandAxis, .vertical)
        hoverAim(at: zoom)
        tap(hold())
        let hover = hold()
        var at = (x: 0.0, y: 0.0)
        _ = stream(hover, from: 0, steps: 140, dx: 0, dy: 0.1, every: 0.02, origin: &at)
        XCTAssertEqual(adjustSteps.count, 2, "slow travel still steps a value: 14° is two detents")
        XCTAssertTrue(adjustSteps.allSatisfy { $0 == .up })
    }

    func testWandAxesFollowEachActionsOwnDirection() {
        for control in [WheelChordControl.zoom, .brightness, .spotifyVolume, .codexResponseSpeed, .codexReasoningEffort, .clipboard, .systemOverview] {
            XCTAssertEqual(control.wandAxis, .vertical, "\(control) changes a value or is a vertical gesture")
        }
        XCTAssertEqual(WheelChordControl.spaces.utilityAction(for: WheelChordControl.spaces.wandDirection(positive: true)), .moveToSpaceLeft)
        XCTAssertEqual(WheelChordControl.magnetWindow.utilityAction(for: WheelChordControl.magnetWindow.wandDirection(positive: true)), .moveWindowRightWithMagnet)
        XCTAssertEqual(WheelChordControl.chromeTabs.chromeTabHistoryAction(for: WheelChordControl.chromeTabs.wandDirection(positive: true)), .forward)
        XCTAssertEqual(WheelChordControl.mediaTracks.mediaTrackAction(for: WheelChordControl.mediaTracks.wandDirection(positive: true)), .next)
        XCTAssertEqual(WheelChordControl.vsCodeCursorHistory.vsCodeCursorHistoryCommand(for: WheelChordControl.vsCodeCursorHistory.wandDirection(positive: true)), .navigateForward)
        XCTAssertEqual(WheelChordControl.codexChatHistory.codexChatHistoryAction(for: WheelChordControl.codexChatHistory.wandDirection(positive: true)), .forward)
        XCTAssertEqual(WheelChordControl.horizontalScroll.wandDirection(positive: true).horizontalWheelDelta, -1, "right scrolls the way the wheel's right ratchet does")
        for control in [WheelChordControl.spaces, .horizontalScroll, .chromeTabs, .claudeTabs, .codexChatHistory, .vsCodeCursorHistory, .mediaTracks, .magnetWindow] {
            XCTAssertEqual(control.wandAxis, .horizontal, "\(control) moves left/right")
        }
        XCTAssertTrue(WheelChordControl.systemOverview.isWandSwipeAction)
        XCTAssertTrue(WheelChordControl.spaces.isWandSwipeAction)
        XCTAssertFalse(WheelChordControl.brightness.isWandSwipeAction)
    }

    // MARK: Submenus stay open (Ethan, 2026-10-30; superseding the 2026-10-29 hide-and-reopen)

    func testAnActionOnASubmenuStaysThereUntilADoubleClickDismisses() {
        frontmost = .codex
        let id = holdFromClosed()
        aim(id, at: .frontmostAppModeSelector)
        releaseHold(id)
        XCTAssertEqual(target.page, .appSpecific)
        let ordinary = PhysicalCell.all.first { cell in
            target.wandRadialLayout.contains(cell) && cell != .frontmostAppModeSelector && cell != .modeExit
                && WheelChordControl.appSpecificControl(for: .codex, cell: cell) == nil
        }!
        hoverAim(at: ordinary)
        tap(hold())
        XCTAssertTrue(control.isOpen, "the ordinary action keeps the HUD open")
        lingerOut()
        XCTAssertTrue(target.isActive, "time alone never closes it")
        XCTAssertEqual(target.page, .appSpecific, "still on Codex")
        XCTAssertEqual(target.appSpecificTarget, .codex)
        control.handle(.init(.dismiss, id: nextID("dismiss")))
        _ = holdFromClosed()
        XCTAssertTrue(target.isWandHome, "a double-click dismissal starts again at home")
    }

    func testDoubleClickWhileHiddenAndLockForgetTheSubmenu() {
        openUtilities()
        // Use an ordinary Utility action: any non-wheel, non-navigation card.
        let action = PhysicalCell.all.first { cell in
            target.wandRadialLayout.contains(cell) && (ModeUtilityAction.directAction(for: cell).map { $0 != .selectAll } ?? false)
        }!
        hoverAim(at: action)
        tap(hold())
        XCTAssertTrue(control.isOpen, "the action keeps Utility open")
        control.handle(.init(.dismiss, id: nextID("dismiss"))) // double click closes
        lingerOut()
        _ = holdFromClosed()
        XCTAssertTrue(target.isWandHome, "dismissed properly")
        control.handle(.init(.dismiss, id: nextID("dismiss")))
        openUtilities()
        hoverAim(at: action)
        tap(hold())
        allowed = false
        tick.fire()
        allowed = true
        _ = holdFromClosed()
        XCTAssertTrue(target.isWandHome, "lock forgets the submenu")
    }

    // MARK: Held-only adjustment and Switch App in an open HUD (Ethan, 2026-10-29 amendment)

    func testAFreshHoldOnSwitchAppInAnOpenHomeHUDChoosesWithoutArming() {
        openUtilities()
        let back = hold()
        aim(back, at: .modeExit)
        releaseHold(back)
        XCTAssertTrue(target.isWandHome, "Back returns home")
        hoverAim(at: .switchApp)
        XCTAssertNil(control.armedCell, "not armed")
        let held = hold()
        XCTAssertTrue(control.switchAppAdjusting, "a fresh hold on Switch App chooses apps at once")
        control.handle(.init(.qualify, id: held, sequence: 1))
        XCTAssertEqual(buttonPhases, ["press"], "a qualified hold opens the switcher")
        control.handle(.init(.motion, id: held, sequence: 2, x: 6.5))
        XCTAssertEqual(switchSteps, [.down], "right steps forward directly")
        releaseHold(held, sequence: 3)
        XCTAssertEqual(buttonPhases, ["press", "release"], "release switches")
        XCTAssertFalse(control.isOpen)
    }

    func testTheHoldThatOpensTheHUDOnlyAims() {
        let opening = holdFromClosed()
        control.handle(.init(.qualify, id: opening, sequence: 1))
        control.handle(.init(.motion, id: opening, sequence: 2, x: 0.5))
        XCTAssertTrue(buttonPhases.isEmpty, "no Switch App chooser on the opening hold")
        XCTAssertFalse(control.switchAppAdjusting)
    }

    func testDottedCardsNeverListenWhileUpAndAStillHoldNeverPressesThem() throws {
        openUtilities()
        let zoom = try XCTUnwrap(WheelChordControl.zoom.utilityCell)
        hoverAim(at: zoom)
        tap(hold())
        XCTAssertEqual(control.armedCell, zoom)
        XCTAssertEqual(target.pointerFocus?.adjustment?.isHeld, false, "dots without the listening glow")
        XCTAssertTrue(wheelChanges.compactMap { $0 }.isEmpty, "selecting presses nothing")
        let up = nextID("hover")
        control.handle(.init(.hover, id: up))
        control.handle(.init(.motion, id: up, sequence: 1, x: 0, y: -14))
        XCTAssertTrue(adjustSteps.isEmpty, "HUD button up: no adjustment, the wand can reset")
        control.handle(.init(.park, id: up, sequence: 2))
        let still = hold()
        XCTAssertEqual(target.pointerFocus?.adjustment?.isHeld, true, "listening glow")
        releaseHold(still, sequence: 1)
        XCTAssertTrue(wheelChanges.compactMap { $0 }.isEmpty && wheelReleases.isEmpty, "a hold without movement presses nothing")
        XCTAssertEqual(control.armedCell, zoom, "a still held release keeps it selected")
        let drag = hold()
        control.handle(.init(.motion, id: drag, sequence: 1, x: 0, y: -14))
        XCTAssertEqual(adjustSteps, [.down, .down])
        releaseHold(drag, sequence: 2)
        XCTAssertEqual(wheelReleases, [.zoom], "release lets go")
        XCTAssertEqual(control.armedCell, zoom, "and keeps it selected for the next hold")
        tap(hold())
        XCTAssertNil(control.armedCell, "a tap leaves dotted mode")
        XCTAssertTrue(control.isOpen)
    }

    func testOneActionControlsNeverActOnTheReturnAfterRelease() throws {
        openUtilities()
        let overview = try XCTUnwrap(WheelChordControl.systemOverview.utilityCell)
        hoverAim(at: overview)
        tap(hold())
        let first = hold()
        var at = (x: 0.0, y: 0.0)
        _ = stream(first, from: 0, steps: 6, dx: 0, dy: -1, origin: &at)
        XCTAssertEqual(adjustSteps.count, 1, "one swipe, one action")
        control.handle(.init(.park, id: first, sequence: 50))
        control.handle(.init(.choose, id: nextID("choose")))
        let up = nextID("hover")
        control.handle(.init(.hover, id: up))
        var back = (x: 0.0, y: 0.0)
        _ = stream(up, from: 0, steps: 6, dx: 0, dy: 1, origin: &back)
        XCTAssertEqual(adjustSteps.count, 1, "resetting the wand with the HUD button up never acts")
        control.handle(.init(.park, id: up, sequence: 50))
        let second = hold()
        var again = (x: 0.0, y: 0.0)
        _ = stream(second, from: 0, steps: 6, dx: 0, dy: -1, origin: &again)
        XCTAssertEqual(adjustSteps.count, 2, "the next held swipe acts again")
        XCTAssertEqual(adjustSteps[0], adjustSteps[1])
    }

    func testTheRingNewCodexChatCardIsAOneShotAction() {
        let id = holdFromClosed()
        let layout = target.wandRadialLayout
        XCTAssertEqual(layout.ringIndex(of: .wandCodexNewChat), 8, "in Screenshot's old ring slot")
        XCTAssertNil(layout.outerIndex(of: .wandCodexNewChat))
        let goal = WandRadialNavigator.restingPosition(of: .wandCodexNewChat, in: layout)
        for step in 1...10 { control.handle(.init(.motion, id: id, sequence: step, x: goal.x * Double(step) / 10, y: goal.y * Double(step) / 10)) }
        XCTAssertEqual(control.focusedCell, .wandCodexNewChat)
        releaseHold(id, sequence: 11)
        XCTAssertEqual(homeActions, [.wandCodexNewChat], "one action on release")
        XCTAssertTrue(control.isOpen, "creating a chat keeps the HUD open")
    }

    func testATapThatOnlyReopensARememberedSubmenuNeverActs() {
        // A tap from closed acts at once (the receiver skips the double-click
        // wait), but when that press only reopened a remembered submenu its
        // tap must not use the start card, so a double click resets to home.
        frontmost = .codex
        let id = holdFromClosed()
        aim(id, at: .frontmostAppModeSelector)
        releaseHold(id)
        let ordinary = PhysicalCell.all.first { cell in
            target.wandRadialLayout.contains(cell) && cell != .frontmostAppModeSelector && cell != .modeExit
                && WheelChordControl.appSpecificControl(for: .codex, cell: cell) == nil
        }!
        hoverAim(at: ordinary)
        tap(hold())
        lingerOut()
        let reopen = holdFromClosed()
        XCTAssertEqual(target.page, .appSpecific)
        tap(reopen)
        XCTAssertEqual(target.page, .appSpecific, "the reopening tap did not use the start card (Back)")
        XCTAssertTrue(control.isOpen)
        control.handle(.init(.dismiss, id: nextID("dismiss")))
        _ = holdFromClosed()
        XCTAssertTrue(target.isWandHome, "the double click reset to home")
    }
}

