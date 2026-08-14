@testable import AgenticMouseApp
import CoreGraphics
import ScimitarKit
import XCTest

@MainActor
final class DesktopSpaceActionExecutorTests: XCTestCase {
    func testSpaceLeftPostsOneControlLeftCycle() {
        var events: [(CGKeyCode, CGEventFlags, Bool)] = []
        let executor = DesktopSpaceActionExecutor { events.append(($0, $1, $2)); return true }

        guard case .success = executor.perform(.moveToSpaceLeft) else {
            return XCTFail("Space Left should dispatch")
        }
        XCTAssertEqual(events.map(\.0), [123, 123])
        XCTAssertEqual(events.map(\.1), [[.maskControl], [.maskControl]])
        XCTAssertEqual(events.map(\.2), [true, false])
    }

    func testSpaceRightPostsOneControlRightCycle() {
        var events: [(CGKeyCode, CGEventFlags, Bool)] = []
        let executor = DesktopSpaceActionExecutor { events.append(($0, $1, $2)); return true }

        guard case .success = executor.perform(.moveToSpaceRight) else {
            return XCTFail("Space Right should dispatch")
        }
        XCTAssertEqual(events.map(\.0), [124, 124])
        XCTAssertEqual(events.map(\.1), [[.maskControl], [.maskControl]])
        XCTAssertEqual(events.map(\.2), [true, false])
    }

    func testFailedEventCreationIsReported() {
        let executor = DesktopSpaceActionExecutor { _, _, _ in false }

        guard case .failure(.eventCreationFailed) = executor.perform(.moveToSpaceLeft) else {
            return XCTFail("event creation failure should be surfaced")
        }
    }

    func testMissingAccessibilityFailsBeforePosting() {
        var posted = false
        let executor = DesktopSpaceActionExecutor(
            postEvent: { _, _, _ in posted = true; return true },
            accessibilityTrusted: { false }
        )
        guard case .failure(.accessibilityPermissionMissing) = executor.perform(.moveToSpaceLeft) else {
            return XCTFail("missing Accessibility must fail closed")
        }
        XCTAssertFalse(posted)
    }
}
