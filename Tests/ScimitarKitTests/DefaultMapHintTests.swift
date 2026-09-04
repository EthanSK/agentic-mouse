import Foundation
import XCTest
@testable import ScimitarKit

final class DefaultMapHintCommandTests: XCTestCase {
    func testDecoderAcceptsOnlyTheSourceSpecificToggleCellAndNamespace() throws {
        let corsair = Data(
            #"{"command":"agentic_mouse_default_map_toggle","source":"corsair","physical_cell":10}"#.utf8
        )
        XCTAssertEqual(try DefaultMapHintCommand.decode(corsair), DefaultMapHintCommand(source: .corsair))
        let razer = Data(
            #"{"command":"agentic_mouse_default_map_toggle","source":"razer","physical_cell":10}"#.utf8
        )
        XCTAssertEqual(try DefaultMapHintCommand.decode(razer), DefaultMapHintCommand(source: .razer))

        for payload in [
            #"{"command":"another_command","source":"razer","physical_cell":10}"#,
            #"{"command":"agentic_mouse_default_map_toggle","source":"razer","physical_cell":12}"#,
            #"{"command":"agentic_mouse_default_map_toggle","source":"razer","physical_cell":2}"#,
            #"{"command":"agentic_mouse_default_map_toggle","source":"corsair","physical_cell":12}"#,
            #"{"command":"agentic_mouse_default_map_toggle","source":"unknown","physical_cell":3}"#,
        ] {
            XCTAssertThrowsError(try DefaultMapHintCommand.decode(Data(payload.utf8)))
        }
    }

    func testYouTubeRewindDecoderAcceptsOnlyTopLevelCellSixAndExactNamespace() throws {
        for source in [MouseSource.corsair, .razer] {
            let payload = Data(
                #"{"command":"agentic_mouse_youtube_rewind_five_seconds","source":"\#(source.rawValue)","physical_cell":6}"#.utf8
            )
            XCTAssertEqual(
                try YouTubeRewindCommand.decode(payload),
                YouTubeRewindCommand(source: source)
            )
        }

        for payload in [
            #"{"command":"another_command","source":"razer","physical_cell":6}"#,
            #"{"command":"agentic_mouse_youtube_rewind_five_seconds","source":"razer","physical_cell":8}"#,
            #"{"command":"agentic_mouse_youtube_rewind_five_seconds","source":"unknown","physical_cell":6}"#,
        ] {
            XCTAssertThrowsError(try YouTubeRewindCommand.decode(Data(payload.utf8)))
        }
    }

    func testYouTubeVolumeModifierDecoderAcceptsOnlyTheExactLifecycleCommand() throws {
        for source in MouseSource.allCases {
            for phase in [ModePickerCommand.Phase.press, .release] {
                let command = YouTubeVolumeModifierCommand(source: source, phase: phase)
                XCTAssertEqual(
                    try YouTubeVolumeModifierCommand.decode(JSONEncoder().encode(command)),
                    command
                )
            }
        }

        for payload in [
            #"{"command":"another_command","source":"corsair","phase":"press"}"#,
            #"{"command":"agentic_mouse_youtube_volume_modifier","source":"unknown","phase":"press"}"#,
            #"{"command":"agentic_mouse_youtube_volume_modifier","source":"razer","phase":"tap"}"#,
        ] {
            XCTAssertThrowsError(try YouTubeVolumeModifierCommand.decode(Data(payload.utf8)))
        }
        XCTAssertEqual(YouTubeVolumeModifierCommand.triggerCell, PhysicalCell(rawValue: 5))
    }

    func testLegendReflectsTheCurrentTopLevelMapAndExactSource() {
        XCTAssertEqual(DefaultMapLegend.legend.map(\.cell), PhysicalCell.all)
        XCTAssertEqual(DefaultMapLegend.legend[0].actionTitle, "Horizontal Scroll + Wheel")
        XCTAssertEqual(DefaultMapLegend.legend[3].actionTitle, "Copy / Paste + Wheel")
        XCTAssertEqual(DefaultMapLegend.legend[2].actionTitle, "Screenshot")
        XCTAssertEqual(DefaultMapLegend.legend[1].actionTitle, "App mode")
        XCTAssertEqual(DefaultMapLegend.legend[1].destinationModeAccent, AppSpecificMode.selectorAccent)
        XCTAssertEqual(DefaultMapLegend.legend[5].actionTitle, "YouTube Scrub + Wheel")
        XCTAssertEqual(DefaultMapLegend.legend[4].actionTitle, "Forward · Hold + 6 for Volume")
        XCTAssertEqual(DefaultMapLegend.legend[8].actionTitle, "Keys mode")
        XCTAssertEqual(DefaultMapLegend.legend[8].accent, ModePickerCoordinator.keysAccent)
        XCTAssertEqual(DefaultMapLegend.legend[8].destinationModeAccent, ModePickerCoordinator.keysAccent)
        XCTAssertEqual(DefaultMapLegend.legend[10].actionTitle, "Switch App")
        XCTAssertEqual(DefaultMapLegend.legend[9].actionTitle, "Legend toggle")
        XCTAssertEqual(DefaultMapLegend.legend[11].actionTitle, "Utility modes")
        XCTAssertEqual(DefaultMapLegend.legend[11].destinationModeAccent, ModePickerCoordinator.accent)
        XCTAssertEqual(DefaultMapLegend.accent, .white)
        XCTAssertEqual(DefaultMapLegend.legend[0].accent, ModeHUDActionFamilyPalette.horizontalScroll)
        XCTAssertEqual(DefaultMapLegend.legend[3].accent, ModeHUDActionFamilyPalette.clipboard)
        XCTAssertEqual(DefaultMapLegend.legend[6].accent, ModeHUDActionFamilyPalette.enter)
        XCTAssertEqual(DefaultMapLegend.legend[9].accent, ModeHUDActionFamilyPalette.legendToggle)
        XCTAssertNotEqual(DefaultMapLegend.legend[6].accent, DefaultMapLegend.legend[3].accent)
        XCTAssertNotEqual(DefaultMapLegend.legend[9].accent, DefaultMapLegend.legend[3].accent)
        XCTAssertNotEqual(DefaultMapLegend.legend[3].accent, DefaultMapLegend.legend[0].accent)
        XCTAssertEqual(DefaultMapLegend.legend[4].accent, DefaultMapLegend.legend[7].accent)

        let snapshot = DefaultMapLegend.snapshot(source: .corsair)
        XCTAssertEqual(snapshot.modeTitle, "Default mode")
        XCTAssertEqual(snapshot.footerTitle, "Default mode")
        XCTAssertNil(snapshot.footerHint)
        XCTAssertTrue(snapshot.showsOnAllDisplays)
        XCTAssertEqual(snapshot.accent, .white)
        XCTAssertEqual(snapshot.legend[9].actionTitle, "Legend toggle")
        XCTAssertEqual(snapshot.legend[11].actionTitle, "Utility modes")
        XCTAssertEqual(snapshot.legend[10].actionTitle, "Switch App")
        XCTAssertEqual(snapshot.legend[2].actionTitle, "Screenshot")
        XCTAssertEqual(snapshot.legend[2].controlStatus, .normal)
        XCTAssertEqual(snapshot.legend[2].printedControlLabel(on: .corsair), "Corsair 3")
        XCTAssertEqual(snapshot.presentationStyle, .neutral)

        let volumeSnapshot = DefaultMapLegend.snapshot(
            source: .corsair,
            youtubeVolumeModifierActive: true
        )
        XCTAssertEqual(volumeSnapshot.legend[4].actionTitle, "YouTube Volume held")
        XCTAssertEqual(volumeSnapshot.legend[5].actionTitle, "YouTube Volume + Wheel")
        XCTAssertEqual(volumeSnapshot.legend[4].accent, DefaultMapLegend.legend[5].accent)
        XCTAssertEqual(volumeSnapshot.legend[5].accent, DefaultMapLegend.legend[5].accent)

        let capturingSnapshot = DefaultMapLegend.snapshot(
            source: .corsair,
            screenshotActionState: .capturing
        )
        XCTAssertEqual(capturingSnapshot.legend[2].actionTitle, "Cancel screenshot")
        XCTAssertEqual(PhysicalCell.defaultMapToggle.printedSide(on: .corsair), 10)
        XCTAssertEqual(PhysicalCell.defaultMapToggle(for: .corsair).printedSide(on: .corsair), 10)
        XCTAssertEqual(PhysicalCell.defaultMapToggle(for: .razer).printedSide(on: .razer), 12)
        XCTAssertEqual(PhysicalCell.screenshotToggle.printedSide(on: .corsair), 3)
        XCTAssertEqual(PhysicalCell.screenshotToggle.printedSide(on: .razer), 1)
        XCTAssertEqual(PhysicalCell.modePickerEntry.printedSide(on: .corsair), 12)
        XCTAssertEqual(PhysicalCell.modePickerEntry.printedSide(on: .razer), 10)

        let razerSnapshot = DefaultMapLegend.snapshot(source: .razer)
        XCTAssertEqual(razerSnapshot.source, .razer)
        XCTAssertEqual(razerSnapshot.legend[4].actionTitle, "Forward · Hold + 4 for Volume")
        XCTAssertEqual(razerSnapshot.legend[9].actionTitle, "Legend toggle")
        XCTAssertEqual(razerSnapshot.legend[11].actionTitle, "Utility modes")
        XCTAssertEqual(razerSnapshot.legend[10].actionTitle, "Switch App")
        XCTAssertEqual(razerSnapshot.legend[2].printedControlLabel(on: .razer), "Razer 1")
        XCTAssertEqual(ModeHUDCopy.referenceHeader(for: razerSnapshot.source), "RAZER BUTTON MAP")
    }

    func testReferenceHUDUsesPlainButtonMapCopy() {
        XCTAssertEqual(ModeHUDCopy.referenceHeader(for: .corsair), "CORSAIR BUTTON MAP")
        XCTAssertEqual(ModeHUDCopy.referenceHeader(for: .razer), "RAZER BUTTON MAP")
        XCTAssertEqual(ModeHUDCopy.referenceStatus, "BUTTON MAP")
        XCTAssertFalse(ModeHUDCopy.referenceHeader(for: .corsair).lowercased().contains("passive"))
        XCTAssertFalse(ModeHUDCopy.referenceStatus.lowercased().contains("reminder"))
    }

    func testPhysicalCellsRenderBothPrintedCrosswalks() {
        let first = PhysicalCell(rawValue: 1)!
        let third = PhysicalCell(rawValue: 3)!
        XCTAssertEqual(first.displayLabel(on: .corsair), "Corsair 1")
        XCTAssertEqual(first.displayLabel(on: .razer), "Razer 3")
        XCTAssertEqual(third.displayLabel(on: .corsair), "Corsair 3")
        XCTAssertEqual(third.displayLabel(on: .razer), "Razer 1")
        XCTAssertEqual(
            PhysicalCell.displayRowsTopToBottom.map { $0.map(\.rawValue) },
            [[3, 6, 9, 12], [2, 5, 8, 11], [1, 4, 7, 10]]
        )
        XCTAssertEqual(
            PhysicalCell.displayRowsTopToBottom(for: .razer).map { $0.map(\.rawValue) },
            [[12, 9, 6, 3], [11, 8, 5, 2], [10, 7, 4, 1]]
        )
    }
}

final class DefaultMapHintCoordinatorTests: XCTestCase {
    private var dismissScheduler: ManualTickScheduler!
    private var hud: RecordingModeHUDPresenter!
    private var isAvailable = true
    private var screenshotActionState = ScreenshotActionPresentationState.idle
    private var frontmostAppContext: FrontmostAppModeContext?
    private var coordinator: DefaultMapHintCoordinator!

    override func setUp() {
        super.setUp()
        dismissScheduler = ManualTickScheduler()
        hud = RecordingModeHUDPresenter()
        isAvailable = true
        screenshotActionState = .idle
        frontmostAppContext = nil
        coordinator = makeCoordinator()
    }

    func testSameMouseLegendPressTogglesThePersistentMap() {
        coordinator.handleToggle(source: .corsair)
        XCTAssertTrue(coordinator.isShowingHint)
        XCTAssertEqual(coordinator.source, .corsair)
        XCTAssertTrue(hud.isVisible)
        XCTAssertEqual(hud.snapshots.last?.legend[9].actionTitle, "Legend toggle")

        dismissScheduler.fire()
        XCTAssertTrue(coordinator.isShowingHint, "duration zero stays visible indefinitely")

        coordinator.handleToggle(source: .corsair)
        XCTAssertFalse(coordinator.isShowingHint)
        XCTAssertFalse(hud.isVisible)
    }

    func testVisibleMapRefreshesKnownScreenshotToggleCopy() {
        coordinator.handleToggle(source: .corsair)
        XCTAssertEqual(hud.snapshots.last?.legend[2].actionTitle, "Screenshot")

        screenshotActionState = .capturing
        coordinator.refresh()
        XCTAssertEqual(hud.snapshots.last?.legend[2].actionTitle, "Cancel screenshot")

        screenshotActionState = .copying
        coordinator.refresh()
        XCTAssertEqual(hud.snapshots.last?.legend[2].actionTitle, "Copying screenshot…")

        screenshotActionState = .pasteReady
        coordinator.refresh()
        XCTAssertEqual(hud.snapshots.last?.legend[2].actionTitle, "Screenshot · 2× Paste")

        screenshotActionState = .idle
        coordinator.refresh()
        XCTAssertEqual(hud.snapshots.last?.legend[2].actionTitle, "Screenshot")
    }

    func testVisibleDefaultMapTracksFrontmostAppNameAndExactIconIdentity() {
        let exactPath = "/Applications/Google Chrome.app"
        frontmostAppContext = FrontmostAppModeContext(
            target: .chrome,
            displayName: "Google Chrome",
            bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier,
            applicationPath: exactPath
        )
        coordinator.handleToggle(source: .corsair)

        XCTAssertEqual(hud.snapshots.last?.legend[1].actionTitle, "Chrome mode")
        XCTAssertEqual(hud.snapshots.last?.legend[5].actionTitle, "YouTube Scrub + Wheel")
        XCTAssertEqual(
            hud.snapshots.last?.legend[1].accent,
            ChromeMode.accent.blended(with: .white, amount: 0.58)
        )
        XCTAssertEqual(hud.snapshots.last?.legend[1].destinationModeAccent, ChromeMode.accent)
        XCTAssertEqual(
            hud.snapshots.last?.legend[1].appBackdrop,
            ModeHUDAppBackdrop(
                bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier,
                applicationPath: exactPath
            )
        )
        XCTAssertNil(hud.snapshots.last?.legend[0].appBackdrop)

        frontmostAppContext = FrontmostAppModeContext(
            target: .vsCode,
            displayName: "Visual Studio Code",
            bundleIdentifier: AppSpecificTarget.vsCode.bundleIdentifier
        )
        coordinator.refresh()

        XCTAssertEqual(hud.snapshots.last?.legend[1].actionTitle, "VS Code mode")
        XCTAssertEqual(hud.snapshots.last?.legend[3].actionTitle, "Copy / Paste · Stage + Previous after 5")
        XCTAssertEqual(hud.snapshots.last?.legend[4].actionTitle, "Previous Change · Hold + 4 to Stage")
        XCTAssertEqual(hud.snapshots.last?.legend[6].actionTitle, "Enter · Stage + Next after 8")
        XCTAssertEqual(hud.snapshots.last?.legend[7].actionTitle, "Next Change · Hold + 7 to Stage")
        XCTAssertEqual(
            hud.snapshots.last?.legend[1].appBackdrop,
            ModeHUDAppBackdrop(bundleIdentifier: AppSpecificTarget.vsCode.bundleIdentifier)
        )
        XCTAssertEqual(hud.snapshots.last?.legend[5].actionTitle, "YouTube Scrub + Wheel")
        XCTAssertTrue(coordinator.isShowingHint)

        let razerSnapshot = DefaultMapLegend.snapshot(
            source: .razer,
            frontmostAppContext: frontmostAppContext
        )
        XCTAssertEqual(razerSnapshot.legend[3].actionTitle, "Copy / Paste · Stage + Previous after 5")
        XCTAssertEqual(razerSnapshot.legend[4].actionTitle, "Previous Change · Hold + 6 to Stage")
        XCTAssertEqual(razerSnapshot.legend[6].actionTitle, "Enter · Stage + Next after 8")
        XCTAssertEqual(razerSnapshot.legend[7].actionTitle, "Next Change · Hold + 9 to Stage")
    }

    func testYouTubeScrubCopyDoesNotDependOnFrontmostAppSupport() {
        frontmostAppContext = FrontmostAppModeContext(
            target: nil,
            displayName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit"
        )
        coordinator.handleToggle(source: .corsair)

        XCTAssertEqual(hud.snapshots.last?.legend[5].actionTitle, "YouTube Scrub + Wheel")
    }

    func testCoordinatorIgnoresCommandsOwnedByTheOtherMouse() {
        coordinator.handleToggle(source: .corsair)
        coordinator.handleToggle(source: .razer)

        XCTAssertTrue(coordinator.isShowingHint)
        XCTAssertTrue(hud.isVisible)
        XCTAssertEqual(coordinator.source, .corsair)
        XCTAssertEqual(hud.snapshots.last?.source, .corsair)

        coordinator.handleToggle(source: .corsair)

        XCTAssertFalse(coordinator.isShowingHint)
        XCTAssertFalse(hud.isVisible)
        XCTAssertNil(coordinator.source)
    }

    func testModeSuspendsAndRestoresOnlyAPreviouslyVisibleMap() {
        XCTAssertNil(coordinator.suspendForMode())
        coordinator.handleToggle(source: .corsair)

        let source = coordinator.suspendForMode()
        XCTAssertEqual(source, .corsair)
        XCTAssertFalse(hud.isVisible)
        XCTAssertFalse(coordinator.isShowingHint)

        coordinator.restoreAfterMode(source: source!)
        XCTAssertTrue(hud.isVisible)
        XCTAssertTrue(coordinator.isShowingHint)
        XCTAssertEqual(coordinator.source, .corsair)
    }

    func testPositiveLegacyDurationStillAutoHides() {
        coordinator = makeCoordinator(displayDuration: 6)
        coordinator.handleToggle(source: .corsair)
        XCTAssertTrue(hud.isVisible)
        dismissScheduler.fire()
        XCTAssertFalse(coordinator.isShowingHint)
        XCTAssertFalse(hud.isVisible)
    }

    func testHiddenDefaultLegendNeverOpensForAWheelTrace() {
        coordinator.flashWheelDiagnostic(
            source: .corsair,
            message: "SPACES B1 ARMED · WAITING FOR WHEEL"
        )

        XCTAssertFalse(hud.isVisible)
        XCTAssertFalse(coordinator.isShowingHint)
        XCTAssertTrue(hud.snapshots.isEmpty)
        XCTAssertTrue(hud.feedback.isEmpty)
        XCTAssertFalse(dismissScheduler.isRunning)
    }

    func testWheelTraceNeverAutoHidesAnAlreadyPersistentLegend() {
        coordinator.handleToggle(source: .corsair)
        coordinator.flashWheelDiagnostic(
            source: .corsair,
            message: "CTRL-FN-RIGHT POSTED · WAITING FOR MACOS"
        )

        XCTAssertTrue(coordinator.isShowingHint)
        XCTAssertEqual(
            hud.feedback.last,
            ModeHUDFeedback(
                message: "CTRL-FN-RIGHT POSTED · WAITING FOR MACOS",
                tone: .informational
            )
        )
        XCTAssertFalse(dismissScheduler.isRunning)
        dismissScheduler.fire()
        XCTAssertTrue(hud.isVisible)
        XCTAssertTrue(coordinator.isShowingHint)
    }

    func testWheelActionFeedbackUsesItsTruthfulToneOnAnOpenLegend() {
        coordinator.handleToggle(source: .corsair)
        let feedback = ModeHUDFeedback(
            message: "Scroll Right sent · 2 ratchets",
            tone: .informational
        )

        coordinator.flashWheelFeedback(source: .corsair, feedback: feedback)

        XCTAssertEqual(hud.feedback.last, feedback)
        XCTAssertTrue(hud.isVisible)
        XCTAssertTrue(coordinator.isShowingHint)
        XCTAssertFalse(dismissScheduler.isRunning)
    }

    func testWheelActionFeedbackNeverOpensAHiddenDefaultLegend() {
        coordinator.flashWheelFeedback(
            source: .corsair,
            feedback: ModeHUDFeedback(
                message: "Scroll Right sent · 1 ratchet",
                tone: .informational
            )
        )

        XCTAssertFalse(hud.isVisible)
        XCTAssertFalse(coordinator.isShowingHint)
        XCTAssertTrue(hud.feedback.isEmpty)
    }

    func testTopLevelActionProblemNeverOpensAHiddenDefaultLegend() {
        coordinator.flashActionProblem(
            source: .corsair,
            message: "Screenshot could not be copied"
        )

        XCTAssertFalse(hud.isVisible)
        XCTAssertFalse(coordinator.isShowingHint)
        XCTAssertTrue(hud.problems.isEmpty)
    }

    func testTopLevelActionProblemUsesAnAlreadyVisibleDefaultLegend() {
        coordinator.handleToggle(source: .corsair)

        coordinator.flashActionProblem(
            source: .corsair,
            message: "Screenshot could not be copied"
        )

        XCTAssertEqual(hud.problems, ["Screenshot could not be copied"])
        XCTAssertTrue(hud.isVisible)
        XCTAssertTrue(coordinator.isShowingHint)
    }

    func testIgnoredHiddenWheelTraceDoesNotChangeTheNextLegendToggle() {
        coordinator.flashWheelDiagnostic(source: .corsair, message: "SPACES B1 ARMED")
        XCTAssertFalse(hud.isVisible)
        XCTAssertTrue(hud.feedback.isEmpty)

        coordinator.handleToggle(source: .corsair)

        XCTAssertTrue(coordinator.isShowingHint)
        XCTAssertTrue(hud.isVisible)
        XCTAssertFalse(dismissScheduler.isRunning)
        XCTAssertTrue(hud.feedback.isEmpty)
    }

    func testWheelTraceDoesNotLeakIntoAnActiveModePresenter() {
        isAvailable = false
        coordinator.flashWheelDiagnostic(source: .corsair, message: "SPACES B1 ARMED")

        XCTAssertFalse(hud.isVisible)
        XCTAssertTrue(hud.snapshots.isEmpty)
        XCTAssertTrue(hud.feedback.isEmpty)
    }

    func testUnavailableGridIgnoresTheParallelCommand() {
        isAvailable = false
        coordinator.handleToggle(source: .corsair)
        XCTAssertFalse(coordinator.isShowingHint)
        XCTAssertFalse(hud.isVisible)
    }

    func testCancelAndShutdownAreIdempotent() {
        coordinator.handleToggle(source: .corsair)
        coordinator.cancel()
        coordinator.cancel()
        coordinator.shutdown()
        XCTAssertFalse(coordinator.isShowingHint)
        XCTAssertFalse(hud.isVisible)
    }

    private func makeCoordinator(displayDuration: TimeInterval = 0) -> DefaultMapHintCoordinator {
        DefaultMapHintCoordinator(
            hud: hud,
            dismissScheduler: dismissScheduler,
            log: Log(category: "test", sink: NullLogSink()),
            source: .corsair,
            isAvailable: { [weak self] in self?.isAvailable == true },
            screenshotActionState: { [weak self] in self?.screenshotActionState ?? .idle },
            frontmostAppContext: { [weak self] in self?.frontmostAppContext },
            displayDuration: displayDuration
        )
    }
}
