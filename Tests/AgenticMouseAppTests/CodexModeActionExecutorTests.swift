import AppKit
import CoreGraphics
import CodexNativeControls
@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class CodexModeActionExecutorTests: XCTestCase {
    func testClaudeSessionCannotOpenAfterModeExitOrWithoutInputPermission() {
        var eventCount = 0
        var inputAllowed = true
        var trusted = true
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 42 },
            postEvent: { _, _, _, _ in eventCount += 1; return true },
            accessibilityTrusted: { trusted },
            inputAllowed: { inputAllowed }
        )
        guard case .failure = executor.perform(.openClaudeSession, requestAllowed: { false }) else {
            return XCTFail("Leaving the source mode must cancel the picker request")
        }
        inputAllowed = false
        guard case .failure = executor.perform(.openClaudeSession) else {
            return XCTFail("Locked input must never open a tab")
        }
        inputAllowed = true
        trusted = false
        guard case .failure = executor.perform(.openClaudeSession) else {
            return XCTFail("Untrusted input must never open a tab")
        }
        XCTAssertEqual(eventCount, 0)
    }

    func testCodexAdjustmentBurstMeasuresInactivityFromTheMostRecentStep() {
        var burst = CodexMouseAdjustment.Burst()
        XCTAssertTrue(burst.begins(at: 10))
        XCTAssertFalse(burst.begins(at: 14))
        XCTAssertFalse(burst.begins(at: 18.9))
        XCTAssertTrue(burst.begins(at: 24))
        XCTAssertFalse(burst.begins(at: 24.1))
    }

    func testSpeedClickCyclesOnceOnEachMouseAndNeverAfterWheelOrTeardown() {
        var commands: [CodexShortcuts.Command] = []
        let executor = CodexModeActionExecutor(accessibilityTrusted: { true },
            requestNativeCommand: { commands.append($0); return true })
        let state = WheelChordStateMachine()
        for source in [MouseSource.corsair, .razer] {
            state.setActive(.codexResponseSpeed, for: source)
            let before = commands.count
            guard let release = state.release(.codexResponseSpeed, for: source),
                  case .success? = executor.performResponseSpeedClick(release)
            else { return XCTFail("A wheel-free release must cycle once") }
            XCTAssertEqual(commands.count, before + 1)
            XCTAssertNil(state.release(.codexResponseSpeed, for: source), "Duplicate releases are inert")
            for delta: Int64 in [-1, 1] {
                state.setActive(.codexResponseSpeed, for: source)
                _ = state.route(verticalDelta: delta, isContinuous: false)
                _ = state.route(verticalDelta: delta, isContinuous: false)
                XCTAssertNil(executor.performResponseSpeedClick(state.release(for: source)!))
            }
            state.setActive(.codexResponseSpeed, for: source)
            state.clear(source: source)
            XCTAssertNil(state.release(for: source), "Mode exit/lock clears without a click")
            XCTAssertEqual(commands.count, before + 1)
        }
        XCTAssertEqual(commands, [.cycleSpeed, .cycleSpeed])
        XCTAssertNil(executor.performResponseSpeedClick(.init(source: .wand, control: .codexResponseSpeed, didObserveWheelInput: false)))
    }

    func testSpeedClickRetainsInputAndAccessibilityGates() {
        for (allowed, trusted) in [(false, true), (true, false)] {
            let executor = CodexModeActionExecutor(accessibilityTrusted: { trusted }, inputAllowed: { allowed },
                requestNativeCommand: { _ in XCTFail("Blocked click must not reach native engine"); return true })
            guard case .failure? = executor.performResponseSpeedClick(.init(source: .corsair, control: .codexResponseSpeed, didObserveWheelInput: false))
            else { return XCTFail("Click must retain the native executor gates") }
        }
    }

    func testSpeedAndReasoningCallNativeCommandsWithoutAnyCompanion() {
        var commands: [CodexShortcuts.Command] = []
        let executor = CodexModeActionExecutor(accessibilityTrusted: { true },
            requestNativeCommand: { commands.append($0); return true }, recentHardwareTyping: { false })
        for speed in [CodexResponseSpeedAction.increase, .decrease] {
            guard case .success = executor.performResponseSpeed(speed) else { return XCTFail("Native cycle rejected") }
        }
        for reasoning in [CodexReasoningEffortAction.increase, .decrease] {
            guard case .success = executor.performReasoningEffort(reasoning) else { return XCTFail("Native effort rejected") }
        }
        executor.cancelPendingActions()
        XCTAssertEqual(commands, [.cycleSpeed, .cycleSpeed, .increaseReasoning, .decreaseReasoning])
    }

    func testNativeReasoningRetainsRecentTypingProtectionWhileSpeedKeepsItsOwnPolicy() {
        var commands: [CodexShortcuts.Command] = []
        let executor = CodexModeActionExecutor(accessibilityTrusted: { true },
            requestNativeCommand: { commands.append($0); return true }, recentHardwareTyping: { true })
        guard case .failure = executor.performReasoningEffort(.increase),
              case .success = executor.performResponseSpeed(.increase)
        else { return XCTFail("Keep the existing command-specific typing policies") }
        XCTAssertEqual(commands, [.cycleSpeed])
    }

    func testSpeedCancellationClearsOnlyAnAdmittedRequestEvenAfterInputIsBlocked() {
        var allowed = true
        var requests: [CodexResponseSpeedAction] = []
        let executor = CodexModeActionExecutor(
            accessibilityTrusted: { true }, inputAllowed: { allowed },
            requestResponseSpeed: { requests.append($0); return true })
        executor.cancelResponseSpeed()
        XCTAssertTrue(requests.isEmpty, "An unused click must not request a native command")
        guard case .success = executor.performResponseSpeed(.increase) else {
            return XCTFail("Request should be admitted")
        }
        allowed = false
        executor.cancelPendingActions()
        executor.cancelResponseSpeed()
        XCTAssertEqual(requests, [.increase, .cancel])
    }

    func testSpeedWheelUsesTheNativeEngineAndHonoursInputGates() {
        for (allowed, trusted) in [(true, true), (false, true), (true, false)] {
            var requests = 0
            var events = 0
            let executor = CodexModeActionExecutor(
                postEvent: { _, _, _, _ in events += 1; return true },
                accessibilityTrusted: { trusted }, inputAllowed: { allowed },
                requestResponseSpeed: { _ in requests += 1; return true }
            )
            let result = executor.performResponseSpeed(.increase)
            XCTAssertEqual(requests, allowed && trusted ? 1 : 0)
            XCTAssertEqual(events, 0)
            if allowed && trusted {
                guard case .success = result else { return XCTFail("Request should reach the native engine") }
            } else {
                guard case .failure = result else { return XCTFail("Input gate must block the request") }
            }
        }
    }

    func testSpeedWheelPreservesOrderAndReportsRejectedNativeRequest() {
        var requests: [CodexResponseSpeedAction] = []
        let executor = CodexModeActionExecutor(
            accessibilityTrusted: { true },
            requestResponseSpeed: { action in requests.append(action); return action == .increase }
        )
        guard case .success = executor.performResponseSpeed(.increase),
              case .success = executor.performResponseSpeed(.increase),
              case .failure = executor.performResponseSpeed(.decrease)
        else { return XCTFail("each request must retain its direction and report admission rejection") }
        XCTAssertEqual(requests, [.increase, .increase, .decrease])
    }

    func testEverySingleShortcutUsesCodexsVerifiedCommandAndTargetPid() {
        let expected: [(CodexModeAction, CodexModeActionExecutor.Shortcut)] = [
            (.newTask, CodexModeActionExecutor.newTaskShortcut),
            (.togglePin, CodexModeActionExecutor.togglePinShortcut),
            (.toggleMicrophoneMute, CodexModeActionExecutor.microphoneShortcut),
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

    func testReasoningWheelUsesTheNativeFocusEngineBeforePostingKeys() {
        for (allowed, trusted) in [(true, true), (false, true), (true, false)] {
            var requests: [CodexReasoningEffortAction] = []
            var events = 0
            let executor = CodexModeActionExecutor(
                postEvent: { _, _, _, _ in events += 1; return true },
                accessibilityTrusted: { trusted }, inputAllowed: { allowed },
                requestReasoningEffort: { requests.append($0); return true }
            )
            for action in [CodexReasoningEffortAction.increase, .decrease] {
                let result = executor.performReasoningEffort(action)
                if allowed && trusted {
                    guard case .success = result else { return XCTFail("Expected native engine request") }
                } else {
                    guard case .failure = result else { return XCTFail("Input gate must reject reasoning") }
                }
            }
            XCTAssertEqual(requests, allowed && trusted ? [.increase, .decrease] : [])
            XCTAssertEqual(events, 0, "The native engine owns intended-chat focus before sending any key")
        }
    }

    func testMissingNativeBindingOrCodexRejectsBothWheelActions() {
        let executor = CodexModeActionExecutor(accessibilityTrusted: { true }, requestNativeCommand: { _ in false })
        guard case .failure = executor.performResponseSpeed(.increase),
              case .failure = executor.performReasoningEffort(.increase)
        else { return XCTFail("A rejected native command must not be reported as sent") }
    }

    func testReasoningReleaseCancelsOnlyAdmittedWorkEvenAfterLock() {
        var allowed = true
        var cancellations = 0
        let executor = CodexModeActionExecutor(
            accessibilityTrusted: { true }, inputAllowed: { allowed },
            requestReasoningEffort: { _ in true },
            cancelReasoningRequest: { cancellations += 1; return true })
        executor.cancelReasoningEffort()
        XCTAssertEqual(cancellations, 0, "An unused hold must not launch Model Bar")
        guard case .success = executor.performReasoningEffort(.increase) else {
            return XCTFail("Expected admitted reasoning request")
        }
        allowed = false
        executor.cancelPendingActions()
        executor.cancelReasoningEffort()
        XCTAssertEqual(cancellations, 1, "Release/teardown must clear queued ratchets once")
    }

    func testChatHistoryBindingsOccupyCodexNativeMenuSlots() throws {
        struct Binding: Decodable {
            let command: String
            let key: String
        }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bindings = try JSONDecoder().decode(
            [Binding].self,
            from: Data(contentsOf: repository.appendingPathComponent(
                "Integrations/Codex/keybindings.json"
            ))
        )

        // Codex 26.901 registers only binding indices 0 and 1 in its native
        // previous/next menus. A third binding can be saved but never reach
        // that input path. Preserve both existing keyboard bindings as well.
        for (command, functionKey, bracket, arrow) in [
            ("previousThread", "F13", "[", "Left"),
            ("nextThread", "F14", "]", "Right"),
        ] {
            let keys = bindings.filter { $0.command == command }.map(\.key)
            let mouseKey = "Command+Control+Option+Shift+\(functionKey)"
            XCTAssertTrue(keys.prefix(2).contains(mouseKey), "\(command): mouse binding must occupy a native menu slot")
            XCTAssertEqual(Set(keys), Set([
                mouseKey, "Command+Shift+\(bracket)", "Command+Alt+\(arrow)",
            ]))
            XCTAssertEqual(keys.count, 3)
        }
    }

    func testChatHistoryWheelUsesDedicatedSidebarShortcuts() {
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
        XCTAssertEqual(events.map(\.1), [107, 107, 105, 105])
        XCTAssertEqual(events.map(\.2), Array(
            repeating: CodexModeActionExecutor.hyper,
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
        var systemShortcuts: [CodexModeActionExecutor.Shortcut] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            postEvent: { pidTargetedEvents.append(($0, $1, $2, $3)); return true },
            targetProcessIsActive: { _ in false },
            postSystemShortcut: { systemShortcuts.append($0); return true },
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
        XCTAssertTrue(systemShortcuts.isEmpty)
    }

    func testVoiceEventsUseHeyChatsPrivateStateAndFreshTimestamps() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        var states: [Int64] = []
        for isDown in [true, false] {
            let event = try XCTUnwrap(CodexModeActionExecutor.voiceKeyboardEvent(
                source: source, keyCode: 64, flags: CodexModeActionExecutor.hyper, isDown: isDown
            ))
            XCTAssertEqual(event.type, isDown ? .keyDown : .keyUp)
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), 64)
            let state = event.getIntegerValueField(.eventSourceStateID)
            // privateState is a creation sentinel; macOS assigns each private
            // source its own ID. Neither shared system state may be used.
            XCTAssertNotEqual(state, Int64(CGEventSourceStateID.hidSystemState.rawValue))
            XCTAssertNotEqual(state, Int64(CGEventSourceStateID.combinedSessionState.rawValue))
            states.append(state)
            XCTAssertEqual(event.flags, CodexModeActionExecutor.hyper)
            XCTAssertGreaterThan(event.timestamp, 0)
        }
        XCTAssertEqual(states.first, states.last, "press/release share one private key state")
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

    func testCloseTabUsesCodexCommandWAccelerator() {
        var keyboardEventCount = 0
        var systemShortcuts: [CodexModeActionExecutor.Shortcut] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 4242 },
            postEvent: { _, _, _, _ in keyboardEventCount += 1; return true },
            targetProcessIsActive: { $0 == 4242 },
            postSystemShortcut: { systemShortcuts.append($0); return true },
            accessibilityTrusted: { true }
        )

        guard case .success = executor.perform(.closeTab) else {
            return XCTFail("Codex's Close Tab shortcut should be sent")
        }
        XCTAssertEqual(
            systemShortcuts,
            [.init(keyCode: 13, flags: .maskCommand)]
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
