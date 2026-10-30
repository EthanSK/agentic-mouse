import XCTest
import ScimitarKit
@testable import AgenticMouseApp

/// Receiver-shaped HUD button gestures through the real coordinator, virtual
/// wheel policy and Copy/Paste executor. Keyboard output is captured, never
/// posted into Ethan's live app or clipboard.
@MainActor
final class WandClipboardRoutingTests: XCTestCase {
    /// Ethan: in wedge selection, holding the HUD button on a card "should drag
    /// the value up and down like I'm scrolling". Never both: that held
    /// adjustment types no Space; a later plain click is exactly one Space.
    func testHeldMiddleOnCopyPasteInWedgeSelectionAdjustsAndNeverAlsoTypesSpace() throws {
        let clock=ManualClock(now:100)
        let target=ModePickerCoordinator(lease:WandModeLease(),hud:RecordingModeHUDPresenter(),
            scheduler:ManualTickScheduler(),log:Log(category:"test",sink:NullLogSink()))
        let wheel=WandVirtualWheel(clock:clock)
        var actions:[ModeUtilityAction]=[]
        var spaces=0
        let executor=ModeUtilityActionExecutor(postKeyboardChord:{_ in true},accessibilityTrusted:{true},inputAllowed:{true})
        target.onWheelControlChange={_,control in wheel.setActive(control)}
        target.onWheelControlRelease={_,control in
            if let release=wheel.release(control),release.control == .clipboard,!release.didObserveWheelInput {spaces+=1}
        }
        let persistent=WandPersistentController(target:target,scheduler:ManualTickScheduler(),clock:clock)
        persistent.onAdjustStep={direction in
            guard let step=wheel.step(direction),let action=step.control.topLevelSystemAction(for:step.direction) else{return false}
            actions.append(action)
            if case .success = executor.perform(action) {return true};return false
        }
        persistent.handle(.init(.open,id:"held-open"))
        let cell=PhysicalCell.clipboardWheelControl
        let layout=target.wandRadialLayout
        let start=WandRadialNavigator.restingPosition(of:.switchApp,in:layout)
        let goal=WandRadialNavigator.restingPosition(of:cell,in:layout)
        // Wedge selection: unheld aiming, then the receiver parks it as the HUD button goes down.
        persistent.handle(.init(.hover,id:"held-aim"))
        persistent.handle(.init(.motion,id:"held-aim",sequence:1,x:goal.x-start.x,y:goal.y-start.y))
        persistent.handle(.init(.park,id:"held-aim",sequence:2))
        XCTAssertNil(wheel.activeControl,"aiming never operates the card")
        persistent.handle(.init(.navigate,id:"held-adjust"))
        XCTAssertNil(wheel.activeControl,"HUD button down listens; nothing is pressed until the wand moves")
        persistent.handle(.init(.motion,id:"held-adjust",sequence:1,y:-7))
        XCTAssertEqual(wheel.activeControl,.clipboard,"the first step holds Copy/Paste")
        XCTAssertEqual(actions,[.copy],"held up means Copy")
        persistent.handle(.init(.park,id:"held-adjust",sequence:2))
        persistent.handle(.init(.choose,id:"held-release"))
        XCTAssertEqual(actions,[.copy]);XCTAssertEqual(spaces,0,"a held adjustment never also types Space")
        XCTAssertNil(wheel.activeControl);XCTAssertNil(persistent.armedCell);XCTAssertTrue(persistent.isOpen)
        // A plain click on the same outlined card selects it (dots): Space is
        // the separate outer card on the wand, never this card's click.
        persistent.handle(.init(.navigate,id:"held-click"))
        persistent.handle(.init(.park,id:"held-click",sequence:1))
        persistent.handle(.init(.activate,id:"held-click-use"))
        XCTAssertEqual(spaces,0,"no Space from Copy / Paste on the wand");XCTAssertEqual(actions,[.copy])
        XCTAssertNil(wheel.activeControl,"selecting presses nothing");XCTAssertEqual(persistent.armedCell,cell);XCTAssertTrue(persistent.isOpen)
    }

    func testArmedMiddleHoldRoutesUpCopyDownPasteAndNeverSpace() throws {
        let clock=ManualClock(now:100)
        let target=ModePickerCoordinator(lease:WandModeLease(),hud:RecordingModeHUDPresenter(),
            scheduler:ManualTickScheduler(),log:Log(category:"test",sink:NullLogSink()))
        let wheel=WandVirtualWheel(clock:clock)
        var events:[[SyntheticKeyboardChordPoster.Event]]=[]
        var actions:[ModeUtilityAction]=[]
        var spaces=0
        let executor=ModeUtilityActionExecutor(postKeyboardChord:{events.append($0);return true},
            accessibilityTrusted:{true},inputAllowed:{true})
        target.onWheelControlChange={_,control in wheel.setActive(control)}
        target.onWheelControlRelease={_,control in
            if let release=wheel.release(control),release.control == .clipboard,!release.didObserveWheelInput {spaces+=1}
        }
        let persistent=WandPersistentController(target:target,scheduler:ManualTickScheduler(),clock:clock)
        persistent.onAdjustStep={direction in
            guard let step=wheel.step(direction),let action=step.control.topLevelSystemAction(for:step.direction) else{return false}
            actions.append(action)
            if case .success = executor.perform(action) {return true};return false
        }
        persistent.handle(.init(.open,id:"clipboard-open"))
        let cell=PhysicalCell.clipboardWheelControl
        let layout=target.wandRadialLayout
        let start=WandRadialNavigator.restingPosition(of:.switchApp,in:layout)
        let goal=WandRadialNavigator.restingPosition(of:cell,in:layout)
        persistent.handle(.init(.navigate,id:"clipboard-aim"))
        persistent.handle(.init(.motion,id:"clipboard-aim",sequence:1,x:goal.x-start.x,y:goal.y-start.y))
        persistent.handle(.init(.park,id:"clipboard-aim",sequence:2))
        persistent.handle(.init(.choose,id:"clipboard-arm"))
        XCTAssertEqual(persistent.armedCell,cell)
        XCTAssertNil(wheel.activeControl,"selected, nothing pressed")
        XCTAssertTrue(actions.isEmpty);XCTAssertEqual(spaces,0)
        // Held-only: with the HUD button up nothing listens.
        persistent.handle(.init(.hover,id:"clipboard-free"))
        persistent.handle(.init(.motion,id:"clipboard-free",sequence:1,y:-7))
        XCTAssertTrue(actions.isEmpty,"HUD button up never copies or pastes")
        persistent.handle(.init(.park,id:"clipboard-free",sequence:2))
        persistent.handle(.init(.navigate,id:"clipboard-adjust"))
        persistent.handle(.init(.motion,id:"clipboard-adjust",sequence:1,y:-7))
        XCTAssertEqual(actions,[.copy],"held up means Copy")
        persistent.handle(.init(.motion,id:"clipboard-adjust",sequence:2,y:0))
        XCTAssertEqual(actions,[.copy,.paste],"held down immediately reverses to Paste")
        persistent.handle(.init(.park,id:"clipboard-adjust",sequence:3))
        persistent.handle(.init(.choose,id:"clipboard-adjusted"))
        XCTAssertEqual(persistent.armedCell,cell,"release keeps it selected");XCTAssertNil(wheel.activeControl)
        // A HUD button click deselects and types no Space.
        persistent.handle(.init(.navigate,id:"clipboard-exit"))
        persistent.handle(.init(.park,id:"clipboard-exit",sequence:1))
        persistent.handle(.init(.activate,id:"clipboard-done"))
        XCTAssertEqual(actions,[.copy,.paste]);XCTAssertEqual(spaces,0)
        XCTAssertTrue(persistent.isOpen,"back to wedge selection");XCTAssertNil(wheel.activeControl)
        XCTAssertEqual(events.map{$0.filter{$0.type == .keyDown}.map(\.keyCode)},[[8],[9]])
        for chord in events {
            XCTAssertEqual(chord.count,4)
            XCTAssertEqual(chord.first?.flags,.maskCommand)
            XCTAssertEqual(chord.last?.flags,[])
        }
    }
    /// Ethan separated Space from the wand's Copy / Paste (2026-10-29): a
    /// click selects the card (dots) and presses nothing, never a Space release.
    func testClipboardTapEntersDottedModeWithoutSpace() {
        let clock=ManualClock(now:100)
        let target=ModePickerCoordinator(lease:WandModeLease(),hud:RecordingModeHUDPresenter(),
            scheduler:ManualTickScheduler(),log:Log(category:"test",sink:NullLogSink()))
        let wheel=WandVirtualWheel(clock:clock)
        var spaces=0
        target.onWheelControlChange={_,control in wheel.setActive(control)}
        target.onWheelControlRelease={_,control in
            if let release=wheel.release(control),release.control == .clipboard,!release.didObserveWheelInput {spaces+=1}
        }
        let persistent=WandPersistentController(target:target,scheduler:ManualTickScheduler(),clock:clock)
        persistent.handle(.init(.open,id:"space-open"))
        let layout=target.wandRadialLayout
        let start=WandRadialNavigator.restingPosition(of:.switchApp,in:layout)
        let goal=WandRadialNavigator.restingPosition(of:.clipboardWheelControl,in:layout)
        persistent.handle(.init(.navigate,id:"space-aim"))
        persistent.handle(.init(.motion,id:"space-aim",sequence:1,x:goal.x-start.x,y:goal.y-start.y))
        persistent.handle(.init(.park,id:"space-aim",sequence:2))
        persistent.handle(.init(.activate,id:"space-tap"))
        persistent.handle(.init(.activate,id:"space-tap"))
        XCTAssertEqual(spaces,0)
        XCTAssertNil(wheel.activeControl,"selecting presses nothing")
        XCTAssertEqual(persistent.armedCell,.clipboardWheelControl)
        XCTAssertTrue(persistent.isOpen)
    }

    /// The wand's own Space card sits in the outer layer beyond Enter (Ethan,
    /// 2026-10-30) and types one Space through the wand home route.
    func testOuterSpaceCardTypesOneSpace() {
        let clock=ManualClock(now:100)
        let target=ModePickerCoordinator(lease:WandModeLease(),hud:RecordingModeHUDPresenter(),
            scheduler:ManualTickScheduler(),log:Log(category:"test",sink:NullLogSink()))
        var home:[PhysicalCell]=[]
        target.onWandHomeInput={cell in home.append(cell);return true}
        let persistent=WandPersistentController(target:target,scheduler:ManualTickScheduler(),clock:clock)
        persistent.handle(.init(.open,id:"outer-open"))
        let layout=target.wandRadialLayout
        XCTAssertEqual(layout.outer.first { $0.cell == .wandSpace }?.parent,PhysicalCell(rawValue:7)!)
        let goal=WandRadialNavigator.restingPosition(of:.wandSpace,in:layout)
        persistent.handle(.init(.navigate,id:"outer-aim"))
        var sequence=0
        for step in 1...10 {
            sequence=step
            persistent.handle(.init(.motion,id:"outer-aim",sequence:step,x:goal.x*Double(step)/10,y:goal.y*Double(step)/10))
        }
        XCTAssertEqual(persistent.focusedCell,.wandSpace)
        persistent.handle(.init(.park,id:"outer-aim",sequence:sequence+1))
        persistent.handle(.init(.choose,id:"outer-use"))
        XCTAssertEqual(home,[.wandSpace])
        XCTAssertTrue(persistent.isOpen,"an ordinary action keeps the HUD open for another click")
    }

}
