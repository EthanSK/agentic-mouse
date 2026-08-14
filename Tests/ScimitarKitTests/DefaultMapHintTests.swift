import Foundation
import XCTest
@testable import ScimitarKit

final class DefaultMapHintCommandTests: XCTestCase {
    func testDecoderAcceptsOnlyTheSourceSpecificToggleCellAndNamespace() throws {
        let corsair = Data(
            #"{"command":"agentic_mouse_default_map_toggle","source":"corsair","physical_cell":12}"#.utf8
        )
        XCTAssertEqual(try DefaultMapHintCommand.decode(corsair), DefaultMapHintCommand(source: .corsair))
        let razer = Data(
            #"{"command":"agentic_mouse_default_map_toggle","source":"razer","physical_cell":12}"#.utf8
        )
        XCTAssertEqual(try DefaultMapHintCommand.decode(razer), DefaultMapHintCommand(source: .razer))

        for payload in [
            #"{"command":"another_command","source":"razer","physical_cell":10}"#,
            #"{"command":"agentic_mouse_default_map_toggle","source":"razer","physical_cell":10}"#,
            #"{"command":"agentic_mouse_default_map_toggle","source":"razer","physical_cell":2}"#,
            #"{"command":"agentic_mouse_default_map_toggle","source":"corsair","physical_cell":10}"#,
            #"{"command":"agentic_mouse_default_map_toggle","source":"unknown","physical_cell":3}"#,
        ] {
            XCTAssertThrowsError(try DefaultMapHintCommand.decode(Data(payload.utf8)))
        }
    }

    func testLegendReflectsTheCurrentTopLevelMapAndExactSource() {
        XCTAssertEqual(DefaultMapLegend.legend.map(\.cell), PhysicalCell.all)
        XCTAssertEqual(DefaultMapLegend.legend[0].actionTitle, "Horizontal scroll left")
        XCTAssertEqual(DefaultMapLegend.legend[2].actionTitle, "Screenshot")
        XCTAssertEqual(DefaultMapLegend.legend[5].actionTitle, "Keys mode")
        XCTAssertEqual(DefaultMapLegend.legend[5].accent, ModePickerCoordinator.keysAccent)
        XCTAssertEqual(DefaultMapLegend.legend[5].destinationModeAccent, ModePickerCoordinator.keysAccent)
        XCTAssertEqual(DefaultMapLegend.legend[1].actionTitle, "App mode")
        XCTAssertEqual(DefaultMapLegend.legend[1].destinationModeAccent, AppSpecificMode.selectorAccent)
        XCTAssertEqual(DefaultMapLegend.legend[8].actionTitle, "App shortcut")
        XCTAssertEqual(DefaultMapLegend.legend[10].actionTitle, "Switch App")
        XCTAssertEqual(DefaultMapLegend.legend[11].actionTitle, "Legend toggle")
        XCTAssertEqual(DefaultMapLegend.legend[11].destinationModeAccent, ModePickerCoordinator.accent)
        XCTAssertEqual(DefaultMapLegend.accent, .white)
        XCTAssertEqual(DefaultMapLegend.legend[0].accent, DefaultMapLegend.legend[3].accent)
        XCTAssertEqual(DefaultMapLegend.legend[4].accent, DefaultMapLegend.legend[7].accent)

        let snapshot = DefaultMapLegend.snapshot(source: .corsair)
        XCTAssertEqual(snapshot.modeTitle, "Default mode")
        XCTAssertEqual(snapshot.footerTitle, "Default mode")
        XCTAssertNil(snapshot.footerHint)
        XCTAssertTrue(snapshot.showsOnAllDisplays)
        XCTAssertEqual(snapshot.accent, .white)
        XCTAssertEqual(snapshot.legend[11].actionTitle, "Legend toggle")
        XCTAssertEqual(snapshot.legend[10].actionTitle, "Switch App")
        XCTAssertEqual(snapshot.legend[2].actionTitle, "Screenshot")
        XCTAssertEqual(snapshot.presentationStyle, .neutral)

        let capturingSnapshot = DefaultMapLegend.snapshot(
            source: .corsair,
            screenshotIsCapturing: true
        )
        XCTAssertEqual(capturingSnapshot.legend[2].actionTitle, "Cancel screenshot")
        XCTAssertEqual(PhysicalCell.defaultMapToggle.printedSide(on: .corsair), 12)
        XCTAssertEqual(PhysicalCell.defaultMapToggle(for: .corsair).printedSide(on: .corsair), 12)
        XCTAssertEqual(PhysicalCell.defaultMapToggle(for: .razer).printedSide(on: .razer), 10)
        XCTAssertEqual(PhysicalCell.screenshotToggle.printedSide(on: .corsair), 3)
        XCTAssertEqual(PhysicalCell.screenshotToggle.printedSide(on: .razer), 1)
        XCTAssertEqual(PhysicalCell.modePickerEntry.printedSide(on: .corsair), 12)
        XCTAssertEqual(PhysicalCell.modePickerEntry.printedSide(on: .razer), 10)

        let razerSnapshot = DefaultMapLegend.snapshot(source: .razer)
        XCTAssertEqual(razerSnapshot.source, .razer)
        XCTAssertEqual(razerSnapshot.legend[11].actionTitle, "Legend toggle")
        XCTAssertEqual(razerSnapshot.legend[10].actionTitle, "Switch App")
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
    private var isScreenshotCapturing = false
    private var frontmostAppContext: FrontmostAppModeContext?
    private var coordinator: DefaultMapHintCoordinator!

    override func setUp() {
        super.setUp()
        dismissScheduler = ManualTickScheduler()
        hud = RecordingModeHUDPresenter()
        isAvailable = true
        isScreenshotCapturing = false
        frontmostAppContext = nil
        coordinator = makeCoordinator()
    }

    func testSameMouseLegendPressTogglesThePersistentMap() {
        coordinator.handleToggle(source: .corsair)
        XCTAssertTrue(coordinator.isShowingHint)
        XCTAssertEqual(coordinator.source, .corsair)
        XCTAssertTrue(hud.isVisible)
        XCTAssertEqual(hud.snapshots.last?.legend[11].actionTitle, "Legend toggle")

        dismissScheduler.fire()
        XCTAssertTrue(coordinator.isShowingHint, "duration zero stays visible indefinitely")

        coordinator.handleToggle(source: .corsair)
        XCTAssertFalse(coordinator.isShowingHint)
        XCTAssertFalse(hud.isVisible)
    }

    func testVisibleMapRefreshesKnownScreenshotToggleCopy() {
        coordinator.handleToggle(source: .corsair)
        XCTAssertEqual(hud.snapshots.last?.legend[2].actionTitle, "Screenshot")

        isScreenshotCapturing = true
        coordinator.refresh()
        XCTAssertEqual(hud.snapshots.last?.legend[2].actionTitle, "Cancel screenshot")

        isScreenshotCapturing = false
        coordinator.refresh()
        XCTAssertEqual(hud.snapshots.last?.legend[2].actionTitle, "Screenshot")
    }

    func testVisibleDefaultMapTracksFrontmostAppNameAndPastelIdentity() {
        frontmostAppContext = FrontmostAppModeContext(
            target: .chrome,
            displayName: "Google Chrome",
            bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier
        )
        coordinator.handleToggle(source: .corsair)

        XCTAssertEqual(hud.snapshots.last?.legend[1].actionTitle, "Chrome mode")
        XCTAssertEqual(
            hud.snapshots.last?.legend[1].accent,
            ChromeMode.accent.blended(with: .white, amount: 0.58)
        )
        XCTAssertEqual(hud.snapshots.last?.legend[1].destinationModeAccent, ChromeMode.accent)

        frontmostAppContext = FrontmostAppModeContext(
            target: .vsCode,
            displayName: "Visual Studio Code",
            bundleIdentifier: AppSpecificTarget.vsCode.bundleIdentifier
        )
        coordinator.refresh()

        XCTAssertEqual(hud.snapshots.last?.legend[1].actionTitle, "VS Code mode")
        XCTAssertTrue(coordinator.isShowingHint)
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
            isScreenshotCapturing: { [weak self] in self?.isScreenshotCapturing == true },
            frontmostAppContext: { [weak self] in self?.frontmostAppContext },
            displayDuration: displayDuration
        )
    }
}
