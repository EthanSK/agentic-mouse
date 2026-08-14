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

    func testCompletionReportsTheExactSavedFile() {
        let process = RecordingScreenshotProcess()
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            inputAllowed: { true }
        )
        let savedURL = URL(fileURLWithPath: "/tmp/example-screenshot.png")
        var results: [InteractiveScreenshotResult] = []
        controller.onCompletion = { results.append($0) }

        XCTAssertEqual(controller.toggle(), .started)
        process.complete(with: .saved(savedURL))
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        XCTAssertEqual(results, [.saved(savedURL)])
    }

    func testNativeProcessUsesSelectedAreaCrosshairAndExplicitDestination() {
        let destination = URL(fileURLWithPath: "/tmp/screenshot-output.png")
        XCTAssertEqual(
            NativeInteractiveScreenshotProcess.arguments(destinationURL: destination),
            ["-i", "-s", "-t", "png", destination.path]
        )
    }

    func testDestinationResolverExpandsConfiguredTildeAndAvoidsCollisions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let screenshots = root.appendingPathComponent("Screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixedDate = Date(timeIntervalSince1970: 1_787_000_000)
        let resolver = ScreenshotDestinationResolver(
            configuredLocation: { "~/Screenshots" },
            homeDirectory: root,
            now: { fixedDate }
        )
        let first = resolver.nextURL()
        XCTAssertEqual(first.deletingLastPathComponent(), screenshots)
        XCTAssertTrue(first.lastPathComponent.hasSuffix(".png"))

        try Data([1]).write(to: first)
        let second = resolver.nextURL()
        XCTAssertNotEqual(second, first)
        XCTAssertTrue(second.lastPathComponent.hasSuffix("-2.png"))
    }

    func testNativeCompletionFailsWhenNoFileWasCreated() {
        let destination = URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString).png")
        XCTAssertEqual(
            NativeInteractiveScreenshotProcess.result(
                terminationStatus: 0,
                destinationURL: destination,
                errorText: ""
            ),
            .failed("screencapture exited with status 0 without creating \(destination.lastPathComponent)")
        )
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
    var onTermination: ((InteractiveScreenshotResult) -> Void)?
    private(set) var runCount = 0
    private(set) var cancelCount = 0

    func run() throws {
        runCount += 1
        isRunning = true
    }

    func cancel() {
        cancelCount += 1
        isRunning = false
        onTermination?(.cancelled)
    }

    func complete(with result: InteractiveScreenshotResult = .cancelled) {
        isRunning = false
        onTermination?(result)
    }
}
