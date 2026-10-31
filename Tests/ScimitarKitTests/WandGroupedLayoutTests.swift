import XCTest
@testable import ScimitarKit

/// Ethan's 2026-10-30 wand wheel: grouped cards, Space beyond Enter, Zoom a
/// second layer beyond Utility, wand arrows on each control's own axis, and
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
        XCTAssertNil(parent(.wandCodexNewChat), "New Codex chat is a ring card, never also an outer card")
        XCTAssertNil(parent(.wandBrightness), "Brightness is not a home outer card")
        XCTAssertEqual(parent(.wandZoom), .modePickerEntry)
        XCTAssertEqual(layout.outer.first { $0.cell == .wandZoom }?.layer, 1, "Zoom is the second layer")
        XCTAssertEqual(parent(.wandReviewChanges), .frontmostAppModeSelector)
        XCTAssertEqual(parent(.wandReviewFiles), .frontmostAppModeSelector)
        // The second-layer Zoom uses Utility's full sector.
        let zoom = layout.outerIndex(of: .wandZoom)!, utility = layout.ringIndex(of: .modePickerEntry)!
        let half = layout.outerHalfWidth(at: zoom)
        XCTAssertEqual(half * 2, layout.sectorWidth, accuracy: 1e-12)
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

    func testHomeRemovesBrightnessButUtilityKeepsIt() {
        let home = coordinator(.chrome)
        XCTAssertFalse(home.wandRadialLayout.contains(.wandBrightness))
        let utility = coordinator(.chrome, open: [12])
        XCTAssertTrue(utility.wandRadialLayout.contains(.brightnessWheelControl))
        XCTAssertEqual(utility.wandAdjustableControl(for: .brightnessWheelControl), .brightness)
    }

    /// One outward reach from Utility now chooses Zoom; farther motion must
    /// not enter a redundant third-layer card or change the inner ring.
    func testSecondReachChoosesZoomWithHysteresis() {
        let layout = coordinator(.chrome).wandRadialLayout
        let tuning = WandRadialTuning()
        var navigator = WandRadialNavigator(layout: layout, start: .modePickerEntry)!
        let theta = layout.outerAngle(at: layout.outerIndex(of: .wandZoom)!)
        let direction = (x: sin(theta), y: -cos(theta))
        func push(_ degrees: Double) { navigator.apply(deltaX: direction.x * degrees, deltaY: direction.y * degrees) }
        push(tuning.outerReachDegrees - tuning.restingDegrees + 0.5)
        XCTAssertEqual(navigator.focusedCell, .wandZoom)
        push(20)
        XCTAssertEqual(navigator.focusedCell, .wandZoom)
        XCTAssertEqual(hypot(navigator.positionX, navigator.positionY), tuning.outerMaximumDegrees, accuracy: 1e-9)
        push(-(tuning.outerMaximumDegrees - tuning.outerReturnDegrees) + 0.5)
        XCTAssertEqual(navigator.focusedCell, .wandZoom)
        push(-1)
        XCTAssertEqual(navigator.focusedCell, .modePickerEntry)
        XCTAssertFalse(layout.outer.contains { $0.parent == .modePickerEntry && $0.layer > 1 })
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
        XCTAssertTrue(clockwiseNeighbours(layout, CodexMode.responseSpeedWheelCell, CodexMode.reasoningEffortWheelCell))
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
        XCTAssertEqual(pin.displayTitle(on: .corsair), "Pin/Unpin + Hold Corsair 2", "the mice name their actual modifier")
        let centre = legend.first { $0.cell == CodexMode.pinModifierCell }!
        XCTAssertEqual(centre.displayTitle(on: .wand), "Exit Codex mode")
        XCTAssertEqual(centre.displayTitle(on: .razer), "Exit · Hold for Pin/Unpin")
        let vsCode = DefaultMapLegend.snapshot(source: .wand, frontmostAppContext:
            FrontmostAppModeContext(target: .vsCode, displayName: "VS Code", bundleIdentifier: AppSpecificTarget.vsCode.bundleIdentifier)).legend
        XCTAssertFalse(vsCode.contains { $0.displayTitle(on: .wand).contains("Hold stage") }, "the wand home only moves to a change")
        XCTAssertEqual(ModeHUDCopy.wandDoubleClickCloseHint, "Double click to close")
    }

    // MARK: New Codex chat in Screenshot's place (Ethan, 2026-10-30)

    func testNewCodexChatTakesScreenshotsExactRingPosition() {
        for frontmost in [AppSpecificTarget.chrome, .vsCode, .codex, nil] {
            let home = coordinator(frontmost)
            let layout = home.wandRadialLayout
            XCTAssertEqual(layout.ring.count, 12, "twelve home ring cards")
            XCTAssertEqual(layout.ring, WandRingOrder.home)
            XCTAssertEqual(layout.ringIndex(of: .wandCodexNewChat), 8, "9 o'clock, where Screenshot was")
            XCTAssertFalse(layout.contains(.screenshotToggle), "no Screenshot card on the wand home")
            XCTAssertEqual(layout.cells.filter { $0 == .wandCodexNewChat }.count, 1, "one New Codex chat card")
            XCTAssertNil(home.wandAdjustableControl(for: .wandCodexNewChat), "a one-press action")
        }
        // Every other card keeps its clock position.
        let expected: [PhysicalCell: Int] = [.modePickerEntry: 0, .wandPlayPause: 1, PhysicalCell(rawValue: 6)!: 2,
            PhysicalCell(rawValue: 1)!: 3, PhysicalCell(rawValue: 5)!: 4, PhysicalCell(rawValue: 8)!: 5,
            PhysicalCell(rawValue: 7)!: 6, PhysicalCell(rawValue: 4)!: 7, .modeExit: 9, .keysModeEntry: 10,
            .frontmostAppModeSelector: 11]
        let layout = coordinator(.chrome).wandRadialLayout
        for (cell, index) in expected { XCTAssertEqual(layout.ringIndex(of: cell), index, "\(cell)") }
    }

    func testRingNewCodexChatCreatesOneChatThroughTheHomeRoute() {
        let home = coordinator(.chrome)
        var actions: [PhysicalCell] = []
        home.onWandHomeInput = { actions.append($0); return true }
        home.handle(.init(action: .select, source: .wand, physicalCell: .wandCodexNewChat, phase: .press))
        home.handle(.init(action: .select, source: .wand, physicalCell: .wandCodexNewChat, phase: .release))
        XCTAssertEqual(actions, [.wandCodexNewChat], "the existing New Codex chat action, once")
        XCTAssertTrue(home.isActive)
    }

    func testPhysicalMiceAndTheirScreenshotCardAreUnchanged() {
        for source in MouseSource.allCases where source != .wand {
            let legend = DefaultMapLegend.snapshot(source: source).legend
            XCTAssertTrue(legend.contains { $0.cell == .screenshotToggle }, "\(source) keeps Screenshot")
            XCTAssertFalse(legend.contains { $0.cell == .wandCodexNewChat })
        }
        // The wand's own screenshot is the receiver's mouse button triple-click.
        XCTAssertNotNil(try? WandScreenshotStartCommand.decode(Data(
            #"{"command":"agentic_mouse_wand_screenshot_start","version":1,"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF"}"#.utf8)))
    }
}
