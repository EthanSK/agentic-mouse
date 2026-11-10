import XCTest
@testable import ScimitarKit

/// Ethan's hierarchy: Utility Select all → Backspace → Copy.
/// HUD navigation should need less rotation without changing value controls.
final class WandUtilityOuterAndSensitivityTests: XCTestCase {
    private func coordinator(open: [Int] = []) -> ModePickerCoordinator {
        let hud = RecordingModeHUDPresenter()
        let coordinator = ModePickerCoordinator(lease: WandModeLease(), hud: hud, scheduler: ManualTickScheduler(),
                                                log: Log(category: "test", sink: NullLogSink()))
        coordinator.resolveFrontmostApp = { FrontmostAppModeContext(target: .chrome, displayName: "Chrome", bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier) }
        coordinator.enterWandHome(source: .wand, pointerFocus: ModeHUDPointerFocus(cell: .switchApp))
        for raw in open {
            let cell = PhysicalCell(rawValue: raw)!
            coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .press))
            coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .release))
        }
        return coordinator
    }

    // MARK: Utility outer layers beyond the existing Select all

    func testSelectAllCarriesBackspaceThenCopyOnUtilityOnly() {
        let utility = coordinator(open: [12]).wandRadialLayout
        XCTAssertEqual(utility.ring, WandRingOrder.utility, "every inner ring position is preserved")
        let backspace = utility.outer.first { $0.cell == .wandBackspace }
        let copy = utility.outer.first { $0.cell == .wandCopy }
        XCTAssertEqual(backspace?.parent, .wandSelectAll)
        XCTAssertEqual(backspace?.layer, 1)
        XCTAssertEqual(copy?.parent, .wandSelectAll)
        XCTAssertEqual(copy?.layer, 2)
        XCTAssertEqual(utility.outer.count, 2)
        let home = coordinator().wandRadialLayout
        XCTAssertFalse(home.contains(.wandBackspace) || home.contains(.wandCopy))
        XCTAssertTrue(home.contains(.wandSpace) && home.contains(.wandUndo) && home.contains(.wandZoom))
        let keys = coordinator(open: [9]).wandRadialLayout
        XCTAssertTrue(keys.outer.isEmpty)
        XCTAssertEqual(keys.ring, WandRingOrder.keys)
        XCTAssertTrue(keys.contains(KeysModeAction.pressBackspace.cell), "the existing Keys Backspace remains")
        for source in MouseSource.allCases where source != .wand {
            XCTAssertFalse(ModePickerCoordinator.keysLegend(for: source).contains { $0.cell.isWandOnlySlot })
            XCTAssertFalse(ModePickerCoordinator.modesLegend(for: source).contains { $0.cell.isWandOnlySlot })
        }
        XCTAssertEqual(ModePickerCoordinator.modesLegend(for: .wand).first { $0.cell == .wandBackspace }?.actionTitle, "⌫ Backspace")
        XCTAssertEqual(ModePickerCoordinator.modesLegend(for: .wand).first { $0.cell == .wandCopy }?.actionTitle, "Copy")
    }

    func testUtilityOuterCardsRunOnceAndStayOnUtilityAndRejectOtherPages() {
        let utility = coordinator(open: [12])
        var actions: [PhysicalCell] = []
        utility.onWandHomeInput = { actions.append($0); return true }
        for cell in [PhysicalCell.wandBackspace, .wandCopy] {
            utility.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .press))
            utility.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .release))
        }
        XCTAssertEqual(actions, [.wandBackspace, .wandCopy])
        XCTAssertTrue(utility.isActive)
        XCTAssertEqual(utility.page, .modes)
        XCTAssertFalse(utility.isWandHome)
        XCTAssertNil(utility.wandAdjustableControl(for: .wandCopy))
        let keys = coordinator(open: [9])
        keys.onWandHomeInput = { actions.append($0); return true }
        keys.handle(.init(action: .select, source: .wand, physicalCell: .wandCopy, phase: .release))
        XCTAssertEqual(actions.count, 2, "an outer card absent from this page cannot act")
    }

    func testTheNavigatorReachesBackspaceThenCopyFromSelectAll() {
        let layout = coordinator(open: [12]).wandRadialLayout
        let tuning = WandRadialTuning()
        var navigator = WandRadialNavigator(layout: layout, start: .wandSelectAll)!
        let theta = layout.angle(at: layout.ringIndex(of: .wandSelectAll)!)
        func push(_ degrees: Double) { navigator.apply(deltaX: sin(theta) * degrees, deltaY: -cos(theta) * degrees) }
        push(tuning.outerReachDegrees - tuning.restingDegrees + 0.5)
        XCTAssertEqual(navigator.focusedCell, .wandBackspace)
        push(tuning.thirdReachDegrees - tuning.outerReachDegrees)
        XCTAssertEqual(navigator.focusedCell, .wandCopy)
        push(-(tuning.thirdMaximumDegrees - tuning.thirdReturnDegrees) - 0.5)
        XCTAssertEqual(navigator.focusedCell, .wandBackspace)
        push(-(tuning.thirdReturnDegrees - tuning.outerReturnDegrees) - 0.5)
        XCTAssertEqual(navigator.focusedCell, .wandSelectAll)
    }

    func testSpacesUsesDragDirectionButPhysicalWheelActionsStayTheSame() {
        let spaces = WheelChordControl.spaces
        XCTAssertEqual(spaces.wandAxis, .horizontal)
        XCTAssertEqual(spaces.utilityAction(for: spaces.wandDirection(positive: true)), .moveToSpaceLeft)
        XCTAssertEqual(spaces.utilityAction(for: spaces.wandDirection(positive: false)), .moveToSpaceRight)
        XCTAssertEqual(spaces.utilityAction(for: .up), .moveToSpaceRight)
        XCTAssertEqual(spaces.utilityAction(for: .down), .moveToSpaceLeft)
    }

    // MARK: Sensitivity

    func testEveryReachNeedsAboutAQuarterLessWandRotation() {
        let t = WandRadialTuning(), old = WandRadialTuning(reachDegrees: 7, centerReturnDegrees: 4, maximumDegrees: 11, restingDegrees: 9,
            outerReachDegrees: 16, outerReturnDegrees: 13, outerMaximumDegrees: 19, outerRestingDegrees: 17,
            thirdReachDegrees: 24, thirdReturnDegrees: 21, thirdMaximumDegrees: 27, thirdRestingDegrees: 25)
        for (new, before) in [(t.reachDegrees, old.reachDegrees), (t.maximumDegrees, old.maximumDegrees),
                              (t.outerReachDegrees, old.outerReachDegrees), (t.thirdReachDegrees, old.thirdReachDegrees)] {
            XCTAssertEqual(new / before, 0.75, accuracy: 0.05)
        }
        XCTAssertEqual(t.sanitized, t, "the defaults are already in range")
        XCTAssertEqual(t.angularHysteresis, old.angularHysteresis, "edge hysteresis keeps its share of a sector")
        // From the centre, the new reach chooses a card the old one did not.
        let layout = coordinator().wandRadialLayout
        let theta = layout.angle(at: 3)
        for (tuning, expected) in [(t, layout.ring[3]), (old, PhysicalCell.switchApp)] {
            var nav = WandRadialNavigator(layout: layout, start: .switchApp, tuning: tuning)!
            nav.apply(deltaX: sin(theta) * 6, deltaY: -cos(theta) * 6)
            XCTAssertEqual(nav.focusedCell, expected)
        }
    }

    func testAReversalAtTheEdgeActsAtOnceWithoutWindUp() {
        let layout = coordinator().wandRadialLayout
        let t = WandRadialTuning()
        let theta = layout.angle(at: layout.ringIndex(of: .keysModeEntry)!)
        var nav = WandRadialNavigator(layout: layout, start: .switchApp)!
        // A long sweep far beyond every band saturates instead of winding up...
        nav.apply(deltaX: sin(theta) * 90, deltaY: -cos(theta) * 90)
        XCTAssertEqual(nav.focusedCell, .wandUndo)
        let reach = (nav.positionX * nav.positionX + nav.positionY * nav.positionY).squareRoot()
        XCTAssertEqual(reach, t.outerMaximumDegrees, accuracy: 1e-9)
        // ...so coming back acts after only the band's own travel.
        nav.apply(deltaX: -sin(theta) * (t.outerMaximumDegrees - t.outerReturnDegrees + 0.1),
                  deltaY: cos(theta) * (t.outerMaximumDegrees - t.outerReturnDegrees + 0.1))
        XCTAssertEqual(nav.focusedCell, .keysModeEntry)
        nav.apply(deltaX: -sin(theta) * (t.outerReturnDegrees - t.centerReturnDegrees + 0.2),
                  deltaY: cos(theta) * (t.outerReturnDegrees - t.centerReturnDegrees + 0.2))
        XCTAssertEqual(nav.focusedCell, .switchApp)
    }

    /// A quarter turn of the ring takes less sideways rotation than before.
    func testGoingAroundTheRingTakesLessTravel() {
        let layout = coordinator().wandRadialLayout
        func stepsToSwitch(_ tuning: WandRadialTuning) -> Int {
            let start = layout.ring[0]
            var nav = WandRadialNavigator(layout: layout, start: start, tuning: tuning)!
            for step in 1...400 {
                let theta = WandRadialLayout.angle(x: nav.positionX, y: nav.positionY)
                nav.apply(deltaX: cos(theta) * 0.1, deltaY: sin(theta) * 0.1) // clockwise, tangential
                if nav.focusedCell != start { return step }
            }
            return .max
        }
        let old = WandRadialTuning(reachDegrees: 7, centerReturnDegrees: 4, maximumDegrees: 11, restingDegrees: 9,
            outerReachDegrees: 16, outerReturnDegrees: 13, outerMaximumDegrees: 19, outerRestingDegrees: 17,
            thirdReachDegrees: 24, thirdReturnDegrees: 21, thirdMaximumDegrees: 27, thirdRestingDegrees: 25)
        XCTAssertLessThan(Double(stepsToSwitch(WandRadialTuning())), Double(stepsToSwitch(old)) * 0.85)
    }
}
