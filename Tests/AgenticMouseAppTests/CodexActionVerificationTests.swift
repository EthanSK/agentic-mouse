import Foundation
@testable import AgenticMouseApp
import XCTest

@MainActor
final class CodexActionVerificationTests: XCTestCase {
    func testPinSetDeltaConfirmsExactlyOneRealCodexStateChange() {
        let before: Set<String> = ["thread-a"]

        XCTAssertEqual(
            CodexPinChangeVerifier.feedback(
                before: before,
                after: ["thread-a", "thread-b"]
            ),
            .confirmed("Pinned — confirmed by Codex")
        )
        XCTAssertEqual(
            CodexPinChangeVerifier.feedback(before: before, after: []),
            .confirmed("Unpinned — confirmed by Codex")
        )
    }

    func testPinSetDeltaRefusesAmbiguousAndUnchangedResults() {
        let before: Set<String> = ["thread-a"]

        XCTAssertNil(CodexPinChangeVerifier.feedback(before: before, after: before))
        XCTAssertEqual(
            CodexPinChangeVerifier.feedback(
                before: before,
                after: ["thread-b"]
            ),
            .notConfirmed("Pin change was ambiguous — not confirmed")
        )
    }

    func testExecutorChecksCodexPinStateBeforeClaimingSuccess() {
        var pinned: Set<String> = ["thread-a"]
        var scheduled: [@Sendable @MainActor () -> Void] = []
        var feedback: [CodexActionFeedback] = []
        let verifier = CodexPinChangeVerifier(
            readPinnedThreadIDs: { pinned },
            schedule: { _, action in scheduled.append(action) },
            retryDelays: [0]
        )
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 42 },
            postEvent: { _, _, _, _ in true },
            accessibilityTrusted: { true },
            pinChangeVerifier: verifier
        )

        guard case .success = executor.perform(.togglePin, feedback: { feedback.append($0) }) else {
            return XCTFail("pin shortcut should dispatch")
        }
        XCTAssertEqual(feedback, [.checking("Pin change sent — checking Codex state")])

        pinned.insert("thread-b")
        scheduled.removeFirst()()
        XCTAssertEqual(
            feedback,
            [
                .checking("Pin change sent — checking Codex state"),
                .confirmed("Pinned — confirmed by Codex"),
            ]
        )
    }

    func testExecutorReportsUnconfirmedWhenCodexPinStateDoesNotChange() {
        let pinned: Set<String> = ["thread-a"]
        var scheduled: [@Sendable @MainActor () -> Void] = []
        var feedback: [CodexActionFeedback] = []
        let verifier = CodexPinChangeVerifier(
            readPinnedThreadIDs: { pinned },
            schedule: { _, action in scheduled.append(action) },
            retryDelays: [0]
        )
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 42 },
            postEvent: { _, _, _, _ in true },
            accessibilityTrusted: { true },
            pinChangeVerifier: verifier
        )

        _ = executor.perform(.togglePin, feedback: { feedback.append($0) })
        scheduled.removeFirst()()

        XCTAssertEqual(
            feedback.last,
            .notConfirmed("Pin change was not confirmed")
        )
    }

    func testRapidSecondPinToggleCancelsConfirmationInsteadOfGuessing() {
        let pinned: Set<String> = ["thread-a"]
        var scheduled: [@Sendable @MainActor () -> Void] = []
        var firstFeedback: [CodexActionFeedback] = []
        var secondFeedback: [CodexActionFeedback] = []
        let verifier = CodexPinChangeVerifier(
            readPinnedThreadIDs: { pinned },
            schedule: { _, action in scheduled.append(action) },
            retryDelays: [0]
        )
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 42 },
            postEvent: { _, _, _, _ in true },
            accessibilityTrusted: { true },
            pinChangeVerifier: verifier
        )

        _ = executor.perform(.togglePin, feedback: { firstFeedback.append($0) })
        _ = executor.perform(.togglePin, feedback: { secondFeedback.append($0) })
        scheduled.forEach { $0() }

        XCTAssertEqual(firstFeedback, [.checking("Pin change sent — checking Codex state")])
        XCTAssertEqual(
            secondFeedback,
            [.sentUnverified("Rapid pin toggle sent — confirmation cancelled")]
        )
    }

    func testOtherCodexActionsNeverPretendDispatchMeansCompletion() {
        var feedback: [CodexActionFeedback] = []
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 42 },
            postEvent: { _, _, _, _ in true },
            accessibilityTrusted: { true },
            editQueuedMessage: { .success(()) }
        )

        guard case .success = executor.perform(.steerQueuedMessage, feedback: {
            feedback.append($0)
        }) else {
            return XCTFail("steer shortcut should dispatch")
        }
        XCTAssertEqual(
            feedback,
            [.sentUnverified("Steer queued message sent — result not exposed by Codex")]
        )

        feedback.removeAll()
        guard case .success = executor.perform(.editQueuedMessage, feedback: {
            feedback.append($0)
        }) else {
            return XCTFail("edit action should dispatch")
        }
        XCTAssertEqual(
            feedback,
            [.sentUnverified("Edit queued message pressed — result not confirmed by Codex")]
        )
    }

    func testVoiceStateTransitionIsTheOnlyConfirmedVoiceResult() {
        XCTAssertEqual(
            CodexVoiceSessionVerifier.feedback(before: .inactive, after: .active),
            .confirmed("Voice mode started — confirmed by Codex")
        )
        XCTAssertEqual(
            CodexVoiceSessionVerifier.feedback(before: .active, after: .inactive),
            .confirmed("Voice mode stopped — confirmed by Codex")
        )
        XCTAssertNil(CodexVoiceSessionVerifier.feedback(before: .active, after: .active))
    }

    func testVoiceDispatchNeverPretendsAnUnobservedChangeSucceeded() {
        let state: CodexVoiceSessionStateReader.State = .inactive
        var scheduled: [@Sendable @MainActor () -> Void] = []
        var feedback: [CodexActionFeedback] = []
        let verifier = CodexVoiceSessionVerifier(
            readState: { state },
            schedule: { _, action in scheduled.append(action) },
            retryDelays: [0]
        )
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 42 },
            targetProcessIsActive: { _ in true },
            postHardwareSystemShortcut: { _ in true },
            accessibilityTrusted: { true },
            voiceSessionVerifier: verifier
        )

        guard case .success = executor.perform(.toggleVoiceMode, feedback: {
            feedback.append($0)
        }) else {
            return XCTFail("voice shortcut should dispatch")
        }
        XCTAssertEqual(
            feedback,
            [.checking("Voice mode shortcut sent — checking Codex state")]
        )
        scheduled.removeFirst()()
        XCTAssertEqual(
            feedback.last,
            .notConfirmed("Voice mode change was not confirmed by Codex")
        )
    }

    func testLockedVoiceActionDoesNotReadCodexAccessibilityState() {
        var stateReadCount = 0
        let verifier = CodexVoiceSessionVerifier(
            readState: { stateReadCount += 1; return .inactive },
            retryDelays: []
        )
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 42 },
            targetProcessIsActive: { _ in true },
            postHardwareSystemShortcut: { _ in true },
            accessibilityTrusted: { true },
            inputAllowed: { false },
            voiceSessionVerifier: verifier
        )

        guard case .failure = executor.perform(.toggleVoiceMode) else {
            return XCTFail("locked Voice Mode must fail before reading Codex")
        }
        XCTAssertEqual(stateReadCount, 0)
    }

    func testCancellingCodexActionsSuppressesDelayedVoiceFeedback() {
        var state: CodexVoiceSessionStateReader.State = .inactive
        var scheduled: [@Sendable @MainActor () -> Void] = []
        var feedback: [CodexActionFeedback] = []
        let verifier = CodexVoiceSessionVerifier(
            readState: { state },
            schedule: { _, action in scheduled.append(action) },
            retryDelays: [0]
        )
        let executor = CodexModeActionExecutor(
            targetProcessResolver: { 42 },
            targetProcessIsActive: { _ in true },
            postHardwareSystemShortcut: { _ in true },
            accessibilityTrusted: { true },
            voiceSessionVerifier: verifier
        )

        _ = executor.perform(.toggleVoiceMode, feedback: { feedback.append($0) })
        executor.cancelPendingActions()
        state = .active
        scheduled.removeFirst()()

        XCTAssertEqual(
            feedback,
            [.checking("Voice mode shortcut sent — checking Codex state")]
        )
    }

    func testDelayedVoicePollRechecksInputAndAccessibilityBeforeReadingCodex() {
        var inputAllowed = true
        var trusted = true
        var scheduled: [@Sendable @MainActor () -> Void] = []
        var postDispatchReadCount = 0
        var feedback: [CodexActionFeedback] = []
        let verifier = CodexVoiceSessionVerifier(
            readState: { postDispatchReadCount += 1; return .active },
            captureState: { .inactive },
            schedule: { _, action in scheduled.append(action) },
            retryDelays: [0],
            inputAllowed: { inputAllowed },
            accessibilityTrusted: { trusted }
        )

        verifier.verify(from: .inactive) { feedback.append($0) }
        inputAllowed = false
        scheduled.removeFirst()()
        XCTAssertEqual(postDispatchReadCount, 0)
        XCTAssertEqual(
            feedback,
            [.notConfirmed("Voice mode change was not confirmed by Codex")]
        )

        inputAllowed = true
        verifier.verify(from: .inactive) { feedback.append($0) }
        trusted = false
        scheduled.removeFirst()()
        XCTAssertEqual(postDispatchReadCount, 0)
    }

    func testStateReaderUsesOnlyCodexPinnedThreadIds() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateURL = directory.appendingPathComponent("state.json")
        let data = try JSONSerialization.data(withJSONObject: [
            "pinned-thread-ids": ["thread-a", "thread-b"],
            "unrelated": ["thread-c"],
        ])
        try data.write(to: stateURL)

        XCTAssertEqual(
            try CodexPinnedThreadStateReader(stateURL: stateURL).read(),
            ["thread-a", "thread-b"]
        )
    }
}
