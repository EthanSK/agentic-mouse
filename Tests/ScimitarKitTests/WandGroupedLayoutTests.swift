import XCTest
@testable import ScimitarKit

/// Ethan's 2026-10-30 wand wheel: grouped cards, Space beyond Enter, Zoom a
/// third reach beyond Utility, wand arrows on each control's own axis, and
/// wand-only wording where the mice's chord cue does not apply.
final class WandGroupedLayoutTests: XCTestCase {
    private func coordinator(_ frontmost: AppSpecificTarget?, open: [Int] = []) -> ModePickerCoordinator {
        let hud = RecordingModeHUDPresenter()
        let coordinator = ModePickerCoordinator(lease: WandModeLease(), hud: hud, scheduler: ManualTickScheduler(),
                                                log: Log(category: "test", sink: NullLogSink()))
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(target: frontmost, displayName: frontmost?.displayName ?? "Finder",
                                    bundleIdentifier: frontmost?.bundleIdentifier)
        }
        coordinator.enterWandHome(source: .wand, pointerFocus: ModeHUDPointerFocus(cell: .switchApp))
        for raw in open {
            let cell = PhysicalCell(rawValue: raw)!
            coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .press))
            coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .release))
        }
        return coordinator
    }

    private func clockwiseNeighbours(_ layout: WandRadialLayout, _ a: PhysicalCell, _ b: PhysicalCell) -> Bool {
        guard let i = layout.ringIndex(of: a), let j = layout.ringIndex(of: b) else { return false }
        return (i + 1) % layout.ring.count == j
    }

    // MARK: Home

    func testHomeGroupsModesAtTheTopAndBackBesideForward() {
        for frontmost in [AppSpecificTarget.chrome, .vsCode, .codex] {
            let layout = coordinator(frontmost).wandRadialLayout
            XCTAssertEqual(layout.ring.count, 12, "the same twelve home cards")
            XCTAssertEqual(layout.ring.last, .frontmostAppModeSelector, "the app card at 12 o'clock")
            XCTAssertTrue(clockwiseNeighbours(layout, .keysModeEntry, .frontmostAppModeSelector), "Keys beside the app card")
            XCTAssertTrue(clockwiseNeighbours(layout, .frontmostAppModeSelector, .modePickerEntry), "Utility beside it")
            XCTAssertTrue(clockwiseNeighbours(layout, .modePickerEntry, .wandPlayPause), "Play/Pause immediately right of Utility")
            let forward = PhysicalCell(rawValue: 5)!, back = PhysicalCell(rawValue: 8)!
            XCTAssertTrue(clockwiseNeighbours(layout, forward, back), "Back and Forward together, Back on the left")
            XCTAssertLessThan(sin(layout.angle(at: layout.ringIndex(of: back)!)),
                              sin(layout.angle(at: layout.ringIndex(of: forward)!)), "Back is drawn left of Forward")
        }
    }

    func testOuterCardsFollowTheirSemanticParents() {
        let layout = coordinator(.vsCode).wandRadialLayout
        let parent = { (cell: PhysicalCell) in layout.outer.first { $0.cell == cell }?.parent }
        XCTAssertEqual(parent(.wandUndo), .keysModeEntry)
        XCTAssertEqual(parent(.wandSpace), PhysicalCell(rawValue: 7)!, "Space beyond Enter, not Copy / Paste")
        XCTAssertEqual(parent(.wandCodexNewChat), .modePickerEntry)
        XCTAssertEqual(parent(.wandZoom), .modePickerEntry)
        XCTAssertEqual(layout.outer.first { $0.cell == .wandZoom }?.layer, 2, "Zoom is the third layer")
        XCTAssertEqual(parent(.wandReviewChanges), .frontmostAppModeSelector)
        XCTAssertEqual(parent(.wandReviewFiles), .frontmostAppModeSelector)
        // Zoom keeps to Utility's own sector, on its side nearer the diagonal.
        let zoom = layout.outerIndex(of: .wandZoom)!, utility = layout.ringIndex(of: .modePickerEntry)!
        let half = layout.outerHalfWidth(at: zoom)
        XCTAssertEqual(half * 2, layout.sectorWidth * WandRadialLayout.thirdLayerSpan, accuracy: 1e-12)
        XCTAssertLessThanOrEqual(abs(WandRadialLayout.angularDifference(layout.outerAngle(at: zoom), layout.angle(at: utility))) + half,
                                 layout.sectorWidth / 2 + 1e-12)
    }

    func testHomeZoomIsUtilitysOwnZoomWheel() {
        let home = coordinator(.chrome)
        XCTAssertEqual(home.wandAdjustableControl(for: .wandZoom), .zoom)
        let item = home.wandRadialLayout.contains(.wandZoom)
        XCTAssertTrue(item)
        home.handle(.init(action: .select, source: .wand, physicalCell: .wandZoom, phase: .press))
        XCTAssertEqual(home.activeWheelControl, .zoom)
        XCTAssertTrue(WheelChordControl.zoom.isActiveUtilityRoute(page: home.page, activeControl: home.activeWheelControl),
                      "the same Utility zoom route accepts its steps")
        home.handle(.init(action: .select, source: .wand, physicalCell: .wandZoom, phase: .release))
        XCTAssertNil(home.activeWheelControl)
        for source in MouseSource.allCases where source != .wand {
            XCTAssertFalse(DefaultMapLegend.snapshot(source: source).legend.contains { $0.cell == .wandZoom })
        }
    }

    // MARK: Navigation: a real third reach

    func testThirdReachChoosesZoomBeyondNewCodexChatWithHysteresis() {
        let layout = coordinator(.chrome).wandRadialLayout
        let tuning = WandRadialTuning()
        var navigator = WandRadialNavigator(layout: layout, start: .modePickerEntry)!
        let theta = layout.outerAngle(at: layout.outerIndex(of: .wandZoom)!)
        let direction = (x: sin(theta), y: -cos(theta))
        func push(_ degrees: Double) { navigator.apply(deltaX: direction.x * degrees, deltaY: direction.y * degrees) }
        push(tuning.outerReachDegrees - tuning.restingDegrees + 0.5)
        XCTAssertEqual(navigator.focusedCell, .wandCodexNewChat, "the second reach")
        push(tuning.thirdReachDegrees - tuning.outerReachDegrees - 1)
        XCTAssertEqual(navigator.focusedCell, .wandCodexNewChat, "short of the third reach")
        push(1.5)
        XCTAssertEqual(navigator.focusedCell, .wandZoom, "the third reach")
        push(20)
        XCTAssertEqual(navigator.focusedCell, .wandZoom, "saturates on Zoom")
        push(-(tuning.thirdMaximumDegrees - tuning.thirdReturnDegrees) + 0.5)
        XCTAssertEqual(navigator.focusedCell, .wandZoom, "inside its return band")
        push(-1)
        XCTAssertEqual(navigator.focusedCell, .wandCodexNewChat, "back below the third return")
        push(-(tuning.thirdReturnDegrees - tuning.outerReturnDegrees) - 0.5)
        XCTAssertEqual(navigator.focusedCell, .modePickerEntry, "back to Utility")
        XCTAssertEqual(WandRadialNavigator(layout: layout, start: .wandZoom)?.focusedCell, .wandZoom)
    }

    func testCardsWithoutAThirdLayerKeepTheirSaturation() {
        let layout = coordinator(.chrome).wandRadialLayout
        var navigator = WandRadialNavigator(layout: layout, start: .keysModeEntry)!
        let theta = layout.angle(at: layout.ringIndex(of: .keysModeEntry)!)
        navigator.apply(deltaX: sin(theta) * 40, deltaY: -cos(theta) * 40)
        XCTAssertEqual(navigator.focusedCell, .wandUndo)
        XCTAssertEqual((navigator.positionX * navigator.positionX + navigator.positionY * navigator.positionY).squareRoot(),
                       WandRadialTuning().outerMaximumDegrees, accuracy: 1e-9, "Undo's wedge stops at the second layer")
    }

    // MARK: Submenus

    func testKeysPutTheFourArrowsTogetherInReadingOrder() {
        let layout = coordinator(.chrome, open: [9]).wandRadialLayout
        let actions = layout.ring.map { KeysModeAction.action(for: $0, source: .wand) }
        let arrows: [KeysModeAction] = [.arrowLeft, .arrowUp, .arrowDown, .arrowRight]
        let start = actions.firstIndex(of: .arrowLeft)!
        for (offset, arrow) in arrows.enumerated() {
            XCTAssertEqual(actions[(start + offset) % actions.count], arrow, "← ↑ ↓ → clockwise across the top")
        }
        XCTAssertEqual(actions.last, .arrowUp, "Up at 12 o'clock")
        XCTAssertTrue(clockwiseNeighbours(layout, KeysModeAction.pressBackspace.cell, KeysModeAction.insertSpace.cell))
        // Each arrow card still sends its own key on the wand.
        for arrow in arrows { XCTAssertEqual(KeysModeAction.action(for: arrow.cell(for: .wand), source: .wand), arrow) }
    }

    func testUtilityGroupsItsSubmenusAtTheTopLikeHome() {
        let layout = coordinator(.chrome, open: [12]).wandRadialLayout
        XCTAssertEqual(layout.ring.last, .appSpecificModeSelector)
        XCTAssertTrue(clockwiseNeighbours(layout, .keysModeSelector, .appSpecificModeSelector))
        XCTAssertTrue(clockwiseNeighbours(layout, .appSpecificModeSelector, .extraUtilitiesSelector))
        XCTAssertTrue(clockwiseNeighbours(layout, .zoomWheelControl, .brightnessWheelControl), "display values together")
        XCTAssertEqual(layout.ring.count, 11, "every Utility card kept")
    }

    func testCodexKeepsModelSettingsAndChatsTogether() {
        let layout = coordinator(.codex, open: [2]).wandRadialLayout
        XCTAssertTrue(clockwiseNeighbours(layout, CodexMode.responseSpeedWheelCell, PhysicalCell(rawValue: 4)!))
        XCTAssertTrue(clockwiseNeighbours(layout, PhysicalCell(rawValue: 11)!, PhysicalCell(rawValue: 12)!), "voice pair")
        XCTAssertEqual(layout.ring.count, 10)
    }

    // MARK: Wording

    func testWandArrowsFollowEachControlsOwnAxis() {
        for control in WheelChordControl.allCases where control.supportsWandAdjustment {
            let gesture = control.hudGesture
            XCTAssertEqual(gesture.motion(on: .wand), control.wandAxis == .horizontal ? .leftRight : control.hudMotion, "\(control)")
            XCTAssertNotEqual(gesture.motion(on: .corsair), .leftRight, "\(control): the wheel never turns sideways")
        }
        let item = ModeHUDLegendItem(cell: .spacesWheelControl, gesture: WheelChordControl.spaces.hudGesture,
                                     accent: WheelChordControl.spaces.hudAccent)
        XCTAssertEqual(item.displayTitle(on: .wand), "Spaces ↔")
        XCTAssertEqual(item.displayTitle(on: .razer), "Spaces ↕")
        XCTAssertTrue(item.accessibilityDescription(on: .wand).contains("left or right"))
        let zoom = ModeHUDLegendItem(cell: .zoomWheelControl, gesture: WheelChordControl.zoom.hudGesture, accent: WheelChordControl.zoom.hudAccent)
        XCTAssertEqual(zoom.displayTitle(on: .wand), "Zoom ↕", "values stay vertical")
    }

    func testCodexPinNamesWhatTheWandDoes() {
        let legend = CodexMode.definition.legend
        let pin = legend.first { $0.cell == CodexMode.pinToggleCell }!
        XCTAssertEqual(pin.displayTitle(on: .wand), "Pin/Unpin", "no physical cell-2 chord cue on the wand")
        XCTAssertEqual(pin.displayTitle(on: .corsair), "Pin/Unpin + Hold 2", "the mice keep their chord")
        let centre = legend.first { $0.cell == CodexMode.pinModifierCell }!
        XCTAssertEqual(centre.displayTitle(on: .wand), "Exit Codex mode")
        XCTAssertEqual(centre.displayTitle(on: .razer), "Exit · Hold for Pin/Unpin")
        let vsCode = DefaultMapLegend.snapshot(source: .wand, frontmostAppContext:
            FrontmostAppModeContext(target: .vsCode, displayName: "VS Code", bundleIdentifier: AppSpecificTarget.vsCode.bundleIdentifier)).legend
        XCTAssertFalse(vsCode.contains { $0.displayTitle(on: .wand).contains("Hold stage") }, "the wand home only moves to a change")
        XCTAssertEqual(ModeHUDCopy.wandDoubleClickCloseHint, "Double click to close")
    }
}
