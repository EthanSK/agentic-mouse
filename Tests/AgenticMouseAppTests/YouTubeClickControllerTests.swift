@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class YouTubeClickControllerTests: XCTestCase {
    func testFirstClickIsImmediateAndDoubleUsesItsExactTokenForEachMouse() {
        for source in [MouseSource.corsair, .razer] {
            var events: [(YouTubeClickController.Action, String)] = []
            let controller = YouTubeClickController(interval: 0.5) { events.append(($0, $1)); return true }
            XCTAssertEqual(controller.click(source: source, time: 10), .rewind)
            XCTAssertEqual(events.count, 1)
            XCTAssertEqual(controller.click(source: source, time: 10.3), .restoreAndPause)
            XCTAssertEqual(events.map(\.0), [.rewind, .restoreAndPause])
            XCTAssertEqual(events[0].1, events[1].1)
            XCTAssertEqual(controller.click(source: source, time: 10.4), .rewind)
            XCTAssertNotEqual(events[0].1, events[2].1)
        }
    }

    func testSourcesDoNotCombineAndExpiredClicksStartFresh() {
        var actions: [YouTubeClickController.Action] = []
        let controller = YouTubeClickController(interval: 0.5) { action, _ in actions.append(action); return true }
        controller.click(source: .corsair, time: 1)
        controller.click(source: .razer, time: 1.1)
        controller.click(source: .corsair, time: 1.51)
        XCTAssertEqual(actions, [.rewind, .rewind, .rewind])
    }

    func testCancellationFailureAndBackwardsTimeNeverRestore() {
        var actions: [YouTubeClickController.Action] = []
        var accepts = false
        let controller = YouTubeClickController(interval: 0.5) { action, _ in actions.append(action); return accepts }
        XCTAssertNil(controller.click(source: .corsair, time: 1))
        accepts = true
        controller.click(source: .corsair, time: 1.1)
        controller.cancel(source: .corsair)
        controller.click(source: .corsair, time: 1.2)
        controller.cancelAll()
        controller.click(source: .corsair, time: 1.3)
        controller.click(source: .corsair, time: 1.2)
        XCTAssertTrue(actions.allSatisfy { $0 == .rewind })
    }
}
