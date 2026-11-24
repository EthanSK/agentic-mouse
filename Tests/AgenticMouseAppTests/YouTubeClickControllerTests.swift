// Exercises Ethan's long-then-short gesture without changing immediate ordinary rewind. — GPT-6.1 Sol
@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class YouTubeClickControllerTests: XCTestCase {
    func testOrdinarySingleAndDoubleClicksBothRewindImmediately() {
        for source in [MouseSource.corsair, .razer] {
            var actions: [YouTubeClickController.Action] = []
            let controller = YouTubeClickController(interval: 0.5) { actions.append($0); return true }
            controller.press(source: source, time: 1)
            XCTAssertEqual(controller.release(source: source, time: 1.1, isShortClick: true, didObserveWheelInput: false), .rewind)
            XCTAssertEqual(actions, [.rewind])
            controller.press(source: source, time: 1.2)
            XCTAssertEqual(controller.release(source: source, time: 1.3, isShortClick: true, didObserveWheelInput: false), .rewind)
            XCTAssertEqual(actions, [.rewind, .rewind])
        }
    }

    func testLongThenShortTogglesOnceForBothMiceAndDoesNotRewind() {
        for source in [MouseSource.corsair, .razer] {
            var actions: [YouTubeClickController.Action] = []
            let controller = YouTubeClickController(interval: 0.5) { actions.append($0); return true }
            controller.press(source: source, time: 1)
            XCTAssertNil(controller.release(source: source, time: 1.4, isShortClick: false, didObserveWheelInput: false))
            XCTAssertTrue(actions.isEmpty)
            controller.press(source: source, time: 1.8)
            XCTAssertEqual(controller.release(source: source, time: 2, isShortClick: true, didObserveWheelInput: false), .togglePlayback)
            XCTAssertEqual(actions, [.togglePlayback])
            controller.press(source: source, time: 2.1)
            XCTAssertEqual(controller.release(source: source, time: 2.2, isShortClick: true, didObserveWheelInput: false), .rewind)
        }
    }

    func testOtherMouseAndExpiredFollowUpDoNotToggle() {
        var actions: [YouTubeClickController.Action] = []
        let controller = YouTubeClickController(interval: 0.5) { actions.append($0); return true }
        controller.press(source: .corsair, time: 1)
        controller.release(source: .corsair, time: 1.4, isShortClick: false, didObserveWheelInput: false)
        controller.press(source: .razer, time: 1.5)
        controller.release(source: .razer, time: 1.6, isShortClick: true, didObserveWheelInput: false)
        controller.press(source: .corsair, time: 2)
        controller.release(source: .corsair, time: 2.1, isShortClick: true, didObserveWheelInput: false)
        XCTAssertEqual(actions, [.rewind, .rewind])
    }

    func testWheelAndCancellationSuppressTheSequence() {
        for cancelAll in [false, true] {
            var actions: [YouTubeClickController.Action] = []
            let controller = YouTubeClickController(interval: 0.5) { actions.append($0); return true }
            controller.press(source: .corsair, time: 1)
            controller.release(source: .corsair, time: 1.4, isShortClick: false, didObserveWheelInput: true)
            controller.press(source: .corsair, time: 1.5)
            controller.release(source: .corsair, time: 1.6, isShortClick: true, didObserveWheelInput: false)
            controller.press(source: .corsair, time: 2)
            controller.release(source: .corsair, time: 2.4, isShortClick: false, didObserveWheelInput: false)
            if cancelAll { controller.cancelAll() } else { controller.cancel(source: .corsair) }
            controller.press(source: .corsair, time: 2.5)
            controller.release(source: .corsair, time: 2.6, isShortClick: true, didObserveWheelInput: false)
            XCTAssertEqual(actions, [.rewind, .rewind])
        }
    }

    func testDuplicatePressBackwardsTimeAndRejectedClickDoNotArmToggle() {
        var actions: [YouTubeClickController.Action] = []
        let controller = YouTubeClickController(interval: 0.5) { actions.append($0); return true }
        controller.press(source: .corsair, time: 2)
        controller.press(source: .corsair, time: 2.3)
        controller.release(source: .corsair, time: 1.9, isShortClick: false, didObserveWheelInput: false)
        controller.press(source: .corsair, time: 3)
        controller.release(source: .corsair, time: 3.1, isShortClick: false, didObserveWheelInput: false)
        controller.press(source: .corsair, time: 3.2)
        controller.release(source: .corsair, time: 3.3, isShortClick: true, didObserveWheelInput: false)
        XCTAssertEqual(actions, [.rewind])
    }
    func testUnusedVolumeModifierPreservesRewindWithoutArmingToggle() {
        for modifierAtPress in [false, true] {
            var actions: [YouTubeClickController.Action] = []
            let controller = YouTubeClickController(interval: 0.5) { actions.append($0); return true }
            controller.press(source: .corsair, time: 1, canArmLongPress: !modifierAtPress)
            if !modifierAtPress { controller.inhibitLongPress(source: .corsair) }
            controller.release(source: .corsair, time: 1.1, isShortClick: true, didObserveWheelInput: false)
            controller.press(source: .corsair, time: 2, canArmLongPress: false)
            controller.release(source: .corsair, time: 2.4, isShortClick: false, didObserveWheelInput: false)
            controller.press(source: .corsair, time: 2.5)
            controller.release(source: .corsair, time: 2.6, isShortClick: true, didObserveWheelInput: false)
            XCTAssertEqual(actions, [.rewind, .rewind])
        }
    }

}
