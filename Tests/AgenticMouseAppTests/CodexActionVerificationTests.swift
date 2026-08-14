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
            accessibilityTrusted: { true }
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
