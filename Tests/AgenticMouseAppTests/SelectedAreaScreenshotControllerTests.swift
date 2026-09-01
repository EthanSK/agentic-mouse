import AppKit
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

    func testCompletedCaptureRemembersTheNewSavedImageAndMakesPasteVisible() {
        let process = RecordingScreenshotProcess()
        let scheduler = ManualTickScheduler()
        let clipboard = RecordingScreenshotClipboardCoordinator()
        clipboard.completedResolutionResult = .success(URL(fileURLWithPath: "/tmp/new-shot.png"))
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            gestureScheduler: scheduler,
            clipboardCoordinator: clipboard
        )
        var resolutionResults: [Result<URL, ScreenshotClipboardError>] = []
        controller.onScreenshotReady = { _, result in resolutionResults.append(result) }

        _ = controller.handlePress(from: .corsair)
        scheduler.fire()
        process.complete(with: .completed)
        drainMainQueue()

        XCTAssertEqual(clipboard.resolveCount, 1)
        XCTAssertEqual(clipboard.hasPasteableScreenshot, true)
        XCTAssertEqual(controller.buttonState, .screenshotReadyToPaste)
        XCTAssertEqual(try? resolutionResults.first?.get().lastPathComponent, "new-shot.png")
    }

    func testCompletedInteractionWithoutASavedFileReturnsToIdleAsCancellation() {
        let process = RecordingScreenshotProcess()
        let scheduler = ManualTickScheduler()
        let clipboard = RecordingScreenshotClipboardCoordinator()
        clipboard.completedResolutionResult = .failure(.screenshotFileNotFound)
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            gestureScheduler: scheduler,
            clipboardCoordinator: clipboard
        )
        var completions: [InteractiveScreenshotResult] = []
        var resolutionResults: [Result<URL, ScreenshotClipboardError>] = []
        controller.onCompletion = { completions.append($0) }
        controller.onScreenshotReady = { _, result in resolutionResults.append(result) }

        _ = controller.handlePress(from: .corsair)
        scheduler.fire()
        process.complete(with: .completed)
        drainMainQueue()

        XCTAssertEqual(controller.buttonState, .screenshot)
        XCTAssertEqual(completions, [.cancelled])
        XCTAssertTrue(resolutionResults.isEmpty, "a click-cancel must not show a screenshot failure")
    }

    func testDoublePressWhileNativeSaveIsPendingQueuesPasteUntilCaptureResolutionCompletes() {
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
        XCTAssertTrue(clipboard.isCapturePending)
        XCTAssertEqual(controller.buttonState, .copyingScreenshot)

        XCTAssertEqual(controller.handlePress(from: .corsair), .awaitingSinglePress)
        XCTAssertEqual(controller.handlePress(from: .corsair), .pasteQueued)
        XCTAssertEqual(clipboard.pasteCount, 0)

        clipboard.completeResolution(.success(URL(fileURLWithPath: "/tmp/new-shot.png")))

        XCTAssertEqual(clipboard.pasteCount, 1)
        XCTAssertEqual(asynchronous.last, .pasted)
    }

    func testAClipboardChangeMakesTheDoublePressFailClosedInsteadOfRestoringStaleImage() {
        let process = RecordingScreenshotProcess()
        let scheduler = ManualTickScheduler()
        let clipboard = RecordingScreenshotClipboardCoordinator()
        clipboard.hasPasteableScreenshot = true
        clipboard.pasteResult = .failure(.screenshotNoLongerAvailable)
        let controller = SelectedAreaScreenshotController(
            makeProcess: { process },
            gestureScheduler: scheduler,
            clipboardCoordinator: clipboard
        )

        _ = controller.handlePress(from: .razer)
        XCTAssertEqual(
            controller.handlePress(from: .razer),
            .failed("The saved screenshot is no longer available")
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

    func testNativeClipboardCoordinatorCopiesTheResolvedScreenshotAndPastesItWithoutRewriting() {
        let scheduler = ManualTickScheduler()
        let clock = ManualClock(now: 10)
        let directory = URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true)
        let candidate = makeTemporaryScreenshot()
        defer { try? FileManager.default.removeItem(at: candidate) }
        var candidates: [URL] = []
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("agentic-mouse-screenshot-tests-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setString("VoiceInk text", forType: .string)
        var writeCount = 0
        var postedProcessIdentifiers: [pid_t] = []
        var restorations: [@MainActor @Sendable () -> Void] = []
        let coordinator = NativeScreenshotClipboardCoordinator(
            scheduler: scheduler,
            clock: clock,
            now: { Date(timeIntervalSince1970: 100) },
            resolveDirectory: { directory },
            snapshotDirectory: { _ in ["/tmp/screenshots/old.png"] },
            findCandidates: { _ in candidates },
            metadataMarksScreenshot: { $0 == candidate },
            pasteboard: pasteboard,
            writeToPasteboard: { pasteboard, url, identifier in
                writeCount += 1
                return NativeScreenshotClipboardCoordinator.writeImageToPasteboard(
                    pasteboard,
                    url,
                    identifier
                )
            },
            postPaste: { postedProcessIdentifiers.append($0); return true },
            frontmostProcessIdentifier: { 4321 },
            scheduleRestore: { restorations.append($0) },
            accessibilityTrusted: { true },
            inputAllowed: { true }
        )
        var result: Result<URL, ScreenshotClipboardError>?

        coordinator.prepareForCapture()
        coordinator.resolveCompletedCapture { result = $0 }
        XCTAssertTrue(coordinator.isCapturePending)

        candidates = [candidate]
        scheduler.fire()

        XCTAssertEqual(try? result?.get(), candidate)
        XCTAssertTrue(coordinator.hasPasteableScreenshot)
        XCTAssertFalse(coordinator.isCapturePending)
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
        XCTAssertEqual(writeCount, 1)
        let copiedChangeCount = pasteboard.changeCount

        XCTAssertNoThrow(try coordinator.pasteScreenshot().get())
        XCTAssertEqual(postedProcessIdentifiers, [4321])
        XCTAssertEqual(restorations.count, 0)
        XCTAssertEqual(writeCount, 1)
        XCTAssertEqual(pasteboard.changeCount, copiedChangeCount)
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
    }

    func testNativeClipboardCoordinatorWaitsForTheSavedImageToBecomeReadableBeforeCopying() {
        let scheduler = ManualTickScheduler()
        let directory = URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true)
        let candidate = makeTemporaryScreenshot()
        defer { try? FileManager.default.removeItem(at: candidate) }
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("agentic-mouse-screenshot-tests-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setString("clipboard before capture", forType: .string)
        var writeAttempts = 0
        let coordinator = NativeScreenshotClipboardCoordinator(
            scheduler: scheduler,
            resolveDirectory: { directory },
            snapshotDirectory: { _ in [] },
            findCandidates: { _ in [candidate] },
            metadataMarksScreenshot: { _ in true },
            pasteboard: pasteboard,
            writeToPasteboard: { pasteboard, url, identifier in
                writeAttempts += 1
                guard writeAttempts > 1 else { return nil }
                return NativeScreenshotClipboardCoordinator.writeImageToPasteboard(
                    pasteboard,
                    url,
                    identifier
                )
            },
            accessibilityTrusted: { true }
        )
        var result: Result<URL, ScreenshotClipboardError>?

        coordinator.prepareForCapture()
        coordinator.resolveCompletedCapture { result = $0 }

        XCTAssertTrue(coordinator.isCapturePending)
        XCTAssertNil(result)
        XCTAssertEqual(pasteboard.string(forType: .string), "clipboard before capture")

        scheduler.fire()

        XCTAssertEqual(try? result?.get(), candidate)
        XCTAssertFalse(coordinator.isCapturePending)
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
    }

    func testVoiceInkClipboardChangeWinsOverScreenshotPasteRestoration() {
        let scheduler = ManualTickScheduler()
        let directory = URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true)
        let candidate = makeTemporaryScreenshot()
        defer { try? FileManager.default.removeItem(at: candidate) }
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("agentic-mouse-screenshot-tests-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setString("before paste", forType: .string)
        var restorations: [@MainActor @Sendable () -> Void] = []
        let coordinator = NativeScreenshotClipboardCoordinator(
            scheduler: scheduler,
            resolveDirectory: { directory },
            snapshotDirectory: { _ in [] },
            findCandidates: { _ in [candidate] },
            metadataMarksScreenshot: { _ in true },
            pasteboard: pasteboard,
            postPaste: { _ in true },
            frontmostProcessIdentifier: { 4321 },
            scheduleRestore: { restorations.append($0) },
            accessibilityTrusted: { true }
        )

        coordinator.prepareForCapture()
        coordinator.resolveCompletedCapture { _ in }
        pasteboard.clearContents()
        pasteboard.setString("new VoiceInk result", forType: .string)
        XCTAssertNoThrow(try coordinator.pasteScreenshot().get())
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
        XCTAssertEqual(restorations.count, 1)
        restorations.first?()

        XCTAssertEqual(pasteboard.string(forType: .string), "new VoiceInk result")
    }

    func testRepeatedScreenshotPastesReuseTheAlreadyCopiedClipboard() {
        let scheduler = ManualTickScheduler()
        let directory = URL(fileURLWithPath: "/tmp/screenshots", isDirectory: true)
        let candidate = makeTemporaryScreenshot()
        defer { try? FileManager.default.removeItem(at: candidate) }
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("agentic-mouse-screenshot-tests-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)
        var restorations: [@MainActor @Sendable () -> Void] = []
        let coordinator = NativeScreenshotClipboardCoordinator(
            scheduler: scheduler,
            resolveDirectory: { directory },
            snapshotDirectory: { _ in [] },
            findCandidates: { _ in [candidate] },
            metadataMarksScreenshot: { _ in true },
            pasteboard: pasteboard,
            postPaste: { _ in true },
            frontmostProcessIdentifier: { 4321 },
            scheduleRestore: { restorations.append($0) },
            accessibilityTrusted: { true }
        )

        coordinator.prepareForCapture()
        coordinator.resolveCompletedCapture { _ in }
        let copiedChangeCount = pasteboard.changeCount
        XCTAssertNoThrow(try coordinator.pasteScreenshot().get())
        XCTAssertNoThrow(try coordinator.pasteScreenshot().get())

        XCTAssertEqual(restorations.count, 0)
        XCTAssertEqual(pasteboard.changeCount, copiedChangeCount)
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
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
            writeToPasteboard: { _, _, _ in XCTFail("must not choose an ambiguous image"); return nil },
            postPaste: { _ in true },
            accessibilityTrusted: { true },
            inputAllowed: { true }
        )
        var result: Result<URL, ScreenshotClipboardError>?

        coordinator.prepareForCapture()
        coordinator.resolveCompletedCapture { result = $0 }
        clock.advance(by: NativeScreenshotClipboardCoordinator.captureResolutionTimeout)
        scheduler.fire()

        XCTAssertEqual(result, .failure(.screenshotFileAmbiguous))
    }

    func testNativeProcessSendsExactShiftCommandFourAndCompletesOnObservedSelection() throws {
        var events: [(CGKeyCode, CGEventFlags, Bool)] = []
        var handler: (@MainActor @Sendable (InteractiveScreenshotResult) -> Void)?
        let monitor = NSObject()
        let lifecycleScheduler = ManualTickScheduler()
        var interactionIsActive = true
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
            removeLifecycleMonitor: { removedMonitor = $0 },
            lifecycleScheduler: lifecycleScheduler,
            interactionIsActive: { interactionIsActive }
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
        interactionIsActive = false
        lifecycleScheduler.fire()

        XCTAssertFalse(process.isRunning)
        XCTAssertTrue((removedMonitor as AnyObject?) === monitor)
        XCTAssertEqual(results, [.completed])
    }

    func testNativeProcessPollDetectsScreenshotDismissalWithoutAGlobalInputEvent() throws {
        let monitor = NSObject()
        let lifecycleScheduler = ManualTickScheduler()
        var interactionIsActive = true
        var removedMonitor: Any?
        let process = NativeInteractiveScreenshotProcess(
            postEvent: { _, _, _ in true },
            startLifecycleMonitor: { _ in monitor },
            removeLifecycleMonitor: { removedMonitor = $0 },
            lifecycleScheduler: lifecycleScheduler,
            interactionIsActive: { interactionIsActive }
        )
        var results: [InteractiveScreenshotResult] = []
        process.onTermination = { results.append($0) }

        try process.run()
        XCTAssertTrue(process.isRunning)
        XCTAssertEqual(lifecycleScheduler.interval, NativeInteractiveScreenshotProcess.lifecyclePollInterval)

        interactionIsActive = false
        lifecycleScheduler.fire()

        XCTAssertFalse(process.isRunning)
        XCTAssertTrue((removedMonitor as AnyObject?) === monitor)
        XCTAssertEqual(results, [.cancelled])
    }

    func testNativeLifecyclePlainClickIsCancellationButDragIsCompletion() {
        var selectionMouseDownLocation: NSPoint?
        var observedSelectionDrag = false

        XCTAssertNil(NativeInteractiveScreenshotProcess.classifyLifecycleEvent(
            .leftMouseDown,
            keyCode: 0,
            location: NSPoint(x: 100, y: 200),
            selectionMouseDownLocation: &selectionMouseDownLocation,
            observedSelectionDrag: &observedSelectionDrag
        ))
        XCTAssertEqual(NativeInteractiveScreenshotProcess.classifyLifecycleEvent(
            .leftMouseUp,
            keyCode: 0,
            location: NSPoint(x: 100, y: 200),
            selectionMouseDownLocation: &selectionMouseDownLocation,
            observedSelectionDrag: &observedSelectionDrag
        ), .cancelled)

        XCTAssertNil(NativeInteractiveScreenshotProcess.classifyLifecycleEvent(
            .leftMouseDown,
            keyCode: 0,
            location: NSPoint(x: 100, y: 200),
            selectionMouseDownLocation: &selectionMouseDownLocation,
            observedSelectionDrag: &observedSelectionDrag
        ))
        XCTAssertNil(NativeInteractiveScreenshotProcess.classifyLifecycleEvent(
            .leftMouseDragged,
            keyCode: 0,
            location: NSPoint(x: 150, y: 250),
            selectionMouseDownLocation: &selectionMouseDownLocation,
            observedSelectionDrag: &observedSelectionDrag
        ))
        XCTAssertEqual(NativeInteractiveScreenshotProcess.classifyLifecycleEvent(
            .leftMouseUp,
            keyCode: 0,
            location: NSPoint(x: 150, y: 250),
            selectionMouseDownLocation: &selectionMouseDownLocation,
            observedSelectionDrag: &observedSelectionDrag
        ), .completed)
    }

    func testNativeLifecycleTapObservesEverySelectionBoundaryBeforeTheOverlayConsumesIt() {
        for type in [
            CGEventType.leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .keyDown,
        ] {
            XCTAssertNotEqual(
                ScreenshotLifecycleEventTap.eventMask & (1 << type.rawValue),
                0
            )
        }
    }

    func testNativeLifecycleCompletesFromMovedMouseUpWhenScreenshotOverlaySwallowsDragEvents() {
        var selectionMouseDownLocation: NSPoint?
        var observedSelectionDrag = false

        XCTAssertNil(NativeInteractiveScreenshotProcess.classifyLifecycleEvent(
            .leftMouseDown,
            keyCode: 0,
            location: NSPoint(x: 100, y: 200),
            selectionMouseDownLocation: &selectionMouseDownLocation,
            observedSelectionDrag: &observedSelectionDrag
        ))
        XCTAssertEqual(NativeInteractiveScreenshotProcess.classifyLifecycleEvent(
            .leftMouseUp,
            keyCode: 0,
            location: NSPoint(x: 220, y: 320),
            selectionMouseDownLocation: &selectionMouseDownLocation,
            observedSelectionDrag: &observedSelectionDrag
        ), .completed)
    }

    func testNativeLifecycleEscapeIsCancellation() {
        var selectionMouseDownLocation: NSPoint?
        var observedSelectionDrag = false

        XCTAssertEqual(NativeInteractiveScreenshotProcess.classifyLifecycleEvent(
            .keyDown,
            keyCode: NativeInteractiveScreenshotProcess.escapeKeyCode,
            location: .zero,
            selectionMouseDownLocation: &selectionMouseDownLocation,
            observedSelectionDrag: &observedSelectionDrag
        ), .cancelled)
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

    private func makeTemporaryScreenshot() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agentic-mouse-screenshot-\(UUID().uuidString).png")
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 4,
            bitsPerPixel: 32
        )
        bitmap?.setColor(.red, atX: 0, y: 0)
        let data = bitmap?.representation(using: .png, properties: [:])
        XCTAssertNotNil(data)
        XCTAssertNoThrow(try data?.write(to: url))
        return url
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
    private(set) var isCapturePending = false
    var completedResolutionResult: Result<URL, ScreenshotClipboardError>?
    var pasteResult: Result<Void, ScreenshotClipboardError> = .success(())
    private(set) var prepareCount = 0
    private(set) var discardCount = 0
    private(set) var resolveCount = 0
    private(set) var pasteCount = 0
    private(set) var cancelCount = 0
    private(set) var lastCancelClearedOwnership = false
    private var captureResolutionCompletion: ((Result<URL, ScreenshotClipboardError>) -> Void)?

    func prepareForCapture() {
        prepareCount += 1
    }

    func discardPreparedCapture() {
        discardCount += 1
    }

    func resolveCompletedCapture(
        completion: @escaping (Result<URL, ScreenshotClipboardError>) -> Void
    ) {
        resolveCount += 1
        isCapturePending = true
        captureResolutionCompletion = completion
        if let completedResolutionResult {
            completeResolution(completedResolutionResult)
        }
    }

    func completeResolution(_ result: Result<URL, ScreenshotClipboardError>) {
        isCapturePending = false
        if case .success = result {
            hasPasteableScreenshot = true
        }
        let completion = captureResolutionCompletion
        captureResolutionCompletion = nil
        completion?(result)
    }

    func pasteScreenshot() -> Result<Void, ScreenshotClipboardError> {
        pasteCount += 1
        return pasteResult
    }

    func cancel(clearOwnership: Bool) {
        cancelCount += 1
        lastCancelClearedOwnership = clearOwnership
        isCapturePending = false
        captureResolutionCompletion = nil
        if clearOwnership { hasPasteableScreenshot = false }
    }
}
