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

    func testModesMenuShowsBrightnessUtilitiesTwoChildModesAndUniversalExit() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)

        coordinator.enter(source: .razer)

        XCTAssertEqual(coordinator.page, .modes)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Utility modes")
        XCTAssertEqual(ModePickerCoordinator.modesLegend.count, 12)
        XCTAssertEqual(ModePickerCoordinator.modesLegend[0].actionTitle, "Brightness Up")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[1].actionTitle, "Zoom In")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[2].actionTitle, "Space Left")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[3].actionTitle, "Brightness Down")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[4].actionTitle, "Zoom Out")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[5].actionTitle, "Space Right")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[6].actionTitle, "Keypad")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[7].actionTitle, "YouTube −5 sec")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[8].actionTitle, "Keys mode")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[10].actionTitle, "Choose App Specific")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[9].actionTitle, "Exit Utility modes")
        XCTAssertEqual(ModePickerCoordinator.modesLegend[11].actionTitle, "Spare")
        XCTAssertFalse(ModePickerCoordinator.modesLegend.contains { $0.actionTitle == "Colour Proof" })
        XCTAssertEqual(ModePickerCoordinator.modesLegend[0].accent, ModePickerCoordinator.modesLegend[3].accent)
        XCTAssertEqual(ModePickerCoordinator.modesLegend[2].accent, ModePickerCoordinator.modesLegend[5].accent)
        XCTAssertEqual(ModePickerCoordinator.modesLegend[1].accent, ModePickerCoordinator.modesLegend[4].accent)
        XCTAssertNotEqual(ModePickerCoordinator.modesLegend[0].accent, ModePickerCoordinator.modesLegend[1].accent)
        XCTAssertNotEqual(ModePickerCoordinator.modesLegend[0].accent, ModePickerCoordinator.modesLegend[2].accent)
        XCTAssertEqual(hud.snapshots.last?.source, .razer)
        XCTAssertTrue(hud.snapshots.last?.showsOnAllDisplays == true)
        XCTAssertEqual(hud.snapshots.last?.presentationStyle, .boldOpaque)
    }

    func testUtilityQuartetUsesTheRequestedRotatedPhysicalCells() {
        XCTAssertEqual(ModeUtilityAction.action(for: PhysicalCell(rawValue: 1)!), .increaseDisplayBrightness)
        XCTAssertEqual(ModeUtilityAction.action(for: PhysicalCell(rawValue: 2)!), .zoomIn)
        XCTAssertEqual(ModeUtilityAction.action(for: PhysicalCell(rawValue: 4)!), .decreaseDisplayBrightness)
        XCTAssertEqual(ModeUtilityAction.action(for: PhysicalCell(rawValue: 5)!), .zoomOut)

        XCTAssertEqual(PhysicalCell(rawValue: 1)!.printedSide(on: .razer), 3)
        XCTAssertEqual(PhysicalCell(rawValue: 2)!.printedSide(on: .razer), 2)
        XCTAssertEqual(PhysicalCell(rawValue: 4)!.printedSide(on: .razer), 6)
        XCTAssertEqual(PhysicalCell(rawValue: 5)!.printedSide(on: .razer), 5)
    }

    func testUtilityCellsRunOnlyOnPress() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var actions: [(MouseSource, ModeUtilityAction)] = []
        coordinator.onUtilityAction = { source, action in
            actions.append((source, action))
            return true
        }

        coordinator.enter(source: .razer)
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .brightnessIncrease, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .brightnessIncrease, phase: .release))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .brightnessDecrease, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .youtubeBackFiveSeconds, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .youtubeBackFiveSeconds, phase: .release))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .applicationZoomIn, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .applicationZoomIn, phase: .release))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .applicationZoomOut, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .desktopSpaceLeft, phase: .press))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .desktopSpaceLeft, phase: .release))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .desktopSpaceRight, phase: .press))

        XCTAssertEqual(actions.map(\.0), Array(repeating: .razer, count: 7))
        XCTAssertEqual(
            actions.map(\.1),
            [
                .increaseDisplayBrightness,
                .decreaseDisplayBrightness,
                .rewindYouTubeFiveSeconds,
                .zoomIn,
                .zoomOut,
                .moveToSpaceRight,
                .moveToSpaceLeft,
            ]
        )
        XCTAssertEqual(coordinator.page, .modes)
    }

    func testNativeKarabinerUtilityUpdatesTheHUDWithoutSynthesizingASecondAction() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var appSynthesizedActions: [ModeUtilityAction] = []
        coordinator.onUtilityAction = { _, action in
            appSynthesizedActions.append(action)
            return true
        }

        coordinator.enter(source: .corsair)
        coordinator.handle(
            .init(
                action: .selectNative,
                source: .corsair,
                physicalCell: .brightnessIncrease,
                phase: .press
            )
        )

        XCTAssertTrue(appSynthesizedActions.isEmpty)
        XCTAssertEqual(hud.snapshots.last?.selection?.title, "Brightness Up")
    }

    func testCellSevenSelectsKeypadAndForwardsBothInputPhases() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var inputs: [(MouseSource, PhysicalCell, ModePickerCommand.Phase)] = []
        coordinator.onKeypadModeRequested = { $0 == .corsair }
        coordinator.onKeypadInput = { inputs.append(($0, $1, $2)) }

        coordinator.enter(source: .corsair)
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
        coordinator.onAppSpecificInput = { _, target, cell in
            selected.append((target, cell))
            return true
        }

        coordinator.enter(source: .razer)
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: .appSpecificModeSelector))

        XCTAssertEqual(coordinator.page, .appSelector)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Choose app")

        coordinator.handle(.init(action: .select, source: .razer, physicalCell: AppSpecificTarget.codex.selectorCell))
        coordinator.handle(.init(action: .select, source: .razer, physicalCell: CodexModeAction.togglePin.cell))

        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .codex)
        XCTAssertEqual(coordinator.appSpecificDefinition, CodexMode.definition)
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Codex mode")
        XCTAssertEqual(hud.snapshots.last?.accent, CodexMode.accent)
        XCTAssertEqual(selected.map(\.0), [.codex])
        XCTAssertEqual(selected.map { $0.1.rawValue }, [9])
    }

    func testTopLevelCellTwoFollowsTheFrontmostAppAndCellTenExits() {
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

        coordinator.handle(
            .init(action: .select, source: .razer, physicalCell: .modeExit)
        )

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(lease.activateCount, 1)
        XCTAssertEqual(lease.deactivateCount, 1)
    }

    func testTopLevelCellSixOpensKeysModeAndCellTenExits() {
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

    func testKeysModeMapsNativeArrowsClipboardMediaSpaceBackspaceAndPasswordOnPressOnly() {
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

        XCTAssertEqual(actions.map(\.0), Array(repeating: .corsair, count: 11))
        XCTAssertEqual(
            actions.map(\.1),
            [
                .arrowUp,
                .arrowDown,
                .arrowLeft,
                .arrowRight,
                .copy,
                .paste,
                .nextTrack,
                .insertSpace,
                .pressBackspace,
                .pasteStoredPassword,
                .escape,
            ]
        )
        XCTAssertEqual(KeysModeAction.arrowUp.cell.rawValue, 5)
        XCTAssertEqual(KeysModeAction.arrowDown.cell.rawValue, 4)
        XCTAssertEqual(KeysModeAction.arrowLeft.cell.rawValue, 1)
        XCTAssertEqual(KeysModeAction.arrowRight.cell.rawValue, 7)
        XCTAssertEqual(KeysModeAction.copy.cell.rawValue, 6)
        XCTAssertEqual(KeysModeAction.paste.cell.rawValue, 3)
        XCTAssertEqual(KeysModeAction.nextTrack.cell.rawValue, 9)
        XCTAssertEqual(KeysModeAction.insertSpace.cell.rawValue, 8)
        XCTAssertEqual(KeysModeAction.pressBackspace.cell.rawValue, 11)
        XCTAssertEqual(KeysModeAction.pasteStoredPassword.cell.rawValue, 2)
        XCTAssertEqual(KeysModeAction.escape.cell.rawValue, 12)
        XCTAssertEqual(ModePickerCoordinator.keysLegend[9].actionTitle, "Exit Keys mode")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[5].actionTitle, "Copy")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[7].actionTitle, "Space")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[1].actionTitle, "Paste password")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[2].actionTitle, "Paste")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[8].actionTitle, "Next Track")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[10].actionTitle, "Backspace")
        XCTAssertEqual(ModePickerCoordinator.keysLegend[11].actionTitle, "Escape")
        let arrowAccents = [
            KeysModeAction.arrowUp,
            .arrowDown,
            .arrowLeft,
            .arrowRight,
        ].compactMap { action in
            ModePickerCoordinator.keysLegend.first { $0.cell == action.cell }?.accent
        }
        XCTAssertEqual(Set(arrowAccents).count, 1)
        XCTAssertEqual(KeysModeAction.copy.hudAccent, KeysModeAction.paste.hudAccent)
        XCTAssertNotEqual(KeysModeAction.copy.hudAccent, KeysModeAction.insertSpace.hudAccent)
        XCTAssertNotEqual(KeysModeAction.insertSpace.hudAccent, KeysModeAction.pressBackspace.hudAccent)
        XCTAssertNotEqual(KeysModeAction.pressBackspace.hudAccent, KeysModeAction.pasteStoredPassword.hudAccent)
    }

    func testRazerMirrorsOnlyTheHorizontalArrowMeanings() {
        XCTAssertEqual(KeysModeAction.action(for: PhysicalCell(rawValue: 1)!, source: .corsair), .arrowLeft)
        XCTAssertEqual(KeysModeAction.action(for: PhysicalCell(rawValue: 7)!, source: .corsair), .arrowRight)
        XCTAssertEqual(KeysModeAction.action(for: PhysicalCell(rawValue: 1)!, source: .razer), .arrowRight)
        XCTAssertEqual(KeysModeAction.action(for: PhysicalCell(rawValue: 7)!, source: .razer), .arrowLeft)
        XCTAssertEqual(ModePickerCoordinator.keysLegend(for: .razer)[0].actionTitle, "Right Arrow")
        XCTAssertEqual(ModePickerCoordinator.keysLegend(for: .razer)[6].actionTitle, "Left Arrow")
        XCTAssertEqual(ModePickerCoordinator.keysLegend(for: .razer)[2].actionTitle, "Paste")
        XCTAssertEqual(ModePickerCoordinator.keysLegend(for: .razer)[5].actionTitle, "Copy")
    }

    func testModeCardsUseModeColourForBorderAndActionColourForFill() {
        let mode = ScimitarKit.RGBColor(red: 255, green: 92, blue: 0)
        let action = ScimitarKit.RGBColor(red: 82, green: 138, blue: 255)
        let colors = ModeHUDCardColors(modeAccent: mode, actionAccent: action)

        XCTAssertEqual(colors.border, mode)
        XCTAssertEqual(colors.fill, action)
        XCTAssertEqual(colors.foreground, .white)
    }

    func testModeNavigationUsesDestinationColourAndStrongerBorder() {
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
        XCTAssertEqual(colors.fill, action)
        XCTAssertGreaterThan(navigation.lineWidth, ordinary.lineWidth)
        XCTAssertGreaterThan(selected.lineWidth, navigation.lineWidth)
        XCTAssertGreaterThan(navigation.opacity, ordinary.opacity)
    }

    func testEveryCurrentModeEntryAdvertisesItsDestinationAccent() {
        XCTAssertEqual(
            ModePickerCoordinator.modesLegend[PhysicalCell.keypadModeSelector.rawValue - 1]
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
        XCTAssertTrue(
            ModePickerCoordinator.modesLegend
                .filter { ![.keypadModeSelector, .keysModeSelector, .appSpecificModeSelector].contains($0.cell) }
                .allSatisfy { $0.destinationModeAccent == nil }
        )
        for target in AppSpecificTarget.allCases {
            let item = AppSpecificMode.selectorDefinition.legend.first { $0.cell == target.selectorCell }
            XCTAssertEqual(item?.destinationModeAccent, target.accent)
        }
    }

    func testBoldCardsStayOpaqueAndChooseReadableForeground() {
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

        XCTAssertEqual(brightColors.fill, bright)
        XCTAssertEqual(brightColors.foreground, RGBColor(red: 18, green: 22, blue: 30))
        XCTAssertEqual(darkColors.fill, dark)
        XCTAssertEqual(darkColors.foreground, .white)
        XCTAssertTrue(ModeHUDPresentationStyle.boldOpaque.requiresOpaqueWindow)
        XCTAssertFalse(ModeHUDPresentationStyle.neutral.requiresOpaqueWindow)
    }

    func testAppModeUsesTheSameBoldOpaqueTreatmentAsOtherModes() {
        let saturated = ChromeMode.accent
        let colors = ModeHUDCardColors(
            modeAccent: saturated,
            actionAccent: saturated,
            presentationStyle: .boldOpaque
        )

        XCTAssertEqual(colors.border, saturated)
        XCTAssertEqual(colors.fill, saturated)
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
            AppSpecificTarget.allCases.map(\.displayName),
            ["Codex", "Chrome", "VS Code"]
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

    func testManualAppSelectionDoesNotRetargetWhenTheFrontmostAppChanges() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)

        coordinator.enterAppSelector(source: .corsair)
        coordinator.handle(.init(
            action: .select,
            source: .corsair,
            physicalCell: AppSpecificTarget.codex.selectorCell
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

    func testCodexChildCellTwelvePerformsReasoningEffortInsteadOfReturningToSelector() {
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(hud: hud)
        var selected: [(AppSpecificTarget, PhysicalCell)] = []
        coordinator.onAppSpecificInput = { _, target, cell in
            selected.append((target, cell))
            return target == .codex && cell == .modePickerEntry
        }

        coordinator.enterAppSelector(source: .corsair)
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: AppSpecificTarget.codex.selectorCell))
        coordinator.handle(.init(action: .select, source: .corsair, physicalCell: .modePickerEntry))

        XCTAssertTrue(coordinator.isActive)
        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .codex)
        XCTAssertEqual(selected.map(\.0), [.codex])
        XCTAssertEqual(selected.map(\.1), [.modePickerEntry])
        XCTAssertEqual(hud.snapshots.last?.modeTitle, "Codex mode")
        XCTAssertEqual(hud.snapshots.last?.selection?.title, "Reasoning effort up")
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
                coordinator.enter(source: .corsair)
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
            AppSpecificMode.selectorAccent,
            CodexMode.accent,
            ChromeMode.accent,
            AppSpecificTarget.vsCode.accent,
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

    func testCodexModePinsTheRequestedActionsWithCellTenExitAndNoAppChoiceCard() {
        XCTAssertEqual(CodexModeAction.newTask.cell.rawValue, 8)
        XCTAssertEqual(CodexModeAction.togglePin.cell.rawValue, 9)
        XCTAssertEqual(CodexModeAction.toggleMicrophoneMute.cell.rawValue, 1)
        XCTAssertEqual(CodexModeAction.toggleVoiceMode.cell.rawValue, 4)
        XCTAssertEqual(CodexModeAction.toggleVoiceMode.title, "Start voice mode")
        XCTAssertEqual(CodexModeAction.steerQueuedMessage.cell.rawValue, 7)
        XCTAssertEqual(CodexModeAction.pressEnter.cell.rawValue, 6)
        XCTAssertEqual(CodexModeAction.startNewVoiceChat.cell.rawValue, 5)
        XCTAssertEqual(CodexModeAction.increaseReasoningEffort.cell.rawValue, 12)
        XCTAssertEqual(CodexModeAction.decreaseReasoningEffort.cell.rawValue, 11)
        XCTAssertEqual(CodexModeAction.action(for: .modePickerEntry), .increaseReasoningEffort)
        XCTAssertEqual(CodexMode.definition.legend[2].actionTitle, "Spare")
        XCTAssertEqual(CodexMode.definition.legend[9].actionTitle, "Exit Codex mode")
        XCTAssertEqual(CodexMode.definition.legend[11].actionTitle, "Reasoning effort up")
        XCTAssertEqual(CodexMode.definition.legend[10].actionTitle, "Reasoning effort down")
        XCTAssertEqual(CodexMode.definition.legend[11].accent, CodexMode.definition.legend[10].accent)
        XCTAssertNotEqual(CodexMode.definition.legend[11].actionTitle, "Choose another app")
    }

    func testCellThreeNeverHidesAnActiveModeLegend() {
        for page in [ModePickerPage.appSelector, .appSpecific, .keys] {
            let hud = RecordingModeHUDPresenter()
            let coordinator = makeCoordinator(hud: hud)
            switch page {
            case .modes: XCTFail("Utility cell 3 owns Space Left")
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
            }

            XCTAssertEqual(
                hud.snapshots.last?.legend[2].actionTitle,
                page == .keys ? "Paste" : "Spare"
            )

            coordinator.handle(.init(action: .select, source: .razer, physicalCell: .modeHUDToggle))
            XCTAssertTrue(coordinator.isActive)
            XCTAssertTrue(coordinator.isLegendVisible)
            XCTAssertTrue(hud.isVisible)

            coordinator.handle(.init(action: .select, source: .corsair, physicalCell: .modeHUDToggle))
            XCTAssertTrue(coordinator.isLegendVisible)
            XCTAssertTrue(hud.isVisible)
        }
    }

    func testKeysCellTwelveIsEscapeRatherThanUtilityNavigation() {
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
        XCTAssertEqual(keysActions, [.escape])
    }

    func testKeypadFailureExitsInsteadOfLeavingTheKarabinerPageDesynchronized() {
        let lease = RecordingModePickerLease()
        let hud = RecordingModeHUDPresenter()
        let coordinator = makeCoordinator(lease: lease, hud: hud)
        coordinator.onKeypadModeRequested = { _ in false }

        coordinator.enter(source: .corsair)
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

        coordinator.enter(source: .corsair)
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
