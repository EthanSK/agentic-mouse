@testable import AgenticMouseApp
import ScimitarKit
import XCTest

final class HorizontalScrollOutputTests: XCTestCase {
    func testReadyStageStartsEyesAndAdjacentTapTogglesItUntilOwnerRelease() {
        for source in MouseSource.allCases {
            let monitor = ScrollWheelChordMonitor(
                inputAllowed: { true },
                log: Log(category: "stage-preview-clear-test", sink: RecordingLogSink())
            )
            let modifier = VSCodeStagePreviewModifierState()
            var modeRequests: [Bool] = []
            monitor.onClear = { clearedSource, nextControl in
                if nextControl != .vsCodeStageRange,
                   modifier.clear(source: clearedSource) {
                    modeRequests.append(false)
                }
            }
            monitor.onControlChange = { changedSource, control, _ in
                guard control == .vsCodeStageRange else { return }
                if modifier.activateDefaultForReadyStage(
                    source: changedSource,
                    appSpecificModeActive: false
                ) {
                    modeRequests.append(true)
                }
            }
            monitor.onRelease = { release, _ in
                if release.control == .vsCodeStageRange,
                   modifier.clear(source: release.source, reason: .ownerRelease) {
                    modeRequests.append(false)
                }
            }

            monitor.handle(.init(control: .vsCodeStageRange, source: source, phase: .press))
            XCTAssertTrue(modifier.isActive(for: source), "Ready holds begin in Eyes mode for \(source)")
            XCTAssertEqual(modeRequests, [true], "Default entry changes mode without requesting navigation")

            let toggle = VSCodeStagePreviewModifierCommand(source: source)
            XCTAssertEqual(modifier.handle(toggle, whileStageRangeActive: true), false)
            XCTAssertFalse(modifier.isActive(for: source), "First adjacent tap restores range selection")
            // Releasing the adjacent button sends no state command, so its latch remains off.
            XCTAssertFalse(modifier.isActive(for: source))
            XCTAssertEqual(modifier.handle(toggle, whileStageRangeActive: true), true)
            XCTAssertTrue(modifier.isActive(for: source), "Second tap restores Eyes mode")

            monitor.handle(.init(control: .vsCodeStageRange, source: source, phase: .release))
            XCTAssertFalse(modifier.isActive(for: source), "Owner release clears Eyes")
            XCTAssertNil(monitor.activeControl(for: source))
            XCTAssertEqual(modeRequests, [true], "Better Git owns mode-off after its stage-release transaction")
        }
    }

    func testStageOwnerReleaseClearsLocalEyesBeforeMonitorWithoutSendingModeOff() {
        for source in MouseSource.allCases {
            let monitor = ScrollWheelChordMonitor(
                inputAllowed: { true },
                log: Log(category: "stage-release-order-test", sink: RecordingLogSink())
            )
            let modifier = VSCodeStagePreviewModifierState()
            var offRequests = 0
            monitor.onRelease = { release, _ in
                if modifier.clear(source: release.source, reason: .ownerRelease) { offRequests += 1 }
            }
            monitor.handle(.init(control: .vsCodeStageRange, source: source, phase: .press))
            modifier.setActive(true, for: source)
            if modifier.clear(source: source, reason: .ownerRelease) { offRequests += 1 }
            XCTAssertFalse(modifier.isActive(for: source))
            monitor.handle(.init(control: .vsCodeStageRange, source: source, phase: .release))
            monitor.handle(.init(control: .vsCodeStageRange, source: source, phase: .release))
            monitor.clear(source: source)
            XCTAssertEqual(offRequests, 0, "Neither release path may race Better Git's release shortcut")
            XCTAssertNil(monitor.activeControl(for: source))
        }
    }

    func testAdjacentTapBeforeStageReadinessDoesNotOverrideDefaultEyesMode() {
        let modifier = VSCodeStagePreviewModifierState()
        let earlyTap = VSCodeStagePreviewModifierCommand(source: .corsair)

        XCTAssertNil(modifier.handle(earlyTap, whileStageRangeActive: false))
        XCTAssertFalse(modifier.isActive(for: .corsair))
        modifier.setActive(true, for: .corsair)
        XCTAssertTrue(modifier.isActive(for: .corsair), "The ready transition must still start Eyes")
        XCTAssertEqual(modifier.handle(earlyTap, whileStageRangeActive: true), false)
        XCTAssertFalse(modifier.isActive(for: .corsair))
    }

    func testEnteredVSCodeModeKeepsItsMomentaryPreviewSeparateFromDefaultEyesLatch() {
        let modifier = VSCodeStagePreviewModifierState()

        XCTAssertFalse(modifier.activateDefaultForReadyStage(
            source: .corsair,
            appSpecificModeActive: true
        ))
        XCTAssertFalse(modifier.isActive(for: .corsair))
        XCTAssertTrue(modifier.activateDefaultForReadyStage(
            source: .corsair,
            appSpecificModeActive: false
        ))
        XCTAssertTrue(modifier.isActive(for: .corsair))
    }

    func testTopLevelYouTubePressAndReleaseReachOneWheelFreeRelease() {
        let monitor = ScrollWheelChordMonitor(
            inputAllowed: { true },
            log: Log(category: "wheel-chord-release-test", sink: RecordingLogSink())
        )
        var releases: [WheelChordStateMachine.Release] = []
        monitor.onRelease = { release, _ in releases.append(release) }

        monitor.handle(WheelChordCommand(
            control: .youtubeScrub,
            source: .razer,
            phase: .press
        ))
        monitor.handle(WheelChordCommand(
            control: .youtubeScrub,
            source: .razer,
            phase: .release
        ))

        XCTAssertEqual(
            releases,
            [.init(
                source: .razer,
                control: .youtubeScrub,
                didObserveWheelInput: false
            )]
        )
    }

    func testKeysTracksPressAndReleaseReachOneWheelFreeRelease() {
        let monitor = ScrollWheelChordMonitor(
            inputAllowed: { true },
            log: Log(category: "wheel-chord-release-test", sink: RecordingLogSink())
        )
        var releases: [WheelChordStateMachine.Release] = []
        monitor.onRelease = { release, _ in releases.append(release) }

        monitor.setActive(.mediaTracks, for: .corsair)
        monitor.handle(WheelChordCommand(
            control: .mediaTracks,
            source: .corsair,
            phase: .release
        ))

        XCTAssertEqual(
            releases,
            [.init(
                source: .corsair,
                control: .mediaTracks,
                didObserveWheelInput: false
            )]
        )
    }

    func testStaleTopLevelReleaseDoesNotEndANewerHold() {
        let monitor = ScrollWheelChordMonitor(
            inputAllowed: { true },
            log: Log(category: "wheel-chord-release-test", sink: RecordingLogSink())
        )
        var releases: [WheelChordStateMachine.Release] = []
        monitor.onRelease = { release, _ in releases.append(release) }
        monitor.handle(WheelChordCommand(
            control: .youtubeScrub,
            source: .corsair,
            phase: .press
        ))

        monitor.handle(WheelChordCommand(
            control: .clipboard,
            source: .corsair,
            phase: .release
        ))
        XCTAssertTrue(releases.isEmpty)
        XCTAssertEqual(monitor.activeControl(for: .corsair), .youtubeScrub)

        monitor.handle(WheelChordCommand(
            control: .youtubeScrub,
            source: .corsair,
            phase: .release
        ))
        XCTAssertEqual(releases.count, 1)
    }

    func testNormalFastDefaultEmitsFourHorizontalLinesPerAcceptedRatchet() {
        let lines = AppConfiguration.InputConfiguration.defaultHorizontalScrollLinesPerRatchet

        XCTAssertEqual(lines, 4)
        XCTAssertEqual(
            ScrollWheelChordMonitor.horizontalWheelDelta(.up, linesPerRatchet: lines),
            -4
        )
        XCTAssertEqual(
            ScrollWheelChordMonitor.horizontalWheelDelta(.down, linesPerRatchet: lines),
            4
        )
    }

    func testCustomSensitivityPreservesAcceptedDirection() {
        XCTAssertEqual(
            ScrollWheelChordMonitor.horizontalWheelDelta(.up, linesPerRatchet: 9),
            -9
        )
        XCTAssertEqual(
            ScrollWheelChordMonitor.horizontalWheelDelta(.down, linesPerRatchet: 9),
            9
        )
    }

    func testOutputRejectsUnsanitizedMagnitude() {
        XCTAssertNil(ScrollWheelChordMonitor.horizontalWheelDelta(.up, linesPerRatchet: 0))
        XCTAssertNil(ScrollWheelChordMonitor.horizontalWheelDelta(.down, linesPerRatchet: 13))
    }
}
