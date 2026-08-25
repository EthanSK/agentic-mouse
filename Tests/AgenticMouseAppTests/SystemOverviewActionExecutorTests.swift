@testable import AgenticMouseApp
import CoreGraphics
import ScimitarKit
import XCTest

@MainActor
final class SystemOverviewActionExecutorTests: XCTestCase {
    func testShowDesktopPostsOneFnF11Cycle() {
        var events: [SystemOverviewActionExecutor.KeyEvent] = []
        let executor = SystemOverviewActionExecutor { events = $0; return true }

        guard case .success = executor.perform(.showDesktop) else {
            return XCTFail("Show Desktop should dispatch")
        }
        XCTAssertEqual(events.map(\.keyCode), [103, 103])
        XCTAssertEqual(events.map(\.flags), [[.maskSecondaryFn], [.maskSecondaryFn]])
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        XCTAssertEqual(events.map(\.timestampOffset), [0, 0.020])
    }

    func testMissionControlPostsThisMacsEnabledControlFnUpCycle() {
        var events: [SystemOverviewActionExecutor.KeyEvent] = []
        let executor = SystemOverviewActionExecutor { events = $0; return true }

        guard case .success = executor.perform(.missionControl) else {
            return XCTFail("Mission Control should dispatch")
        }
        XCTAssertEqual(events.map(\.keyCode), [59, 126, 126, 59])
        XCTAssertEqual(
            events.map(\.flags),
            [
                [.maskControl],
                [.maskControl, .maskSecondaryFn],
                [.maskControl, .maskSecondaryFn],
                [],
            ]
        )
        XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
    }

    func testApplicationWindowsPostsThisMacsEnabledControlFnDownCycle() {
        var events: [SystemOverviewActionExecutor.KeyEvent] = []
        let executor = SystemOverviewActionExecutor { events = $0; return true }

        guard case .success = executor.perform(.showApplicationWindows) else {
            return XCTFail("Application Windows should dispatch")
        }
        XCTAssertEqual(events.map(\.keyCode), [59, 125, 125, 59])
        XCTAssertEqual(
            events.map(\.flags),
            [
                [.maskControl],
                [.maskControl, .maskSecondaryFn],
                [.maskControl, .maskSecondaryFn],
                [],
            ]
        )
        XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
    }

    func testFailedEventCreationIsReported() {
        let executor = SystemOverviewActionExecutor { _ in false }

        guard case .failure(.eventCreationFailed) = executor.perform(.showDesktop) else {
            return XCTFail("event creation failure should be surfaced")
        }
    }

    func testMissingAccessibilityFailsBeforePosting() {
        var posted = false
        let executor = SystemOverviewActionExecutor(
            postChord: { _ in posted = true; return true },
            accessibilityTrusted: { false }
        )

        guard case .failure(.accessibilityPermissionMissing) = executor.perform(.missionControl) else {
            return XCTFail("missing Accessibility must fail closed")
        }
        XCTAssertFalse(posted)
    }
}
