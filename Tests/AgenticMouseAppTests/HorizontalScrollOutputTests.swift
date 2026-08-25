@testable import AgenticMouseApp
import ScimitarKit
import XCTest

final class HorizontalScrollOutputTests: XCTestCase {
    func testTopLevelYouTubePressAndReleaseReachOneWheelFreeRelease() {
        let monitor = ScrollWheelChordMonitor(
            inputAllowed: { true },
            log: Log(category: "wheel-chord-release-test", sink: RecordingLogSink())
        )
        var releases: [WheelChordStateMachine.Release] = []
        monitor.onRelease = { releases.append($0) }

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

    func testStaleTopLevelReleaseDoesNotEndANewerHold() {
        let monitor = ScrollWheelChordMonitor(
            inputAllowed: { true },
            log: Log(category: "wheel-chord-release-test", sink: RecordingLogSink())
        )
        var releases: [WheelChordStateMachine.Release] = []
        monitor.onRelease = { releases.append($0) }
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
