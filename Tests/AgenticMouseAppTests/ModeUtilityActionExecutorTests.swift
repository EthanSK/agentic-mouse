@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class ModeUtilityActionExecutorTests: XCTestCase {
    func testDispatcherWiresEveryNativeUtilityToItsRealExecutor() {
        var brightnessEvents: [(Int32, Bool)] = []
        var zoomEvents: [(CGKeyCode, CGEventFlags, Bool)] = []
        var spaceEvents: [(CGKeyCode, CGEventFlags, Bool)] = []
        let executor = ModeUtilityActionExecutor(
            brightness: DisplayBrightnessActionExecutor {
                brightnessEvents.append(($0, $1)); return true
            },
            zoom: ApplicationZoomActionExecutor {
                zoomEvents.append(($0, $1, $2)); return true
            },
            spaces: DesktopSpaceActionExecutor {
                spaceEvents.append(($0, $1, $2)); return true
            }
        )

        for action in [
            ModeUtilityAction.increaseDisplayBrightness,
            .decreaseDisplayBrightness,
            .zoomIn,
            .zoomOut,
            .moveToSpaceLeft,
            .moveToSpaceRight,
        ] {
            guard case .success = executor.perform(action) else {
                return XCTFail("\(action) should reach its native executor")
            }
        }

        XCTAssertEqual(brightnessEvents.count, 4)
        XCTAssertEqual(zoomEvents.count, 4)
        XCTAssertEqual(spaceEvents.count, 4)
    }

    func testYouTubeRewindPostsOnlyTheBridgeNotificationPath() {
        var notificationCount = 0
        let executor = ModeUtilityActionExecutor(
            notifyYouTube: {
                notificationCount += 1
                return true
            }
        )

        guard case .success = executor.perform(.rewindYouTubeFiveSeconds) else {
            return XCTFail("YouTube bridge notification should succeed")
        }
        XCTAssertEqual(notificationCount, 1)
        XCTAssertEqual(
            ModeUtilityActionExecutor.youtubeSeekBackwardFiveSecondsNotification.rawValue,
            "com.ethansk.agenticmouse.youtube.seekBackwardFiveSeconds"
        )
    }

    func testYouTubeBridgeFailureIsReported() {
        let executor = ModeUtilityActionExecutor(notifyYouTube: { false })

        guard case .failure(.youtubeBridgeNotificationFailed) =
            executor.perform(.rewindYouTubeFiveSeconds)
        else {
            return XCTFail("bridge notification failure should be surfaced")
        }
    }
}
