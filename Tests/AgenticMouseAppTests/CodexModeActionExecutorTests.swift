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

    func testVoiceModeUsesCodexsDedicatedAppCommandBinding() {
        XCTAssertEqual(CodexModeActionExecutor.voiceModeShortcut.keyCode, 64)
        XCTAssertEqual(
            CodexModeActionExecutor.voiceModeShortcut.flags,
            CodexModeActionExecutor.hyper
        )
        var pidTargetedEvents: [(pid_t, CGKeyCode, CGEventFlags, Bool)] = []
        var hardwareShortcuts: [CodexModeActionExecutor.Shortcut] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            postEvent: { pidTargetedEvents.append(($0, $1, $2, $3)); return true },
            targetProcessIsActive: { _ in false },
            postHardwareSystemShortcut: { hardwareShortcuts.append($0); return true },
            accessibilityTrusted: { true },
        )

        guard case .success = executor.perform(.toggleVoiceMode) else {
            return XCTFail("Voice Mode should use Codex's app-scoped command")
        }
        XCTAssertEqual(pidTargetedEvents.map(\.0), [4242, 4242])
        XCTAssertEqual(pidTargetedEvents.map(\.1), [64, 64])
        XCTAssertEqual(pidTargetedEvents.map(\.2), [
            CodexModeActionExecutor.hyper,
            CodexModeActionExecutor.hyper,
        ])
        XCTAssertEqual(pidTargetedEvents.map(\.3), [true, false])
        XCTAssertTrue(hardwareShortcuts.isEmpty)
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

    func testVoiceModeTargetsRunningCodexWithoutForegroundActivation() {
        var targetPids: [pid_t] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            postEvent: { pid, _, _, _ in targetPids.append(pid); return true },
            targetProcessIsActive: { _ in false },
            accessibilityTrusted: { true },
        )

        guard case .success = executor.perform(.toggleVoiceMode) else {
            return XCTFail("the app-scoped Voice Mode command should target Codex directly")
        }
        XCTAssertEqual(targetPids, [4242, 4242])
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

    func testAddToChatCannotFallThroughToCodexShortcutTransport() {
        var keyboardEventCount = 0
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            postEvent: { _, _, _, _ in keyboardEventCount += 1; return true },
            accessibilityTrusted: { true }
        )

        guard case .failure(let error) = executor.perform(.addToChat) else {
            return XCTFail("Add to chat must use the VS Code command bridge")
        }
        XCTAssertEqual(
            error.description,
            "Add to chat must use the VS Code command bridge"
        )
        XCTAssertEqual(keyboardEventCount, 0)
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

    func testVoiceModeInvokesComposerVoiceCommandWithoutCreatingAPlainChat() {
        var pidTargetedEvents: [(CGKeyCode, CGEventFlags, Bool)] = []
        var hardwareShortcuts: [CodexModeActionExecutor.Shortcut] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 9001 },
            postEvent: { _, keyCode, flags, isDown in
                pidTargetedEvents.append((keyCode, flags, isDown))
                return true
            },
            postHardwareSystemShortcut: { hardwareShortcuts.append($0); return true },
            accessibilityTrusted: { true }
        )

        guard case .success = executor.perform(.toggleVoiceMode) else {
            return XCTFail("voice mode should schedule")
        }
        XCTAssertEqual(pidTargetedEvents.map(\.0), [64, 64])
        XCTAssertEqual(pidTargetedEvents.map(\.1), [
            CodexModeActionExecutor.hyper,
            CodexModeActionExecutor.hyper,
        ])
        XCTAssertEqual(pidTargetedEvents.map(\.2), [true, false])
        XCTAssertTrue(hardwareShortcuts.isEmpty)
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
        var events: [(CGKeyCode, Bool)] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 42 },
            postEvent: { _, keyCode, _, isDown in
                events.append((keyCode, isDown))
                return true
            },
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
        XCTAssertTrue(events.isEmpty)

        allowed = true
        guard case .success = executor.perform(.toggleVoiceMode) else {
            return XCTFail("unlocked session should invoke the voice command")
        }
        XCTAssertEqual(events.map(\.0), [64, 64])
        XCTAssertEqual(events.map(\.1), [true, false])
    }

    func testPinUsesTheNormalCodexKeyboardShortcutWithoutAUserOverride() {
        XCTAssertEqual(CodexModeActionExecutor.togglePinShortcut.keyCode, 35)
        XCTAssertEqual(
            CodexModeActionExecutor.togglePinShortcut.flags,
            [.maskCommand, .maskAlternate]
        )
    }
}
