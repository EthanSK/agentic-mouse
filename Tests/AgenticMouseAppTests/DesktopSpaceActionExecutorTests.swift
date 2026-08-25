@testable import AgenticMouseApp
import CoreGraphics
import ScimitarKit
import XCTest

@MainActor
final class DesktopSpaceActionExecutorTests: XCTestCase {
    func testSpaceLeftPostsOneControlLeftCycle() {
        var events: [DesktopSpaceActionExecutor.KeyEvent] = []
        let executor = DesktopSpaceActionExecutor { events = $0; return true }

        guard case .success = executor.perform(.moveToSpaceLeft) else {
            return XCTFail("Space Left should dispatch")
        }
        XCTAssertEqual(events.map(\.keyCode), [59, 123, 123, 59])
        XCTAssertEqual(
            events.map(\.flags),
            [[.maskControl], [.maskControl, .maskSecondaryFn], [.maskControl, .maskSecondaryFn], []]
        )
        XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        XCTAssertEqual(events.map(\.timestampOffset), [0, 0.006, 0.026, 0.032])
    }

    func testSpaceRightPostsOneControlRightCycle() {
        var events: [DesktopSpaceActionExecutor.KeyEvent] = []
        let executor = DesktopSpaceActionExecutor { events = $0; return true }

        guard case .success = executor.perform(.moveToSpaceRight) else {
            return XCTFail("Space Right should dispatch")
        }
        XCTAssertEqual(events.map(\.keyCode), [59, 124, 124, 59])
        XCTAssertEqual(
            events.map(\.flags),
            [[.maskControl], [.maskControl, .maskSecondaryFn], [.maskControl, .maskSecondaryFn], []]
        )
        XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        XCTAssertEqual(events.map(\.timestampOffset), [0, 0.006, 0.026, 0.032])
    }

    func testFailedEventCreationIsReported() {
        let executor = DesktopSpaceActionExecutor { _ in false }

        guard case .failure(.eventCreationFailed) = executor.perform(.moveToSpaceLeft) else {
            return XCTFail("event creation failure should be surfaced")
        }
    }

    func testMissingAccessibilityFailsBeforePosting() {
        var posted = false
        let executor = DesktopSpaceActionExecutor(
            postChord: { _ in posted = true; return true },
            accessibilityTrusted: { false }
        )
        guard case .failure(.accessibilityPermissionMissing) = executor.perform(.moveToSpaceLeft) else {
            return XCTFail("missing Accessibility must fail closed")
        }
        XCTAssertFalse(posted)
    }
}
