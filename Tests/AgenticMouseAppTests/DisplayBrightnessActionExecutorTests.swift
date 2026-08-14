import IOKit.hidsystem
@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class DisplayBrightnessActionExecutorTests: XCTestCase {
    func testBrightnessUpPostsOneDownAndOneUpAuxiliaryEvent() {
        var events: [(Int32, Bool)] = []
        let executor = DisplayBrightnessActionExecutor { keyType, isDown in
            events.append((keyType, isDown))
            return true
        }

        guard case .success = executor.perform(.increaseDisplayBrightness) else {
            return XCTFail("brightness-up event dispatch should succeed")
        }
        XCTAssertEqual(events.map(\.0), [Int32(NX_KEYTYPE_BRIGHTNESS_UP), Int32(NX_KEYTYPE_BRIGHTNESS_UP)])
        XCTAssertEqual(events.map(\.1), [true, false])
    }

    func testBrightnessDownPostsOneDownAndOneUpAuxiliaryEvent() {
        var events: [(Int32, Bool)] = []
        let executor = DisplayBrightnessActionExecutor { keyType, isDown in
            events.append((keyType, isDown))
            return true
        }

        guard case .success = executor.perform(.decreaseDisplayBrightness) else {
            return XCTFail("brightness-down event dispatch should succeed")
        }
        XCTAssertEqual(events.map(\.0), [Int32(NX_KEYTYPE_BRIGHTNESS_DOWN), Int32(NX_KEYTYPE_BRIGHTNESS_DOWN)])
        XCTAssertEqual(events.map(\.1), [true, false])
    }

    func testFailureIsReportedWithoutPretendingBrightnessChanged() {
        let executor = DisplayBrightnessActionExecutor { _, _ in false }

        guard case .failure(.eventCreationFailed) = executor.perform(.increaseDisplayBrightness) else {
            return XCTFail("failed event creation should be reported")
        }
    }

    func testMissingAccessibilityFailsBeforePosting() {
        var posted = false
        let executor = DisplayBrightnessActionExecutor(
            postEvent: { _, _ in posted = true; return true },
            accessibilityTrusted: { false }
        )
        guard case .failure(.accessibilityPermissionMissing) =
            executor.perform(.increaseDisplayBrightness)
        else {
            return XCTFail("missing Accessibility must fail closed")
        }
        XCTAssertFalse(posted)
    }
}
