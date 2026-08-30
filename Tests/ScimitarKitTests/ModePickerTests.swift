import XCTest
@testable import ScimitarKit

final class ModePickerTests: XCTestCase {
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
        XCTAssertEqual(ModePickerCoordinator.modesLegend[0].actionTitle, "Brightness + Wheel")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[1].actionTitle, "Zoom + Wheel")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[2].actionTitle, "Spaces + Wheel")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[3].actionTitle, "Mission / Desktop + Wheel")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[4].actionTitle, "App Exposé + Wheel")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[5].actionTitle, "Magnet + Wheel")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[6].actionTitle, "PP")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[7].actionTitle, "Intelligence on demand")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[8].actionTitle, "Keys mode")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[10].actionTitle, "Choose App Specific")
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
        let brokenCodexActions: [CodexModeAction] = [
            .toggleVoiceMode,
            .editQueuedMessage,
        ]
        for action in CodexModeAction.allCases {
            let expected: ModeHUDControlStatus = brokenCodexActions.contains(action)
                ? .reportedBroken
                : .normal
            XCTAssertEqual(action.hudControlStatus, expected, "Codex action \(action)")
        }

        let edit = CodexMode.definition.legend.first {
            $0.cell == CodexModeAction.editQueuedMessage.cell
        }!
        XCTAssertEqual(edit.printedControlLabel(on: .corsair), "Corsair 8 ❌")
        XCTAssertEqual(edit.printedControlLabel(on: .razer), "Razer 8 ❌")

        let steer = CodexMode.definition.legend.first {
            $0.cell == CodexModeAction.steerQueuedMessage.cell
        }!
        XCTAssertEqual(steer.controlStatus, .normal)
        XCTAssertEqual(steer.printedControlLabel(on: .corsair), "Corsair 1")
        XCTAssertEqual(steer.printedControlLabel(on: .razer), "Razer 3")

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
        XCTAssertNil(ModeUtilityAction.directAction(for: PhysicalCell(rawValue: 5)!))
        XCTAssertEqual(PhysicalCell.systemOverviewWheelControl.printedSide(on: .corsair), 4)
        XCTAssertEqual(PhysicalCell.systemOverviewWheelControl.printedSide(on: .razer), 6)
    }

    func testOnlyOnePressUtilityCardsUseTheDirectActionRoute() {
        XCTAssertFalse(ModeUtilityAction.showDesktop.isDirectAction)
        XCTAssertFalse(ModeUtilityAction.missionControl.isDirectAction)
        XCTAssertFalse(ModeUtilityAction.showApplicationWindows.isDirectAction)
        XCTAssertTrue(ModeUtilityAction.organizeWindows.isDirectAction)
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
        XCTAssertEqual(WheelChordControl.utilityControl(for: PhysicalCell(rawValue: 2)!), .zoom)
        XCTAssertEqual(WheelChordControl.utilityControl(for: PhysicalCell(rawValue: 3)!), .spaces)
        XCTAssertEqual(WheelChordControl.utilityControl(for: PhysicalCell(rawValue: 4)!), .systemOverview)
        XCTAssertEqual(
            WheelChordControl.utilityControl(for: PhysicalCell(rawValue: 5)!),
            .applicationWindows
        )
        XCTAssertEqual(PhysicalCell.applicationWindowsWheelControl.printedSide(on: .corsair), 5)
        XCTAssertEqual(PhysicalCell.applicationWindowsWheelControl.printedSide(on: .razer), 5)
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
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .applicationWindowsWheelControl, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .applicationWindowsWheelControl, phase: .release))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .magnetWheelControl, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .magnetWheelControl, phase: .release))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .interruptTerminal, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .interruptTerminal, phase: .release))

        XCTAssertEqual(actions.map(\.0), [.razer])
        XCTAssertEqual(actions.map(\.1), [.openIntelligenceOnDemand])
        XCTAssertEqual(controls.map(\.0), Array(repeating: .razer, count: 10))
        XCTAssertEqual(
            controls.map(\.1),
            [
                .brightness, nil,
                .spaces, nil,
                .systemOverview, nil,
                .applicationWindows, nil,
                .magnetWindow, nil,
            ]
        )
        XCTAssertEqual(coordinator.page, .extraUtilities)
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
        XCTAssertEqual(hud.snapshots.last?.selection?.title, "Brightness + Wheel")
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

    func testUtilityCellTwelveOpensExtraUtilitiesAndOrganizeWindowsUsesSharedCellOne() {
        for source in MouseSource.allCases {
            let lease = RecordingModePickerLease()
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(lease: lease, hud: hud)
            var actions: [(MouseSource, ModeUtilityAction)] = []
            coordinator.onUtilityAction = { requestedSource, action in
                actions.append((requestedSource, action))
                return .performed
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
        XCTAssertEqual(PhysicalCell.organizeWindows.printedSide(on: .corsair), 1)
        XCTAssertEqual(PhysicalCell.organizeWindows.printedSide(on: .razer), 3)
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

    func testOrganizeWindowsOneShotResetsAfterLeavingExtraUtilities() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var actionCount = 0
        coordinator.onUtilityAction = { _, action in
            if action == .organizeWindows { actionCount += 1 }
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

        XCTAssertEqual(actionCount, 2)
        XCTAssertEqual(
            hud.feedback,
            [
                ModeHUDFeedback(
                    message: "Stay restore requested",
                    tone: .informational
                ),
                ModeHUDFeedback(
                    message: "Stay restore already requested",
                    tone: .informational
                ),
            ]
        )
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

    func testCellElevenOpensTheSelectorThenLocksCodexAndRoutesItsActions() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var selected: [(AppSpecificTarget, PhysicalCell)] = []
        coordinator.onAppSpecificInput = { _, target, cell, _ in
            selected.append((target, cell))
            return true
        }

        coordinator.enter(source: .razer)
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .appSpecificModeSelector))

        XCTAssertEqual(coordinator.page, .appSelector)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Choose app")

        coordinator.handle(.init(action: .select, source: .razer, physicalCell: AppSpecificTarget.codex.selectorCell!))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: CodexModeAction.togglePin.cell))

        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .codex)
        XCTAssertEqual(coordinator.appSpecificDefinition, CodexMode.definition)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Codex mode")
        XCTAssertEqual(hud.snapshots.last?.accent, CodexMode.accent)
        XCTAssertEqual(selected.map(\.0), [.codex])
        XCTAssertEqual(selected.map { $0.1.rawValue }, [3])
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
            coordinator.onAppSpecificInput = { _, _, cell, _ in
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
            XCTAssertEqual(hud.snapshots.last?.selection?.title, "Tabs + Wheel")
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
                coordinator.onAppSpecificInput = { _, _, cell, _ in
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
                XCTAssertEqual(hud.snapshots.last?.selection?.title, "Volume + Wheel")
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
                coordinator.onAppSpecificInput = { _, _, cell, _ in
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
                XCTAssertEqual(hud.snapshots.last?.selection?.title, "Cursor History + Wheel")
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

    func testChromeDoubleSpeedHoldForwardsPressAndReleaseWithoutStealingTheWheelCell() {
        for source in MouseSource.allCases {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            var inputs: [(MouseSource, AppSpecificTarget, PhysicalCell, ModePickerCommand.Phase)] = []
            coordinator.onAppSpecificInput = { source, target, cell, phase in
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

    func testChromeCellThreeOpensDevToolsThroughBothAppSpecificJourneys() {
        XCTAssertEqual(ChromeModeAction.openDevTools.cell.rawValue, 3)
        XCTAssertEqual(ChromeModeAction.openDevTools.title, "Open DevTools")
        XCTAssertEqual(ChromeMode.definition.legend[2].actionTitle, "Open DevTools")

        for source in MouseSource.allCases {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            var inputs: [(MouseSource, AppSpecificTarget, PhysicalCell, ModePickerCommand.Phase)] = []
            coordinator.onAppSpecificInput = { source, target, cell, phase in
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
                physicalCell: .init(rawValue: 3)!,
                phase: .press
            ))

            XCTAssertEqual(inputs.map(\.0), [source])
            XCTAssertEqual(inputs.map(\.1), [.chrome])
            XCTAssertEqual(inputs.map(\.2), [.init(rawValue: 3)!])
            XCTAssertEqual(inputs.map(\.3), [.press])
            XCTAssertEqual(hud.snapshots.last?.selection?.title, "Open DevTools")
        }
    }

    func testChromeCellSixReloadsTheCurrentTabThroughBothAppSpecificJourneys() {
        XCTAssertEqual(ChromeModeAction.reloadCurrentTab.cell.rawValue, 6)
        XCTAssertEqual(ChromeModeAction.reloadCurrentTab.title, "Reload current tab")
        XCTAssertEqual(ChromeMode.definition.legend[5].actionTitle, "Reload current tab")

        for source in MouseSource.allCases {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            var inputs: [(MouseSource, AppSpecificTarget, PhysicalCell, ModePickerCommand.Phase)] = []
            coordinator.onAppSpecificInput = { source, target, cell, phase in
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
            coordinator.onAppSpecificInput = { source, target, cell, phase in
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

    func testChromeModeKeepsHistoryInDefaultAndDuplicatesNewTabOnCellEight() {
        XCTAssertEqual(ChromeModeAction.closeCurrentTab.cell.rawValue, 1)
        XCTAssertEqual(ChromeMode.definition.legend[0].actionTitle, "Close current tab")
        XCTAssertEqual(ChromeModeAction.action(for: PhysicalCell(rawValue: 8)!), .newTab)
        XCTAssertEqual(ChromeMode.definition.legend[7].actionTitle, "New tab")
        XCTAssertEqual(ChromeModeAction.holdYouTubeDoubleSpeed.cell.rawValue, 7)
        XCTAssertEqual(ChromeMode.definition.legend[6].actionTitle, "Hold 2× speed")
        XCTAssertFalse(ChromeModeAction.allCases.contains { $0.title == "Close current window" })
        XCTAssertFalse(ChromeModeAction.allCases.contains { $0.title == "Back" })
        XCTAssertFalse(ChromeModeAction.allCases.contains { $0.title == "Forward" })
    }

    func testChromeNewTabDuplicateSharesOneDefinitionAcrossAutomaticAndManualJourneys() {
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
        manual.enter(source: .razer)
        manual.handle(.init(
            action: .select,
            source: .razer,
            physicalCell: .appSpecificModeSelector
        ))
        manual.handle(.init(
            action: .select,
            source: .razer,
            physicalCell: AppSpecificTarget.chrome.selectorCell!
        ))

        XCTAssertEqual(automatic.appSpecificDefinition, ChromeMode.definition)
        XCTAssertEqual(manual.appSpecificDefinition, ChromeMode.definition)
        XCTAssertEqual(automaticHUD.snapshots.last?.legend[0].actionTitle, "Close current tab")
        XCTAssertEqual(manualHUD.snapshots.last?.legend[0].actionTitle, "Close current tab")
        XCTAssertEqual(automaticHUD.snapshots.last?.legend[7].actionTitle, "New tab")
        XCTAssertEqual(manualHUD.snapshots.last?.legend[7].actionTitle, "New tab")
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

    func testKeysModeMapsArrowsUndoMediaSpaceBackspaceAndEnterOnPressOnly() {
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
                .nextTrack,
                .insertSpace,
                .pressBackspace,
                .pressEnter,
            ]
        )
        XCTAssertEqual(KeysModeAction.arrowUp.cell.rawValue, 5)
        XCTAssertEqual(KeysModeAction.arrowDown.cell.rawValue, 4)
        XCTAssertEqual(KeysModeAction.arrowLeft.cell.rawValue, 1)
        XCTAssertEqual(KeysModeAction.arrowRight.cell.rawValue, 7)
        XCTAssertEqual(KeysModeAction.undo.cell.rawValue, 3)
        XCTAssertEqual(KeysModeAction.undo.cell(for: .razer).printedSide(on: .razer), 1)
        XCTAssertEqual(KeysModeAction.nextTrack.cell.rawValue, 9)
        XCTAssertEqual(KeysModeAction.insertSpace.cell.rawValue, 8)
        XCTAssertEqual(KeysModeAction.pressBackspace.cell.rawValue, 11)
        XCTAssertEqual(KeysModeAction.pressEnter.cell.rawValue, 12)
        XCTAssertEqual(ModePickerCoordinator.keysLegend[9].actionTitle, "Exit Keys mode")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[5].actionTitle, "Keypad")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[7].actionTitle, "Space")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[1].actionTitle, "Spare")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[2].actionTitle, "Undo")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[8].actionTitle, "Next Track")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[10].actionTitle, "Backspace")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[11].actionTitle, "Enter")
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
        XCTAssertNotEqual(KeysModeAction.pressBackspace.hudAccent, KeysModeAction.pressEnter.hudAccent)
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
        XCTAssertEqual(ModePickerCoordinator.keysLegend(for: .razer)[0].actionTitle, "Right Arrow")
        XCTAssertEqual(ModePickerCoordinator.keysLegend(for: .razer)[6].actionTitle, "Left Arrow")
        XCTAssertEqual(ModePickerCoordinator.keysLegend(for: .razer)[2].actionTitle, "Undo")
        XCTAssertEqual(ModePickerCoordinator.keysLegend(for: .razer)[5].actionTitle, "Keypad")

        XCTAssertEqual(WheelChordControl.spaces.utilityAction(for: .up), .moveToSpaceRight)
        XCTAssertEqual(WheelChordControl.spaces.utilityAction(for: .down), .moveToSpaceLeft)
        XCTAssertEqual(
            ModePickerCoordinator.modesLegend(for: .razer)[2].actionTitle,
            "Spaces + Wheel"
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
            ModePickerCoordinator.modesLegend[PhysicalCell.appSpecificModeSelector.rawValue - 1]
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
        XCTAssertEqual(hud.snapshots.last?.selection?.title, "Up Arrow")
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
        coordinator.onNativeAppSpecificInput = { _, _, cell, _ in
            nativeInputs.append(cell)
            return true
        }
        coordinator.onAppSpecificInput = { _, _, cell, _ in
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

    func testUtilityCellElevenOpensTheManualConfiguredAppSelector() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)

        coordinator.enter(source: .corsair)
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
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

    func testEveryAppSpecificChildReservesCellsTwoAndTenAsTheSameExit() {
        for target in AppSpecificTarget.allCases {
            let definition = target.definition
            let expectedTitle = "Exit \(target.displayName) mode"
            let exitItems = definition.legend.filter { $0.cell.isAppSpecificModeExit }

            XCTAssertEqual(exitItems.count, 2, "\(target.displayName) exit count")
            XCTAssertEqual(Set(exitItems.map(\.actionTitle)), [expectedTitle])
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
            "Volume + Wheel"
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

    func testSafariLayoutDuplicatesChromeNewTabOnCellEight() {
        let actions = StandardAppMode.actions(for: .safari)
        let expectedTitlesByCell = [
            1: "Close tab",
            3: "Open DevTools",
            4: "Previous tab",
            5: "New tab",
            6: "Reload",
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
                "1|Close tab|13|1",
                "3|Open DevTools|34|5",
                "4|Previous tab|48|10",
                "5|New tab|17|1",
                "6|Reload|15|1",
                "7|Next tab|48|8",
                "8|New tab|17|1",
                "9|Forward|30|1",
                "11|Reopen tab|17|3",
                "12|Find page|3|1",
            ]
        )
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[0].actionTitle, "Close tab")
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[2].actionTitle, "Open DevTools")
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[4].actionTitle, "New tab")
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[5].actionTitle, "Reload")
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[7].actionTitle, "New tab")
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[10].actionTitle, "Reopen tab")
        XCTAssertEqual(AppSpecificTarget.safari.definition.legend[11].actionTitle, "Find page")

        let devTools = StandardAppMode.action(
            for: .safari,
            cell: PhysicalCell(rawValue: 3)!
        )
        XCTAssertEqual(devTools?.keyCode, 34)
        XCTAssertEqual(devTools?.modifiers, [.command, .option])
        XCTAssertEqual(devTools?.cell.displayLabel(on: .corsair), "Corsair 3")
        XCTAssertEqual(devTools?.cell.displayLabel(on: .razer), "Razer 1")
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
            coordinator.onAppSpecificInput = { _, receivedTarget, cell, phase in
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
            "Cursor History + Wheel"
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

    func testCodexChildCellFourArmsReasoningEffortWheel() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var controls: [WheelChordControl?] = []
        coordinator.onWheelControlChange = { _, control in
            controls.append(control)
        }

        coordinator.enterAppSelector(source: .corsair)
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: AppSpecificTarget.codex.selectorCell!))
        let reasoningEffortCell = PhysicalCell(rawValue: 4)!
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: reasoningEffortCell))

        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .codex)
        XCTAssertEqual(controls, [.codexReasoningEffort])
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Codex mode")
        XCTAssertEqual(hud.snapshots.last?.selection?.title, "Reasoning Effort + Wheel")

        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: reasoningEffortCell,
            phase: .release
        ))
        XCTAssertEqual(controls, [.codexReasoningEffort, nil])
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
        XCTAssertEqual(CodexModeAction.togglePin.cell.rawValue, 3)
        XCTAssertEqual(CodexModeAction.toggleMicrophoneMute.cell.rawValue, 6)
        XCTAssertEqual(CodexModeAction.toggleMicrophoneMute.cell.printedSide(on: .corsair), 6)
        XCTAssertEqual(CodexModeAction.toggleMicrophoneMute.cell.printedSide(on: .razer), 4)
        XCTAssertEqual(
            CodexModeAction.toggleMicrophoneMute.title,
            "Mute / unmute voice mic"
        )
        XCTAssertEqual(CodexModeAction.togglePin.cell.printedSide(on: .razer), 1)
        XCTAssertEqual(CodexModeAction.togglePin.cell.printedSide(on: .corsair), 3)
        XCTAssertEqual(CodexModeAction.toggleVoiceMode.cell.rawValue, 12)
        XCTAssertEqual(CodexModeAction.toggleVoiceMode.cell.printedSide(on: .corsair), 12)
        XCTAssertEqual(CodexModeAction.toggleVoiceMode.cell.printedSide(on: .razer), 10)
        XCTAssertEqual(CodexModeAction.newTask.title, "New chat")
        XCTAssertEqual(CodexModeAction.toggleVoiceMode.title, "Voice mode")
        XCTAssertEqual(CodexModeAction.openSideChat.cell.rawValue, 9)
        XCTAssertEqual(CodexModeAction.openSideChat.cell.printedSide(on: .corsair), 9)
        XCTAssertEqual(CodexModeAction.openSideChat.cell.printedSide(on: .razer), 7)
        XCTAssertEqual(CodexModeAction.openSideChat.title, "Open side chat")
        XCTAssertEqual(CodexModeAction.steerQueuedMessage.cell.rawValue, 1)
        XCTAssertEqual(CodexModeAction.steerQueuedMessage.cell.printedSide(on: .corsair), 1)
        XCTAssertEqual(CodexModeAction.steerQueuedMessage.cell.printedSide(on: .razer), 3)
        XCTAssertEqual(CodexModeAction.editQueuedMessage.cell.rawValue, 8)
        XCTAssertEqual(CodexModeAction.editQueuedMessage.title, "Edit queued message")
        XCTAssertEqual(CodexModeAction.pressEnter.cell.rawValue, 7)
        XCTAssertEqual(CodexModeAction.pressEnter.cell.printedSide(on: .razer), 9)
        XCTAssertEqual(CodexModeAction.pressEnter.cell.printedSide(on: .corsair), 7)
        XCTAssertEqual(CodexModeAction.action(for: .modePickerEntry), .toggleVoiceMode)
        XCTAssertNil(CodexModeAction.action(for: PhysicalCell(rawValue: 4)!))
        XCTAssertNil(CodexModeAction.action(for: PhysicalCell(rawValue: 11)!))
        XCTAssertEqual(
            WheelChordControl.appSpecificControl(
                for: .codex,
                cell: PhysicalCell(rawValue: 4)!
            ),
            .codexReasoningEffort
        )
        XCTAssertEqual(
            WheelChordControl.appSpecificControl(
                for: .codex,
                cell: PhysicalCell(rawValue: 11)!
            ),
            .codexChatHistory
        )
        XCTAssertEqual(CodexMode.definition.legend[1].actionTitle, "Exit Codex mode")
        XCTAssertEqual(CodexMode.definition.legend[4].actionTitle, "New chat")
        XCTAssertEqual(CodexMode.definition.legend[2].actionTitle, "Pin / unpin")
        XCTAssertEqual(CodexMode.definition.legend[0].actionTitle, "Steer queued message")
        XCTAssertEqual(CodexMode.definition.legend[5].actionTitle, "Mute / unmute voice mic")
        XCTAssertEqual(CodexMode.definition.legend[8].actionTitle, "Open side chat")
        XCTAssertEqual(CodexMode.definition.legend[9].actionTitle, "Exit Codex mode")
        XCTAssertEqual(CodexMode.definition.legend[3].actionTitle, "Reasoning Effort + Wheel")
        XCTAssertEqual(CodexMode.definition.legend[11].actionTitle, "Voice mode")
        XCTAssertEqual(CodexMode.definition.legend[10].actionTitle, "Chats Selection + Wheel")
        XCTAssertEqual(
            CodexMode.definition.legend[3].accent,
            ModeHUDActionFamilyPalette.reasoningEffort
        )
        XCTAssertEqual(
            CodexMode.definition.legend[10].accent,
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
            }

            let expectedCellThreeTitle: String
            switch page {
            case .appSpecific: expectedCellThreeTitle = "Pin / unpin"
            case .appSelector: expectedCellThreeTitle = "Claude"
            case .keys: expectedCellThreeTitle = "Undo"
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

    func testKeysCellTwelveIsEnterRatherThanUtilityNavigation() {
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
        XCTAssertEqual(keysActions, [.pressEnter])
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

    private func makeCoordinator(
        lease: RecordingModePickerLease = RecordingModePickerLease(),
        hud: RecordingModeHUDPresenter = RecordingModeHUDPresenter(),
        scheduler: ManualTickScheduler = ManualTickScheduler()
    ) -> ModePickerCoordinator {
        ModePickerCoordinator(
            lease: lease,
            hud: hud,
            scheduler: scheduler,
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
