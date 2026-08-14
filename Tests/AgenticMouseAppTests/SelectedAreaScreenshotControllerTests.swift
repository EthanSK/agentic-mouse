import Foundation
import ScimitarKit
@testable import AgenticMouseApp
import XCTest

@MainActor
final class SelectedAreaScreenshotControllerTests: XCTestCase {
    func testCommandAcceptsOnlyTheSharedPhysicalCellThree() throws {
        let valid = Data(
            #"{"command":"agentic_mouse_selected_area_screenshot_toggle","source":"razer","physical_cell":3}"#.utf8
        )
        XCTAssertEqual(
            try SelectedAreaScreenshotCommand.decode(valid),
            SelectedAreaScreenshotCommand(source: .razer)
        )

        for payload in [
            #"{"command":"another_command","source":"razer","physical_cell":3}"#,
            #"{"command":"agentic_mouse_selected_area_screenshot_toggle","source":"razer","physical_cell":10}"#,
            #"{"command":"agentic_mouse_selected_area_screenshot_toggle","source":"unknown","physical_cell":3}"#,
        ] {
            XCTAssertThrowsError(try SelectedAreaScreenshotCommand.decode(Data(payload.utf8)))
        }
    }

    func testSecondToggleCancelsOnlyTheStillRunningScreenshotProcess() {
        let process = RecordingScreenshotProcess()
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            inputAllowed: { true }
        )
        var states: [Bool] = []
        controller.onCapturingChange = { states.append($0) }

        XCTAssertEqual(controller.toggle(), .started)
        XCTAssertTrue(controller.isCapturing)
        XCTAssertEqual(process.runCount, 1)

        XCTAssertEqual(controller.toggle(), .cancelled)
        XCTAssertFalse(controller.isCapturing)
        XCTAssertEqual(process.cancelCount, 1)
        XCTAssertEqual(states, [true, false])
    }

    func testCompletedScreenshotDoesNotMakeTheNextPressCancelAStaleProcess() {
        let first = RecordingScreenshotProcess()
        let second = RecordingScreenshotProcess()
        var processes: [RecordingScreenshotProcess] = [first, second]
        let controller = SelectedAreaScreenshotController(
            makeProcess: { processes.removeFirst() },
            inputAllowed: { true }
        )

        XCTAssertEqual(controller.toggle(), .started)
        first.complete()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        XCTAssertFalse(controller.isCapturing)

        XCTAssertEqual(controller.toggle(), .started)
        XCTAssertEqual(first.cancelCount, 0)
        XCTAssertEqual(second.runCount, 1)
    }

    func testLockedSessionFailsClosedWithoutCreatingAProcess() {
        var factoryCalls = 0
        let controller = SelectedAreaScreenshotController(
            makeProcess: { factoryCalls += 1; return RecordingScreenshotProcess() },
            inputAllowed: { false }
        )

        XCTAssertEqual(controller.toggle(), .blocked)
        XCTAssertEqual(factoryCalls, 0)
    }
}

@MainActor
private final class RecordingScreenshotProcess: InteractiveScreenshotProcess {
    var isRunning = false
    var onTermination: (() -> Void)?
    private(set) var runCount = 0
    private(set) var cancelCount = 0

    func run() throws {
        runCount += 1
        isRunning = true
    }

    func cancel() {
        cancelCount += 1
        isRunning = false
        onTermination?()
    }

    func complete() {
        isRunning = false
        onTermination?()
    }
}
