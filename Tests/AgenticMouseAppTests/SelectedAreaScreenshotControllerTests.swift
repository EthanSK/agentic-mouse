import ApplicationServices
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

    func testSinglePressWaitsForBoundedDoublePressWindowThenStartsNativeCapture() {
        let process = RecordingScreenshotProcess()
        let scheduler = ManualTickScheduler()
        let clipboard = RecordingScreenshotClipboardCoordinator()
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            gestureScheduler: scheduler,
            clipboardCoordinator: clipboard
        )
        var asynchronous: [(MouseSource, SelectedAreaScreenshotController.TriggerResult)] = []
        controller.onAsynchronousResult = { asynchronous.append(($0, $1)) }

        XCTAssertEqual(controller.handlePress(from: .corsair), .awaitingSinglePress)
        XCTAssertEqual(scheduler.interval, SelectedAreaScreenshotController.doublePressInterval)
        XCTAssertEqual(process.runCount, 0)

        scheduler.fire()

        XCTAssertEqual(process.runCount, 1)
        XCTAssertTrue(controller.isCapturing)
        XCTAssertEqual(controller.buttonState, .cancelScreenshot)
        XCTAssertEqual(asynchronous.count, 1)
        XCTAssertEqual(asynchronous[0].0, .corsair)
        XCTAssertEqual(asynchronous[0].1, .started)
        XCTAssertEqual(clipboard.prepareCount, 1)
    }

    func testRapidDoublePressPastesOwnedScreenshotWithoutStartingCapture() {
        let process = RecordingScreenshotProcess()
        let scheduler = ManualTickScheduler()
        let clipboard = RecordingScreenshotClipboardCoordinator()
        clipboard.hasPasteableScreenshot = true
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            gestureScheduler: scheduler,
            clipboardCoordinator: clipboard
        )

        XCTAssertEqual(controller.handlePress(from: .razer), .awaitingSinglePress)
        XCTAssertEqual(controller.handlePress(from: .razer), .pasted)

        XCTAssertEqual(process.runCount, 0)
        XCTAssertEqual(clipboard.pasteCount, 1)
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(controller.buttonState, .screenshotReadyToPaste)
    }

    func testRapidDoublePressWithoutAnOwnedScreenshotStartsCaptureImmediately() {
        let process = RecordingScreenshotProcess()
        let scheduler = ManualTickScheduler()
        let clipboard = RecordingScreenshotClipboardCoordinator()
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            gestureScheduler: scheduler,
            clipboardCoordinator: clipboard
        )

        XCTAssertEqual(controller.handlePress(from: .corsair), .awaitingSinglePress)
        XCTAssertEqual(controller.handlePress(from: .corsair), .started)

        XCTAssertEqual(process.runCount, 1)
        XCTAssertTrue(controller.isCapturing)
        XCTAssertFalse(scheduler.isRunning)
    }

    func testPressDuringRunningNativeCaptureCancelsOnlyThatInteraction() {
        let process = RecordingScreenshotProcess()
        let scheduler = ManualTickScheduler()
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            gestureScheduler: scheduler,
            clipboardCoordinator: RecordingScreenshotClipboardCoordinator()
        )

        XCTAssertEqual(controller.handlePress(from: .corsair), .awaitingSinglePress)
        scheduler.fire()
        XCTAssertTrue(controller.isCapturing)

        XCTAssertEqual(controller.handlePress(from: .corsair), .cancelled)
        XCTAssertFalse(controller.isCapturing)
        XCTAssertEqual(process.cancelCount, 1)
    }

    func testCompletedCaptureCopiesTheNewSavedImageAndMakesPasteVisible() {
        let process = RecordingScreenshotProcess()
        let scheduler = ManualTickScheduler()
        let clipboard = RecordingScreenshotClipboardCoordinator()
        clipboard.completedCopyResult = .success(URL(fileURLWithPath: "/tmp/new-shot.png"))
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            gestureScheduler: scheduler,
            clipboardCoordinator: clipboard
        )
        var copyResults: [Result<URL, ScreenshotClipboardError>] = []
        controller.onClipboardCopy = { _, result in copyResults.append(result) }

        _ = controller.handlePress(from: .corsair)
        scheduler.fire()
        process.complete(with: .completed)
        drainMainQueue()

        XCTAssertEqual(clipboard.copyCount, 1)
        XCTAssertEqual(clipboard.hasPasteableScreenshot, true)
        XCTAssertEqual(controller.buttonState, .screenshotReadyToPaste)
        XCTAssertEqual(try? copyResults.first?.get().lastPathComponent, "new-shot.png")
    }

    func testDoublePressWhileNativeSaveIsPendingQueuesPasteUntilClipboardCopyCompletes() {
        let process = RecordingScreenshotProcess()
        let scheduler = ManualTickScheduler()
        let clipboard = RecordingScreenshotClipboardCoordinator()
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            gestureScheduler: scheduler,
            clipboardCoordinator: clipboard
        )
        var asynchronous: [SelectedAreaScreenshotController.TriggerResult] = []
        controller.onAsynchronousResult = { _, result in asynchronous.append(result) }

        _ = controller.handlePress(from: .corsair)
        scheduler.fire()
        process.complete(with: .completed)
        drainMainQueue()
        XCTAssertTrue(clipboard.isCopyPending)
        XCTAssertEqual(controller.buttonState, .copyingScreenshot)

        XCTAssertEqual(controller.handlePress(from: .corsair), .awaitingSinglePress)
        XCTAssertEqual(controller.handlePress(from: .corsair), .pasteQueued)
        XCTAssertEqual(clipboard.pasteCount, 0)

        clipboard.completeCopy(.success(URL(fileURLWithPath: "/tmp/new-shot.png")))

        XCTAssertEqual(clipboard.pasteCount, 1)
        XCTAssertEqual(asynchronous.last, .pasted)
    }

    func testAClipboardChangeMakesTheDoublePressFailClosedInsteadOfRestoringStaleImage() {
        let process = RecordingScreenshotProcess()
        let scheduler = ManualTickScheduler()
        let clipboard = RecordingScreenshotClipboardCoordinator()
        clipboard.hasPasteableScreenshot = true
        clipboard.pasteResult = .failure(.screenshotNoLongerOnClipboard)
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            gestureScheduler: scheduler,
            clipboardCoordinator: clipboard
        )

        _ = controller.handlePress(from: .razer)
        XCTAssertEqual(
            controller.handlePress(from: .razer),
            .failed("The screenshot is no longer on the clipboard")
        )
        XCTAssertEqual(process.runCount, 0)
    }

    func testDifferentMouseCannotCompleteTheOtherSourcesDoublePress() {
        let process = RecordingScreenshotProcess()
        let scheduler = ManualTickScheduler()
        let clipboard = RecordingScreenshotClipboardCoordinator()
        clipboard.hasPasteableScreenshot = true
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            gestureScheduler: scheduler,
            clipboardCoordinator: clipboard
        )
        var asynchronous: [(MouseSource, SelectedAreaScreenshotController.TriggerResult)] = []
        controller.onAsynchronousResult = { asynchronous.append(($0, $1)) }

        XCTAssertEqual(controller.handlePress(from: .corsair), .awaitingSinglePress)
        XCTAssertEqual(controller.handlePress(from: .razer), .awaitingSinglePress)
        XCTAssertEqual(clipboard.pasteCount, 0)
        XCTAssertEqual(process.runCount, 1)
        XCTAssertEqual(asynchronous.first?.0, .corsair)
        XCTAssertEqual(asynchronous.first?.1, .started)
    }

    func testCancelClearsPendingClassifierAndPreventsLateCapture() {
        let process = RecordingScreenshotProcess()
        let scheduler = ManualTickScheduler()
        let clipboard = RecordingScreenshotClipboardCoordinator()
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            gestureScheduler: scheduler,
            clipboardCoordinator: clipboard
        )

        _ = controller.handlePress(from: .corsair)
        controller.cancel()
        scheduler.fire()

        XCTAssertEqual(process.runCount, 0)
        XCTAssertEqual(clipboard.cancelCount, 1)
        XCTAssertTrue(clipboard.lastCancelClearedOwnership)
    }

    func testNativeClipboardCoordinatorCopiesOnlyTheBoundedNewCandidate() {
        let scheduler = ManualTickScheduler()
        let clock = ManualClock(now: 10)
        let directory = URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true)
        let candidate = directory.appendingPathComponent("Screenshot.png")
        var candidates: [URL] = []
        var pasteboardCount = 41
        var writtenURLs: [URL] = []
        let coordinator = NativeScreenshotClipboardCoordinator(
            scheduler: scheduler,
            clock: clock,
            now: { Date(timeIntervalSince1970: 100) },
            resolveDirectory: { directory },
            snapshotDirectory: { _ in ["/tmp/screenshots/old.png"] },
            findCandidates: { _ in candidates },
            metadataMarksScreenshot: { $0 == candidate },
            writeToPasteboard: {
                writtenURLs.append($0)
                return pasteboardCount
            },
            pasteboardChangeCount: { pasteboardCount },
            postPaste: { true },
            accessibilityTrusted: { true },
            inputAllowed: { true }
        )
        var result: Result<URL, ScreenshotClipboardError>?

        coordinator.prepareForCapture()
        coordinator.copyCompletedCapture { result = $0 }
        XCTAssertTrue(coordinator.isCopyPending)

        candidates = [candidate]
        scheduler.fire()

        XCTAssertEqual(try? result?.get(), candidate)
        XCTAssertEqual(writtenURLs, [candidate])
        XCTAssertTrue(coordinator.hasPasteableScreenshot)
        XCTAssertFalse(coordinator.isCopyPending)

        pasteboardCount = 42
        XCTAssertFalse(coordinator.hasPasteableScreenshot)
        switch coordinator.pasteScreenshot() {
        case .success:
            XCTFail("a changed clipboard must not paste the stale screenshot")
        case .failure(let error):
            XCTAssertEqual(error, .screenshotNoLongerOnClipboard)
        }
    }

    func testNativeClipboardCoordinatorFailsClosedOnAmbiguousNewImagesAtTimeout() {
        let scheduler = ManualTickScheduler()
        let clock = ManualClock(now: 5)
        let directory = URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true)
        let coordinator = NativeScreenshotClipboardCoordinator(
            scheduler: scheduler,
            clock: clock,
            now: { Date(timeIntervalSince1970: 100) },
            resolveDirectory: { directory },
            snapshotDirectory: { _ in [] },
            findCandidates: { _ in [
                directory.appendingPathComponent("one.png"),
                directory.appendingPathComponent("two.png"),
            ] },
            metadataMarksScreenshot: { _ in false },
            writeToPasteboard: { _ in XCTFail("must not choose an ambiguous image"); return nil },
            pasteboardChangeCount: { 0 },
            postPaste: { true },
            accessibilityTrusted: { true },
            inputAllowed: { true }
        )
        var result: Result<URL, ScreenshotClipboardError>?

        coordinator.prepareForCapture()
        coordinator.copyCompletedCapture { result = $0 }
        clock.advance(by: NativeScreenshotClipboardCoordinator.copyTimeout)
        scheduler.fire()

        XCTAssertEqual(result, .failure(.screenshotFileAmbiguous))
    }

    func testNativeProcessSendsExactShiftCommandFourAndCompletesOnObservedSelection() throws {
        var events: [(CGKeyCode, CGEventFlags, Bool)] = []
        var handler: (@MainActor (InteractiveScreenshotResult) -> Void)?
        let monitor = NSObject()
        var removedMonitor: Any?
        let process = NativeInteractiveScreenshotProcess(
            postEvent: { keyCode, flags, isDown in
                events.append((keyCode, flags, isDown))
                return true
            },
            startLifecycleMonitor: { lifecycleHandler in
                handler = lifecycleHandler
                return monitor
            },
            removeLifecycleMonitor: { removedMonitor = $0 }
        )
        var results: [InteractiveScreenshotResult] = []
        process.onTermination = { results.append($0) }

        try process.run()

        XCTAssertTrue(process.isRunning)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].0, NativeInteractiveScreenshotProcess.screenshotKeyCode)
        XCTAssertEqual(events[0].1, NativeInteractiveScreenshotProcess.screenshotFlags)
        XCTAssertTrue(events[0].2)
        XCTAssertEqual(events[1].0, NativeInteractiveScreenshotProcess.screenshotKeyCode)
        XCTAssertEqual(events[1].1, NativeInteractiveScreenshotProcess.screenshotFlags)
        XCTAssertFalse(events[1].2)

        handler?(.completed)

        XCTAssertFalse(process.isRunning)
        XCTAssertTrue((removedMonitor as AnyObject?) === monitor)
        XCTAssertEqual(results, [.completed])
    }

    func testNativeProcessCancellationSendsEscapeAndRemovesItsMonitor() throws {
        var events: [(CGKeyCode, CGEventFlags, Bool)] = []
        let monitor = NSObject()
        var removedMonitor: Any?
        let process = NativeInteractiveScreenshotProcess(
            postEvent: { keyCode, flags, isDown in
                events.append((keyCode, flags, isDown))
                return true
            },
            startLifecycleMonitor: { _ in monitor },
            removeLifecycleMonitor: { removedMonitor = $0 }
        )
        var results: [InteractiveScreenshotResult] = []
        process.onTermination = { results.append($0) }

        try process.run()
        process.cancel()

        XCTAssertFalse(process.isRunning)
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[2].0, NativeInteractiveScreenshotProcess.escapeKeyCode)
        XCTAssertTrue(events[2].1.isEmpty)
        XCTAssertTrue(events[2].2)
        XCTAssertEqual(events[3].0, NativeInteractiveScreenshotProcess.escapeKeyCode)
        XCTAssertTrue(events[3].1.isEmpty)
        XCTAssertFalse(events[3].2)
        XCTAssertTrue((removedMonitor as AnyObject?) === monitor)
        XCTAssertEqual(results, [.cancelled])
    }

    func testNativeProcessFailsClosedWhenItCannotSendTheShortcut() {
        let monitor = NSObject()
        var removedMonitor: Any?
        let process = NativeInteractiveScreenshotProcess(
            postEvent: { _, _, _ in false },
            startLifecycleMonitor: { _ in monitor },
            removeLifecycleMonitor: { removedMonitor = $0 }
        )

        XCTAssertThrowsError(try process.run()) { error in
            XCTAssertEqual(
                error.localizedDescription,
                NativeScreenshotShortcutError.eventCreationFailed.localizedDescription
            )
        }
        XCTAssertFalse(process.isRunning)
        XCTAssertTrue((removedMonitor as AnyObject?) === monitor)
    }

    func testLockedSessionFailsClosedWithoutCreatingAProcess() {
        var factoryCalls = 0
        let controller = SelectedAreaScreenshotController(
            makeProcess: { factoryCalls += 1; return RecordingScreenshotProcess() },
            gestureScheduler: ManualTickScheduler(),
            clipboardCoordinator: RecordingScreenshotClipboardCoordinator(),
            inputAllowed: { false }
        )

        XCTAssertEqual(controller.handlePress(from: .corsair), .blocked)
        XCTAssertEqual(factoryCalls, 0)
    }

    private func drainMainQueue() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
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

@MainActor
private final class RecordingScreenshotClipboardCoordinator: ScreenshotClipboardCoordinating {
    var hasPasteableScreenshot = false
    private(set) var isCopyPending = false
    var completedCopyResult: Result<URL, ScreenshotClipboardError>?
    var pasteResult: Result<Void, ScreenshotClipboardError> = .success(())
    private(set) var prepareCount = 0
    private(set) var discardCount = 0
    private(set) var copyCount = 0
    private(set) var pasteCount = 0
    private(set) var cancelCount = 0
    private(set) var lastCancelClearedOwnership = false
    private var copyCompletion: ((Result<URL, ScreenshotClipboardError>) -> Void)?

    func prepareForCapture() {
        prepareCount += 1
    }

    func discardPreparedCapture() {
        discardCount += 1
    }

    func copyCompletedCapture(
        completion: @escaping (Result<URL, ScreenshotClipboardError>) -> Void
    ) {
        copyCount += 1
        isCopyPending = true
        copyCompletion = completion
        if let completedCopyResult {
            completeCopy(completedCopyResult)
        }
    }

    func completeCopy(_ result: Result<URL, ScreenshotClipboardError>) {
        isCopyPending = false
        if case .success = result {
            hasPasteableScreenshot = true
        }
        let completion = copyCompletion
        copyCompletion = nil
        completion?(result)
    }

    func pasteScreenshot() -> Result<Void, ScreenshotClipboardError> {
        pasteCount += 1
        return pasteResult
    }

    func cancel(clearOwnership: Bool) {
        cancelCount += 1
        lastCancelClearedOwnership = clearOwnership
        isCopyPending = false
        copyCompletion = nil
        if clearOwnership { hasPasteableScreenshot = false }
    }
}
