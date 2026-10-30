import XCTest
@testable import ScimitarKit

final class WandPersistentControlTests:XCTestCase {
    var clock:ManualClock!,tick:ManualTickScheduler!,target:ModePickerCoordinator!,control:WandPersistentController!
    var clicks:[PhysicalCell]=[],presses:[String]=[],steps:[WheelChordDirection]=[]
    override func setUp(){
        clock=ManualClock(now:100);tick=ManualTickScheduler()
        target=ModePickerCoordinator(lease:WandModeLease(),hud:RecordingModeHUDPresenter(),scheduler:ManualTickScheduler(),log:Log(category:"test",sink:NullLogSink()))
        target.resolveFrontmostApp={FrontmostAppModeContext(target:.chrome,displayName:"Chrome",bundleIdentifier:"com.google.Chrome")}
        target.onWandHomeInput={[unowned self] in self.clicks.append($0);return true}
        target.onAppSpecificInput={[unowned self] _,_,cell,phase,_ in self.presses.append("\(cell.rawValue):\(phase)");return true}
        control=WandPersistentController(target:target,scheduler:tick,clock:clock)
        control.onAdjustStep={[unowned self] in self.steps.append($0);return true}
        control.handle(.init(.open,id:"open-0001"))
    }
    /// Cumulative motion from the parked outline to `cell`, using the
    /// HUD's own weapon-wheel layout, exactly as the receiver streams it.
    func offset(to cell:PhysicalCell,scale:Double=1)->(x:Double,y:Double){
        let layout=target.wandRadialLayout
        let start=WandRadialNavigator.restingPosition(of:control.focusedCell ?? .switchApp,in:layout)
        let goal=WandRadialNavigator.restingPosition(of:cell,in:layout)
        return (goal.x*scale-start.x,goal.y*scale-start.y)
    }
    var navigateCount=0
    func select(_ cell:PhysicalCell){
        navigateCount+=1
        let id="navigate-\(navigateCount)-wand"
        let goal=offset(to:cell)
        control.handle(.init(.navigate,id:id))
        control.handle(.init(.motion,id:id,sequence:1,x:goal.x/2,y:goal.y/2))
        control.handle(.init(.motion,id:id,sequence:2,x:goal.x,y:goal.y))
        control.handle(.init(.park,id:id,sequence:3))
    }
    func operate(){control.handle(.init(.press,id:UUID().uuidString))}
    func testReleaseParksWithoutClickAndStaysOpen(){
        select(.frontmostAppModeSelector)
        XCTAssertTrue(control.isOpen);XCTAssertEqual(control.focusedCell,.frontmostAppModeSelector)
        XCTAssertTrue(clicks.isEmpty);XCTAssertTrue(presses.isEmpty)
        clock.advance(by:600);tick.fire()
        XCTAssertTrue(control.isOpen);XCTAssertEqual(control.focusedCell,.frontmostAppModeSelector)
    }
    func testExplicitAppEntryReusesFrontmostAppAndRetainsOwnership(){
        target.resolveFrontmostApp={FrontmostAppModeContext(target:.vsCode,displayName:"VS Code",bundleIdentifier:"com.microsoft.VSCode")}
        control.handle(.init(.appSpecific,id:"app-mode-001"))
        XCTAssertTrue(control.isOpen)
        XCTAssertEqual(target.page,.appSpecific)
        XCTAssertEqual(target.appSpecificTarget,.vsCode)
        XCTAssertTrue(clicks.isEmpty)
        clock.advance(by:2);tick.fire();XCTAssertTrue(control.isOpen)
    }
    func testNativePressReleaseAndChildBackKeepOutline(){
        select(.frontmostAppModeSelector)
        control.handle(.init(.press,id:"operate-001"));XCTAssertTrue(target.isWandHome)
        control.handle(.init(.release,id:"operate-001",sequence:1));XCTAssertFalse(target.isWandHome)
        XCTAssertEqual(control.focusedCell,.frontmostAppModeSelector)
        control.handle(.init(.press,id:"operate-002"));control.handle(.init(.release,id:"operate-002",sequence:1))
        XCTAssertTrue(target.isWandHome);XCTAssertTrue(control.isOpen)
    }
    func testOneTapActsOnceAndKeepsHomeOpen(){
        control.handle(.init(.press,id:"operate-001"));XCTAssertTrue(clicks.isEmpty)
        control.handle(.init(.release,id:"operate-001",sequence:1))
        control.handle(.init(.release,id:"operate-001",sequence:1))
        XCTAssertEqual(clicks,[.switchApp]);XCTAssertTrue(control.isOpen)
    }
    func testHoldWheelUsesSameControlAndRelease(){
        select(PhysicalCell(rawValue:1)!) // home cell 1: horizontal scroll
        XCTAssertEqual(control.focusedCell?.rawValue,1)
        control.handle(.init(.press,id:"operate-001"))
        XCTAssertEqual(target.activeWheelControl,.horizontalScroll)
        control.handle(.init(.motion,id:"operate-001",sequence:1,x:-12.5)) // Horizontal Scroll moves left/right on the wand
        XCTAssertEqual(steps,[.down,.down])
        control.handle(.init(.release,id:"operate-001",sequence:2))
        XCTAssertNil(target.activeWheelControl);XCTAssertTrue(control.isOpen)
        XCTAssertEqual(control.focusedCell?.rawValue,1)
    }
    func testHeldSwitchAppUsesHorizontalMotionAndPreservesRelease() {
        var switched:[WheelChordDirection]=[]
        control.onSwitchAppStep={switched.append($0);return true}
        control.handle(.init(.press,id:"switch-app-1"))
        control.handle(.init(.motion,id:"switch-app-1",sequence:1,y:20))
        XCTAssertTrue(switched.isEmpty,"vertical aiming cannot select another app")
        control.handle(.init(.motion,id:"switch-app-1",sequence:2,x:7,y:20))
        XCTAssertEqual(switched,[.down])
        control.handle(.init(.motion,id:"switch-app-1",sequence:3,x:-7,y:20))
        XCTAssertEqual(switched,[.down,.up,.up])
        control.handle(.init(.release,id:"switch-app-1",sequence:4))
        XCTAssertTrue(control.isOpen)
    }
    func testUnheldAimingOutlinesAnotherCardWithoutOperatingIt(){
        let goal=offset(to:.frontmostAppModeSelector)
        control.handle(.init(.hover,id:"hover-switch"))
        control.handle(.init(.motion,id:"hover-switch",sequence:1,x:goal.x,y:goal.y))
        XCTAssertEqual(control.focusedCell,.frontmostAppModeSelector)
        XCTAssertNil(control.armedCell)
        control.handle(.init(.park,id:"hover-switch",sequence:2))
        XCTAssertTrue(clicks.isEmpty);XCTAssertTrue(presses.isEmpty);XCTAssertTrue(steps.isEmpty)
        XCTAssertEqual(control.focusedCell,.frontmostAppModeSelector)
    }

    func testDottedStreamPauseKeepsItThenAClickSwitches(){
        var switched:[WheelChordDirection]=[]
        control.onSwitchAppStep={switched.append($0);return true}
        control.handle(.init(.choose,id:"arm-switch"))
        control.handle(.init(.hover,id:"hover-switch"))
        control.handle(.init(.motion,id:"hover-switch",sequence:1,x:0.1,y:0.1))
        control.handle(.init(.park,id:"hover-switch",sequence:2))
        XCTAssertEqual(control.armedCell,.switchApp)
        XCTAssertTrue(switched.isEmpty,"unheld movement never switches apps")
        control.handle(.init(.navigate,id:"held-switch"))
        control.handle(.init(.motion,id:"held-switch",sequence:1,x:7))
        XCTAssertTrue(switched.isEmpty,"the first detent right is Command-Tab itself")
        control.handle(.init(.motion,id:"held-switch",sequence:2,x:14))
        XCTAssertEqual(switched,[.down])
        control.handle(.init(.park,id:"held-switch",sequence:3))
        XCTAssertFalse(control.isOpen,"releasing the chooser commits")
        XCTAssertNil(control.armedCell)
    }

    func testQualifiedHoldKeepsPlainOutlineUntilChoosingLockedAdjustment() {
        control.handle(.init(.navigate,id:"qualifying-hold"))
        XCTAssertFalse(target.pointerFocus?.isArmed ?? false)
        control.handle(.init(.qualify,id:"qualifying-hold",sequence:1))
        XCTAssertFalse(target.pointerFocus?.isArmed ?? false,"dots must never mean freely aiming")
        XCTAssertNil(control.armedCell,"only release actually arms the next hold")
        XCTAssertTrue(clicks.isEmpty);XCTAssertTrue(presses.isEmpty);XCTAssertTrue(steps.isEmpty)
        let goal=offset(to:.frontmostAppModeSelector)
        control.handle(.init(.motion,id:"qualifying-hold",sequence:2,x:goal.x,y:goal.y))
        XCTAssertFalse(target.pointerFocus?.isArmed ?? false)
        control.handle(.init(.motion,id:"qualifying-hold",sequence:3))
        XCTAssertFalse(target.pointerFocus?.isArmed ?? false)
        control.handle(.init(.park,id:"qualifying-hold",sequence:4))
        XCTAssertFalse(target.pointerFocus?.isArmed ?? false,"park is not yet a selection")
        control.handle(.init(.choose,id:"choose-qualified"))
        XCTAssertEqual(control.armedCell,.switchApp)
        XCTAssertTrue(target.pointerFocus?.isArmed ?? false,"only the actual locked adjustment shows dots")
        XCTAssertTrue(clicks.isEmpty)
    }
    func testPassiveAimingSurvivesTelemetryPauseWithoutHoldingKeys(){
        control.handle(.init(.hover,id:"hover-rest"))
        clock.advance(by:600);tick.fire()
        XCTAssertTrue(control.isOpen)
        XCTAssertNil(control.armedCell)
        XCTAssertTrue(clicks.isEmpty);XCTAssertTrue(presses.isEmpty)
        let goal=offset(to:.frontmostAppModeSelector)
        control.handle(.init(.motion,id:"hover-rest",sequence:1,x:goal.x,y:goal.y))
        XCTAssertEqual(control.focusedCell,.frontmostAppModeSelector)
        control.handle(.init(.dismiss,id:"dismiss-rest"))
        XCTAssertFalse(control.isOpen)
    }

    func testUnheldAimingMovesTheOutlineButNeverActsOrOpensAHiddenHUD(){
        control.handle(.init(.hover,id:"unarmed-hover"))
        control.handle(.init(.motion,id:"unarmed-hover",sequence:1,x:20,y:20))
        XCTAssertNotEqual(control.focusedCell,.switchApp,"wedge selection follows unheld motion")
        XCTAssertTrue(clicks.isEmpty);XCTAssertTrue(presses.isEmpty);XCTAssertNil(control.armedCell)
        control.handle(.init(.dismiss,id:"dismiss-hover"))
        control.handle(.init(.hover,id:"hidden-hover"))
        XCTAssertFalse(control.isOpen);XCTAssertTrue(clicks.isEmpty)
    }

    func testScreenshotUsesNativePressReleaseWithoutDuplicateAction(){
        var released:[WheelChordControl]=[]
        target.onWheelControlRelease={_,control in released.append(control)}
        select(.screenshotToggle)
        XCTAssertEqual(control.focusedCell,.screenshotToggle)
        control.handle(.init(.press,id:"screenshot-1"))
        XCTAssertEqual(target.activeWheelControl,.screenshotPaste)
        control.handle(.init(.release,id:"screenshot-1",sequence:1))
        XCTAssertEqual(released,[.screenshotPaste]);XCTAssertTrue(clicks.isEmpty)
        XCTAssertTrue(control.isOpen)
    }
    func testDismissAndLostHeldReleaseCloseWithoutClick(){
        control.handle(.init(.dismiss,id:"dismiss-001"));XCTAssertFalse(control.isOpen)
        control.handle(.init(.open,id:"open-0002"));control.handle(.init(.press,id:"operate-001"))
        clock.advance(by:1.1);tick.fire();XCTAssertFalse(control.isOpen);XCTAssertTrue(clicks.isEmpty)
    }
    func testHealthyHeldNavigationAndOperationHaveNoDurationLimit() {
        for phase in [WandPersistentCommand.Phase.navigate, .press] {
            let id = "long-hold-\(phase.rawValue)"
            control.handle(.init(phase,id:id))
            // Zero movement is a live report too; remaining still must not dismiss.
            for sequence in 1...240 {
                clock.advance(by:0.5)
                control.handle(.init(.motion,id:id,sequence:sequence))
                tick.fire()
                XCTAssertTrue(control.isOpen,"healthy \(phase) closed after \(sequence / 2) seconds")
            }
            XCTAssertTrue(clicks.isEmpty)
            control.handle(.init(phase == .navigate ? .park : .release,id:id,sequence:241))
            XCTAssertTrue(control.isOpen)
        }
        XCTAssertEqual(clicks,[.switchApp],"only the explicit operation release selects")
    }
    func testMissingTelemetryStillClosesAfterLongHealthyHold() {
        control.handle(.init(.press,id:"long-then-lost"))
        for sequence in 1...80 {
            clock.advance(by:0.5)
            control.handle(.init(.motion,id:"long-then-lost",sequence:sequence))
            tick.fire()
        }
        XCTAssertTrue(control.isOpen)
        clock.advance(by:1.1);tick.fire()
        XCTAssertFalse(control.isOpen)
        XCTAssertTrue(clicks.isEmpty)
    }
    func testWireRejectsForgedSourceAndNonFiniteOffsets() throws {
        let valid=#"{"command":"agentic_mouse_wand_control","version":1,"phase":"open","id":"open-0001","seq":0}"#
        XCTAssertNotNil(try WandPersistentCommand.decodeIfPresent(Data(valid.utf8)))
        let forged=valid.dropLast()+",\"source\":\"corsair\"}"
        XCTAssertThrowsError(try WandPersistentCommand.decodeIfPresent(Data(forged.utf8)))
        let bool=valid.replacingOccurrences(of:"\"seq\":0",with:"\"seq\":true")
        XCTAssertThrowsError(try WandPersistentCommand.decodeIfPresent(Data(bool.utf8)))
    }
    func testVSCodeShortcutsAreWandOnlyAndUseHeldReviewContext() {
        XCTAssertNil(PhysicalCell(rawValue:13))
        XCTAssertEqual(PhysicalCell.all.count,12)
        XCTAssertEqual(target.wandRadialLayout.ring.count,12)
        XCTAssertFalse(target.wandRadialLayout.contains(.wandReviewChanges))
        target.resolveFrontmostApp={FrontmostAppModeContext(target:.vsCode,displayName:"VS Code",bundleIdentifier:"com.microsoft.VSCode")}
        XCTAssertEqual(target.wandRadialLayout.ring.count,12,"the ring never changes for VS Code")
        XCTAssertTrue(target.wandRadialLayout.contains(.wandReviewChanges),"review lives in the outer layer")
        XCTAssertEqual(target.wandRadialLayout.center,.switchApp)
        select(.wandReviewChanges)
        XCTAssertEqual(control.focusedCell,.wandReviewChanges)
        XCTAssertNil(control.reviewMode)
        control.handle(.init(.press,id:"review-changes-1"))
        XCTAssertEqual(control.reviewMode,"changes")
        XCTAssertTrue(clicks.isEmpty);XCTAssertTrue(presses.isEmpty)
        control.handle(.init(.motion,id:"review-changes-1",sequence:1,y:10))
        XCTAssertEqual(control.focusedCell,.wandReviewChanges)
        control.handle(.init(.release,id:"review-changes-1",sequence:2))
        XCTAssertNil(control.reviewMode)
        select(.wandReviewFiles)
        XCTAssertEqual(control.focusedCell,.wandReviewFiles)
        control.handle(.init(.press,id:"review-files-1"))
        XCTAssertEqual(control.reviewMode,"files")
        target.resolveFrontmostApp={FrontmostAppModeContext(target:.chrome,displayName:"Chrome",bundleIdentifier:"com.google.Chrome")}
        XCTAssertNil(control.reviewMode,"leaving VS Code revokes the hold")
        XCTAssertEqual(target.wandRadialLayout.ring.count,12)
        control.handle(.init(.dismiss,id:"dismiss-extra-1"))
        XCTAssertNil(control.reviewMode)
    }
    func testReviewSelectionSurvivesNavigationHidingAndAppSwitch() {
        target.resolveFrontmostApp={FrontmostAppModeContext(target:.vsCode,displayName:"VS Code",bundleIdentifier:"com.microsoft.VSCode")}
        select(.wandReviewChanges)
        control.handle(.init(.activate,id:"select-review-1"))
        XCTAssertEqual(control.selectedReviewMode,"changes")
        XCTAssertEqual(control.pinnedReviewCell,.wandReviewChanges)
        XCTAssertFalse(control.isOpen,"selection immediately hides the full HUD")
        control.handle(.init(.dismiss,id:"hide-review-1"))
        XCTAssertEqual(control.selectedReviewMode,"changes")
        var reported=0;control.onContext={_ in reported+=1}
        clock.advance(by:120);tick.fire()
        XCTAssertGreaterThan(reported,0,"hidden selected mode keeps its context heartbeat")
        target.resolveFrontmostApp={FrontmostAppModeContext(target:.chrome,displayName:"Chrome",bundleIdentifier:"com.google.Chrome")}
        XCTAssertNil(control.selectedReviewMode)
        target.resolveFrontmostApp={FrontmostAppModeContext(target:.vsCode,displayName:"VS Code",bundleIdentifier:"com.microsoft.VSCode")}
        XCTAssertEqual(control.selectedReviewMode,"changes")
        control.reset(reason:.systemSleep)
        XCTAssertNil(control.selectedReviewMode)
        XCTAssertNil(control.pinnedReviewCell)
    }

    func testPlayPauseIsAlwaysRightOfUtilityAndOnlyActsOnceOnRelease() {
        XCTAssertNil(PhysicalCell(rawValue:15),"not a physical mouse button")
        let ring=target.wandRadialLayout.ring
        XCTAssertEqual(ring.firstIndex(of:.wandPlayPause),ring.firstIndex(of:.modePickerEntry).map{$0+1},
                       "Play/Pause sits immediately after Utility, clockwise round the wheel")
        XCTAssertFalse(PhysicalCell.wandRows(source:.corsair,legend:[]).joined().contains(.wandPlayPause))
        XCTAssertFalse(PhysicalCell.wandRows(source:.razer,legend:[]).joined().contains(.wandPlayPause))
        select(.wandPlayPause)
        XCTAssertEqual(control.focusedCell,.wandPlayPause)
        control.handle(.init(.press,id:"media-1"))
        XCTAssertTrue(clicks.isEmpty)
        control.handle(.init(.release,id:"media-1",sequence:1))
        control.handle(.init(.release,id:"media-1",sequence:1))
        XCTAssertEqual(clicks,[.wandPlayPause]);XCTAssertTrue(control.isOpen)
    }
    func testWheelChangingUnderALiveHoldKeepsTheSameCard() {
        let id="live-reseat-1"
        let toward=offset(to:PhysicalCell(rawValue:5)!)
        control.handle(.init(.navigate,id:id))
        control.handle(.init(.motion,id:id,sequence:1,x:toward.x,y:toward.y))
        XCTAssertEqual(control.focusedCell?.rawValue,5)
        // VS Code comes to the front mid-hold: two review cards join the wheel.
        target.resolveFrontmostApp={FrontmostAppModeContext(target:.vsCode,displayName:"VS Code",bundleIdentifier:"com.microsoft.VSCode")}
        control.handle(.init(.motion,id:id,sequence:2,x:toward.x+0.2,y:toward.y))
        XCTAssertEqual(control.focusedCell?.rawValue,5,"the outline never jumps to whatever now sits there")
        XCTAssertEqual(target.wandRadialLayout.ring.count,12)
        XCTAssertEqual(target.wandRadialLayout.outer.count,6,"Review, Stage, Undo, Space, New Codex chat and Zoom")
        control.handle(.init(.park,id:id,sequence:3))
        XCTAssertTrue(clicks.isEmpty,"hover alone never acts")
    }

    func testTappingSelectedReviewCardAgainClearsMode() {
        target.resolveFrontmostApp={FrontmostAppModeContext(target:.vsCode,displayName:"VS Code",bundleIdentifier:"com.microsoft.VSCode")}
        select(.wandReviewFiles)
        control.handle(.init(.activate,id:"select-files-1"))
        XCTAssertEqual(control.selectedReviewMode,"files")
        control.handle(.init(.activate,id:"select-files-1"))
        XCTAssertEqual(control.selectedReviewMode,"files","a duplicate datagram cannot toggle the selected mode off")
        control.handle(.init(.exitReview,id:"clear-files-1"))
        XCTAssertNil(control.selectedReviewMode)
        XCTAssertTrue(clicks.isEmpty)
    }

    func testExtendedRowsClampInsteadOfWrappingOrEnteringBlankSpace() throws {
        let rows=PhysicalCell.displayRowsTopToBottom.enumerated().map { i,row in i==1 ? row+[.wandReviewChanges,.wandReviewFiles] : row }
        var nav=try XCTUnwrap(WandGridNavigator(rows:rows,start:.switchApp))
        nav.apply(deltaX:800,deltaY:0);XCTAssertEqual(nav.focusedCell,.wandReviewFiles)
        nav.apply(deltaX:0,deltaY:-80);XCTAssertEqual(nav.focusedCell,rows[0][3])
        nav.apply(deltaX:8,deltaY:0);XCTAssertEqual(nav.focusedCell,rows[0][3])
        XCTAssertEqual(PhysicalCell.wandRows(source:.corsair,legend:[.init(cell:.wandReviewChanges,actionTitle:"Review",accent:.init(red:1,green:1,blue:1)),.init(cell:.wandReviewFiles,actionTitle:"Files",accent:.init(red:1,green:1,blue:1))]).map(\.count),[4,4,4])
    }

}


extension WandPersistentControlTests {
    func testHighMouseStreamUsesReferenceDistanceAndIgnoresRawAngle(){
        var switched:[WheelChordDirection]=[]
        control.onSwitchAppStep={switched.append($0);return true}
        control.handle(.init(.choose,id:"arm-high"))
        control.handle(.init(.navigate,id:"high-stream"))
        control.handle(.init(.motion,id:"high-stream",sequence:1,x:100,mouseX:500))
        XCTAssertTrue(switched.isEmpty,"the first cumulative sample is a baseline")
        // Fine movement accumulates exactly the same travel as one fast sweep.
        for n in 1...20 {
            control.handle(.init(.motion,id:"high-stream",sequence:n+1,x:100+Double(n)*10,
                                 mouseX:500+Double(n)*30.24))
        }
        // A Middle hold presses Command with its first detent: Command-Tab
        // itself highlights the next app, so that detent sends no extra step.
        XCTAssertTrue(switched.isEmpty,"604.8 HIGH counts are one seven-degree reference detent: Command-Tab")
        control.handle(.init(.motion,id:"high-stream",sequence:22,x:300,mouseX:500+2*604.8))
        XCTAssertEqual(switched,[.down],"the next detent steps on, independent of raw angle")
        XCTAssertEqual(target.pointerFocus?.adjustment?.netSteps,1)
        control.handle(.init(.motion,id:"high-stream",sequence:23,x:300,mouseX:500))
        XCTAssertEqual(switched,[.down,.up,.up],"opposite HIGH travel reverses without any angular motion")
        control.handle(.init(.park,id:"high-stream",sequence:24))
        XCTAssertFalse(control.isOpen,"releasing switches apps and closes")
    }

    func testHighMouseAndLegacyAnglesHaveEquivalentDetents() {
        var switched:[WheelChordDirection]=[]
        control.onSwitchAppStep={switched.append($0);return true}
        control.handle(.init(.press,id:"legacy-reference"))
        control.handle(.init(.motion,id:"legacy-reference",sequence:1,x:7))
        XCTAssertEqual(switched,[.down])
        control.handle(.init(.release,id:"legacy-reference",sequence:2))
        control.handle(.init(.press,id:"high-reference"))
        control.handle(.init(.motion,id:"high-reference",sequence:1,mouseX:0))
        control.handle(.init(.motion,id:"high-reference",sequence:2,mouseX:604.8))
        XCTAssertEqual(switched,[.down,.down])
        control.handle(.init(.motion,id:"high-reference",sequence:3,mouseX:604.8+200_000))
        XCTAssertEqual(switched.count,8,"one oversized sample is capped at six")
        control.handle(.init(.motion,id:"high-reference",sequence:4,mouseX:604.8+200_000))
        XCTAssertEqual(switched.count,8,"excess movement is dropped, not queued")
    }

    func testHighMouseMetricTransitionsRebaseWithoutJumping() {
        var switched:[WheelChordDirection]=[]
        control.onSwitchAppStep={switched.append($0);return true}
        control.handle(.init(.press,id:"metric-change"))
        control.handle(.init(.motion,id:"metric-change",sequence:1,x:7))
        XCTAssertEqual(switched,[.down])
        control.handle(.init(.motion,id:"metric-change",sequence:2,x:100,mouseX:20_000))
        XCTAssertEqual(switched.count,1,"new HIGH metric only rebases")
        control.handle(.init(.motion,id:"metric-change",sequence:3,x:100,mouseX:20_604.8))
        XCTAssertEqual(switched,[.down,.down])
        control.handle(.init(.motion,id:"metric-change",sequence:4,x:300))
        XCTAssertEqual(switched.count,2,"missing stream rebases the angular metric")
        control.handle(.init(.motion,id:"metric-change",sequence:5,x:307))
        XCTAssertEqual(switched,[.down,.down,.down])
        control.handle(.init(.motion,id:"metric-change",sequence:6,x:307,mouseX:-10_000))
        XCTAssertEqual(switched.count,3,"returning stream cannot replay old cumulative travel")
        control.handle(.init(.motion,id:"metric-change",sequence:7,x:307,mouseX:-10_604.8))
        XCTAssertEqual(switched,[.down,.down,.down,.up])
    }

    func testHighMouseCannotBypassSequenceOrGestureIdentity() {
        var switched:[WheelChordDirection]=[]
        control.onSwitchAppStep={switched.append($0);return true}
        control.handle(.init(.press,id:"high-identity"))
        control.handle(.init(.motion,id:"high-identity",sequence:1,mouseX:0))
        control.handle(.init(.motion,id:"wrong-identity",sequence:2,mouseX:6000))
        control.handle(.init(.motion,id:"high-identity",sequence:1,mouseX:6000))
        XCTAssertTrue(switched.isEmpty)
        control.handle(.init(.motion,id:"high-identity",sequence:2,mouseX:604.8))
        XCTAssertEqual(switched,[.down])
        control.reset(reason:.systemSleep)
        control.handle(.init(.motion,id:"high-identity",sequence:3,mouseX:6000))
        XCTAssertEqual(switched.count,1)
    }

    func testHighMouseMetadataDoesNotChangeNavigationOrOtherWheelCards() {
        var switched:[WheelChordDirection]=[]
        control.onSwitchAppStep={switched.append($0);return true}
        let goal=offset(to:.frontmostAppModeSelector)
        control.handle(.init(.navigate,id:"nav-with-high"))
        control.handle(.init(.motion,id:"nav-with-high",sequence:1,x:goal.x,y:goal.y,mouseX:100_000))
        XCTAssertEqual(control.focusedCell,.frontmostAppModeSelector)
        XCTAssertTrue(switched.isEmpty)
        control.handle(.init(.park,id:"nav-with-high",sequence:2))
        select(PhysicalCell(rawValue:1)!)
        control.handle(.init(.press,id:"wheel-with-high"))
        control.handle(.init(.motion,id:"wheel-with-high",sequence:1,x:-12.5,mouseX:100_000)) // left/right on the wand
        XCTAssertEqual(steps,[.down,.down])
        XCTAssertTrue(switched.isEmpty)
        control.handle(.init(.release,id:"wheel-with-high",sequence:2))
        XCTAssertNil(target.activeWheelControl)
    }

    func testHighMouseWireValidationAndLegacyCompatibility() throws {
        func wire(_ extra:String,phase:String="motion")->Data {
            Data(("{\"command\":\"agentic_mouse_wand_control\",\"version\":1,\"phase\":\""+phase+"\",\"id\":\"wire-high\",\"seq\":1"+extra+"}").utf8)
        }
        XCTAssertNil(try WandPersistentCommand.decodeIfPresent(wire(""))?.mouseX)
        XCTAssertEqual(try WandPersistentCommand.decodeIfPresent(wire(",\"mouseX\":7200000"))?.mouseX,7_200_000)
        XCTAssertEqual(try WandPersistentCommand.decodeIfPresent(wire(",\"mouseX\":-12.5"))?.mouseX,-12.5)
        for value in ["true","null","\"604.8\"","7200001","-7200001"] {
            XCTAssertThrowsError(try WandPersistentCommand.decodeIfPresent(wire(",\"mouseX\":"+value)))
        }
        for phase in ["open","hover","navigate","qualify","park","release","choose"] {
            XCTAssertThrowsError(try WandPersistentCommand.decodeIfPresent(wire(",\"mouseX\":0",phase:phase)))
        }
        // Non-finite JSON is rejected before a command exists.
        XCTAssertNil(try WandPersistentCommand.decodeIfPresent(wire(",\"mouseX\":NaN")))
    }
}


extension WandPersistentControlTests {
    func testScreenshotContextRenewsAfterHiddenHUDAndPublishesTermination() {
        var contexts:[Bool]=[]
        control.onContext={contexts.append($0)}
        control.refreshContext(screenshotActive:true)
        // Screenshot is the one home action that still parks the HUD.
        target.setPointerFocus(.init(cell:.screenshotToggle))
        control.handle(.init(.activate,id:"hide-during-capture"))
        XCTAssertTrue(control.isConcealed)
        let initial=contexts.count
        clock.advance(by:0.5);tick.fire()
        XCTAssertGreaterThan(contexts.count,initial,"renew screenshot while HUD follow-up lingers")
        clock.advance(by:4);tick.fire()
        XCTAssertFalse(control.isOpen)
        XCTAssertTrue(tick.isRunning,"capture retains receiver context beyond two-second HUD linger")
        let before=contexts.count
        clock.advance(by:20);tick.fire()
        XCTAssertGreaterThan(contexts.count,before)
        control.refreshContext(screenshotActive:false)
        XCTAssertEqual(contexts.last,false)
        XCTAssertFalse(tick.isRunning,"completion/cancel stops screenshot-only heartbeat")
    }

    func testScreenshotContextCannotOutliveLockReset() {
        control.refreshContext(screenshotActive:true)
        control.reset(reason:.systemSleep)
        XCTAssertFalse(tick.isRunning)
        XCTAssertFalse(control.isOpen)
    }
}

extension WandPersistentControlTests {
    private func selectReview(_ cell:PhysicalCell) {
        target.resolveFrontmostApp={FrontmostAppModeContext(target:.vsCode,displayName:"VS Code",bundleIdentifier:"com.microsoft.VSCode")}
        select(cell)
        control.handle(.init(.activate,id:"select-review-\(cell.rawValue)"))
        XCTAssertFalse(control.isOpen)
    }

    func testDoubleMiddleTogglesReviewModesBackAndForthWithTheHUDHidden() {
        selectReview(.wandReviewChanges)
        XCTAssertEqual(control.selectedReviewMode,"changes")
        var contexts:[Bool]=[];control.onContext={contexts.append($0)}
        control.handle(.init(.toggleReview,id:"toggle-review-1"))
        XCTAssertEqual(control.selectedReviewMode,"files")
        XCTAssertEqual(control.pinnedReviewCell,.wandReviewFiles)
        XCTAssertEqual(contexts.last,false,"context is republished with the HUD still hidden")
        XCTAssertFalse(control.isOpen);XCTAssertFalse(target.isActive)
        control.handle(.init(.toggleReview,id:"toggle-review-1"))
        XCTAssertEqual(control.selectedReviewMode,"files","a duplicate datagram never flips back")
        control.handle(.init(.toggleReview,id:"toggle-review-2"))
        XCTAssertEqual(control.selectedReviewMode,"changes")
        control.handle(.init(.toggleReview,id:"toggle-review-1"))
        XCTAssertEqual(control.selectedReviewMode,"changes","a delayed older duplicate also stays inert")
        XCTAssertTrue(tick.isRunning,"the selected mode keeps its heartbeat")
        XCTAssertTrue(clicks.isEmpty);XCTAssertTrue(presses.isEmpty);XCTAssertTrue(steps.isEmpty,
            "toggling never fabricates a wheel, commit or card action")
    }

    func testToggleNeedsALiveSelectionInVSCode() {
        control.handle(.init(.toggleReview,id:"toggle-none"))
        XCTAssertNil(control.selectedReviewMode)
        XCTAssertTrue(control.isOpen,"an unrelated toggle leaves the open HUD alone")
        XCTAssertEqual(control.focusedCell,.switchApp)
        selectReview(.wandReviewFiles)
        target.resolveFrontmostApp={FrontmostAppModeContext(target:.chrome,displayName:"Chrome",bundleIdentifier:"com.google.Chrome")}
        control.handle(.init(.toggleReview,id:"toggle-chrome"))
        XCTAssertEqual(control.pinnedReviewCell,.wandReviewFiles,"no toggle outside VS Code")
        target.resolveFrontmostApp={FrontmostAppModeContext(target:.vsCode,displayName:"VS Code",bundleIdentifier:"com.microsoft.VSCode")}
        XCTAssertEqual(control.selectedReviewMode,"files")
        control.handle(.init(.exitReview,id:"exit-review-1"))
        control.handle(.init(.toggleReview,id:"toggle-after-exit"))
        XCTAssertNil(control.selectedReviewMode,"exit stays a single, final exit")
    }

    func testToggleDoesNotCutAnotherActionsFollowUpShort() {
        selectReview(.wandReviewChanges)
        control.handle(.init(.open,id:"open-again"))
        target.setPointerFocus(.init(cell:.screenshotToggle))
        control.handle(.init(.activate,id:"tap-screenshot"))
        XCTAssertTrue(control.isConcealed)
        control.handle(.init(.toggleReview,id:"toggle-while-hidden"))
        XCTAssertTrue(control.isConcealed)
        XCTAssertEqual(control.selectedReviewMode,"files")
    }

    func testTheWireAcceptsToggleReviewOnly() throws {
        let json=#"{"command":"agentic_mouse_wand_control","version":1,"phase":"toggleReview","id":"toggle-0001","seq":0}"#
        XCTAssertEqual(try WandPersistentCommand.decodeIfPresent(Data(json.utf8))?.phase,.toggleReview)
        let withMouse=json.dropLast()+",\"mouseX\":0}"
        XCTAssertThrowsError(try WandPersistentCommand.decodeIfPresent(Data(withMouse.utf8)))
    }
}
