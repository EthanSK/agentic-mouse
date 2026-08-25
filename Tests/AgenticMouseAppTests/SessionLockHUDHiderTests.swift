@testable import AgenticMouseApp
import ScimitarKit
import XCTest

final class SessionLockHUDHiderTests: XCTestCase {
    func testLockHidesEveryModeAndKeypadPresenterEvenWhenVisibilityStateIsUnknown() {
        let corsairMode = RecordingModePresenter()
        let razerMode = RecordingModePresenter()
        let corsairKeypad = RecordingKeypadPresenter()
        let razerKeypad = RecordingKeypadPresenter()

        SessionLockHUDHider.hideAll(
            modeHUDs: [corsairMode, razerMode],
            keypadHUDs: [corsairKeypad, razerKeypad]
        )

        XCTAssertEqual(corsairMode.hideCount, 1)
        XCTAssertEqual(razerMode.hideCount, 1)
        XCTAssertEqual(corsairKeypad.hideCount, 1)
        XCTAssertEqual(razerKeypad.hideCount, 1)
    }
}

private final class RecordingModePresenter: ModeHUDPresenting {
    private(set) var hideCount = 0
    var isVisible = false

    func show(_ snapshot: ModeHUDSnapshot) {}
    func update(_ snapshot: ModeHUDSnapshot) {}
    func hide() { hideCount += 1 }
    func flashProblem(_ message: String) {}
    func flashFeedback(_ feedback: ModeHUDFeedback) {}
}

private final class RecordingKeypadPresenter: HUDPresenting {
    private(set) var hideCount = 0
    var isVisible = false

    func show(_ snapshot: HUDSnapshot) {}
    func update(_ snapshot: HUDSnapshot) {}
    func hide() { hideCount += 1 }
    func flashProblem(_ message: String) {}
}
