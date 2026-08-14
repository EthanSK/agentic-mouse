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
            (.toggleVoiceMode, CodexModeActionExecutor.startVoiceShortcut),
            (.steerQueuedMessage, CodexModeActionExecutor.steerShortcut),
            (.pressEnter, CodexModeActionExecutor.submitShortcut),
            (.increaseReasoningEffort, CodexModeActionExecutor.increaseReasoningEffortShortcut),
            (.decreaseReasoningEffort, CodexModeActionExecutor.decreaseReasoningEffortShortcut),
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

    func testNewVoiceChatCreatesATaskThenSchedulesVoiceMode() {
        var events: [(CGKeyCode, Bool)] = []
        var scheduledDelay: TimeInterval?
        var scheduled: (@Sendable @MainActor () -> Void)?
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 9001 },
            postEvent: { _, keyCode, _, isDown in
                events.append((keyCode, isDown))
                return true
            },
            accessibilityTrusted: { true },
            scheduleDelayedAction: { delay, action in
                scheduledDelay = delay
                scheduled = action
            }
        )

        guard case .success = executor.perform(.startNewVoiceChat) else {
            return XCTFail("new voice chat should schedule")
        }
        XCTAssertEqual(
            events.map(\.0),
            [CodexModeActionExecutor.newTaskShortcut.keyCode,
             CodexModeActionExecutor.newTaskShortcut.keyCode]
        )
        XCTAssertEqual(events.map(\.1), [true, false])
        XCTAssertEqual(scheduledDelay, 0.75)

        scheduled?()
        XCTAssertEqual(
            events.map(\.0),
            [CodexModeActionExecutor.newTaskShortcut.keyCode,
             CodexModeActionExecutor.newTaskShortcut.keyCode,
             CodexModeActionExecutor.startVoiceShortcut.keyCode,
             CodexModeActionExecutor.startVoiceShortcut.keyCode]
        )
        XCTAssertEqual(events.map(\.1), [true, false, true, false])
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
        var delayed: (@Sendable @MainActor () -> Void)?
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 42 },
            postEvent: { _, keyCode, _, isDown in
                events.append((keyCode, isDown))
                return true
            },
            accessibilityTrusted: { true },
            inputAllowed: { allowed },
            scheduleDelayedAction: { _, action in delayed = action }
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
        guard case .success = executor.perform(.startNewVoiceChat) else {
            return XCTFail("unlocked session should schedule the second shortcut")
        }
        XCTAssertEqual(events.count, 2)

        allowed = false
        delayed?()
        XCTAssertEqual(events.count, 2, "lock after scheduling must suppress the delayed shortcut")
    }

    func testPinUsesTheNormalCodexKeyboardShortcutWithoutAUserOverride() {
        XCTAssertEqual(CodexModeActionExecutor.togglePinShortcut.keyCode, 35)
        XCTAssertEqual(
            CodexModeActionExecutor.togglePinShortcut.flags,
            [.maskCommand, .maskAlternate]
        )
    }
}
