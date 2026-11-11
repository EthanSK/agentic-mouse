import XCTest
@testable import ScimitarKit

final class ModePickerTests: XCTestCase {
    func testUtilityButtonsAndExtraUtilitiesWheelKeepTheirPageAndDispatchOnce() {
        for source in MouseSource.allCases {
            let clickScheduler = ManualTickScheduler()
            let coordinator = makeCoordinator(reservedHUDScheduler: clickScheduler)
            var actions: [ModeUtilityAction] = []
            coordinator.onUtilityAction = { _, action in actions.append(action); return .performed }
            coordinator.enter(source: source)
            for phase in [ModePickerCommand.Phase.press, .release] {
                coordinator.handle(.init(action: .select, source: source, physicalCell: .selectAll, phase: phase))
            }
            XCTAssertEqual(actions, [])
            clickScheduler.fire()
            XCTAssertEqual(actions, [.selectAll])
            XCTAssertNil(coordinator.activeWheelControl)
            XCTAssertEqual(coordinator.page, .modes)
            for phase in [ModePickerCommand.Phase.press, .release] {
                coordinator.handle(.init(action: .select, source: source, physicalCell: .applicationWindowsButton, phase: phase))
            }
            XCTAssertEqual(actions, [.selectAll, .showApplicationWindows])
            XCTAssertNil(coordinator.activeWheelControl)
            XCTAssertEqual(coordinator.page, .modes)
            coordinator.handle(.init(action: .select, source: source, physicalCell: .extraUtilitiesSelector, phase: .press))
            coordinator.handle(.init(action: .select, source: source, physicalCell: .extraUtilitiesTab, phase: .press))
            coordinator.handle(.init(action: .select, source: source, physicalCell: .extraUtilitiesTab, phase: .release))
            coordinator.handle(.init(action: .select, source: source, physicalCell: .applicationWindowsWheelControl, phase: .press))
            XCTAssertEqual(coordinator.activeWheelControl, .applicationWindows)
            coordinator.handle(.init(action: .select, source: source, physicalCell: .applicationWindowsWheelControl, phase: .release))
            XCTAssertNil(coordinator.activeWheelControl)
            coordinator.handle(.init(action: .select, source: source, physicalCell: .extraUtilitiesSave, phase: .press))
            coordinator.handle(.init(action: .select, source: source, physicalCell: .extraUtilitiesSave, phase: .release))
            XCTAssertEqual(actions, [.selectAll, .showApplicationWindows, .tab, .save])
            XCTAssertEqual(ModePickerCoordinator.modesLegend(for: source)[1].actionTitle, "⌘A Select all")
            XCTAssertEqual(ModePickerCoordinator.modesLegend(for: source)[4].actionTitle, "App Exposé")
            XCTAssertEqual(ModePickerCoordinator.extraUtilitiesLegend(for: source)[0].actionTitle, "App Exposé")
            XCTAssertEqual(ModePickerCoordinator.extraUtilitiesLegend(for: source)[1].actionTitle, "⇥ Tab")
            XCTAssertEqual(ModePickerCoordinator.extraUtilitiesLegend(for: source)[6].actionTitle, "Save")
            XCTAssertEqual(PhysicalCell.extraUtilitiesTab.printedSide(on: source), 2)
        }
    }

    func testSelectAllDoubleClickInsertsOneSpaceWithoutSelectingAll() {
        for source in MouseSource.allCases {
            let clock = ManualClock()
            let clickScheduler = ManualTickScheduler()
            let coordinator = makeCoordinator(
                reservedHUDScheduler: clickScheduler,
                reservedHUDClock: clock
            )
            var utilityActions: [ModeUtilityAction] = []
            var keyActions: [KeysModeAction] = []
            coordinator.onUtilityAction = { _, action in utilityActions.append(action); return .performed }
            coordinator.onKeysInput = { _, action in keyActions.append(action); return true }
            coordinator.enter(source: source)

            coordinator.handle(.init(action: .select, source: source, physicalCell: .selectAll, phase: .press))
            coordinator.handle(.init(action: .select, source: source, physicalCell: .selectAll, phase: .release))
            clock.advance(by: 0.2)
            coordinator.handle(.init(action: .select, source: source, physicalCell: .selectAll, phase: .press))
            coordinator.handle(.init(action: .select, source: source, physicalCell: .selectAll, phase: .release))
            clickScheduler.fire()

            XCTAssertEqual(utilityActions, [])
            XCTAssertEqual(keyActions, [.insertSpace])
        }
    }

    func testPendingSelectAllCancelsOnExitAndCommitsBeforeAnotherUtilityAction() {
        let clickScheduler = ManualTickScheduler()
        let coordinator = makeCoordinator(reservedHUDScheduler: clickScheduler)
        var actions: [ModeUtilityAction] = []
        coordinator.onUtilityAction = { _, action in actions.append(action); return .performed }
        coordinator.enter(source: .corsair)

        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: .selectAll, phase: .press))
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: .storedPassword, phase: .press))
        XCTAssertEqual(actions, [.selectAll, .pasteStoredPassword])

        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: .selectAll, phase: .press))
        coordinator.exit()
        clickScheduler.fire()
        XCTAssertEqual(actions, [.selectAll, .pasteStoredPassword])
    }

    func testExtraUtilitiesResizeControlsHoldReleaseAndExitOnBothMice() {
        for source in MouseSource.allCases {
            let coordinator = makeCoordinator()
            var changes: [WheelChordControl?] = []
            var releases: [WheelChordControl] = []
            coordinator.onWheelControlChange = { _, control in changes.append(control) }
            coordinator.onWheelControlRelease = { _, control in releases.append(control) }
            coordinator.enter(source: source)
            coordinator.handle(.init(action: .select, source: source, physicalCell: .extraUtilitiesSelector, phase: .press))
            for (cell, control) in [(PhysicalCell.windowWidthWheelControl, WheelChordControl.windowWidth),
                                    (.windowHeightWheelControl, .windowHeight)] {
                coordinator.handle(.init(action: .select, source: source, physicalCell: cell, phase: .press))
                XCTAssertEqual(coordinator.activeWheelControl, control)
                coordinator.handle(.init(action: .select, source: source, physicalCell: cell, phase: .release))
                XCTAssertNil(coordinator.activeWheelControl)
                XCTAssertEqual(releases.last, control)
                XCTAssertNil(changes.last!)
                XCTAssertNil(WheelChordControl.utilityControl(for: cell)?.windowResizeAxis)
                XCTAssertNil(WheelChordControl.topLevelControl(for: cell)?.windowResizeAxis)
            }
            coordinator.handle(.init(action: .select, source: source, physicalCell: .windowWidthWheelControl, phase: .press))
            coordinator.exit(reason: .userRequested)
            XCTAssertNil(changes.last!)
            XCTAssertFalse(coordinator.isActive)
        }
    }

    func testSongRadioUsesApprovedExtraUtilitiesCellAndDoesNotClaimImmediateSuccess() {
        for source in MouseSource.allCases {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            var actions: [ModeUtilityAction] = []
            coordinator.onUtilityAction = { requestedSource, action in
                XCTAssertEqual(requestedSource, source)
                actions.append(action)
                return .started(message: "Starting Spotify Song Radio…")
            }
            coordinator.enter(source: source)
            coordinator.handle(.init(action: .select, source: source, physicalCell: .extraUtilitiesSelector, phase: .press))
            XCTAssertEqual(hud.snapshots.last?.legend[2].actionTitle, "Spotify Song Radio")
            coordinator.handle(.init(action: .select, source: source, physicalCell: .spotifySongRadio, phase: .press))
            coordinator.handle(.init(action: .select, source: source, physicalCell: .spotifySongRadio, phase: .release))
            XCTAssertEqual(actions, [.spotifySongRadio])
            XCTAssertEqual(hud.feedback.last, ModeHUDFeedback(message: "Starting Spotify Song Radio…", tone: .informational))
            XCTAssertEqual(coordinator.page, .extraUtilities)
            XCTAssertTrue(coordinator.isActive)
        }
        XCTAssertEqual(PhysicalCell.spotifySongRadio.printedSide(on: .corsair), 3)
        XCTAssertEqual(PhysicalCell.spotifySongRadio.printedSide(on: .razer), 1)
        XCTAssertNil(ModeUtilityAction.directAction(for: .spotifySongRadio))
    }

    func testCellTwelveOpensAndCellTenClosesTheSharedModesLeaseFromEitherMouse() {
        let lease = RecordingModePickerLease()
        let hud = RecordingModeHUDPresenter()
        let scheduler = ManualTickScheduler()
        let coordinator = makeCoordinator(lease: lease, hud: hud, scheduler: scheduler)

        coordinator.handle(.init(action: .open, source: .corsair, physicalCell: .modePickerEntry))
        scheduler.fire()
        coordinator.handle(.init(action: .close, source: .corsair, physicalCell: .modeExit))

        XCTAssertEqual(lease.activateCount, 1)
        XCTAssertEqual(lease.renewCount, 1)
        XCTAssertEqual(lease.deactivateCount, 1)
        XCTAssertFalse(coordinator.isActive)
        XCTAssertFalse(hud.isVisible)
    }

    func testModesMenuShowsWheelUtilitiesClipboardActionsAndChildModes() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)

        coordinator.enter(source: .razer)

        XCTAssertEqual(coordinator.page, .modes)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Utility modes")
        XCTAssertEqual(ModePickerCoordinator.modesLegend.count, 12)
        XCTAssertEqual(ModePickerCoordinator.modesLegend[0].actionTitle, "Brightness")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[1].actionTitle, "⌘A Select all")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[2].actionTitle, "Spaces")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[3].actionTitle, "Mission / Desktop")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[4].actionTitle, "App Exposé")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[5].actionTitle, "Magnet")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[6].actionTitle, "PP")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[7].actionTitle, "Intelligence on demand")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[8].actionTitle, "Keys mode")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[10].actionTitle, "Zoom")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[9].actionTitle, "Exit Utility modes")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[11].actionTitle, "Extra Utilities")
        XCTAssertFalse(ModePickerCoordinator.modesLegend.contains { $0.actionTitle == "Colour Proof" })
        XCTAssertNotEqual(ModePickerCoordinator.modesLegend[0].accent, ModePickerCoordinator.modesLegend[1].accent)
        XCTAssertEqual(
            ModePickerCoordinator.modesLegend[3].accent,
            ModeHUDActionFamilyPalette.systemOverview
        )
        XCTAssertEqual(hud.snapshots.last?.source, .razer)
        XCTAssertTrue(hud.snapshots.last?.showsOnAllDisplays == true)
        XCTAssertEqual(hud.snapshots.last?.presentationStyle, .boldOpaque)
    }

    func testAcceptedWheelControlsRenderWithoutRepairMarkers() {
        let missionDesktop = ModePickerCoordinator.modesLegend[3]
        let magnet = ModePickerCoordinator.modesLegend[5]
        let intelligenceOnDemand = ModePickerCoordinator.modesLegend[7]
        let keypad = ModePickerCoordinator.keysLegend[5]

        XCTAssertEqual(missionDesktop.controlStatus, .normal)
        XCTAssertEqual(magnet.controlStatus, .normal)
        XCTAssertEqual(keypad.controlStatus, .normal)
        XCTAssertEqual(intelligenceOnDemand.controlStatus, .normal)
        XCTAssertEqual(missionDesktop.printedControlLabel(on: .corsair), "Corsair 4")
        XCTAssertEqual(missionDesktop.printedControlLabel(on: .razer), "Razer 6")
        XCTAssertEqual(magnet.printedControlLabel(on: .corsair), "Corsair 6")
        XCTAssertEqual(magnet.printedControlLabel(on: .razer), "Razer 4")
        XCTAssertEqual(keypad.printedControlLabel(on: .corsair), "Corsair 6")
        XCTAssertEqual(keypad.printedControlLabel(on: .razer), "Razer 4")
        XCTAssertEqual(intelligenceOnDemand.printedControlLabel(on: .corsair), "Corsair 8")
        XCTAssertEqual(intelligenceOnDemand.printedControlLabel(on: .razer), "Razer 8")
    }

    func testCodexAndVSCodeMarkersFollowLatestPhysicalReports() {
        let brokenCodexActions: [CodexModeAction] = []
        for action in CodexModeAction.allCases {
            let expected: ModeHUDControlStatus = brokenCodexActions.contains(action)
                ? .reportedBroken
                : .normal
            XCTAssertEqual(action.hudControlStatus, expected, "Codex action \(action)")
        }

        let closeTab = CodexMode.definition.legend.first {
            $0.cell == CodexModeAction.closeTab.cell
        }!
        XCTAssertEqual(closeTab.actionTitle, "⌘W Close tab")
        XCTAssertEqual(closeTab.controlStatus, .normal)
        XCTAssertEqual(closeTab.printedControlLabel(on: .corsair), "Corsair 8")
        XCTAssertEqual(closeTab.printedControlLabel(on: .razer), "Razer 8")

        let speed = CodexMode.definition.legend.first {
            $0.cell == CodexMode.responseSpeedWheelCell
        }!
        XCTAssertEqual(speed.controlStatus, .normal)
        XCTAssertEqual(speed.actionTitle, "Cycle speed · Speed")

        XCTAssertEqual(VSCodeModeAction.toggleTerminal.hudControlStatus, .normal)
        XCTAssertEqual(VSCodeModeAction.stageAndNext.hudControlStatus, .normal)
        XCTAssertEqual(VSCodeModeAction.interruptTerminal.hudControlStatus, .normal)

        let stageAndUndo = VSCodeMode.definition.legend.first {
            $0.cell == VSCodeModeAction.stageAndNext.cell
        }!
        XCTAssertEqual(stageAndUndo.printedControlLabel(on: .corsair), "Corsair 9")
        XCTAssertEqual(stageAndUndo.printedControlLabel(on: .razer), "Razer 7")

        let cursorHistory = VSCodeMode.definition.legend.first {
            $0.cell == VSCodeMode.cursorHistoryWheelCell
        }!
        XCTAssertEqual(cursorHistory.controlStatus, .normal)
        XCTAssertEqual(cursorHistory.printedControlLabel(on: .corsair), "Corsair 6")
        XCTAssertEqual(cursorHistory.printedControlLabel(on: .razer), "Razer 4")

        let interrupt = VSCodeMode.definition.legend.first {
            $0.cell == VSCodeModeAction.interruptTerminal.cell
        }!
        XCTAssertEqual(interrupt.printedControlLabel(on: .corsair), "Corsair 12")
        XCTAssertEqual(interrupt.printedControlLabel(on: .razer), "Razer 10")
    }

    func testSystemOverviewWheelUsesSharedCanonicalCellOnBothMice() {
        XCTAssertEqual(
            WheelChordControl.utilityControl(for: .systemOverviewWheelControl),
            .systemOverview
        )
        XCTAssertNil(ModeUtilityAction.directAction(for: PhysicalCell(rawValue: 4)!))
        XCTAssertEqual(ModeUtilityAction.directAction(for: PhysicalCell(rawValue: 5)!), .showApplicationWindows)
        XCTAssertEqual(PhysicalCell.systemOverviewWheelControl.printedSide(on: .corsair), 4)
        XCTAssertEqual(PhysicalCell.systemOverviewWheelControl.printedSide(on: .razer), 6)
    }

    func testOnlyOnePressUtilityCardsUseTheDirectActionRoute() {
        XCTAssertFalse(ModeUtilityAction.showDesktop.isDirectAction)
        XCTAssertFalse(ModeUtilityAction.missionControl.isDirectAction)
        XCTAssertTrue(ModeUtilityAction.showApplicationWindows.isDirectAction)
        XCTAssertTrue(ModeUtilityAction.organizeWindows.isDirectAction)
        XCTAssertTrue(ModeUtilityAction.tab.isDirectAction)
        XCTAssertTrue(ModeUtilityAction.quitApp.isDirectAction)
        XCTAssertTrue(ModeUtilityAction.rewindYouTubeFiveSeconds.isDirectAction)
        XCTAssertTrue(ModeUtilityAction.openIntelligenceOnDemand.isDirectAction)
        XCTAssertFalse(ModeUtilityAction.copy.isDirectAction)
        XCTAssertFalse(ModeUtilityAction.paste.isDirectAction)
        XCTAssertFalse(ModeUtilityAction.moveWindowLeftWithMagnet.isDirectAction)
        XCTAssertFalse(ModeUtilityAction.moveWindowRightWithMagnet.isDirectAction)
        XCTAssertTrue(ModeUtilityAction.pasteStoredPassword.isDirectAction)

        XCTAssertFalse(ModeUtilityAction.increaseDisplayBrightness.isDirectAction)
        XCTAssertFalse(ModeUtilityAction.decreaseDisplayBrightness.isDirectAction)
        XCTAssertFalse(ModeUtilityAction.zoomIn.isDirectAction)
        XCTAssertFalse(ModeUtilityAction.zoomOut.isDirectAction)
        XCTAssertFalse(ModeUtilityAction.moveToSpaceLeft.isDirectAction)
        XCTAssertFalse(ModeUtilityAction.moveToSpaceRight.isDirectAction)
        XCTAssertNil(ModeUtilityAction.directAction(for: .spacesWheelControl))
        XCTAssertNil(ModeUtilityAction.directAction(for: .systemOverviewWheelControl))
        XCTAssertNil(ModeUtilityAction.directAction(for: .applicationWindowsWheelControl))
        XCTAssertNil(ModeUtilityAction.directAction(for: .magnetWheelControl))
        XCTAssertEqual(
            ModeUtilityAction.directAction(for: .storedPassword),
            .pasteStoredPassword
        )
        XCTAssertEqual(
            ModeUtilityAction.directAction(for: .intelligenceOnDemand),
            .openIntelligenceOnDemand
        )
        XCTAssertNil(ModeUtilityAction.directAction(for: .youtubeBackFiveSeconds))
        XCTAssertNil(ModeUtilityAction.directAction(for: .interruptTerminal))
        XCTAssertEqual(
            ModeUtilityAction.extraUtilitiesAction(for: .extraUtilitiesTab),
            .tab
        )
        XCTAssertEqual(
            ModeUtilityAction.extraUtilitiesAction(for: .organizeWindows),
            .organizeWindows
        )
        XCTAssertEqual(
            ModeUtilityAction.extraUtilitiesAction(for: .quitApp),
            .quitApp
        )
        XCTAssertNil(ModeUtilityAction.extraUtilitiesAction(for: .modeExit))
    }

    func testUtilityWheelControlsUseOneCellForEachTwoWayFamily() {
        XCTAssertEqual(WheelChordControl.utilityControl(for: PhysicalCell(rawValue: 1)!), .brightness)
        XCTAssertNil(WheelChordControl.utilityControl(for: PhysicalCell(rawValue: 2)!))
        XCTAssertEqual(WheelChordControl.utilityControl(for: PhysicalCell(rawValue: 11)!), .zoom)
        XCTAssertEqual(WheelChordControl.utilityControl(for: PhysicalCell(rawValue: 3)!), .spaces)
        XCTAssertEqual(WheelChordControl.utilityControl(for: PhysicalCell(rawValue: 4)!), .systemOverview)
        XCTAssertEqual(
            WheelChordControl.extraUtilitiesControl(for: .applicationWindowsWheelControl),
            .applicationWindows
        )
        XCTAssertEqual(PhysicalCell.applicationWindowsWheelControl.printedSide(on: .corsair), 1)
        XCTAssertEqual(PhysicalCell.applicationWindowsWheelControl.printedSide(on: .razer), 3)
        XCTAssertEqual(WheelChordControl.utilityControl(for: PhysicalCell(rawValue: 6)!), .magnetWindow)

        XCTAssertEqual(PhysicalCell(rawValue: 1)!.printedSide(on: .razer), 3)
        XCTAssertEqual(PhysicalCell(rawValue: 2)!.printedSide(on: .razer), 2)
        XCTAssertEqual(PhysicalCell(rawValue: 3)!.printedSide(on: .razer), 1)
    }

    func testUtilityWheelControlsArmForThePhysicalHoldAndDirectActionsRunOnlyOnPress() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var actions: [(MouseSource, ModeUtilityAction)] = []
        var controls: [(MouseSource, WheelChordControl?)] = []
        coordinator.onUtilityAction = { source, action in
            actions.append((source, action))
            return .performed
        }
        coordinator.onWheelControlChange = { controls.append(($0, $1)) }

        coordinator.enter(source: .razer)
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .brightnessWheelControl, phase: .press))
        XCTAssertEqual(coordinator.activeWheelControl, .brightness)
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .brightnessWheelControl, phase: .release))
        XCTAssertNil(coordinator.activeWheelControl)
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .intelligenceOnDemand, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .intelligenceOnDemand, phase: .release))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .spacesWheelControl, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .spacesWheelControl, phase: .release))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .systemOverviewWheelControl, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .systemOverviewWheelControl, phase: .release))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .magnetWheelControl, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .magnetWheelControl, phase: .release))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .interruptTerminal, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .interruptTerminal, phase: .release))

        XCTAssertEqual(actions.map(\.0), [.razer])
        XCTAssertEqual(actions.map(\.1), [.openIntelligenceOnDemand])
        XCTAssertEqual(controls.map(\.0), Array(repeating: .razer, count: 8))
        XCTAssertEqual(
            controls.map(\.1),
            [
                .brightness, nil,
                .spaces, nil,
                .systemOverview, nil,
                .magnetWindow, nil,
            ]
        )
        XCTAssertEqual(coordinator.page, .extraUtilities)
    }

    func testUtilityZoomReleaseReturnsSubsequentWheelInputToNormalScrollingOnBothMice() {
        for source in MouseSource.allCases {
            let coordinator = makeCoordinator()
            let wheel = WheelChordStateMachine()
            coordinator.onWheelControlChange = { actualSource, control in
                wheel.setActive(control, for: actualSource)
            }
            coordinator.onWheelControlRelease = { actualSource, control in
                _ = wheel.release(control, for: actualSource)
            }
            coordinator.enter(source: source)
            func input(_ phase: ModePickerCommand.Phase, from actualSource: MouseSource? = nil) {
                coordinator.handle(.init(action: .select, source: actualSource ?? source,
                    physicalCell: .zoomWheelControl, phase: phase))
            }
            input(.press)
            XCTAssertEqual(coordinator.page, .modes)
            XCTAssertEqual(coordinator.activeWheelControl, .zoom)
            guard case .consume(let action) = wheel.route(verticalDelta: 1, isContinuous: false) else {
                return XCTFail("Held Zoom should consume the wheel")
            }
            XCTAssertEqual(action.control, .zoom)
            input(.release, from: source == .corsair ? .razer : .corsair)
            XCTAssertEqual(coordinator.activeWheelControl, .zoom)
            input(.release)
            XCTAssertNil(coordinator.activeWheelControl)
            XCTAssertEqual(coordinator.page, .modes)
            for delta: Int64 in [1, -1, 8] {
                XCTAssertEqual(wheel.route(verticalDelta: delta, isContinuous: false), .passThrough)
            }
            input(.release) // Duplicate release remains harmless.
            input(.press); input(.release)
            XCTAssertEqual(wheel.route(verticalDelta: -1, isContinuous: false), .passThrough)
        }
    }

    func testWheelControlPressUpdatesTheHUDWithoutRunningEitherDirection() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var appSynthesizedActions: [ModeUtilityAction] = []
        coordinator.onUtilityAction = { _, action in
            appSynthesizedActions.append(action)
            return .performed
        }

        coordinator.enter(source: .corsair)
        coordinator.handle(
            .init(
                action: .select,
                source: .corsair,
                physicalCell: .brightnessWheelControl,
                phase: .press
            )
        )

        XCTAssertTrue(appSynthesizedActions.isEmpty)
        XCTAssertEqual(hud.snapshots.last?.selection?.title, "Brightness")
    }

    func testUtilityPreservesASpecificFailureInsteadOfOverwritingItWithGenericCopy() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        coordinator.onUtilityAction = { _, _ in
            .failed(message: "Set the Utility password from the Agentic Mouse menu")
        }

        coordinator.enter(source: .corsair)
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .storedPassword,
            phase: .press
        ))

        XCTAssertEqual(
            hud.problems.last,
            "Set the Utility password from the Agentic Mouse menu"
        )
    }

    func testExtraUtilitiesSuppressesOnlyPendingOrganizeWindowsRequests() {
        for source in MouseSource.allCases {
            let lease = RecordingModePickerLease()
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(lease: lease, hud: hud)
            var actions: [(MouseSource, ModeUtilityAction)] = []
            coordinator.onUtilityAction = { requestedSource, action in
                actions.append((requestedSource, action))
                return .started(message: "Stay restore requested")
            }

            coordinator.enter(source: source)
            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: .extraUtilitiesSelector,
                phase: .press
            ))

            XCTAssertEqual(coordinator.page, .extraUtilities)
            XCTAssertEqual(coordinator.navigationPath, [.modes, .extraUtilities])
            XCTAssertEqual(hud.snapshots.last?.modeTitle, "Extra Utilities")
            XCTAssertEqual(hud.snapshots.last?.source, source)
            XCTAssertEqual(
                hud.snapshots.last?.legend[PhysicalCell.organizeWindows.rawValue - 1].actionTitle,
                "Organize Windows"
            )
            XCTAssertEqual(
                hud.snapshots.last?.legend[PhysicalCell.quitApp.rawValue - 1].actionTitle,
                "Quit App"
            )
            XCTAssertEqual(
                hud.snapshots.last?.legend[PhysicalCell.modeExit.rawValue - 1].actionTitle,
                "Exit Extra Utilities"
            )

            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: .organizeWindows,
                phase: .press
            ))
            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: .organizeWindows,
                phase: .release
            ))

            for _ in 0..<4 {
                coordinator.handle(.init(
                    action: .select,
                    source: source,
                    physicalCell: .organizeWindows,
                    phase: .press
                ))
            }

            XCTAssertEqual(actions.map(\.0), [source])
            XCTAssertEqual(actions.map(\.1), [.organizeWindows])
            XCTAssertEqual(hud.snapshots.last?.selection?.title, "Organize Windows")
            XCTAssertEqual(
                hud.feedback.first,
                ModeHUDFeedback(message: "Stay restore requested", tone: .informational)
            )
            XCTAssertEqual(
                hud.feedback.last,
                ModeHUDFeedback(message: "Stay restore already requested", tone: .informational)
            )

            coordinator.organizeWindowsRequestDidFinish()
            coordinator.handle(.init(
                action: .select, source: source,
                physicalCell: .organizeWindows, phase: .press
            ))
            XCTAssertEqual(actions.map(\.0), [source, source])
            XCTAssertEqual(actions.map(\.1), [.organizeWindows, .organizeWindows])
            XCTAssertEqual(
                hud.snapshots.last?.legend[PhysicalCell.organizeWindows.rawValue - 1].controlStatus,
                .normal
            )

            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: .modeExit,
                phase: .press
            ))
            XCTAssertFalse(coordinator.isActive)
            XCTAssertFalse(hud.isVisible)
            XCTAssertEqual(lease.deactivateCount, 1)
        }

        XCTAssertEqual(PhysicalCell.extraUtilitiesSelector.printedSide(on: .corsair), 12)
        XCTAssertEqual(PhysicalCell.extraUtilitiesSelector.printedSide(on: .razer), 10)
        XCTAssertEqual(PhysicalCell.modeExit.printedSide(on: .corsair), 10)
        XCTAssertEqual(PhysicalCell.modeExit.printedSide(on: .razer), 12)
        XCTAssertEqual(PhysicalCell.organizeWindows.printedSide(on: .corsair), 12)
        XCTAssertEqual(PhysicalCell.organizeWindows.printedSide(on: .razer), 10)
        XCTAssertEqual(PhysicalCell.quitApp.printedSide(on: .corsair), 9)
        XCTAssertEqual(PhysicalCell.quitApp.printedSide(on: .razer), 7)
    }

    func testExtraUtilitiesQuitAppIsOneShotPerVisitAndReportsDispatchHonestly() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var actions: [ModeUtilityAction] = []
        coordinator.onUtilityAction = { _, action in
            actions.append(action)
            return .performed
        }

        coordinator.enter(source: .corsair)
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .extraUtilitiesSelector,
            phase: .press
        ))
        for _ in 0..<2 {
            coordinator.handle(.init(
                action: .select,
                source: .corsair,
                physicalCell: .quitApp,
                phase: .press
            ))
        }

        XCTAssertEqual(actions, [.quitApp])
        XCTAssertEqual(hud.snapshots.last?.selection?.title, "Quit App")
        XCTAssertEqual(
            hud.feedback.last,
            ModeHUDFeedback(message: "Quit App already sent", tone: .informational)
        )
    }

    func testExtraUtilitiesRejectsUnexpectedNativeRouteWithoutFalseSuccessOrLatch() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var actions: [ModeUtilityAction] = []
        coordinator.onUtilityAction = { _, action in
            actions.append(action)
            return .performed
        }

        coordinator.enter(source: .corsair)
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .extraUtilitiesSelector,
            phase: .press
        ))
        coordinator.handle(.init(
            action: .selectNative,
            source: .corsair,
            physicalCell: .quitApp,
            phase: .press
        ))

        XCTAssertTrue(actions.isEmpty)
        XCTAssertTrue(hud.feedback.isEmpty)
        XCTAssertEqual(hud.problems.last, "Unexpected native route for Quit App")

        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .quitApp,
            phase: .press
        ))
        XCTAssertEqual(actions, [.quitApp], "the rejected route must not burn the latch")
    }

    func testExtraUtilitiesQuitAppOneShotResetsAfterLeavingThePage() {
        let coordinator = makeCoordinator()
        var actionCount = 0
        coordinator.onUtilityAction = { _, action in
            if action == .quitApp { actionCount += 1 }
            return .performed
        }

        for expectedCount in 1...2 {
            coordinator.enter(source: .corsair)
            coordinator.handle(.init(
                action: .select,
                source: .corsair,
                physicalCell: .extraUtilitiesSelector,
                phase: .press
            ))
            coordinator.handle(.init(
                action: .select,
                source: .corsair,
                physicalCell: .quitApp,
                phase: .press
            ))
            XCTAssertEqual(actionCount, expectedCount)
            coordinator.exit()
        }
    }

    func testPendingOrganizeWindowsRequestResetsAfterLeavingExtraUtilities() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var actionCount = 0
        coordinator.onUtilityAction = { _, action in
            if action == .organizeWindows { actionCount += 1 }
            return .started(message: "Stay restore requested")
        }

        for expectedCount in 1...2 {
            coordinator.enter(source: .corsair)
            coordinator.handle(.init(
                action: .select,
                source: .corsair,
                physicalCell: .extraUtilitiesSelector,
                phase: .press
            ))
            coordinator.handle(.init(
                action: .select,
                source: .corsair,
                physicalCell: .organizeWindows,
                phase: .press
            ))
            XCTAssertEqual(actionCount, expectedCount)
            coordinator.exit()
        }
    }

    func testFailedOrganizeWindowsRequestDoesNotBurnTheRetryLatch() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var actionCount = 0
        coordinator.onUtilityAction = { _, action in
            guard action == .organizeWindows else { return .failed(message: nil) }
            actionCount += 1
            return actionCount == 1
                ? .failed(message: "Stay shortcut could not be posted")
                : .performed
        }

        coordinator.enter(source: .corsair)
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .extraUtilitiesSelector,
            phase: .press
        ))
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .organizeWindows,
            phase: .press
        ))

        XCTAssertEqual(actionCount, 1)
        XCTAssertEqual(hud.problems.last, "Stay shortcut could not be posted")
        XCTAssertTrue(hud.feedback.isEmpty)

        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .organizeWindows,
            phase: .press
        ))
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .organizeWindows,
            phase: .press
        ))

        XCTAssertEqual(actionCount, 3)
        XCTAssertEqual(
            hud.feedback,
            [
                ModeHUDFeedback(
                    message: "Stay restore requested",
                    tone: .informational
                ),
                ModeHUDFeedback(
                    message: "Stay restore requested",
                    tone: .informational
                ),
            ]
        )
    }

    func testCompletedOrganizeWindowsFailureAllowsRetryWithoutLeavingPage() {
        for source in MouseSource.allCases {
            let coordinator = makeCoordinator()
            var attempts = 0
            coordinator.onUtilityAction = { _, action in
                guard action == .organizeWindows else { return .failed(message: nil) }
                attempts += 1
                return .started(message: "Stay restore requested")
            }
            coordinator.enter(source: source)
            coordinator.handle(.init(action: .select, source: source,
                                     physicalCell: .extraUtilitiesSelector, phase: .press))
            let press = ModePickerCommand(action: .select, source: source,
                                          physicalCell: .organizeWindows, phase: .press)
            coordinator.handle(press)
            coordinator.handle(press)
            XCTAssertEqual(attempts, 1)

            // The asynchronous controller completes even when capture, moving
            // Chrome, or dispatching the Stay shortcut fails.
            coordinator.organizeWindowsRequestDidFinish()
            coordinator.handle(press)
            XCTAssertEqual(attempts, 2)
            XCTAssertEqual(coordinator.page, .extraUtilities)
            coordinator.handle(press)
            XCTAssertEqual(attempts, 2, "A retry must acquire its own in-flight guard")
        }
    }

    func testKeysCellSixSelectsKeypadAndForwardsBothInputPhases() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var inputs: [(MouseSource, PhysicalCell, ModePickerCommand.Phase)] = []
        coordinator.onKeypadModeRequested = { $0 == .corsair }
        coordinator.onKeypadInput = { inputs.append(($0, $1, $2)) }

        coordinator.enterKeys(source: .corsair)
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: .keypadModeSelector))
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: PhysicalCell(rawValue: 2)!, phase: .press))
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: PhysicalCell(rawValue: 2)!, phase: .release))

        XCTAssertEqual(coordinator.page, .keypad)
        XCTAssertFalse(hud.isVisible, "the dedicated keypad HUD owns the presentation")
        XCTAssertEqual(inputs.map { $0.0 }, [.corsair, .corsair])
        XCTAssertEqual(inputs.map { $0.1.rawValue }, [2, 2])
        XCTAssertEqual(inputs.map { $0.2 }, [.press, .release])
    }

    func testCellTwoOpensTheSelectorThenLocksCodexAndRoutesItsActions() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var selected: [(AppSpecificTarget, PhysicalCell)] = []
        coordinator.onAppSpecificInput = { _, target, cell, _, _ in
            selected.append((target, cell))
            return true
        }

        coordinator.enterAppSelector(source: .razer)

        XCTAssertEqual(coordinator.page, .appSelector)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Choose app")

        coordinator.handle(.init(action: .select, source: .razer, physicalCell: AppSpecificTarget.codex.selectorCell!))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: CodexModeAction.newTask.cell))

        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .codex)
        XCTAssertEqual(coordinator.appSpecificDefinition, CodexMode.definition)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Codex mode")
        XCTAssertEqual(hud.snapshots.last?.accent, CodexMode.accent)
        XCTAssertEqual(selected.map(\.0), [.codex])
        XCTAssertEqual(selected.map { $0.1.rawValue }, [5])
    }

    func testTopLevelCellTwoFollowsTheFrontmostAppAndBothAppExitCellsCloseIt() {
        let lease = RecordingModePickerLease()
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(lease: lease, hud: hud)
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(
                target: .chrome,
                displayName: "Google Chrome",
                bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier
            )
        }

        coordinator.handle(
            .init(action: .openAppSpecific, source: .razer, physicalCell: .frontmostAppModeSelector)
        )

        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .chrome)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Chrome mode")
        XCTAssertEqual(hud.snapshots.last?.presentationStyle, .boldOpaque)

        coordinator.handle(.init(
            action: .select,
            source: .razer,
            physicalCell: .frontmostAppModeSelector,
            phase: .release
        ))
        XCTAssertTrue(coordinator.isActive)
        coordinator.handle(.init(
            action: .select,
            source: .razer,
            physicalCell: .frontmostAppModeSelector,
            phase: .press
        ))

        XCTAssertFalse(coordinator.isActive)

        coordinator.enterAppSpecific(source: .razer)
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .modeExit))

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(lease.activateCount, 2)
        XCTAssertEqual(lease.deactivateCount, 2)
    }

    func testManualSelectorKeepsCellTwoAsTerminalThenCellTwoExitsTheChild() {
        let coordinator = makeCoordinator()

        coordinator.enterAppSelector(source: .corsair)
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .frontmostAppModeSelector
        ))

        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .terminal)

        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .frontmostAppModeSelector
        ))

        XCTAssertFalse(coordinator.isActive)
    }

    func testChromeCellFourArmsTabsWheelOnBothAppSpecificJourneys() {
        for source in MouseSource.allCases {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            var controls: [(MouseSource, WheelChordControl?)] = []
            var onePressActions: [PhysicalCell] = []
            coordinator.onWheelControlChange = { controls.append(($0, $1)) }
            coordinator.onAppSpecificInput = { _, _, cell, _, _ in
                onePressActions.append(cell)
                return true
            }
            coordinator.resolveFrontmostApp = {
                FrontmostAppModeContext(
                    target: .chrome,
                    displayName: "Google Chrome",
                    bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier
                )
            }

            coordinator.enterAppSpecific(source: source)
            let cell = ChromeModeAction.cycleTabsWithWheel.cell
            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: cell,
                phase: .press
            ))
            XCTAssertEqual(coordinator.activeWheelControl, .chromeTabs)
            XCTAssertEqual(hud.snapshots.last?.selection?.title, "Tab History")
            XCTAssertTrue(onePressActions.isEmpty)

            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: cell,
                phase: .release
            ))
            XCTAssertNil(coordinator.activeWheelControl)
            XCTAssertEqual(controls.map(\.0), [source, source])
            XCTAssertEqual(controls.map(\.1), [.chromeTabs, nil])
        }
    }

    func testSpotifyCellSevenArmsVolumeWheelOnBothAppSpecificJourneys() {
        for source in MouseSource.allCases {
            for usesManualJourney in [false, true] {
                let hud = RecordingModeHUDPresenter()
                let coordinator = makeCoordinator(hud: hud)
                var controls: [(MouseSource, WheelChordControl?)] = []
                var onePressActions: [PhysicalCell] = []
                coordinator.onWheelControlChange = { controls.append(($0, $1)) }
                coordinator.onAppSpecificInput = { _, _, cell, _, _ in
                    onePressActions.append(cell)
                    return true
                }

                if usesManualJourney {
                    coordinator.enterAppSelector(source: source)
                    coordinator.handle(.init(
                        action: .select,
                        source: source,
                        physicalCell: AppSpecificTarget.spotify.selectorCell!
                    ))
                } else {
                    coordinator.resolveFrontmostApp = {
                        FrontmostAppModeContext(
                            target: .spotify,
                            displayName: "Spotify",
                            bundleIdentifier: AppSpecificTarget.spotify.bundleIdentifier
                        )
                    }
                    coordinator.enterAppSpecific(source: source)
                }

                let cell = StandardAppMode.spotifyVolumeWheelCell
                coordinator.handle(.init(
                    action: .select,
                    source: source,
                    physicalCell: cell,
                    phase: .press
                ))
                XCTAssertEqual(coordinator.activeWheelControl, .spotifyVolume)
                XCTAssertEqual(hud.snapshots.last?.selection?.title, "Volume")
                XCTAssertTrue(onePressActions.isEmpty)

                coordinator.handle(.init(
                    action: .select,
                    source: source,
                    physicalCell: cell,
                    phase: .release
                ))
                XCTAssertNil(coordinator.activeWheelControl)
                XCTAssertEqual(controls.map(\.0), [source, source])
                XCTAssertEqual(controls.map(\.1), [.spotifyVolume, nil])
            }
        }
    }

    func testVSCodeCellSixArmsCursorHistoryWheelOnBothAppSpecificJourneys() {
        for source in MouseSource.allCases {
            for usesManualJourney in [false, true] {
                let hud = RecordingModeHUDPresenter()
                let coordinator = makeCoordinator(hud: hud)
                var controls: [(MouseSource, WheelChordControl?)] = []
                var onePressActions: [PhysicalCell] = []
                coordinator.onWheelControlChange = { controls.append(($0, $1)) }
                coordinator.onAppSpecificInput = { _, _, cell, _, _ in
                    onePressActions.append(cell)
                    return true
                }

                if usesManualJourney {
                    coordinator.enterAppSelector(source: source)
                    coordinator.handle(.init(
                        action: .select,
                        source: source,
                        physicalCell: AppSpecificTarget.vsCode.selectorCell!
                    ))
                } else {
                    coordinator.resolveFrontmostApp = {
                        FrontmostAppModeContext(
                            target: .vsCode,
                            displayName: "Visual Studio Code",
                            bundleIdentifier: AppSpecificTarget.vsCode.bundleIdentifier
                        )
                    }
                    coordinator.enterAppSpecific(source: source)
                }

                let cell = VSCodeMode.cursorHistoryWheelCell
                coordinator.handle(.init(
                    action: .select,
                    source: source,
                    physicalCell: cell,
                    phase: .press
                ))
                XCTAssertEqual(coordinator.activeWheelControl, .vsCodeCursorHistory)
                XCTAssertEqual(hud.snapshots.last?.selection?.title, "Cursor History")
                XCTAssertTrue(onePressActions.isEmpty)

                coordinator.handle(.init(
                    action: .select,
                    source: source,
                    physicalCell: cell,
                    phase: .release
                ))
                XCTAssertNil(coordinator.activeWheelControl)
                XCTAssertEqual(controls.map(\.0), [source, source])
                XCTAssertEqual(controls.map(\.1), [.vsCodeCursorHistory, nil])
            }
        }
    }

    func testFrontmostAppRetargetDisarmsAnAppSpecificWheelChord() {
        let coordinator = makeCoordinator()
        var controls: [WheelChordControl?] = []
        coordinator.onWheelControlChange = { _, control in controls.append(control) }
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(
                target: .vsCode,
                displayName: "Visual Studio Code",
                bundleIdentifier: AppSpecificTarget.vsCode.bundleIdentifier
            )
        }

        coordinator.enterAppSpecific(source: .corsair)
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: VSCodeMode.cursorHistoryWheelCell,
            phase: .press
        ))
        coordinator.updateFrontmostApp(.init(
            target: .chrome,
            displayName: "Google Chrome",
            bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier
        ))

        XCTAssertNil(coordinator.activeWheelControl)
        XCTAssertEqual(controls, [.vsCodeCursorHistory, nil])
        XCTAssertEqual(coordinator.appSpecificTarget, .chrome)
    }

    func testVSCodePreviousPreviewPressOverridesCursorHistoryOnlyDuringStageHold() {
        let coordinator = makeCoordinator()
        var routed: [ModePickerCommand.Phase] = []
        var stageHoldActive = false
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(target: .vsCode, displayName: "Visual Studio Code",
                                    bundleIdentifier: AppSpecificTarget.vsCode.bundleIdentifier)
        }
        coordinator.onAppSpecificInput = { _, _, cell, phase, _ in
            guard cell == VSCodeMode.cursorHistoryWheelCell, stageHoldActive else { return false }
            routed.append(phase)
            return true
        }
        coordinator.shouldRouteVSCodeCursorHistoryAsButton = { _ in stageHoldActive }
        coordinator.enterAppSpecific(source: .corsair)
        let cell = VSCodeMode.cursorHistoryWheelCell
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: cell, phase: .press))
        XCTAssertEqual(coordinator.activeWheelControl, .vsCodeCursorHistory)
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: cell, phase: .release))
        stageHoldActive = true
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: cell, phase: .press))
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: cell, phase: .release))
        XCTAssertEqual(routed, [.press, .release])
        XCTAssertNil(coordinator.activeWheelControl)
    }

    func testChromeDoubleSpeedHoldForwardsPressAndReleaseWithoutStealingTheWheelCell() {
        for source in MouseSource.allCases {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            var inputs: [(MouseSource, AppSpecificTarget, PhysicalCell, ModePickerCommand.Phase)] = []
            coordinator.onAppSpecificInput = { source, target, cell, phase, _ in
                inputs.append((source, target, cell, phase))
                return true
            }
            coordinator.resolveFrontmostApp = {
                FrontmostAppModeContext(
                    target: .chrome,
                    displayName: "Google Chrome",
                    bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier
                )
            }

            coordinator.enterAppSpecific(source: source)
            let cell = ChromeModeAction.holdYouTubeDoubleSpeed.cell
            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: cell,
                phase: .press
            ))
            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: cell,
                phase: .release
            ))

            XCTAssertNil(coordinator.activeWheelControl)
            XCTAssertEqual(inputs.map(\.0), [source, source])
            XCTAssertEqual(inputs.map(\.1), [.chrome, .chrome])
            XCTAssertEqual(inputs.map(\.2), [cell, cell])
            XCTAssertEqual(inputs.map(\.3), [.press, .release])
            XCTAssertEqual(hud.snapshots.last?.selection?.title, "Hold 2× speed")
        }
    }

    func testChromeCellSixOpensDevToolsThroughBothAppSpecificJourneys() {
        XCTAssertEqual(ChromeModeAction.openDevTools.cell.rawValue, 6)
        XCTAssertEqual(ChromeModeAction.openDevTools.title, "Open DevTools")
        XCTAssertEqual(ChromeMode.definition.legend[5].actionTitle, "Open DevTools")

        for source in MouseSource.allCases {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            var inputs: [(MouseSource, AppSpecificTarget, PhysicalCell, ModePickerCommand.Phase)] = []
            coordinator.onAppSpecificInput = { source, target, cell, phase, _ in
                inputs.append((source, target, cell, phase))
                return true
            }
            coordinator.resolveFrontmostApp = {
                FrontmostAppModeContext(
                    target: .chrome,
                    displayName: "Google Chrome",
                    bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier
                )
            }

            coordinator.enterAppSpecific(source: source)
            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: .init(rawValue: 6)!,
                phase: .press
            ))

            XCTAssertEqual(inputs.map(\.0), [source])
            XCTAssertEqual(inputs.map(\.1), [.chrome])
            XCTAssertEqual(inputs.map(\.2), [.init(rawValue: 6)!])
            XCTAssertEqual(inputs.map(\.3), [.press])
            XCTAssertEqual(hud.snapshots.last?.selection?.title, "Open DevTools")
        }
    }

    func testChromeCellOneReloadsTheCurrentTabThroughBothAppSpecificJourneys() {
        XCTAssertEqual(ChromeModeAction.reloadCurrentTab.cell.rawValue, 1)
        XCTAssertEqual(ChromeModeAction.reloadCurrentTab.title, "Reload current tab")
        XCTAssertEqual(ChromeMode.definition.legend[0].actionTitle, "Reload current tab")

        for source in MouseSource.allCases {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            var inputs: [(MouseSource, AppSpecificTarget, PhysicalCell, ModePickerCommand.Phase)] = []
            coordinator.onAppSpecificInput = { source, target, cell, phase, _ in
                inputs.append((source, target, cell, phase))
                return true
            }
            coordinator.resolveFrontmostApp = {
                FrontmostAppModeContext(
                    target: .chrome,
                    displayName: "Google Chrome",
                    bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier
                )
            }

            coordinator.enterAppSpecific(source: source)
            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: ChromeModeAction.reloadCurrentTab.cell,
                phase: .press
            ))
            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: ChromeModeAction.reloadCurrentTab.cell,
                phase: .release
            ))

            XCTAssertEqual(inputs.map(\.0), [source, source])
            XCTAssertEqual(inputs.map(\.1), [.chrome, .chrome])
            XCTAssertEqual(inputs.map(\.2), [
                ChromeModeAction.reloadCurrentTab.cell,
                ChromeModeAction.reloadCurrentTab.cell,
            ])
            XCTAssertEqual(inputs.map(\.3), [.press, .release])
            XCTAssertEqual(hud.snapshots.last?.selection?.title, "Reload current tab")
        }
    }

    func testChromeCellFiveOpensANewTabThroughBothAppSpecificJourneys() {
        XCTAssertEqual(ChromeModeAction.newTab.cell.rawValue, 5)
        XCTAssertEqual(ChromeModeAction.newTab.title, "New tab")
        XCTAssertEqual(ChromeMode.definition.legend[4].actionTitle, "New tab")
        XCTAssertEqual(ChromeMode.definition.legend[4].controlStatus, .normal)

        for source in MouseSource.allCases {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            var inputs: [(MouseSource, AppSpecificTarget, PhysicalCell, ModePickerCommand.Phase)] = []
            coordinator.onAppSpecificInput = { source, target, cell, phase, _ in
                inputs.append((source, target, cell, phase))
                return true
            }
            coordinator.resolveFrontmostApp = {
                FrontmostAppModeContext(
                    target: .chrome,
                    displayName: "Google Chrome",
                    bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier
                )
            }

            coordinator.enterAppSpecific(source: source)
            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: ChromeModeAction.newTab.cell,
                phase: .press
            ))
            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: ChromeModeAction.newTab.cell,
                phase: .release
            ))

            XCTAssertEqual(inputs.map(\.0), [source, source])
            XCTAssertEqual(inputs.map(\.1), [.chrome, .chrome])
            XCTAssertEqual(inputs.map(\.2), [
                ChromeModeAction.newTab.cell,
                ChromeModeAction.newTab.cell,
            ])
            XCTAssertEqual(inputs.map(\.3), [.press, .release])
            XCTAssertEqual(hud.snapshots.last?.selection?.title, "New tab")
        }
    }

    func testChromeModeKeepsHistoryInDefaultAndUsesCellEightForWebsites() {
        XCTAssertEqual(ChromeModeAction.closeCurrentTab.cell.rawValue, 3)
        XCTAssertEqual(ChromeMode.definition.legend[2].actionTitle, "Close current tab")
        XCTAssertEqual(ChromeModeAction.action(for: PhysicalCell(rawValue: 8)!), .openWebsites)
        XCTAssertEqual(ChromeMode.definition.legend[7].actionTitle, "Open website")
        XCTAssertEqual(
            ChromeMode.definition.legend[7].destinationModeAccent,
            ChromeWebsitesMode.accent
        )
        XCTAssertEqual(ChromeModeAction.holdYouTubeDoubleSpeed.cell.rawValue, 7)
        XCTAssertEqual(ChromeMode.definition.legend[6].actionTitle, "Hold 2× speed")
        XCTAssertFalse(ChromeModeAction.allCases.contains { $0.title == "Close current window" })
        XCTAssertFalse(ChromeModeAction.allCases.contains { $0.title == "Back" })
        XCTAssertFalse(ChromeModeAction.allCases.contains { $0.title == "Forward" })
    }

    func testChromeWebsiteEntrySharesOneDefinitionAcrossAutomaticAndManualJourneys() {
        let automaticHUD = RecordingModeHUDPresenter()
        let automatic = makeCoordinator(hud: automaticHUD)
        automatic.resolveFrontmostApp = {
            FrontmostAppModeContext(
                target: .chrome,
                displayName: "Google Chrome",
                bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier
            )
        }
        automatic.enterAppSpecific(source: .corsair)

        let manualHUD = RecordingModeHUDPresenter()
        let manual = makeCoordinator(hud: manualHUD)
        manual.enterAppSelector(source: .razer)
        manual.handle(.init(
            action: .select,
            source: .razer,
            physicalCell: AppSpecificTarget.chrome.selectorCell!
        ))

        XCTAssertEqual(automatic.appSpecificDefinition, ChromeMode.definition)
        XCTAssertEqual(manual.appSpecificDefinition, ChromeMode.definition)
        XCTAssertEqual(automaticHUD.snapshots.last?.legend[2].actionTitle, "Close current tab")
        XCTAssertEqual(manualHUD.snapshots.last?.legend[2].actionTitle, "Close current tab")
        XCTAssertEqual(automaticHUD.snapshots.last?.legend[7].actionTitle, "Open website")
        XCTAssertEqual(manualHUD.snapshots.last?.legend[7].actionTitle, "Open website")
    }

    func testChromeWebsiteSubmenuRoutesEveryAllowListedWebsiteAndReturnsToChrome() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        let dynamicAccent = ScimitarKit.RGBColor(red: 58, green: 222, blue: 144)
        let dynamicChromeDefinition = ChromeMode.definition.replacingIdentityAccent(
            with: dynamicAccent
        )
        var actions: [(MouseSource, ChromeWebsiteAction)] = []
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(
                target: .chrome,
                displayName: "Google Chrome",
                bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier,
                iconAccent: dynamicAccent
            )
        }
        coordinator.onChromeWebsiteInput = { source, action in
            actions.append((source, action))
            return true
        }

        coordinator.enterAppSpecific(source: .razer)
        coordinator.handle(.init(
            action: .select,
            source: .razer,
            physicalCell: ChromeWebsitesMode.parentCell,
            phase: .press
        ))
        coordinator.handle(.init(
            action: .select,
            source: .razer,
            physicalCell: ChromeWebsitesMode.parentCell,
            phase: .release
        ))

        XCTAssertEqual(coordinator.page, .chromeWebsites)
        XCTAssertEqual(coordinator.navigationPath, [.appSpecific, .chromeWebsites])
        XCTAssertEqual(coordinator.appSpecificTarget, .chrome)
        XCTAssertTrue(coordinator.followsFrontmostApp)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Chrome websites")
        XCTAssertEqual(hud.snapshots.last?.accent, dynamicAccent)
        XCTAssertEqual(hud.snapshots.last?.legend[7].actionTitle, "Back to Chrome")

        for action in ChromeWebsiteAction.allCases {
            coordinator.handle(.init(
                action: .select,
                source: .razer,
                physicalCell: action.cell,
                phase: .press
            ))
        }

        XCTAssertEqual(actions.map(\.0), Array(repeating: .razer, count: 7))
        XCTAssertEqual(actions.map(\.1), ChromeWebsiteAction.allCases)
        XCTAssertEqual(hud.snapshots.last?.selection?.title, "Grok")

        coordinator.handle(.init(
            action: .select,
            source: .razer,
            physicalCell: ChromeWebsitesMode.parentCell,
            phase: .press
        ))

        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.navigationPath, [.appSpecific])
        XCTAssertEqual(coordinator.appSpecificDefinition, dynamicChromeDefinition)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Chrome mode")
    }

    func testChromeWebsiteSubmenuUsesSevenSitesAndBothChromeExitCells() {
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: ChromeWebsiteAction.allCases.map {
                ($0.cell.rawValue, $0.title)
            }),
            [
                1: "YouTube",
                3: "X",
                4: "Facebook",
                5: "GitHub",
                6: "LinkedIn",
                7: "Gemini",
                9: "Grok",
            ]
        )
        XCTAssertEqual(ChromeWebsitesMode.definition.legend[1].actionTitle, "Exit Chrome mode")
        XCTAssertEqual(ChromeWebsitesMode.definition.legend[9].actionTitle, "Exit Chrome mode")
        XCTAssertEqual(ChromeWebsitesMode.definition.legend[7].actionTitle, "Back to Chrome")

        for exitCell in [PhysicalCell.frontmostAppModeSelector, .modeExit] {
            let coordinator = makeCoordinator()
            coordinator.resolveFrontmostApp = {
                FrontmostAppModeContext(
                    target: .chrome,
                    displayName: "Google Chrome",
                    bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier
                )
            }
            coordinator.enterAppSpecific(source: .corsair)
            coordinator.handle(.init(
                action: .select,
                source: .corsair,
                physicalCell: ChromeWebsitesMode.parentCell,
                phase: .press
            ))
            coordinator.handle(.init(
                action: .select,
                source: .corsair,
                physicalCell: exitCell,
                phase: .press
            ))
            XCTAssertFalse(coordinator.isActive)
        }
    }

    func testTopLevelCellNineOpensKeysModeAndCellTenExits() {
        let lease = RecordingModePickerLease()
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(lease: lease, hud: hud)

        coordinator.handle(
            .init(action: .openKeys, source: .razer, physicalCell: .keysModeEntry)
        )

        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(coordinator.page, .keys)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Keys mode")
        XCTAssertEqual(hud.snapshots.last?.source, .razer)
        XCTAssertEqual(hud.snapshots.last?.presentationStyle, .boldOpaque)

        coordinator.handle(
            .init(action: .select, source: .razer, physicalCell: .modeExit)
        )

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(lease.activateCount, 1)
        XCTAssertEqual(lease.deactivateCount, 1)
    }

    func testKeysModeMapsArrowsUndoSpaceAndBackspaceOnPressOnly() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var actions: [(MouseSource, KeysModeAction)] = []
        coordinator.onKeysInput = { source, action in
            actions.append((source, action))
            return true
        }

        coordinator.enterKeys(source: .corsair)
        for action in KeysModeAction.allCases {
            coordinator.handle(
                .init(action: .select, source: .corsair, physicalCell: action.cell, phase: .press)
            )
            coordinator.handle(
                .init(action: .select, source: .corsair, physicalCell: action.cell, phase: .release)
            )
        }

        XCTAssertEqual(actions.map(\.0), Array(repeating: .corsair, count: 9))
        XCTAssertEqual(
            actions.map(\.1),
            [
                .arrowUp,
                .arrowDown,
                .arrowLeft,
                .arrowRight,
                .undo,
                .insertSpace,
                .pressBackspace,
                .save,
                .holdShift,
            ]
        )
        XCTAssertEqual(KeysModeAction.arrowUp.cell.rawValue, 5)
        XCTAssertEqual(KeysModeAction.arrowDown.cell.rawValue, 4)
        XCTAssertEqual(KeysModeAction.arrowLeft.cell.rawValue, 1)
        XCTAssertEqual(KeysModeAction.arrowRight.cell.rawValue, 7)
        XCTAssertEqual(KeysModeAction.undo.cell.rawValue, 3)
        XCTAssertEqual(KeysModeAction.undo.cell(for: .razer).printedSide(on: .razer), 1)
        XCTAssertEqual(KeysModeAction.insertSpace.cell.rawValue, 8)
        XCTAssertEqual(KeysModeAction.pressBackspace.cell.rawValue, 11)
        XCTAssertEqual(ModePickerCoordinator.keysLegend[9].actionTitle, "Exit Keys mode")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[5].actionTitle, "Keypad")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[7].actionTitle, "␣ Space")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[1].actionTitle, "⇧ Hold Shift")
        XCTAssertEqual(KeysModeAction.holdShift.cell.rawValue, 2)
        XCTAssertEqual(KeysModeAction.holdShift.cell(for: .razer).printedSide(on: .razer), 2)
        XCTAssertEqual(ModePickerCoordinator.keysLegend[2].actionTitle, "⌘Z Undo")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[8].actionTitle, "Next Track · Tracks")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[10].actionTitle, "⌫ Backspace")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[11].actionTitle, "⌘S Save")
        XCTAssertEqual(KeysModeAction.save.cell.rawValue, 12)
        XCTAssertEqual(KeysModeAction.save.cell(for: .razer).printedSide(on: .razer), 10)
        XCTAssertEqual(ModePickerCoordinator.keysLegend(for: .razer)[11].actionTitle, "⌘S Save")
        XCTAssertEqual(
            ModePickerCoordinator.keysLegend(for: .corsair)[11].printedControlLabel(on: .corsair),
            "Corsair 12"
        )
        XCTAssertEqual(
            ModePickerCoordinator.keysLegend(for: .razer)[11].printedControlLabel(on: .razer),
            "Razer 10"
        )
        let arrowAccents = [
            KeysModeAction.arrowUp,
            .arrowDown,
            .arrowLeft,
            .arrowRight,
        ].compactMap { action in
            ModePickerCoordinator.keysLegend.first { $0.cell == action.cell }?.accent
        }
        XCTAssertEqual(Set(arrowAccents).count, 1)
        XCTAssertNotEqual(KeysModeAction.insertSpace.hudAccent, KeysModeAction.pressBackspace.hudAccent)
    }

    func testKeysCellNineArmsTracksWheelUntilRelease() {
        for source in MouseSource.allCases {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            var controls: [(MouseSource, WheelChordControl?)] = []
            var releases: [(MouseSource, WheelChordControl)] = []
            var keysActions: [KeysModeAction] = []
            coordinator.onWheelControlChange = { controls.append(($0, $1)) }
            coordinator.onWheelControlRelease = { releases.append(($0, $1)) }
            coordinator.onKeysInput = { _, action in keysActions.append(action); return true }
            coordinator.enterKeys(source: source)

            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: .mediaTracksWheelControl,
                phase: .press
            ))
            XCTAssertEqual(coordinator.activeWheelControl, .mediaTracks)
            XCTAssertEqual(hud.snapshots.last?.selection?.title, "Next Track · Tracks")
            XCTAssertTrue(keysActions.isEmpty)

            coordinator.handle(.init(
                action: .select,
                source: source,
                physicalCell: .mediaTracksWheelControl,
                phase: .release
            ))
            XCTAssertNil(coordinator.activeWheelControl)
            XCTAssertEqual(controls.map(\.0), [source, source])
            XCTAssertEqual(controls.map(\.1), [.mediaTracks, nil])
            XCTAssertEqual(releases.map(\.0), [source])
            XCTAssertEqual(releases.map(\.1), [.mediaTracks])
            XCTAssertTrue(keysActions.isEmpty)
        }
    }

    func testKeysExitDisarmsTracksWheelWithoutReportingAPhysicalRelease() {
        let coordinator = makeCoordinator()
        var releases: [WheelChordControl] = []
        coordinator.onWheelControlRelease = { _, control in releases.append(control) }
        coordinator.enterKeys(source: .corsair)
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .mediaTracksWheelControl,
            phase: .press
        ))

        coordinator.exit(reason: .userRequested)

        XCTAssertTrue(releases.isEmpty)
        XCTAssertNil(coordinator.activeWheelControl)
    }

    func testTopLevelWheelChordsAreSharedWhileKeysArrowsRemainHanded() {
        XCTAssertEqual(
            DefaultMouseMapping.assignment(for: PhysicalCell(rawValue: 1)!, source: .corsair)?.action,
            "Horizontal Scroll + Wheel"
        )
        XCTAssertEqual(
            DefaultMouseMapping.assignment(for: PhysicalCell(rawValue: 4)!, source: .corsair)?.action,
            "Copy / Paste + Wheel"
        )
        XCTAssertEqual(PhysicalCell(rawValue: 1)!.printedSide(on: .razer), 3)
        XCTAssertEqual(
            DefaultMouseMapping.assignment(for: PhysicalCell(rawValue: 1)!, source: .razer)?.action,
            "Horizontal Scroll + Wheel"
        )
        XCTAssertEqual(PhysicalCell(rawValue: 4)!.printedSide(on: .razer), 6)
        XCTAssertEqual(
            DefaultMouseMapping.assignment(for: PhysicalCell(rawValue: 4)!, source: .razer)?.action,
            "Copy / Paste + Wheel"
        )

        XCTAssertEqual(KeysModeAction.action(for: PhysicalCell(rawValue: 1)!, source: .corsair), .arrowLeft)
        XCTAssertEqual(KeysModeAction.action(for: PhysicalCell(rawValue: 7)!, source: .corsair), .arrowRight)
        XCTAssertEqual(KeysModeAction.action(for: PhysicalCell(rawValue: 1)!, source: .razer), .arrowRight)
        XCTAssertEqual(KeysModeAction.action(for: PhysicalCell(rawValue: 7)!, source: .razer), .arrowLeft)
        XCTAssertEqual(ModePickerCoordinator.keysLegend(for: .razer)[0].actionTitle, "→ Right")
        XCTAssertEqual(ModePickerCoordinator.keysLegend(for: .razer)[6].actionTitle, "← Left")
        XCTAssertEqual(ModePickerCoordinator.keysLegend(for: .razer)[2].actionTitle, "⌘Z Undo")
        XCTAssertEqual(ModePickerCoordinator.keysLegend(for: .razer)[5].actionTitle, "Keypad")

        XCTAssertEqual(WheelChordControl.spaces.utilityAction(for: .up), .moveToSpaceRight)
        XCTAssertEqual(WheelChordControl.spaces.utilityAction(for: .down), .moveToSpaceLeft)
        XCTAssertEqual(
            ModePickerCoordinator.modesLegend(for: .razer)[2].actionTitle,
            "Spaces"
        )
    }

    func testModeCardsUseModeColourForBorderAndActionColourForFill() {
        let mode = ScimitarKit.RGBColor(red: 255, green: 92, blue: 0)
        let action = ScimitarKit.RGBColor(red: 82, green: 138, blue: 255)
        let colors = ModeHUDCardColors(modeAccent: mode, actionAccent: action)

        XCTAssertEqual(colors.border, mode)
        XCTAssertEqual(colors.fill, action)
        XCTAssertEqual(colors.foreground, .white)
        XCTAssertFalse(colors.usesStrongDestinationFill)
    }

    func testDefaultModeNavigationUsesFullStrengthDestinationColourAndStrongerBorder() {
        let currentMode = ScimitarKit.RGBColor(red: 255, green: 92, blue: 0)
        let destinationMode = ScimitarKit.RGBColor(red: 164, green: 48, blue: 255)
        let action = ScimitarKit.RGBColor(red: 82, green: 138, blue: 255)
        let colors = ModeHUDCardColors(
            modeAccent: currentMode,
            actionAccent: action,
            destinationModeAccent: destinationMode
        )
        let ordinary = ModeHUDCardBorderTreatment(isSelected: false, isModeNavigation: false)
        let navigation = ModeHUDCardBorderTreatment(isSelected: false, isModeNavigation: true)
        let selected = ModeHUDCardBorderTreatment(isSelected: true, isModeNavigation: true)

        XCTAssertEqual(colors.border, destinationMode)
        XCTAssertEqual(colors.fill, destinationMode)
        XCTAssertTrue(colors.usesStrongDestinationFill)
        XCTAssertGreaterThan(navigation.lineWidth, ordinary.lineWidth)
        XCTAssertGreaterThan(selected.lineWidth, navigation.lineWidth)
        XCTAssertGreaterThan(navigation.opacity, ordinary.opacity)
    }

    func testActiveModeNavigationUsesFullStrengthDestinationFillAndBorder() {
        let currentMode = ScimitarKit.RGBColor(red: 255, green: 92, blue: 0)
        let destinationMode = ScimitarKit.RGBColor(red: 164, green: 48, blue: 255)
        let action = ScimitarKit.RGBColor(red: 82, green: 138, blue: 255)
        let colors = ModeHUDCardColors(
            modeAccent: currentMode,
            actionAccent: action,
            destinationModeAccent: destinationMode,
            presentationStyle: .boldOpaque
        )

        XCTAssertEqual(colors.border, destinationMode)
        XCTAssertEqual(colors.fill, destinationMode)
        XCTAssertTrue(colors.usesStrongDestinationFill)
    }

    func testEveryCurrentModeEntryAdvertisesItsDestinationAccent() {
        XCTAssertEqual(
            ModePickerCoordinator.keysLegend[PhysicalCell.keypadModeSelector.rawValue - 1]
                .destinationModeAccent,
            ModePickerCoordinator.keypadAccent
        )
        XCTAssertEqual(
            ModePickerCoordinator.modesLegend[PhysicalCell.keysModeSelector.rawValue - 1]
                .destinationModeAccent,
            ModePickerCoordinator.keysAccent
        )
        XCTAssertEqual(
            ModePickerCoordinator.modesLegend(for: .wand)[PhysicalCell.appSpecificModeSelector.rawValue - 1]
                .destinationModeAccent,
            ModePickerCoordinator.appSpecificAccent
        )
        XCTAssertEqual(
            ModePickerCoordinator.modesLegend[PhysicalCell.extraUtilitiesSelector.rawValue - 1]
                .destinationModeAccent,
            ModePickerCoordinator.extraUtilitiesAccent
        )
        XCTAssertTrue(
            ModePickerCoordinator.modesLegend
                .filter {
                    ![
                        .keysModeSelector,
                        .appSpecificModeSelector,
                        .extraUtilitiesSelector,
                    ].contains($0.cell)
                }
                .allSatisfy { $0.destinationModeAccent == nil }
        )
        for target in AppSpecificTarget.manuallySelectableCases {
            let item = AppSpecificMode.selectorDefinition.legend.first { $0.cell == target.selectorCell }
            XCTAssertEqual(item?.destinationModeAccent, target.accent)
        }
    }

    func testBoldActionCardsUseCalmerOpaqueTintsAndKeepWhiteForeground() {
        let bright = ScimitarKit.RGBColor(red: 255, green: 220, blue: 30)
        let dark = ScimitarKit.RGBColor(red: 30, green: 55, blue: 120)

        let brightColors = ModeHUDCardColors(
            modeAccent: ModePickerCoordinator.accent,
            actionAccent: bright,
            presentationStyle: .boldOpaque
        )
        let darkColors = ModeHUDCardColors(
            modeAccent: ModePickerCoordinator.accent,
            actionAccent: dark,
            presentationStyle: .boldOpaque
        )

        XCTAssertEqual(brightColors.fill, bright.scaledBrightness(0.52))
        XCTAssertEqual(brightColors.foreground, .white)
        XCTAssertEqual(darkColors.fill, dark.scaledBrightness(0.52))
        XCTAssertEqual(darkColors.foreground, .white)
        XCTAssertTrue(ModeHUDPresentationStyle.boldOpaque.requiresOpaqueWindow)
        XCTAssertFalse(ModeHUDPresentationStyle.neutral.requiresOpaqueWindow)
    }

    func testUtilityAndKeysUseStrongDistinctIdentityColours() {
        XCTAssertEqual(
            ModePickerCoordinator.accent,
            ScimitarKit.RGBColor(red: 200, green: 0, blue: 255)
        )
        XCTAssertEqual(
            ModePickerCoordinator.keysAccent,
            ScimitarKit.RGBColor(red: 255, green: 104, blue: 0)
        )
        XCTAssertEqual(
            ModePickerCoordinator.extraUtilitiesAccent,
            ScimitarKit.RGBColor(red: 0, green: 229, blue: 168)
        )
        XCTAssertEqual(ModeHUDPresentationStyle.boldOpaque.panelAccentOpacity, 0.48)
        XCTAssertEqual(ModeHUDPresentationStyle.neutral.panelAccentOpacity, 0)
    }

    func testAppModeUsesTheSameBoldOpaqueTreatmentAsOtherModes() {
        let saturated = ChromeMode.accent
        let colors = ModeHUDCardColors(
            modeAccent: saturated,
            actionAccent: saturated,
            presentationStyle: .boldOpaque
        )

        XCTAssertEqual(colors.border, saturated)
        XCTAssertEqual(colors.fill, saturated.scaledBrightness(0.52))
        XCTAssertEqual(ChromeMode.definition.accent, saturated, "hardware identity stays saturated")
    }

    func testNativeKarabinerArrowUpdatesTheHUDWithoutSynthesizingASecondKey() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var appSynthesizedActions: [KeysModeAction] = []
        coordinator.onKeysInput = { _, action in
            appSynthesizedActions.append(action)
            return true
        }

        coordinator.enterKeys(source: .corsair)
        coordinator.handle(
            .init(
                action: .selectNative,
                source: .corsair,
                physicalCell: KeysModeAction.arrowUp.cell,
                phase: .press
            )
        )

        XCTAssertTrue(appSynthesizedActions.isEmpty)
        XCTAssertEqual(hud.snapshots.last?.selection?.title, "↑ Up")
    }

    func testNativeCodexVoiceUpdatesTheHUDWithoutCallingTheSyntheticAppRoute() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var nativeInputs: [PhysicalCell] = []
        var syntheticInputs: [PhysicalCell] = []
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(
                target: .codex,
                displayName: "Codex",
                bundleIdentifier: AppSpecificTarget.codex.bundleIdentifier
            )
        }
        coordinator.onNativeAppSpecificInput = { _, _, cell, _, _ in
            nativeInputs.append(cell)
            return true
        }
        coordinator.onAppSpecificInput = { _, _, cell, _, _ in
            syntheticInputs.append(cell)
            return true
        }

        coordinator.enterAppSpecific(source: .razer)
        coordinator.handle(.init(
            action: .selectNative,
            source: .razer,
            physicalCell: CodexModeAction.toggleVoiceMode.cell,
            phase: .press
        ))

        XCTAssertEqual(nativeInputs, [CodexModeAction.toggleVoiceMode.cell])
        XCTAssertTrue(syntheticInputs.isEmpty)
        XCTAssertEqual(hud.snapshots.last?.selection?.title, "Voice mode")
    }

    func testWandUtilityCellTwoStillOpensTheManualConfiguredAppSelector() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)

        coordinator.enter(source: .wand)
        coordinator.handle(.init(
            action: .select,
            source: .wand,
            physicalCell: .appSpecificModeSelector
        ))

        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(coordinator.page, .appSelector)
        XCTAssertEqual(
            AppSpecificTarget.manuallySelectableCases.map(\.displayName),
            [
                "Codex", "Chrome", "VS Code", "Spotify", "OBS", "Claude",
                "Notion", "Telegram", "Safari", "Terminal", "iTerm",
            ]
        )
        XCTAssertTrue(hud.problems.isEmpty)
    }

    func testFrontmostAppModeRefreshesAsTheActiveAppChanges() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(
                target: .codex,
                displayName: "Codex",
                bundleIdentifier: AppSpecificTarget.codex.bundleIdentifier
            )
        }

        coordinator.enterAppSpecific(source: .razer)
        coordinator.updateFrontmostApp(
            FrontmostAppModeContext(
                target: .chrome,
                displayName: "Google Chrome",
                bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier
            )
        )

        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .chrome)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Chrome mode")
        XCTAssertEqual(hud.snapshots.last?.accent, ChromeMode.accent)
        XCTAssertEqual(hud.snapshots.last?.presentationStyle, .boldOpaque)
    }

    func testUnknownAppIdentityColourIsStableAndBundleSpecific() {
        let first = AppSpecificMode.identityAccent(
            appName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit"
        )
        let repeated = AppSpecificMode.identityAccent(
            appName: "Different localized name",
            bundleIdentifier: "com.apple.TextEdit"
        )
        let other = AppSpecificMode.identityAccent(
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview"
        )

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, other)
        XCTAssertEqual(
            FrontmostAppModeContext(
                target: nil,
                displayName: "TextEdit",
                bundleIdentifier: "com.apple.TextEdit"
            ).definition.accent,
            first
        )
    }

    func testFrontmostContextAppliesIconAccentAcrossAppIdentityRoles() {
        let iconAccent = ScimitarKit.RGBColor(red: 238, green: 72, blue: 152)
        let definition = FrontmostAppModeContext(
            target: .chrome,
            displayName: "Google Chrome",
            bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier,
            iconAccent: iconAccent
        ).definition

        XCTAssertEqual(definition.accent, iconAccent)
        XCTAssertTrue(
            definition.legend
                .filter { $0.cell.isAppSpecificModeExit }
                .allSatisfy { $0.accent == iconAccent }
        )
        XCTAssertEqual(
            definition.legend.first { $0.cell == ChromeModeAction.cycleTabsWithWheel.cell }?.accent,
            ChromeMode.definition.legend.first {
                $0.cell == ChromeModeAction.cycleTabsWithWheel.cell
            }?.accent,
            "semantic action-family fills must not be flattened into the icon colour"
        )
    }

    func testCodexKeepsBlueOutlineAndExitArtworkInBothEntryJourneys() {
        let paleIcon = ScimitarKit.RGBColor(red: 130, green: 170, blue: 180)
        for source in [MouseSource.corsair, .razer] {
            for manual in [false, true] {
                let hud = RecordingModeHUDPresenter()
                let coordinator = makeCoordinator(hud: hud)
                coordinator.resolveFrontmostApp = {
                    FrontmostAppModeContext(
                        target: .codex, displayName: "Codex",
                        bundleIdentifier: CodexMode.bundleIdentifier, iconAccent: paleIcon
                    )
                }
                coordinator.resolveAppSpecificDefinition = { $0.definition(iconAccent: paleIcon) }
                if manual {
                    coordinator.enterAppSelector(source: source)
                    coordinator.handle(.init(action: .select, source: source,
                                             physicalCell: AppSpecificTarget.codex.selectorCell!))
                } else {
                    coordinator.enterAppSpecific(source: source)
                }
                let snapshot = hud.snapshots.last
                XCTAssertEqual(snapshot?.accent, CodexMode.accent)
                XCTAssertEqual(snapshot?.outlineWidth, 4.5)
                XCTAssertEqual(snapshot?.legend.filter { $0.appBackdrop != nil }.map(\.cell.rawValue), [2, 10])
                for item in snapshot?.legend ?? [] {
                    if item.cell.isAppSpecificModeExit {
                        XCTAssertEqual(item.appBackdrop?.bundleIdentifier, CodexMode.bundleIdentifier)
                    } else {
                        XCTAssertEqual(item, CodexMode.definition.legend.first { $0.cell == item.cell })
                    }
                }
            }
        }
        XCTAssertEqual(AppSpecificTarget.chrome.definition(iconAccent: paleIcon).accent, paleIcon)
        XCTAssertNil(AppSpecificTarget.chrome.definition(iconAccent: paleIcon).outlineWidth)
    }

    func testSelectorCanUseIconDerivedAccentWithoutChangingStaticFallback() {
        let dynamic = ScimitarKit.RGBColor(red: 248, green: 88, blue: 34)
        let selector = AppSpecificMode.selectorDefinition { target in
            target == .chrome ? dynamic : target.accent
        }
        let chrome = selector.legend.first { $0.cell == AppSpecificTarget.chrome.selectorCell }

        XCTAssertEqual(chrome?.accent, dynamic)
        XCTAssertEqual(chrome?.destinationModeAccent, dynamic)
        XCTAssertEqual(
            AppSpecificMode.selectorDefinition.legend.first {
                $0.cell == AppSpecificTarget.chrome.selectorCell
            }?.destinationModeAccent,
            ChromeMode.accent
        )
    }

    func testManualSelectionUsesInjectedIconDerivedDefinition() {
        let dynamic = ScimitarKit.RGBColor(red: 58, green: 222, blue: 144)
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var modeLightingAccents: [ScimitarKit.RGBColor?] = []
        coordinator.onAppearanceChange = { modeAccent, _ in
            modeLightingAccents.append(modeAccent)
            return []
        }
        coordinator.resolveAppSpecificDefinition = { target in
            target.definition.replacingIdentityAccent(with: dynamic)
        }

        coordinator.enterAppSelector(source: .corsair)
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: AppSpecificTarget.chrome.selectorCell!
        ))

        XCTAssertEqual(coordinator.appSpecificDefinition?.accent, dynamic)
        XCTAssertEqual(hud.snapshots.last?.accent, dynamic)
        XCTAssertEqual(modeLightingAccents.last, dynamic)
    }

    func testManualAppSelectionDoesNotRetargetWhenTheFrontmostAppChanges() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)

        coordinator.enterAppSelector(source: .corsair)
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: AppSpecificTarget.codex.selectorCell!
        ))
        coordinator.updateFrontmostApp(
            FrontmostAppModeContext(
                target: .chrome,
                displayName: "Google Chrome",
                bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier
            )
        )

        XCTAssertEqual(coordinator.appSpecificTarget, .codex)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Codex mode")
    }

    func testAutomaticAndManualAppJourneysShareEveryConfiguredAppDefinition() {
        for target in AppSpecificTarget.manuallySelectableCases {
            let automaticHUD = RecordingModeHUDPresenter()
            let automatic = makeCoordinator(hud: automaticHUD)
            automatic.resolveFrontmostApp = {
                FrontmostAppModeContext(
                    target: target,
                    displayName: target.displayName,
                    bundleIdentifier: target.bundleIdentifier
                )
            }
            automatic.enterAppSpecific(source: .corsair)

            let manualHUD = RecordingModeHUDPresenter()
            let manual = makeCoordinator(hud: manualHUD)
            manual.enterAppSelector(source: .razer)
            manual.handle(.init(
                action: .select,
                source: .razer,
                physicalCell: target.selectorCell!
            ))

            XCTAssertEqual(automatic.appSpecificDefinition, target.definition)
            XCTAssertEqual(manual.appSpecificDefinition, target.definition)
            XCTAssertEqual(automaticHUD.snapshots.last?.modeTitle, manualHUD.snapshots.last?.modeTitle)
            XCTAssertEqual(automaticHUD.snapshots.last?.legend, manualHUD.snapshots.last?.legend)
            XCTAssertEqual(automaticHUD.snapshots.last?.accent, manualHUD.snapshots.last?.accent)
        }
    }

    func testEveryAppSpecificChildReservesBothExitsAndNamesItsPinModifier() {
        for target in AppSpecificTarget.allCases {
            let definition = target.definition
            let expectedTitle = "Exit \(target.displayName) mode"
            let exitItems = definition.legend.filter { $0.cell.isAppSpecificModeExit }

            XCTAssertEqual(exitItems.count, 2, "\(target.displayName) exit count")
            let expectedTitles: Set<String> = target == .codex || target == .claude
                ? [expectedTitle, "Exit · Hold for Pin/Unpin"] : [expectedTitle]
            XCTAssertEqual(Set(exitItems.map(\.actionTitle)), expectedTitles)
        }

        let unsupported = AppSpecificMode.unsupportedDefinition(
            appName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit"
        )
        XCTAssertEqual(
            Set(
                unsupported.legend
                    .filter { $0.cell.isAppSpecificModeExit }
                    .map(\.actionTitle)
            ),
            ["Exit TextEdit mode"]
        )

        XCTAssertNil(CodexModeAction.action(for: .frontmostAppModeSelector))
        XCTAssertNil(ChromeModeAction.action(for: .frontmostAppModeSelector))
        XCTAssertNil(VSCodeModeAction.action(for: .frontmostAppModeSelector))
        XCTAssertNil(TerminalModeAction.action(for: .frontmostAppModeSelector))
        XCTAssertNil(IPhoneMirroringModeAction.action(for: .frontmostAppModeSelector))
        for target in AppSpecificTarget.allCases {
            XCTAssertNil(StandardAppMode.action(for: target, cell: .frontmostAppModeSelector))
        }
    }

    func testEveryConfiguredAppSelectorCardCarriesItsCanonicalIconIdentity() {
        for target in AppSpecificTarget.manuallySelectableCases {
            let item = AppSpecificMode.selectorDefinition.legend.first {
                $0.cell == target.selectorCell
            }
            XCTAssertEqual(
                item?.appBackdrop,
                ModeHUDAppBackdrop(bundleIdentifier: target.bundleIdentifier)
            )
        }
        XCTAssertNil(
            AppSpecificMode.selectorDefinition.legend.first {
                AppSpecificTarget.target(for: $0.cell) == nil
            }?.appBackdrop
        )
    }

    func testTerminalAndITermPagesExposeUsefulShortcutsAndKeepInterruptOnCellTwelve() {
        XCTAssertEqual(AppSpecificTarget.terminal.bundleIdentifier, "com.apple.Terminal")
        XCTAssertEqual(AppSpecificTarget.iTerm.bundleIdentifier, "com.googlecode.iterm2")
        XCTAssertEqual(TerminalModeAction.interruptTerminal.cell, .interruptTerminal)

        for target in [AppSpecificTarget.terminal, .iTerm] {
            let definition = target.definition
            XCTAssertEqual(definition.legend[11].actionTitle, "Interrupt terminal")
            XCTAssertEqual(definition.legend[9].actionTitle, "Exit \(target.displayName) mode")
            XCTAssertEqual(definition.legend[0].actionTitle, "Previous tab")
            XCTAssertEqual(definition.legend[1].actionTitle, "Exit \(target.displayName) mode")
            XCTAssertEqual(definition.legend[2].actionTitle, "Next tab")
            XCTAssertEqual(definition.legend[5].actionTitle, "New tab")
            XCTAssertEqual(definition.legend[10].actionTitle, "Settings")
            XCTAssertFalse(
                definition.legend
                    .filter { !$0.cell.isAppSpecificModeExit }
                    .contains { $0.actionTitle == "Spare" }
            )
            XCTAssertEqual(
                AppSpecificTarget.target(forBundleIdentifier: target.bundleIdentifier),
                target
            )
        }

        XCTAssertEqual(ModePickerCoordinator.modesLegend[11].actionTitle, "Extra Utilities")
        XCTAssertNil(ModeUtilityAction.directAction(for: .interruptTerminal))
    }

    func testMeasuredHighUseAppsResolveToNamedDefinitions() {
        let expected: [(AppSpecificTarget, String)] = [
            (.spotify, "Spotify mode"),
            (.obs, "OBS mode"),
            (.claude, "Claude mode"),
            (.notion, "Notion mode"),
            (.telegram, "Telegram mode"),
            (.safari, "Safari mode"),
            (.firefox, "Firefox mode"),
            (.opera, "Opera mode"),
            (.restreamChat, "Restream Chat++ mode"),
            (.preview, "Preview mode"),
            (.mail, "Mail mode"),
            (.iCue, "iCUE mode"),
            (.karabinerSettings, "Karabiner-Elements mode"),
            (.systemSettings, "System Settings mode"),
            (.finder, "Finder mode"),
            (.karabinerEventViewer, "Karabiner-EventViewer mode"),
            (.iPhoneMirroring, "iPhone Mirroring mode"),
        ]

        for (target, title) in expected {
            XCTAssertEqual(
                AppSpecificTarget.target(forBundleIdentifier: target.bundleIdentifier),
                target
            )
            XCTAssertEqual(target.definition.title, title)
            XCTAssertEqual(target.definition.legend.count, PhysicalCell.all.count)
            XCTAssertEqual(target.definition.legend[9].actionTitle, "Exit \(target.displayName) mode")
        }
    }

    func testIPhoneMirroringIsAutomaticOnlyAndUsesNotificationsOnCellOne() {
        let target = AppSpecificTarget.iPhoneMirroring

        XCTAssertNil(target.selectorCell)
        XCTAssertFalse(AppSpecificTarget.manuallySelectableCases.contains(target))
        XCTAssertEqual(target.bundleIdentifier, "com.apple.ScreenContinuity")
        XCTAssertEqual(
            AppSpecificTarget.target(forBundleIdentifier: "com.apple.ScreenContinuity"),
            target
        )
        XCTAssertEqual(IPhoneMirroringModeAction.notifications.cell, PhysicalCell(rawValue: 1)!)
        XCTAssertEqual(target.definition.legend[0].actionTitle, "Notifications")
        XCTAssertEqual(target.definition.legend[0].cell.displayLabel(on: .corsair), "Corsair 1")
        XCTAssertEqual(target.definition.legend[0].cell.displayLabel(on: .razer), "Razer 3")
        XCTAssertEqual(target.definition.legend[1].actionTitle, "Exit iPhone Mirroring mode")
        XCTAssertEqual(target.definition.legend[9].actionTitle, "Exit iPhone Mirroring mode")
    }

    func testSpotifyCombinesVolumeOnCellSevenWhileNotionFillsEveryNonExitCell() {
        let usableCells = Set(PhysicalCell.all.filter { !$0.isAppSpecificModeExit })
        let spotify = StandardAppMode.actions(for: .spotify)
        let notion = StandardAppMode.actions(for: .notion)

        XCTAssertEqual(
            Set(spotify.map(\.cell)),
            usableCells.subtracting([
                StandardAppMode.spotifyVolumeWheelCell,
                PhysicalCell(rawValue: 8)!,
            ])
        )
        XCTAssertEqual(Set(notion.map(\.cell)), usableCells)
        XCTAssertEqual(StandardAppMode.action(for: .spotify, cell: PhysicalCell(rawValue: 4)!)?.title, "Next track")
        XCTAssertNil(StandardAppMode.action(for: .spotify, cell: StandardAppMode.spotifyVolumeWheelCell))
        XCTAssertNil(StandardAppMode.action(for: .spotify, cell: PhysicalCell(rawValue: 8)!))
        XCTAssertEqual(
            StandardAppMode.definition(for: .spotify).legend[6].actionTitle,
            "Volume"
        )
        XCTAssertEqual(StandardAppMode.definition(for: .spotify).legend[7].actionTitle, "Spare")
        XCTAssertEqual(StandardAppMode.action(for: .spotify, cell: PhysicalCell(rawValue: 12)!)?.title, "Queue")
        XCTAssertEqual(StandardAppMode.action(for: .notion, cell: PhysicalCell(rawValue: 3)!)?.title, "New tab")
        XCTAssertNil(StandardAppMode.action(for: .notion, cell: .frontmostAppModeSelector))
        XCTAssertEqual(StandardAppMode.action(for: .notion, cell: PhysicalCell(rawValue: 12)!)?.title, "Reopen tab")
    }

    func testEveryStandardAppActionUsesAUniqueNonExitCell() {
        for target in AppSpecificTarget.allCases {
            let actions = StandardAppMode.actions(for: target)
            guard !actions.isEmpty else { continue }

            XCTAssertEqual(
                Set(actions.map(\.cell)).count,
                actions.count,
                "\(target.displayName) must not assign two actions to one physical cell"
            )
            XCTAssertFalse(
                actions.contains { $0.cell.isAppSpecificModeExit },
                "\(target.displayName) must preserve physical cells 2 and 10 as app exits"
            )
            XCTAssertTrue(
                actions.allSatisfy { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            )
        }
    }

    func testSafariLayoutMatchesChromeLabelsAndDuplicatesNewTabOnCellEight() {
        let actions = StandardAppMode.actions(for: .safari)
        let expectedTitlesByCell = [
            1: "Reload current tab",
            3: "Close current tab",
            4: "Previous tab",
            5: "New tab",
            6: "Open DevTools",
            7: "Next tab",
            8: "New tab",
            9: "Forward",
            11: "Reopen tab",
            12: "Find page",
        ]

        XCTAssertEqual(
            Dictionary(
                uniqueKeysWithValues: actions.map {
                    ($0.cell.rawValue, $0.title)
                }
            ),
            expectedTitlesByCell
        )
        XCTAssertEqual(
            actions.map {
                "\($0.cell.rawValue)|\($0.title)|\($0.keyCode)|\($0.modifiers.rawValue)"
            },
            [
                "1|Reload current tab|15|1",
                "3|Close current tab|13|1",
                "4|Previous tab|48|10",
                "5|New tab|17|1",
                "6|Open DevTools|34|5",
                "7|Next tab|48|8",
                "8|New tab|17|1",
                "9|Forward|30|1",
                "11|Reopen tab|17|3",
                "12|Find page|3|1",
            ]
        )
        let sharedChromeActions: [ChromeModeAction] = [
            .reloadCurrentTab,
            .closeCurrentTab,
            .newTab,
            .openDevTools,
            .reopenClosedTab,
            .findPage,
        ]
        for chromeAction in sharedChromeActions {
            XCTAssertEqual(
                StandardAppMode.action(for: .safari, cell: chromeAction.cell)?.title,
                chromeAction.title
            )
        }
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[0].actionTitle, "Reload current tab")
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[2].actionTitle, "Close current tab")
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[4].actionTitle, "New tab")
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[5].actionTitle, "Open DevTools")
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[7].actionTitle, "New tab")
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[10].actionTitle, "Reopen tab")
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[11].actionTitle, "Find page")

        let devTools = StandardAppMode.action(
            for: .safari,
            cell: PhysicalCell(rawValue: 6)!
        )
        XCTAssertEqual(devTools?.keyCode, 34)
        XCTAssertEqual(devTools?.modifiers, [.command, .option])
        XCTAssertEqual(devTools?.cell.displayLabel(on: .corsair), "Corsair 6")
        XCTAssertEqual(devTools?.cell.displayLabel(on: .razer), "Razer 4")
        XCTAssertEqual(
            StandardAppMode.action(for: .safari, cell: PhysicalCell(rawValue: 12)!)?
                .cell.displayLabel(on: .razer),
            "Razer 10"
        )
        XCTAssertFalse(
            StandardAppMode.actions(for: .safari).contains { $0.title == "Downloads" }
        )
        XCTAssertEqual(
            StandardAppMode.action(
                for: .firefox,
                cell: PhysicalCell(rawValue: 12)!
            )?.title,
            "Downloads"
        )
    }

    func testMaintenanceAppsExposeOnlyObservedNonDestructiveShortcuts() {
        XCTAssertEqual(
            StandardAppMode.actions(for: .iCue).map(\.title),
            ["Open profile", "Preferences", "Minimise"]
        )
        XCTAssertEqual(StandardAppMode.actions(for: .karabinerSettings).count, 3)
        XCTAssertEqual(StandardAppMode.actions(for: .karabinerEventViewer).count, 3)
        XCTAssertFalse(
            StandardAppMode.actions(for: .iCue).contains {
                $0.title.localizedCaseInsensitiveContains("quit")
            }
        )
    }

    func testTerminalAndITermCellTwelveRouteThroughTheAppSpecificActionBoundary() {
        for target in [AppSpecificTarget.terminal, .iTerm] {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            var inputs: [(AppSpecificTarget, PhysicalCell, ModePickerCommand.Phase)] = []
            coordinator.onAppSpecificInput = { _, receivedTarget, cell, phase, _ in
                inputs.append((receivedTarget, cell, phase))
                return true
            }
            coordinator.resolveFrontmostApp = {
                FrontmostAppModeContext(
                    target: target,
                    displayName: target.displayName,
                    bundleIdentifier: target.bundleIdentifier
                )
            }

            coordinator.enterAppSpecific(source: .corsair)
            coordinator.handle(.init(
                action: .select,
                source: .corsair,
                physicalCell: .interruptTerminal,
                phase: .press
            ))
            coordinator.handle(.init(
                action: .select,
                source: .corsair,
                physicalCell: .interruptTerminal,
                phase: .release
            ))

            XCTAssertEqual(inputs.map(\.0), [target, target])
            XCTAssertEqual(inputs.map(\.1), [.interruptTerminal, .interruptTerminal])
            XCTAssertEqual(inputs.map(\.2), [.press, .release])
            XCTAssertEqual(hud.snapshots.last?.selection?.title, "Interrupt terminal")
        }
    }

    func testVSCodeModeUsesCloseTabCommandPaletteAndGoToDefinitionCells() {
        XCTAssertEqual(VSCodeModeAction.closeTab.cell, PhysicalCell(rawValue: 1))
        XCTAssertEqual(VSCodeModeAction.closeTab.singlePressCommand, .closeTab)
        XCTAssertNil(VSCodeModeAction.closeTab.doublePressCommand)
        XCTAssertEqual(VSCodeMode.definition.legend[0].actionTitle, "Close tab")
        XCTAssertEqual(VSCodeModeAction.commandPalette.cell, PhysicalCell(rawValue: 7))
        XCTAssertEqual(VSCodeModeAction.commandPalette.singlePressCommand, .commandPalette)
        XCTAssertNil(VSCodeModeAction.commandPalette.doublePressCommand)
        XCTAssertEqual(VSCodeMode.definition.legend[6].actionTitle, "Command Palette")
        XCTAssertEqual(
            VSCodeModeAction.action(for: PhysicalCell(rawValue: 7)!),
            .commandPalette
        )
        XCTAssertEqual(VSCodeModeAction.goToDefinition.cell, PhysicalCell(rawValue: 11))
        XCTAssertEqual(
            VSCodeModeAction.goToDefinition.singlePressCommand,
            .goToDefinition
        )
        XCTAssertNil(VSCodeModeAction.goToDefinition.doublePressCommand)
        XCTAssertEqual(VSCodeMode.definition.legend[10].actionTitle, "Go to Definition")
        XCTAssertEqual(
            VSCodeModeAction.action(for: PhysicalCell(rawValue: 11)!),
            .goToDefinition
        )

        XCTAssertEqual(VSCodeModeAction.previousChange.cell, PhysicalCell(rawValue: 5))
        XCTAssertEqual(VSCodeModeAction.nextChange.cell, PhysicalCell(rawValue: 8))
        XCTAssertEqual(VSCodeModeAction.stageAndNext.cell, PhysicalCell(rawValue: 9))
        XCTAssertEqual(VSCodeMode.cursorHistoryWheelCell, PhysicalCell(rawValue: 6))
        XCTAssertEqual(VSCodeModeAction.interruptTerminal.cell, PhysicalCell(rawValue: 12))

        XCTAssertEqual(
            VSCodeMode.definition.legend[4].actionTitle,
            VSCodeModeAction.previousChange.title
        )
        XCTAssertEqual(
            VSCodeMode.definition.legend[7].actionTitle,
            VSCodeModeAction.nextChange.title
        )
        XCTAssertEqual(
            VSCodeMode.definition.legend[8].actionTitle,
            VSCodeModeAction.stageAndNext.title
        )
        XCTAssertEqual(
            VSCodeMode.definition.legend[5].actionTitle,
            "Cursor History"
        )
        XCTAssertEqual(
            VSCodeMode.definition.legend[11].actionTitle,
            VSCodeModeAction.interruptTerminal.title
        )
    }

    func testVSCodeModeKeepsNavigationGesturesAndCombinesStageAndUndoOnCellNine() {
        XCTAssertEqual(VSCodeModeAction.previousChange.singlePressCommand, .previousChange)
        XCTAssertEqual(VSCodeModeAction.previousChange.doublePressCommand, .stageAndPrevious)
        XCTAssertEqual(VSCodeModeAction.nextChange.singlePressCommand, .nextChange)
        XCTAssertEqual(VSCodeModeAction.nextChange.doublePressCommand, .stageAndNext)
        XCTAssertEqual(VSCodeModeAction.stageAndNext.singlePressCommand, .stageAndNext)
        XCTAssertEqual(VSCodeModeAction.stageAndNext.doublePressCommand, .undoLastStageAndAdvance)
        XCTAssertEqual(VSCodeModeAction.stageAndNext.title, "Stage + Next / Undo Stage ×2")
        XCTAssertEqual(VSCodeModeAction.interruptTerminal.singlePressCommand, .interruptTerminal)
        XCTAssertNil(VSCodeModeAction.interruptTerminal.doublePressCommand)
    }

    func testVSCodeModeGestureDelaysSinglesAndClassifiesMatchingDoubles() {
        let clock = ManualClock()
        let scheduler = ManualTickScheduler()
        let classifier = VSCodeModeGestureClassifier(clock: clock, scheduler: scheduler)
        var commands: [VSCodeModeCommand] = []

        classifier.handlePress(action: .previousChange) { commands.append($0) }
        XCTAssertTrue(commands.isEmpty)
        scheduler.fire()
        XCTAssertEqual(commands, [.previousChange])

        clock.advance(by: 0.1)
        classifier.handlePress(action: .stageAndNext) { commands.append($0) }
        XCTAssertEqual(commands, [.previousChange])
        clock.advance(by: 0.1)
        classifier.handlePress(action: .stageAndNext) { commands.append($0) }
        XCTAssertEqual(commands, [.previousChange, .undoLastStageAndAdvance])

        clock.advance(by: 0.4)
        classifier.handlePress(action: .stageAndNext) { commands.append($0) }
        scheduler.fire()
        XCTAssertEqual(
            commands,
            [.previousChange, .undoLastStageAndAdvance, .stageAndNext]
        )
    }

    func testVSCodeModeGestureCommitsAWaitingActionBeforeAnotherCell() {
        let clock = ManualClock()
        let scheduler = ManualTickScheduler()
        let classifier = VSCodeModeGestureClassifier(clock: clock, scheduler: scheduler)
        var commands: [VSCodeModeCommand] = []

        classifier.handlePress(action: .previousChange) { commands.append($0) }
        classifier.handlePress(action: .nextChange) { commands.append($0) }

        XCTAssertEqual(commands, [.previousChange])
        scheduler.fire()
        XCTAssertEqual(commands, [.previousChange, .nextChange])
    }

    func testVSCodeModeGestureCancelDropsAPendingCommandFailClosed() {
        let clock = ManualClock()
        let scheduler = ManualTickScheduler()
        let classifier = VSCodeModeGestureClassifier(clock: clock, scheduler: scheduler)
        var commands: [VSCodeModeCommand] = []

        classifier.handlePress(action: .previousChange) { commands.append($0) }
        classifier.cancel()
        scheduler.fire()

        XCTAssertTrue(commands.isEmpty)
        XCTAssertFalse(scheduler.isRunning)
    }

    func testUnsupportedFrontmostAppIsNamedHonestly() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(
                target: nil,
                displayName: "TextEdit",
                bundleIdentifier: "com.apple.TextEdit"
            )
        }

        coordinator.enterAppSpecific(source: .corsair)

        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertNil(coordinator.appSpecificTarget)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "TextEdit mode")
        XCTAssertEqual(hud.snapshots.last?.footerTitle, "App-specific — TextEdit")
    }

    func testCodexChildCellSixArmsReasoningEffortWheel() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var controls: [WheelChordControl?] = []
        coordinator.onWheelControlChange = { _, control in
            controls.append(control)
        }

        coordinator.enterAppSelector(source: .corsair)
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: AppSpecificTarget.codex.selectorCell!))
        let reasoningEffortCell = CodexMode.reasoningEffortWheelCell
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: reasoningEffortCell))

        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .codex)
        XCTAssertEqual(controls, [.codexReasoningEffort])
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Codex mode")
        XCTAssertEqual(hud.snapshots.last?.selection?.title, "Reasoning Effort")

        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: reasoningEffortCell,
            phase: .release
        ))
        XCTAssertEqual(controls, [.codexReasoningEffort, nil])
    }

    func testCodexSwappedChatWheelAndMicWorkForBothMiceAndEntryJourneys() {
        for source in MouseSource.allCases {
            for manual in [false, true] {
                let hud = RecordingModeHUDPresenter()
                let coordinator = makeCoordinator(hud: hud)
                var presses: [PhysicalCell] = []
                coordinator.onAppSpecificInput = { _, _, cell, phase, _ in
                    if phase == .press { presses.append(cell) }
                    return true
                }
                if manual {
                    coordinator.enterAppSelector(source: source)
                    coordinator.handle(.init(action: .select, source: source, physicalCell: AppSpecificTarget.codex.selectorCell!))
                } else {
                    coordinator.resolveFrontmostApp = {
                        FrontmostAppModeContext(target: .codex, displayName: "Codex", bundleIdentifier: CodexMode.bundleIdentifier)
                    }
                    coordinator.enterAppSpecific(source: source)
                }

                let chatCell = CodexMode.chatHistoryWheelCell
                let micCell = PhysicalCell(rawValue: 11)!
                coordinator.handle(.init(action: .select, source: source, physicalCell: chatCell))
                XCTAssertEqual(coordinator.activeWheelControl, .codexChatHistory)
                XCTAssertEqual(hud.snapshots.last?.selection?.title, "Chats Selection")
                XCTAssertTrue(presses.isEmpty)
                coordinator.handle(.init(action: .select, source: source, physicalCell: chatCell, phase: .release))
                XCTAssertNil(coordinator.activeWheelControl)

                coordinator.handle(.init(action: .select, source: source, physicalCell: micCell))
                XCTAssertEqual(presses, [micCell])
                XCTAssertEqual(CodexModeAction.action(for: micCell), .toggleMicrophoneMute)
                XCTAssertEqual(hud.snapshots.last?.selection?.title, "Mute / unmute voice mic")
                XCTAssertNil(coordinator.activeWheelControl)
                coordinator.handle(.init(action: .select, source: source, physicalCell: micCell, phase: .release))
                XCTAssertEqual(presses, [micCell])
                XCTAssertTrue(coordinator.isActive)
                coordinator.handle(.init(action: .close, source: source, physicalCell: .modeExit))
            }
        }
    }

    func testEveryModeExitsFromUniversalCellTen() {
        for entry in [PhysicalCell.keypadModeSelector, .appSpecificModeSelector, .keysModeSelector] {
            let lease = RecordingModePickerLease()
            let coordinator = makeCoordinator(lease: lease)
            coordinator.onKeypadModeRequested = { _ in true }
            if entry == .keysModeSelector {
                coordinator.enterKeys(source: .corsair)
            } else if entry == .appSpecificModeSelector {
                coordinator.enterAppSelector(source: .corsair)
            } else {
                coordinator.enterKeys(source: .corsair)
                coordinator.handle(.init(action: .select, source: .corsair, physicalCell: entry))
            }

            coordinator.handle(.init(action: .select, source: .corsair, physicalCell: .modeExit))

            XCTAssertFalse(coordinator.isActive)
            XCTAssertEqual(lease.deactivateCount, 1)
        }
    }

    func testRepeatedOpenCommandIsIgnoredUntilUniversalExit() {
        let lease = RecordingModePickerLease()
        let coordinator = makeCoordinator(lease: lease)

        coordinator.handle(.init(action: .open, source: .corsair, physicalCell: .modePickerEntry))
        coordinator.handle(.init(action: .open, source: .corsair, physicalCell: .modePickerEntry))

        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(lease.activateCount, 1)
        XCTAssertEqual(lease.deactivateCount, 0)

        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: .modeExit))

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(lease.deactivateCount, 1)
    }

    func testEveryModeHasAVisuallyDistinctColour() {
        let accents = [
            ModePickerCoordinator.accent,
            ModePickerCoordinator.keypadAccent,
            ModePickerCoordinator.keysAccent,
            ModePickerCoordinator.extraUtilitiesAccent,
            AppSpecificMode.selectorAccent,
            CodexMode.accent,
            ChromeMode.accent,
            AppSpecificTarget.vsCode.accent,
            AppSpecificTarget.terminal.accent,
            AppSpecificTarget.iTerm.accent,
        ]
        XCTAssertEqual(Set(accents).count, accents.count)
        for accent in accents {
            let channels = [accent.red, accent.green, accent.blue]
            XCTAssertEqual(accent.alpha, 255)
            XCTAssertGreaterThanOrEqual(
                Int(channels.max()!) - Int(channels.min()!),
                180,
                "mode colours should be bold and strongly saturated"
            )
        }
        XCTAssertEqual(CodexMode.definition.accent, CodexMode.accent)
    }

    func testCodexModePinsTheRequestedActionsWithBothExitsAndNoAppChoiceCard() {
        XCTAssertEqual(CodexModeAction.newTask.cell.rawValue, 5)
        XCTAssertEqual(CodexModeAction.newTask.cell.printedSide(on: .razer), 5)
        XCTAssertEqual(CodexModeAction.newTask.cell.printedSide(on: .corsair), 5)
        XCTAssertEqual(CodexModeAction.togglePin.cell.rawValue, 1)
        XCTAssertEqual(CodexModeAction.toggleMicrophoneMute.cell.rawValue, 11)
        XCTAssertEqual(CodexModeAction.toggleMicrophoneMute.cell.printedSide(on: .corsair), 11)
        XCTAssertEqual(CodexModeAction.toggleMicrophoneMute.cell.printedSide(on: .razer), 11)
        XCTAssertEqual(CodexMode.chatHistoryWheelCell.printedSide(on: .corsair), 9)
        XCTAssertEqual(CodexMode.chatHistoryWheelCell.printedSide(on: .razer), 7)
        XCTAssertEqual(
            CodexModeAction.toggleMicrophoneMute.title,
            "Mute / unmute voice mic"
        )
        XCTAssertEqual(CodexModeAction.togglePin.cell.printedSide(on: .razer), 3)
        XCTAssertEqual(CodexModeAction.togglePin.cell.printedSide(on: .corsair), 1)
        XCTAssertEqual(CodexModeAction.toggleVoiceMode.cell.rawValue, 12)
        XCTAssertEqual(CodexModeAction.toggleVoiceMode.cell.printedSide(on: .corsair), 12)
        XCTAssertEqual(CodexModeAction.toggleVoiceMode.cell.printedSide(on: .razer), 10)
        XCTAssertEqual(CodexModeAction.newTask.title, "New chat")
        XCTAssertEqual(CodexModeAction.toggleVoiceMode.title, "Voice mode")
        XCTAssertEqual(CodexModeAction.openSideChat.cell.rawValue, 4)
        XCTAssertEqual(CodexModeAction.openSideChat.cell.printedSide(on: .corsair), 4)
        XCTAssertEqual(CodexModeAction.openSideChat.cell.printedSide(on: .razer), 6)
        XCTAssertEqual(CodexModeAction.openSideChat.title, "Open side chat")
        XCTAssertNil(CodexModeAction.action(for: PhysicalCell(rawValue: 3)!))
        XCTAssertEqual(CodexMode.responseSpeedWheelCell.printedSide(on: .corsair), 3)
        XCTAssertEqual(CodexMode.responseSpeedWheelCell.printedSide(on: .razer), 1)
        XCTAssertEqual(CodexModeAction.closeTab.cell.rawValue, 8)
        XCTAssertEqual(CodexModeAction.closeTab.title, "⌘W Close tab")
        XCTAssertEqual(CodexModeAction.pressEnter.cell.rawValue, 7)
        XCTAssertEqual(CodexModeAction.pressEnter.cell.printedSide(on: .razer), 9)
        XCTAssertEqual(CodexModeAction.pressEnter.cell.printedSide(on: .corsair), 7)
        XCTAssertEqual(CodexModeAction.action(for: .modePickerEntry), .toggleVoiceMode)
        XCTAssertEqual(CodexModeAction.action(for: PhysicalCell(rawValue: 4)!), .openSideChat)
        XCTAssertNil(CodexModeAction.action(for: PhysicalCell(rawValue: 6)!))
        XCTAssertEqual(CodexModeAction.action(for: PhysicalCell(rawValue: 11)!), .toggleMicrophoneMute)
        XCTAssertNil(WheelChordControl.appSpecificControl(for: .codex, cell: PhysicalCell(rawValue: 11)!))
        XCTAssertEqual(
            WheelChordControl.appSpecificControl(
                for: .codex,
                cell: PhysicalCell(rawValue: 6)!
            ),
            .codexReasoningEffort
        )
        XCTAssertEqual(
            WheelChordControl.appSpecificControl(
                for: .codex,
                cell: PhysicalCell(rawValue: 9)!
            ),
            .codexChatHistory
        )
        XCTAssertEqual(CodexMode.definition.legend[1].actionTitle, "Exit · Hold for Pin/Unpin")
        XCTAssertEqual(CodexMode.definition.legend[4].actionTitle, "New chat")
        XCTAssertEqual(CodexMode.definition.legend[0].actionTitle, "Pin/Unpin")
        XCTAssertEqual(CodexMode.definition.legend[2].actionTitle, "Cycle speed · Speed")
        XCTAssertEqual(CodexMode.definition.legend[10].actionTitle, "Mute / unmute voice mic")
        XCTAssertEqual(CodexMode.definition.legend[3].actionTitle, "Open side chat")
        XCTAssertEqual(CodexMode.definition.legend[9].actionTitle, "Exit Codex mode")
        XCTAssertEqual(CodexMode.definition.legend[5].actionTitle, "Reasoning Effort")
        XCTAssertEqual(CodexMode.definition.legend[11].actionTitle, "Voice mode")
        XCTAssertEqual(CodexMode.definition.legend[8].actionTitle, "Chats Selection")
        XCTAssertEqual(
            CodexMode.definition.legend[5].accent,
            ModeHUDActionFamilyPalette.reasoningEffort
        )
        XCTAssertEqual(
            CodexMode.definition.legend[8].accent,
            ModeHUDActionFamilyPalette.historyNavigation
        )
        XCTAssertNotEqual(CodexMode.definition.legend[11].actionTitle, "Choose another app")
    }

    func testCellThreeNeverHidesAnActiveModeLegend() {
        for page in [ModePickerPage.appSelector, .appSpecific, .keys, .extraUtilities] {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            switch page {
            case .modes: XCTFail("Utility cell 3 owns Spaces + Wheel")
            case .appSelector: coordinator.enterAppSelector(source: .razer)
            case .appSpecific:
                coordinator.resolveFrontmostApp = {
                    FrontmostAppModeContext(
                        target: .codex,
                        displayName: "Codex",
                        bundleIdentifier: AppSpecificTarget.codex.bundleIdentifier
                    )
                }
                coordinator.enterAppSpecific(source: .razer)
            case .keys: coordinator.enterKeys(source: .razer)
            case .keypad: XCTFail("keypad is covered separately")
            case .extraUtilities:
                coordinator.enter(source: .razer)
                coordinator.handle(.init(
                    action: .select,
                    source: .razer,
                    physicalCell: .extraUtilitiesSelector
                ))
            case .chromeWebsites: XCTFail("Chrome websites is covered separately")
            }

            let expectedCellThreeTitle: String
            switch page {
            case .appSpecific: expectedCellThreeTitle = "Cycle speed · Speed"
            case .appSelector: expectedCellThreeTitle = "Claude"
            case .keys: expectedCellThreeTitle = "⌘Z Undo"
            case .chromeWebsites: expectedCellThreeTitle = "X"
            case .extraUtilities: expectedCellThreeTitle = "Spotify Song Radio"
            default: expectedCellThreeTitle = "Spare"
            }
            XCTAssertEqual(hud.snapshots.last?.legend[2].actionTitle, expectedCellThreeTitle)

            coordinator.handle(.init(action: .select, source: .razer, physicalCell: .modeHUDToggle))
            XCTAssertTrue(coordinator.isActive)
            XCTAssertTrue(coordinator.isLegendVisible)
            XCTAssertTrue(hud.isVisible)

            coordinator.handle(.init(action: .select, source: .corsair, physicalCell: .modeHUDToggle))
            XCTAssertTrue(coordinator.isLegendVisible)
            XCTAssertTrue(hud.isVisible)
        }
    }

    func testKeysCellTwelveSavesWithoutLeavingKeysMode() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)

        coordinator.enter(source: .corsair)
        var keysActions: [KeysModeAction] = []
        coordinator.onKeysInput = { _, action in keysActions.append(action); return true }
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .keysModeSelector
        ))

        XCTAssertEqual(coordinator.page, .keys)
        XCTAssertEqual(coordinator.navigationPath, [.modes, .keys])
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Keys mode")

        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .modePickerEntry
        ))

        XCTAssertEqual(coordinator.page, .keys)
        XCTAssertEqual(coordinator.navigationPath, [.modes, .keys])
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Keys mode")
        XCTAssertEqual(hud.snapshots.last?.legend[11].actionTitle, "⌘S Save")
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: .modePickerEntry, phase: .release))
        XCTAssertEqual(keysActions, [.save])

        for source in MouseSource.allCases {
            coordinator.exit(reason: .userRequested)
            coordinator.enterKeys(source: source)
            keysActions.removeAll()
            coordinator.handle(.init(action: .selectNative, source: source, physicalCell: .modePickerEntry, phase: .press))
            coordinator.handle(.init(action: .selectNative, source: source, physicalCell: .modePickerEntry, phase: .release))
            coordinator.handle(.init(action: .selectNative, source: source, physicalCell: PhysicalCell(rawValue: 2)!, phase: .press))
            coordinator.handle(.init(action: .selectNative, source: source, physicalCell: PhysicalCell(rawValue: 2)!, phase: .release))
            XCTAssertEqual(hud.snapshots.last?.legend[1].actionTitle, "⇧ Hold Shift")
            XCTAssertTrue(keysActions.isEmpty, "Native editing actions must not emit a second app-owned shortcut")
            XCTAssertEqual(coordinator.page, .keys)
            XCTAssertEqual(hud.snapshots.last?.legend[11].actionTitle, "⌘S Save")
        }
    }

    func testKeypadFailureExitsInsteadOfLeavingTheKarabinerPageDesynchronized() {
        let lease = RecordingModePickerLease()
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(lease: lease, hud: hud)
        coordinator.onKeypadModeRequested = { _ in false }

        coordinator.enterKeys(source: .corsair)
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: .keypadModeSelector
        ))

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(coordinator.navigationPath, [])
        XCTAssertEqual(lease.deactivateCount, 1)
        XCTAssertTrue(hud.problems.contains("Keypad mode could not start"))
    }

    func testCellThreeReachesTheDedicatedKeypadAsDEF() {
        let coordinator = makeCoordinator()
        var keypadInputs: [(PhysicalCell, ModePickerCommand.Phase)] = []
        coordinator.onKeypadModeRequested = { _ in true }
        coordinator.onKeypadInput = { _, cell, phase in keypadInputs.append((cell, phase)) }

        coordinator.enterKeys(source: .corsair)
        coordinator.handle(
            .init(action: .select, source: .corsair, physicalCell: .keypadModeSelector)
        )
        coordinator.handle(
            .init(action: .select, source: .corsair, physicalCell: .modeHUDToggle, phase: .press)
        )
        coordinator.handle(
            .init(action: .select, source: .corsair, physicalCell: .modeHUDToggle, phase: .release)
        )

        XCTAssertEqual(coordinator.page, .keypad)
        XCTAssertTrue(coordinator.isLegendVisible)
        XCTAssertEqual(keypadInputs.map { $0.0.rawValue }, [3, 3])
        XCTAssertEqual(keypadInputs.map(\.1), [.press, .release])
    }

    func testCodexInitialEntryHoldCanPinImmediatelyOnBothMice() {
        for source in MouseSource.allCases {
            for modifierReleasedFirst in [false, true] {
                let coordinator = makeCoordinator()
                coordinator.resolveFrontmostApp = {
                    .init(target: .codex, displayName: "Codex", bundleIdentifier: CodexMode.bundleIdentifier)
                }
                var count = 0
                coordinator.onAppSpecificInput = { actualSource, target, cell, phase, _ in
                    XCTAssertEqual(actualSource, source)
                    XCTAssertEqual(target, .codex)
                    XCTAssertEqual(cell, CodexMode.pinToggleCell)
                    XCTAssertEqual(phase, .press)
                    count += 1
                    return true
                }
                let opener = ModePickerCommand(action: .openAppSpecific, source: source,
                    physicalCell: CodexMode.pinModifierCell, phase: .press)
                let entryRelease = ModePickerCommand(action: .openAppSpecific, source: source,
                    physicalCell: CodexMode.pinModifierCell, phase: .release)
                func pin(_ phase: ModePickerCommand.Phase) {
                    coordinator.handle(.init(action: .select, source: source,
                        physicalCell: CodexMode.pinToggleCell, phase: phase), inputTime: 1.001)
                }
                coordinator.handle(opener, inputTime: 1)
                let other: MouseSource = source == .corsair ? .razer : .corsair
                coordinator.handle(.init(action: .openAppSpecific, source: other,
                    physicalCell: CodexMode.pinModifierCell, phase: .release))
                coordinator.handle(.init(action: .select, source: other,
                    physicalCell: CodexMode.pinToggleCell, phase: .press))
                XCTAssertEqual(count, 0)
                pin(.press); pin(.press)
                XCTAssertEqual(count, 1) // No timer or second modifier press is needed.
                coordinator.handle(opener) // Duplicate opener must not erase the used hold.
                if modifierReleasedFirst { coordinator.handle(entryRelease); pin(.release) }
                else { pin(.release); coordinator.handle(entryRelease) }
                XCTAssertTrue(coordinator.isActive)
                pin(.press); pin(.release)
                XCTAssertEqual(count, 1) // Entry release disarmed the modifier.
                coordinator.handle(.init(action: .select, source: source,
                    physicalCell: CodexMode.pinModifierCell, phase: .press))
                coordinator.handle(entryRelease) // A stale opener release cannot end a later hold.
                XCTAssertTrue(coordinator.isActive)
                coordinator.handle(.init(action: .select, source: source,
                    physicalCell: CodexMode.pinModifierCell, phase: .release))
                XCTAssertFalse(coordinator.isActive) // A subsequent solo click still exits.
            }
        }
    }

    func testUnusedEntryReleaseKeepsAppModeOpenAndDoesNotBorrowPinAcrossFocusChanges() {
        for source in MouseSource.allCases {
            let coordinator = makeCoordinator()
            coordinator.resolveFrontmostApp = {
                .init(target: .codex, displayName: "Codex", bundleIdentifier: CodexMode.bundleIdentifier)
            }
            var count = 0
            coordinator.onAppSpecificInput = { _, _, _, _, _ in count += 1; return true }
            let opener = ModePickerCommand(action: .openAppSpecific, source: source,
                physicalCell: CodexMode.pinModifierCell, phase: .press)
            let release = ModePickerCommand(action: .openAppSpecific, source: source,
                physicalCell: CodexMode.pinModifierCell, phase: .release)
            coordinator.handle(opener); coordinator.handle(release)
            XCTAssertTrue(coordinator.isActive)
            coordinator.handle(.init(action: .select, source: source,
                physicalCell: CodexMode.pinToggleCell, phase: .press))
            XCTAssertEqual(count, 0)
            coordinator.exit()
            coordinator.handle(opener)
            coordinator.updateFrontmostApp(.init(target: .chrome, displayName: "Chrome", bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier))
            coordinator.updateFrontmostApp(.init(target: .codex, displayName: "Codex", bundleIdentifier: CodexMode.bundleIdentifier))
            coordinator.handle(.init(action: .select, source: source,
                physicalCell: CodexMode.pinToggleCell, phase: .press))
            coordinator.handle(release)
            XCTAssertEqual(count, 0)
            XCTAssertTrue(coordinator.isActive)
            coordinator.exit()
            coordinator.handle(opener)
            coordinator.handleSystemSleep()
            coordinator.enterAppSpecific(source: source)
            coordinator.handle(.init(action: .select, source: source,
                physicalCell: CodexMode.pinToggleCell, phase: .press))
            coordinator.handle(release)
            XCTAssertEqual(count, 0)
            XCTAssertTrue(coordinator.isActive)
        }
    }

    func testCodexPinRequiresSameMouseModifierAndFreshClicksInBothJourneys() {
        for source in MouseSource.allCases {
            for manual in [false, true] {
                let coordinator = makeCoordinator()
                coordinator.resolveFrontmostApp = {
                    FrontmostAppModeContext(target: .codex, displayName: "Codex", bundleIdentifier: CodexMode.bundleIdentifier)
                }
                var pinCount = 0
                coordinator.onAppSpecificInput = { actualSource, target, cell, phase, _ in
                    XCTAssertEqual(actualSource, source)
                    if target == .codex, cell == CodexMode.pinToggleCell, phase == .press { pinCount += 1 }
                    return true
                }
                if manual {
                    coordinator.enterAppSelector(source: source)
                    coordinator.handle(.init(action: .select, source: source, physicalCell: PhysicalCell(rawValue: 1)!, phase: .press))
                } else { coordinator.enterAppSpecific(source: source) }
                func input(_ cell: PhysicalCell, _ phase: ModePickerCommand.Phase, from inputSource: MouseSource? = nil) {
                    coordinator.handle(.init(action: .select, source: inputSource ?? source, physicalCell: cell, phase: phase))
                }
                let modifier = CodexMode.pinModifierCell, pin = CodexMode.pinToggleCell
                let other: MouseSource = source == .corsair ? .razer : .corsair
                input(pin, .press); input(pin, .release)
                XCTAssertEqual(pinCount, 0)
                input(modifier, .press, from: other)
                input(pin, .press); input(pin, .release)
                XCTAssertEqual(pinCount, 0)
                input(modifier, .press)
                XCTAssertTrue(coordinator.isActive)
                input(pin, .press, from: other)
                XCTAssertEqual(pinCount, 0)
                input(pin, .press); input(pin, .press)
                XCTAssertEqual(pinCount, 1) // A repeated transport down is not another click.
                input(modifier, .press) // Must not forget that the chord consumed Exit.
                input(pin, .release)
                input(pin, .press); input(pin, .release)
                XCTAssertEqual(pinCount, 2)
                input(modifier, .release)
                XCTAssertTrue(coordinator.isActive)
                XCTAssertNil(coordinator.activeWheelControl)
                input(pin, .press); input(pin, .release)
                XCTAssertEqual(pinCount, 2)
                XCTAssertFalse(coordinator.toggleCodexPinFromWheel(.init(source: source, control: .codexPin, direction: .up), inputTime: 3))
                XCTAssertFalse(coordinator.toggleCodexPinFromWheel(.init(source: source, control: .codexPin, direction: .down), inputTime: 4))
                input(modifier, .press)
                XCTAssertTrue(coordinator.isActive)
                input(modifier, .release)
                XCTAssertFalse(coordinator.isActive) // A wheel-free, unused click still exits.
            }
        }
    }

    func testCodexPinChordConsumesFailedDispatchAndEitherReleaseOrder() {
        for source in MouseSource.allCases {
            let coordinator = makeCoordinator()
            coordinator.resolveFrontmostApp = {
                .init(target: .codex, displayName: "Codex", bundleIdentifier: CodexMode.bundleIdentifier)
            }
            var attempts = 0
            coordinator.onAppSpecificInput = { _, _, _, _, _ in attempts += 1; return false }
            coordinator.enterAppSpecific(source: source)
            func input(_ cell: PhysicalCell, _ phase: ModePickerCommand.Phase) {
                coordinator.handle(.init(action: .select, source: source, physicalCell: cell, phase: phase))
            }
            input(CodexMode.pinModifierCell, .press)
            input(CodexMode.pinToggleCell, .press)
            input(CodexMode.pinModifierCell, .release)
            input(CodexMode.pinToggleCell, .release)
            XCTAssertEqual(attempts, 1)
            XCTAssertTrue(coordinator.isActive)
            // Holding Pin first must not retroactively fire when 2 arrives.
            input(CodexMode.pinToggleCell, .press)
            input(CodexMode.pinModifierCell, .press)
            input(CodexMode.pinToggleCell, .release)
            XCTAssertEqual(attempts, 1)
            coordinator.exit()
        }
    }

    func testCodexPinModifierDoesNotSurviveExitFocusChangeOrSleep() {
        for source in MouseSource.allCases {
            for cancel in 0..<3 {
                let coordinator = makeCoordinator()
                coordinator.resolveFrontmostApp = {
                    .init(target: .codex, displayName: "Codex", bundleIdentifier: CodexMode.bundleIdentifier)
                }
                var count = 0
                coordinator.onAppSpecificInput = { _, _, _, _, _ in count += 1; return true }
                coordinator.enterAppSpecific(source: source)
                coordinator.handle(.init(action: .select, source: source, physicalCell: CodexMode.pinModifierCell, phase: .press))
                if cancel == 0 { coordinator.exit(); coordinator.enterAppSpecific(source: source) }
                else if cancel == 1 {
                    coordinator.updateFrontmostApp(.init(target: .chrome, displayName: "Chrome", bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier))
                    coordinator.updateFrontmostApp(.init(target: .codex, displayName: "Codex", bundleIdentifier: CodexMode.bundleIdentifier))
                } else { coordinator.handleSystemSleep(); coordinator.enterAppSpecific(source: source) }
                coordinator.handle(.init(action: .select, source: source, physicalCell: CodexMode.pinToggleCell, phase: .press))
                coordinator.handle(.init(action: .select, source: source, physicalCell: CodexMode.pinToggleCell, phase: .release))
                coordinator.handle(.init(action: .select, source: source, physicalCell: CodexMode.pinModifierCell, phase: .release))
                XCTAssertEqual(count, 0)
                XCTAssertTrue(coordinator.isActive) // Old modifier release cannot exit a new journey.
            }
        }
    }

    func testClaudeUsesCodexCellsWithClaudeActions() {
        let expected = [
            "Pin/Unpin", "Exit · Hold for Pin/Unpin", "Fast mode", "Open side chat",
            "New chat", "Choose effort", "Enter", "Close pane", "Chats Selection",
            "Exit Claude mode", "Spare", "Dictation",
        ]
        XCTAssertEqual(ClaudeMode.definition.legend.map(\.actionTitle), expected)
        XCTAssertEqual(ClaudeMode.definition.legend[0].controlStatus, .reportedBroken)
        XCTAssertEqual(ClaudeMode.pinToggleCell, CodexMode.pinToggleCell)
        XCTAssertEqual(ClaudeMode.tabsWheelCell, CodexMode.chatHistoryWheelCell)
        XCTAssertEqual(WheelChordControl.appSpecificControl(for: .claude, cell: ClaudeMode.pinToggleCell), .claudePin)
        XCTAssertEqual(WheelChordControl.appSpecificControl(for: .claude, cell: ClaudeMode.tabsWheelCell), .claudeTabs)

        for source in MouseSource.allCases {
            let coordinator = makeCoordinator()
            coordinator.resolveFrontmostApp = {
                FrontmostAppModeContext(target: .claude, displayName: "Claude", bundleIdentifier: ClaudeMode.bundleIdentifier)
            }
            var actions: [ClaudeModeAction] = []
            coordinator.onAppSpecificInput = { _, target, cell, phase, _ in
                guard target == .claude, phase == .press,
                      let action = ClaudeModeAction.action(for: cell) else { return false }
                actions.append(action)
                return true
            }
            coordinator.enterAppSpecific(source: source)
            for cell in [3, 4, 6, 8] {
                let physicalCell = PhysicalCell(rawValue: cell)!
                coordinator.handle(.init(action: .select, source: source, physicalCell: physicalCell, phase: .press))
                coordinator.handle(.init(action: .select, source: source, physicalCell: physicalCell, phase: .release))
            }
            XCTAssertEqual(actions, [.toggleFastMode, .openSideChat, .chooseEffort, .closePane])
            coordinator.handle(.init(action: .select, source: source, physicalCell: ClaudeMode.tabsWheelCell, phase: .press))
            XCTAssertEqual(coordinator.activeWheelControl, .claudeTabs)
            coordinator.handle(.init(action: .select, source: source, physicalCell: ClaudeMode.tabsWheelCell, phase: .release))
            XCTAssertNil(coordinator.activeWheelControl)
        }
    }

    func testClaudePinUsesTheOpeningModifierOnBothMice() {
        for source in MouseSource.allCases where source.isPhysicalAdapter {
            let coordinator = makeCoordinator()
            coordinator.resolveFrontmostApp = {
                .init(target: .claude, displayName: "Claude", bundleIdentifier: ClaudeMode.bundleIdentifier)
            }
            var toggles = 0
            coordinator.onAppSpecificInput = { _, target, cell, phase, _ in
                guard target == .claude, cell == ClaudeMode.pinToggleCell, phase == .press else { return false }
                toggles += 1
                return true
            }
            func send(_ cell: PhysicalCell, _ phase: ModePickerCommand.Phase,
                      action: ModePickerCommand.Action = .select, from mouse: MouseSource? = nil) {
                coordinator.handle(.init(action: action, source: mouse ?? source, physicalCell: cell, phase: phase))
            }
            send(CodexMode.pinModifierCell, .press, action: .openAppSpecific)
            send(ClaudeMode.pinToggleCell, .press, from: source == .corsair ? .razer : .corsair)
            XCTAssertEqual(toggles, 0)
            send(ClaudeMode.pinToggleCell, .press)
            send(ClaudeMode.pinToggleCell, .press)
            send(ClaudeMode.pinToggleCell, .release)
            send(CodexMode.pinModifierCell, .release, action: .openAppSpecific)
            XCTAssertEqual(toggles, 1)
            XCTAssertTrue(coordinator.isActive)
            send(ClaudeMode.pinToggleCell, .press)
            send(ClaudeMode.pinToggleCell, .release)
            XCTAssertEqual(toggles, 1)
            send(CodexMode.pinModifierCell, .press)
            send(CodexMode.pinModifierCell, .release)
            XCTAssertFalse(coordinator.isActive)
        }
    }

    func testClaudeWandPinUsesEitherDirectionOncePerHold() {
        for source in [MouseSource.wand] {
            let coordinator = makeCoordinator()
            coordinator.resolveFrontmostApp = {
                FrontmostAppModeContext(target: .claude, displayName: "Claude",
                                         bundleIdentifier: ClaudeMode.bundleIdentifier)
            }
            var toggles = 0
            coordinator.onAppSpecificInput = { _, target, cell, phase, _ in
                if target == .claude, cell == ClaudeMode.pinToggleCell, phase == .press {
                    toggles += 1
                }
                return true
            }
            coordinator.enterAppSpecific(source: source)
            func input(_ phase: ModePickerCommand.Phase) {
                coordinator.handle(.init(action: .select, source: source,
                                         physicalCell: ClaudeMode.pinToggleCell, phase: phase))
            }
            let up = WheelChordStateMachine.Step(source: source, control: .claudePin, direction: .down)
            let down = WheelChordStateMachine.Step(source: source, control: .claudePin, direction: .up)
            input(.press)
            input(.release)
            XCTAssertEqual(toggles, 0)
            XCTAssertFalse(coordinator.toggleClaudePinFromWheel(up, inputTime: 1))
            input(.press)
            XCTAssertEqual(coordinator.activeWheelControl, .claudePin)
            XCTAssertFalse(coordinator.toggleClaudePinFromWheel(
                .init(source: source == .corsair ? .razer : .corsair,
                      control: .claudePin, direction: .down), inputTime: 2
            ))
            XCTAssertTrue(coordinator.toggleClaudePinFromWheel(up, inputTime: 2))
            XCTAssertFalse(coordinator.toggleClaudePinFromWheel(down, inputTime: 2.05))
            input(.press)
            XCTAssertFalse(coordinator.toggleClaudePinFromWheel(up, inputTime: 2.1))
            input(.release)
            XCTAssertEqual(toggles, 1)
            input(.press)
            XCTAssertTrue(coordinator.toggleClaudePinFromWheel(down, inputTime: 3))
            input(.release)
            XCTAssertEqual(toggles, 2)
            input(.press)
            coordinator.exit()
            XCTAssertFalse(coordinator.toggleClaudePinFromWheel(up, inputTime: 4))
            XCTAssertEqual(toggles, 2)
        }
    }

    func testCodexPinLabelStaysVisibleBeforeDuringAndAfterHoldOnBothMice() {
        for source in MouseSource.allCases {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            coordinator.resolveFrontmostApp = {
                FrontmostAppModeContext(target: .codex, displayName: "Codex", bundleIdentifier: CodexMode.bundleIdentifier)
            }
            coordinator.enterAppSpecific(source: source)
            let cell = CodexMode.screenshotPinWheelCell
            XCTAssertEqual(hud.snapshots.last?.legend.first { $0.cell == cell }?.actionTitle, "Pin/Unpin")
            coordinator.handle(.init(action: .select, source: source, physicalCell: cell, phase: .press))
            XCTAssertEqual(hud.snapshots.last?.legend.first { $0.cell == cell }?.actionTitle, "Pin/Unpin")
            coordinator.handle(.init(action: .select, source: source, physicalCell: cell, phase: .release))
            XCTAssertEqual(hud.snapshots.last?.legend.first { $0.cell == cell }?.actionTitle, "Pin/Unpin")
            XCTAssertNil(coordinator.activeWheelControl)
            XCTAssertTrue(coordinator.isActive)
        }
    }

    func testCodexSpeedHoldUsesTheSameControlInAutomaticAndManualModes() {
        for source in MouseSource.allCases {
            for manual in [false, true] {
                let coordinator = makeCoordinator()
                coordinator.resolveFrontmostApp = {
                    FrontmostAppModeContext(target: .codex, displayName: "Codex", bundleIdentifier: CodexMode.bundleIdentifier)
                }
                var controls: [WheelChordControl?] = []
                var clicks = 0
                coordinator.onWheelControlChange = { _, control in controls.append(control) }
                coordinator.onAppSpecificInput = { _, _, _, _, _ in clicks += 1; return true }
                if manual {
                    coordinator.enterAppSelector(source: source)
                    coordinator.handle(.init(action: .select, source: source, physicalCell: AppSpecificTarget.codex.selectorCell!))
                } else {
                    coordinator.enterAppSpecific(source: source)
                }
                let cell = CodexMode.responseSpeedWheelCell
                coordinator.handle(.init(action: .select, source: source, physicalCell: cell, phase: .press))
                XCTAssertEqual(coordinator.activeWheelControl, .codexResponseSpeed)
                coordinator.handle(.init(action: .select, source: source, physicalCell: cell, phase: .release))
                XCTAssertNil(coordinator.activeWheelControl)
                XCTAssertEqual(controls.suffix(2), [.codexResponseSpeed, nil])
                XCTAssertEqual(clicks, 0, "The completed wheel-hold path owns speed clicks; never dispatch the old Astra action")
            }
        }
    }

    func testRepeatedCodexExitAndSpeedClicksDoNotRouteActionsOnEitherMouse() {
        for source in MouseSource.allCases {
            for cell in [PhysicalCell.frontmostAppModeSelector, .modeExit, CodexMode.responseSpeedWheelCell] {
                let coordinator = makeCoordinator()
                coordinator.resolveFrontmostApp = {
                    FrontmostAppModeContext(target: .codex, displayName: "Codex", bundleIdentifier: CodexMode.bundleIdentifier)
                }
                var actions: [CodexModeAction] = []
                coordinator.onAppSpecificInput = { _, target, cell, phase, _ in
                    if target == .codex, phase == .press, let action = CodexModeAction.action(for: cell) { actions.append(action) }
                    return true
                }
                coordinator.enterAppSpecific(source: source)
                for _ in 0..<2 {
                    coordinator.handle(.init(action: .select, source: source, physicalCell: cell, phase: .press))
                    coordinator.handle(.init(action: .select, source: source, physicalCell: cell, phase: .release))
                }
                XCTAssertFalse(actions.contains(.newTask))
                XCTAssertEqual(actions, [])
            }
        }
    }

    func testCodexCreationAuditDistinguishesAcceptedNewChatAndNativeVoiceWithoutExtraDispatch() {
        let sink = RecordingLogSink()
        let coordinator = ModePickerCoordinator(lease: RecordingModePickerLease(),
            hud: RecordingModeHUDPresenter(), scheduler: ManualTickScheduler(),
            log: Log(category: "test", sink: sink))
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(target: .codex, displayName: "Codex", bundleIdentifier: CodexMode.bundleIdentifier)
        }
        var appInputs: [PhysicalCell] = [], nativeInputs: [PhysicalCell] = []
        coordinator.onAppSpecificInput = { _, _, cell, phase, _ in
            if phase == .press { appInputs.append(cell) }; return true
        }
        coordinator.onNativeAppSpecificInput = { _, _, cell, phase, _ in
            if phase == .press { nativeInputs.append(cell) }; return true
        }
        coordinator.enterAppSpecific(source: .razer)
        for phase in [ModePickerCommand.Phase.press, .release] {
            coordinator.handle(.init(action: .select, source: .razer, physicalCell: CodexModeAction.newTask.cell, phase: phase))
            coordinator.handle(.init(action: .selectNative, source: .razer, physicalCell: CodexModeAction.toggleVoiceMode.cell, phase: phase))
        }
        coordinator.handle(.init(action: .selectNative, source: .corsair, physicalCell: CodexModeAction.toggleVoiceMode.cell, phase: .press))
        XCTAssertEqual(appInputs, [CodexModeAction.newTask.cell])
        XCTAssertEqual(nativeInputs, [CodexModeAction.toggleVoiceMode.cell])
        XCTAssertEqual(sink.entries.map(\.message).filter { $0.contains("requested via") }, [
            "Codex newTask requested via app route, source razer, cell 5",
            "Codex toggleVoiceMode requested via native route, source razer, cell 12"
        ])
    }

    private func makeCoordinator(
        lease: RecordingModePickerLease = RecordingModePickerLease(),
        hud: RecordingModeHUDPresenter = RecordingModeHUDPresenter(),
        scheduler: ManualTickScheduler = ManualTickScheduler(),
        reservedHUDScheduler: ManualTickScheduler = ManualTickScheduler(),
        reservedHUDClock: MonotonicClock = SystemMonotonicClock()
    ) -> ModePickerCoordinator {
        ModePickerCoordinator(
            lease: lease,
            hud: hud,
            scheduler: scheduler,
            reservedHUDScheduler: reservedHUDScheduler,
            reservedHUDClock: reservedHUDClock,
            log: Log(category: "test", sink: NullLogSink())
        )
    }
}

private final class RecordingModePickerLease: ColorProofLeaseControlling {
    var activateCount = 0
    var renewCount = 0
    var deactivateCount = 0

    func activate() throws { activateCount += 1 }
    func renew() throws { renewCount += 1 }
    func deactivate() { deactivateCount += 1 }
}
