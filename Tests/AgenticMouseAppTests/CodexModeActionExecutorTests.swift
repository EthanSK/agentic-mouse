import CoreGraphics
@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class CodexModeActionExecutorTests: XCTestCase {
    func testEverySingleShortcutUsesCodexsVerifiedCommandAndTargetPid() {
        let expected: [(CodexModeAction, CodexModeActionExecutor.Shortcut)] = [
            (.newTask, CodexModeActionExecutor.newTaskShortcut),
            (.togglePin, CodexModeActionExecutor.togglePinShortcut),
            (.toggleMicrophoneMute, CodexModeActionExecutor.microphoneShortcut),
            (.steerQueuedMessage, CodexModeActionExecutor.steerQueuedMessageShortcut),
            (.pressEnter, CodexModeActionExecutor.submitShortcut),
        ]

        for (action, shortcut) in expected {
            var events: [(pid_t, CGKeyCode, CGEventFlags, Bool)] = []
            let executor = CodexModeActionExecutor(
                targetProcessResolver: { 4242 },
                postEvent: { events.append(($0, $1, $2, $3)); return true },
                accessibilityTrusted: { true }
            )

            if case .failure(let error) = executor.perform(action) {
                XCTFail("\(action) should dispatch: \(error.description)")
                continue
            }
            XCTAssertEqual(events.map(\.0), [4242, 4242], "\(action)")
            XCTAssertEqual(events.map(\.1), [shortcut.keyCode, shortcut.keyCode], "\(action)")
            XCTAssertEqual(events.map(\.2), [shortcut.flags, shortcut.flags], "\(action)")
            XCTAssertEqual(events.map(\.3), [true, false], "\(action)")
        }
    }

    func testReasoningEffortWheelUsesTheExistingAdditiveShortcuts() {
        var events: [(pid_t, CGKeyCode, CGEventFlags, Bool)] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            postEvent: { events.append(($0, $1, $2, $3)); return true },
            accessibilityTrusted: { true }
        )

        guard case .success = executor.performReasoningEffort(.increase),
              case .success = executor.performReasoningEffort(.decrease)
        else { return XCTFail("both Reasoning Effort wheel directions should dispatch") }

        XCTAssertEqual(events.map(\.0), [4242, 4242, 4242, 4242])
        XCTAssertEqual(events.map(\.1), [79, 79, 80, 80])
        XCTAssertEqual(events.map(\.2), [
            CodexModeActionExecutor.hyper,
            CodexModeActionExecutor.hyper,
            CodexModeActionExecutor.hyper,
            CodexModeActionExecutor.hyper,
        ])
        XCTAssertEqual(events.map(\.3), [true, false, true, false])
    }

    func testChatHistoryWheelSendsOptionCommandRightAndLeft() {
        var events: [(pid_t, CGKeyCode, CGEventFlags, Bool)] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            postEvent: { events.append(($0, $1, $2, $3)); return true },
            accessibilityTrusted: { true }
        )

        guard case .success = executor.performChatHistory(.forward),
              case .success = executor.performChatHistory(.back)
        else { return XCTFail("both Chats Selection wheel directions should dispatch") }

        XCTAssertEqual(events.map(\.0), [4242, 4242, 4242, 4242])
        XCTAssertEqual(events.map(\.1), [124, 124, 123, 123])
        XCTAssertEqual(events.map(\.2), Array(
            repeating: [.maskCommand, .maskAlternate],
            count: 4
        ))
        XCTAssertEqual(events.map(\.3), [true, false, true, false])
    }

    func testVoiceModeUsesCodexsCurrentRealtimeVoiceShortcut() {
        XCTAssertEqual(CodexModeActionExecutor.realtimeVoiceShortcut.keyCode, 9)
        XCTAssertEqual(
            CodexModeActionExecutor.realtimeVoiceShortcut.flags,
            [.maskControl, .maskShift]
        )
        var pidTargetedEvents = 0
        var hardwareShortcuts: [CodexModeActionExecutor.Shortcut] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            postEvent: { _, _, _, _ in pidTargetedEvents += 1; return true },
            targetProcessIsActive: { $0 == 4242 },
            postHardwareSystemShortcut: { hardwareShortcuts.append($0); return true },
            accessibilityTrusted: { true },
        )

        guard case .success = executor.perform(.toggleVoiceMode) else {
            return XCTFail("Voice Mode should use Codex's foreground accelerator")
        }
        XCTAssertEqual(hardwareShortcuts, [CodexModeActionExecutor.realtimeVoiceShortcut])
        XCTAssertEqual(pidTargetedEvents, 0)
    }

    func testOpenSideChatUsesCodexsBuiltInAppShortcut() {
        XCTAssertEqual(CodexModeActionExecutor.openSideChatShortcut.keyCode, 41)
        XCTAssertEqual(
            CodexModeActionExecutor.openSideChatShortcut.flags,
            [.maskCommand, .maskAlternate]
        )
    }

    func testOpenSideChatUsesTheForegroundSystemAccelerator() {
        var pidTargetedEvents = 0
        var systemShortcuts: [CodexModeActionExecutor.Shortcut] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            postEvent: { _, _, _, _ in pidTargetedEvents += 1; return true },
            targetProcessIsActive: { $0 == 4242 },
            postSystemShortcut: { systemShortcuts.append($0); return true },
            accessibilityTrusted: { true }
        )

        guard case .success = executor.perform(.openSideChat) else {
            return XCTFail("Open in Side Chat should use Codex's foreground accelerator")
        }
        XCTAssertEqual(systemShortcuts, [CodexModeActionExecutor.openSideChatShortcut])
        XCTAssertEqual(pidTargetedEvents, 0)
    }

    func testVoiceModeFailsClosedWhenCodexIsNotFrontmost() {
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            targetProcessIsActive: { _ in false },
            postSystemShortcut: { _ in true },
            accessibilityTrusted: { true },
        )

        guard case .failure(let error) = executor.perform(.toggleVoiceMode) else {
            return XCTFail("a global Voice Mode accelerator must not target another app")
        }
        XCTAssertEqual(error.description, "Codex must be frontmost for this shortcut")
    }

    func testSteerUsesCodexsBuiltInCommandReturnShortcut() {
        var events: [(pid_t, CGKeyCode, CGEventFlags, Bool)] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            postEvent: { events.append(($0, $1, $2, $3)); return true },
            accessibilityTrusted: { true }
        )

        guard case .success = executor.perform(.steerQueuedMessage) else {
            return XCTFail("Steer should use Codex's built-in shortcut")
        }
        XCTAssertEqual(events.map(\.0), [4242, 4242])
        XCTAssertEqual(events.map(\.1), [36, 36])
        XCTAssertEqual(events.map(\.2), [.maskCommand, .maskCommand])
        XCTAssertEqual(events.map(\.3), [true, false])
    }

    func testEditPressesCodexQueuedMessageActionInsteadOfInventingAShortcut() {
        var keyboardEventCount = 0
        var editCount = 0
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            postEvent: { _, _, _, _ in keyboardEventCount += 1; return true },
            accessibilityTrusted: { true },
            editQueuedMessage: {
                editCount += 1
                return .success(())
            }
        )

        guard case .success = executor.perform(.editQueuedMessage) else {
            return XCTFail("queued Edit button should be pressed")
        }
        XCTAssertEqual(editCount, 1)
        XCTAssertEqual(keyboardEventCount, 0)
    }

    func testQueuedEditCanBeCancelledIndependentlyOfOtherCodexVerification() {
        var cancellationCount = 0
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            accessibilityTrusted: { true },
            editQueuedMessage: { .success(()) },
            cancelQueuedMessageEditor: { cancellationCount += 1 }
        )

        executor.cancelQueuedMessageEdit()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testVoiceCannotNestInsideAnEditAccessibilityJourney() {
        var executor: CodexModeActionExecutor!
        var nestedResult: Result<Void, CodexModeActionExecutor.ActionError>?
        executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            targetProcessIsActive: { _ in true },
            postHardwareSystemShortcut: { _ in true },
            accessibilityTrusted: { true },
            editQueuedMessage: {
                nestedResult = executor.perform(.toggleVoiceMode)
                return .success(())
            }
        )

        guard case .success = executor.perform(.editQueuedMessage) else {
            return XCTFail("the outer Edit journey should complete")
        }
        guard case .failure(let error)? = nestedResult else {
            return XCTFail("Voice must not start a nested AX traversal inside Edit")
        }
        XCTAssertEqual(
            error.description,
            "Another Codex Accessibility action is already in progress"
        )
    }

    func testActionsTargetRunningCodexEvenWhenAnotherAppIsFrontmost() {
        var targetPids: [pid_t] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 5150 },
            postEvent: { pid, _, _, _ in targetPids.append(pid); return true },
            accessibilityTrusted: { true }
        )

        guard case .success = executor.perform(.pressEnter) else {
            return XCTFail("background Codex should receive its own shortcut")
        }
        XCTAssertEqual(targetPids, [5150, 5150])
    }

    func testVoiceModeInvokesRealtimeVoiceDirectlyWithoutCreatingAPlainChat() {
        var pidTargetedEvents = 0
        var hardwareShortcuts: [CodexModeActionExecutor.Shortcut] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 9001 },
            postEvent: { _, _, _, _ in pidTargetedEvents += 1; return true },
            targetProcessIsActive: { $0 == 9001 },
            postHardwareSystemShortcut: { hardwareShortcuts.append($0); return true },
            accessibilityTrusted: { true }
        )

        guard case .success = executor.perform(.toggleVoiceMode) else {
            return XCTFail("voice mode should schedule")
        }
        XCTAssertEqual(hardwareShortcuts, [CodexModeActionExecutor.realtimeVoiceShortcut])
        XCTAssertEqual(pidTargetedEvents, 0)
    }

    func testKeyUpIsStillAttemptedWhenKeyDownFails() {
        var phases: [Bool] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 42 },
            postEvent: { _, _, _, isDown in phases.append(isDown); return !isDown },
            accessibilityTrusted: { true }
        )

        guard case .failure = executor.perform(.pressEnter) else {
            return XCTFail("failed down dispatch must be reported")
        }
        XCTAssertEqual(phases, [true, false])
    }

    func testMissingCodexAndAccessibilityFailClosed() {
        var eventCount = 0
        let missing = CodexModeActionExecutor(
            targetProcessResolver: { nil },
            postEvent: { _, _, _, _ in eventCount += 1; return true },
            accessibilityTrusted: { true }
        )
        guard case .failure(let missingError) = missing.perform(.newTask) else {
            return XCTFail("missing Codex must fail")
        }
        XCTAssertEqual(missingError.description, "Codex is not running")

        let untrusted = CodexModeActionExecutor(
            targetProcessResolver: { 42 },
            postEvent: { _, _, _, _ in eventCount += 1; return true },
            accessibilityTrusted: { false }
        )
        guard case .failure(let permissionError) = untrusted.perform(.newTask) else {
            return XCTFail("untrusted dispatch must fail")
        }
        XCTAssertEqual(
            permissionError.description,
            "Accessibility permission is required for Codex shortcuts"
        )
        XCTAssertEqual(eventCount, 0)
    }

    func testLockedSessionBlocksImmediateAndDelayedCodexEvents() {
        var allowed = false
        var hardwareShortcuts: [CodexModeActionExecutor.Shortcut] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 42 },
            targetProcessIsActive: { _ in true },
            postHardwareSystemShortcut: { hardwareShortcuts.append($0); return true },
            accessibilityTrusted: { true },
            inputAllowed: { allowed }
        )

        guard case .failure(let lockedError) = executor.perform(.pressEnter) else {
            return XCTFail("locked session must reject an immediate shortcut")
        }
        XCTAssertEqual(
            lockedError.description,
            "Mouse commands are disabled while macOS is locked"
        )
        XCTAssertTrue(hardwareShortcuts.isEmpty)

        allowed = true
        guard case .success = executor.perform(.toggleVoiceMode) else {
            return XCTFail("unlocked session should invoke realtime voice")
        }
        XCTAssertEqual(hardwareShortcuts, [CodexModeActionExecutor.realtimeVoiceShortcut])
    }

    func testPinUsesTheNormalCodexKeyboardShortcutWithoutAUserOverride() {
        XCTAssertEqual(CodexModeActionExecutor.togglePinShortcut.keyCode, 35)
        XCTAssertEqual(
            CodexModeActionExecutor.togglePinShortcut.flags,
            [.maskCommand, .maskAlternate]
        )
    }
}
