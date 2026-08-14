import CoreGraphics
@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class ApplicationZoomActionExecutorTests: XCTestCase {
    func testZoomInPostsOneCommandShiftEqualsDownUpCycle() {
        var events: [(CGKeyCode, CGEventFlags, Bool)] = []
        let executor = ApplicationZoomActionExecutor { keyCode, flags, isDown in
            events.append((keyCode, flags, isDown))
            return true
        }

        guard case .success = executor.perform(.zoomIn) else {
            return XCTFail("zoom-in dispatch should succeed")
        }
        XCTAssertEqual(events.map(\.0), [24, 24])
        XCTAssertEqual(events.map(\.1), [[.maskCommand, .maskShift], [.maskCommand, .maskShift]])
        XCTAssertEqual(events.map(\.2), [true, false])
    }

    func testZoomOutPostsOneCommandMinusDownUpCycle() {
        var events: [(CGKeyCode, CGEventFlags, Bool)] = []
        let executor = ApplicationZoomActionExecutor { keyCode, flags, isDown in
            events.append((keyCode, flags, isDown))
            return true
        }

        guard case .success = executor.perform(.zoomOut) else {
            return XCTFail("zoom-out dispatch should succeed")
        }
        XCTAssertEqual(events.map(\.0), [27, 27])
        XCTAssertEqual(events.map(\.1), [[.maskCommand], [.maskCommand]])
        XCTAssertEqual(events.map(\.2), [true, false])
    }

    func testFailureIsReportedWithoutPretendingZoomChanged() {
        let executor = ApplicationZoomActionExecutor { _, _, _ in false }

        guard case .failure(.eventCreationFailed) = executor.perform(.zoomIn) else {
            return XCTFail("failed event creation should be reported")
        }
    }

    func testMissingAccessibilityFailsBeforePosting() {
        var posted = false
        let executor = ApplicationZoomActionExecutor(
            postEvent: { _, _, _ in posted = true; return true },
            accessibilityTrusted: { false }
        )
        guard case .failure(.accessibilityPermissionMissing) = executor.perform(.zoomIn) else {
            return XCTFail("missing Accessibility must fail closed")
        }
        XCTAssertFalse(posted)
    }
}
