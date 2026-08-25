import ApplicationServices
@testable import AgenticMouseApp
import XCTest

@MainActor
final class CodexQueuedMessageSteererTests: XCTestCase {
    func testBoundedTraversalDeduplicatesAliasesBeforeTheyConsumeTheLimit() {
        let children: [Int: [Int]] = [
            0: [1, 1],
            1: [2, 2],
            2: [3, 3],
            3: [0],
        ]

        XCTAssertEqual(
            CodexQueuedMessageSteerer.boundedBreadthFirstTraversal(
                roots: [0],
                limit: 4,
                identity: { $0 },
                children: { children[$0] ?? [] }
            ),
            [0, 1, 2, 3]
        )
    }

    func testBoundedTraversalReportsWhenCapOrCancellationMakesItPartial() {
        let capped = CodexQueuedMessageSteerer.boundedBreadthFirstTraversalResult(
            roots: [0],
            limit: 2,
            identity: { $0 },
            children: { $0 < 3 ? [$0 + 1] : [] }
        )
        XCTAssertEqual(capped.nodes, [0, 1])
        XCTAssertFalse(capped.completed)

        var allowed = true
        let cancelled = CodexQueuedMessageSteerer.boundedBreadthFirstTraversalResult(
            roots: [0],
            limit: 4,
            identity: { $0 },
            children: { node in
                if node == 0 { allowed = false }
                return [node + 1]
            },
            shouldContinue: { allowed }
        )
        XCTAssertEqual(cancelled.nodes, [0])
        XCTAssertFalse(cancelled.completed)
    }

    func testEditSnapshotPrefilterAcceptsOnlyExactQueuedRowButtons() {
        let buttonRole = kAXButtonRole as String
        XCTAssertTrue(CodexQueuedMessageSteerer.isPotentialQueuedRowControl(
            role: buttonRole,
            labels: ["steer"]
        ))
        XCTAssertTrue(CodexQueuedMessageSteerer.isPotentialQueuedRowControl(
            role: buttonRole,
            labels: ["delete queued message"]
        ))
        XCTAssertTrue(CodexQueuedMessageSteerer.isPotentialQueuedRowControl(
            role: buttonRole,
            labels: ["queued message actions"]
        ))
        XCTAssertFalse(CodexQueuedMessageSteerer.isPotentialQueuedRowControl(
            role: kAXStaticTextRole as String,
            labels: ["steer"]
        ))
        XCTAssertFalse(CodexQueuedMessageSteerer.isPotentialQueuedRowControl(
            role: buttonRole,
            labels: ["steer this queued message later"]
        ))
    }

    func testStrictQueuedRowCandidateTakesPrecedenceOverFallbackPosition() {
        let fallback = candidate(index: 1, y: 100)
        let strict = candidate(index: 2, y: 300, strict: true)

        XCTAssertEqual(
            CodexQueuedMessageSteerer.selectSteerCandidate([fallback, strict]),
            .strict(2)
        )
    }

    func testOneExactVisibleCandidateUsesTheFallback() {
        XCTAssertEqual(
            CodexQueuedMessageSteerer.selectSteerCandidate([candidate(index: 7, y: 220)]),
            .fallback(7)
        )
    }

    func testFallbackChoosesTheVisuallyHighestQueuedCandidate() {
        XCTAssertEqual(
            CodexQueuedMessageSteerer.selectSteerCandidate([
                candidate(index: 4, y: 420),
                candidate(index: 2, y: 180),
                candidate(index: 3, y: 300),
            ]),
            .fallback(2)
        )
    }

    func testFallbackRejectsInvalidHiddenAndNonpressableCandidates() {
        XCTAssertNil(CodexQueuedMessageSteerer.selectSteerCandidate([
            candidate(index: 1, y: 100, width: 2),
            candidate(index: 2, y: 200, enabled: false),
            candidate(index: 3, y: 300, pressable: false),
            candidate(index: 4, y: 400, insideWindow: false),
            candidate(index: 5, y: .infinity),
        ]))
    }

    func testFallbackFailsClosedWhenTheTopCandidatesAreVisuallyTied() {
        XCTAssertNil(CodexQueuedMessageSteerer.selectSteerCandidate([
            candidate(index: 1, y: 100),
            candidate(index: 2, y: 102),
        ]))
    }

    func testMatchesOnlyAPressableCodexSteerButtonLabel() {
        XCTAssertTrue(CodexQueuedMessageSteerer.isQueuedSteerButton(
            role: kAXButtonRole as String,
            title: "Steer",
            description: nil,
            help: nil
        ))
        XCTAssertTrue(CodexQueuedMessageSteerer.isQueuedSteerButton(
            role: kAXButtonRole as String,
            title: "Submit without interrupting the model",
            description: nil,
            help: nil
        ))
        XCTAssertTrue(CodexQueuedMessageSteerer.isQueuedSteerButton(
            role: kAXButtonRole as String,
            title: nil,
            description: "Submit without interrupting the model",
            help: nil
        ))
        XCTAssertTrue(CodexQueuedMessageSteerer.isQueuedSteerButton(
            role: kAXButtonRole as String,
            title: nil,
            description: nil,
            help: "Submit without interrupting the model"
        ))
        XCTAssertFalse(CodexQueuedMessageSteerer.isQueuedSteerButton(
            role: kAXStaticTextRole as String,
            title: "Steer",
            description: nil,
            help: nil
        ))
        XCTAssertFalse(CodexQueuedMessageSteerer.isQueuedSteerButton(
            role: kAXButtonRole as String,
            title: "Queue",
            description: nil,
            help: nil
        ))
        XCTAssertFalse(CodexQueuedMessageSteerer.isQueuedSteerButton(
            role: kAXButtonRole as String,
            title: "Queue",
            description: nil,
            help: "Choose whether a future message should steer"
        ))
    }

    func testMatchesOnlyAnExactQueuedEditButtonLabel() {
        XCTAssertTrue(CodexQueuedMessageSteerer.isQueuedActionButton(
            .edit,
            role: kAXButtonRole as String,
            title: "Edit message",
            description: nil,
            help: nil
        ))
        XCTAssertFalse(CodexQueuedMessageSteerer.isQueuedActionButton(
            .edit,
            role: kAXButtonRole as String,
            title: "Edit",
            description: nil,
            help: nil
        ))
        XCTAssertFalse(CodexQueuedMessageSteerer.isQueuedActionButton(
            .edit,
            role: kAXButtonRole as String,
            title: "Edit keybindings",
            description: nil,
            help: nil
        ))
    }

    func testQueuedRowRequiresVisibleOrderedControlsOnOneLine() {
        XCTAssertTrue(CodexQueuedMessageSteerer.formsQueuedMessageRow(
            actionFrame: CGRect(x: 100, y: 300, width: 74, height: 28),
            deleteFrame: CGRect(x: 180, y: 300, width: 28, height: 28),
            actionMenuFrame: CGRect(x: 214, y: 300, width: 28, height: 28)
        ))

        XCTAssertFalse(CodexQueuedMessageSteerer.formsQueuedMessageRow(
            actionFrame: CGRect(x: 100, y: 300, width: 74, height: 2),
            deleteFrame: CGRect(x: 180, y: 300, width: 28, height: 2),
            actionMenuFrame: CGRect(x: 214, y: 300, width: 28, height: 2)
        ), "clipped controls from a broad flattened conversation must be rejected")
        XCTAssertFalse(CodexQueuedMessageSteerer.formsQueuedMessageRow(
            actionFrame: CGRect(x: 100, y: 300, width: 74, height: 28),
            deleteFrame: CGRect(x: 180, y: 340, width: 28, height: 28),
            actionMenuFrame: CGRect(x: 214, y: 300, width: 28, height: 28)
        ), "controls from different rows must be rejected")
        XCTAssertFalse(CodexQueuedMessageSteerer.formsQueuedMessageRow(
            actionFrame: CGRect(x: 214, y: 300, width: 74, height: 28),
            deleteFrame: CGRect(x: 180, y: 300, width: 28, height: 28),
            actionMenuFrame: CGRect(x: 100, y: 300, width: 28, height: 28)
        ), "the exact Codex left-to-right row order is required")
    }

    func testFailsClosedWhenNoQueuedSteerButtonExists() {
        let steerer = CodexQueuedMessageSteerer(
            targetProcessResolver: { 42 },
            accessibilityTrusted: { true },
            inputAllowed: { true },
            pressQueuedButton: { _, _ in false }
        )

        guard case .failure(let error) = steerer.perform() else {
            return XCTFail("missing queued Steer action must fail")
        }
        XCTAssertEqual(
            error.description,
            "No queued Codex message with a Steer action was found"
        )
    }

    func testLockAndAccessibilityGatesPreventAnyUIAction() {
        var pressCount = 0
        let locked = CodexQueuedMessageSteerer(
            targetProcessResolver: { 42 },
            accessibilityTrusted: { true },
            inputAllowed: { false },
            pressQueuedButton: { _, _ in pressCount += 1; return true }
        )
        guard case .failure(let lockedError) = locked.perform() else {
            return XCTFail("locked session must fail closed")
        }
        XCTAssertEqual(
            lockedError.description,
            "Mouse commands are disabled while macOS is locked"
        )

        let untrusted = CodexQueuedMessageSteerer(
            targetProcessResolver: { 42 },
            accessibilityTrusted: { false },
            inputAllowed: { true },
            pressQueuedButton: { _, _ in pressCount += 1; return true }
        )
        guard case .failure(let permissionError) = untrusted.perform() else {
            return XCTFail("untrusted session must fail closed")
        }
        XCTAssertEqual(
            permissionError.description,
            "Accessibility permission is required for Codex shortcuts"
        )
        XCTAssertEqual(pressCount, 0)
    }

    func testEditUsesTheExactQueuedActionAndReportsItsOwnMissingState() {
        var observed: CodexQueuedMessageAction?
        let editor = CodexQueuedMessageSteerer(
            targetProcessResolver: { 42 },
            accessibilityTrusted: { true },
            inputAllowed: { true },
            pressQueuedButton: { _, action in observed = action; return false }
        )

        guard case .failure(let error) = editor.perform(.edit) else {
            return XCTFail("missing queued Edit action must fail")
        }
        XCTAssertEqual(observed, .edit)
        XCTAssertEqual(error.description, "No queued Codex message with an Edit action was found")
    }

    func testEditRejectsAReentrantJourney() {
        var editor: CodexQueuedMessageSteerer!
        var nestedResult: Result<Void, ApplicationShortcutDispatcher.DispatchError>?
        editor = CodexQueuedMessageSteerer(
            targetProcessResolver: { 42 },
            accessibilityTrusted: { true },
            inputAllowed: { true },
            pressQueuedButton: { _, action in
                XCTAssertEqual(action, .edit)
                nestedResult = editor.perform(.edit)
                return true
            }
        )

        guard case .success = editor.perform(.edit) else {
            return XCTFail("the outer exact Edit journey should complete")
        }
        guard case .failure(let error)? = nestedResult else {
            return XCTFail("a nested Edit journey must fail closed")
        }
        XCTAssertEqual(error.description, "Edit Queued Message is already in progress")
    }

    func testCancellingAnEditJourneyPreventsLateSuccess() {
        var editor: CodexQueuedMessageSteerer!
        editor = CodexQueuedMessageSteerer(
            targetProcessResolver: { 42 },
            accessibilityTrusted: { true },
            inputAllowed: { true },
            pressQueuedButton: { _, _ in
                editor.cancelPendingAction()
                return true
            }
        )

        guard case .failure(let error) = editor.perform(.edit) else {
            return XCTFail("a cancelled Edit journey must not report success")
        }
        XCTAssertEqual(
            error.description,
            "No queued Codex message with an Edit action was found"
        )
    }

    func testEditJourneyFailsClosedAfterItsWallClockBudgetExpires() {
        var now: TimeInterval = 10
        let editor = CodexQueuedMessageSteerer(
            targetProcessResolver: { 42 },
            accessibilityTrusted: { true },
            inputAllowed: { true },
            pressQueuedButton: { _, _ in
                now += CodexQueuedMessageSteerer.editJourneyTimeout + 0.1
                return true
            },
            uptime: { now }
        )

        guard case .failure(let error) = editor.perform(.edit) else {
            return XCTFail("an expired Edit journey must not report success")
        }
        XCTAssertEqual(error.description, "No queued Codex message with an Edit action was found")
    }

    func testQueuedActionsMenuSelectionChoosesOnlyAnUnambiguousHighestRow() {
        XCTAssertEqual(CodexQueuedMessageSteerer.selectVisuallyHighestMenuCandidate([
            .init(index: 4, frame: CGRect(x: 200, y: 400, width: 28, height: 28)),
            .init(index: 2, frame: CGRect(x: 200, y: 300, width: 28, height: 28)),
        ]), 2)
        XCTAssertNil(CodexQueuedMessageSteerer.selectVisuallyHighestMenuCandidate([
            .init(index: 1, frame: CGRect(x: 200, y: 300, width: 28, height: 28)),
            .init(index: 2, frame: CGRect(x: 260, y: 303, width: 28, height: 28)),
        ]))
    }

    private func candidate(
        index: Int,
        y: CGFloat,
        width: CGFloat = 80,
        enabled: Bool = true,
        pressable: Bool = true,
        insideWindow: Bool = true,
        strict: Bool = false
    ) -> CodexQueuedMessageSteerer.SteerCandidate {
        CodexQueuedMessageSteerer.SteerCandidate(
            index: index,
            frame: CGRect(x: 100, y: y, width: width, height: 28),
            hasExactLabel: true,
            isEnabled: enabled,
            supportsPress: pressable,
            isInsideFocusedWindow: insideWindow,
            isStrictQueuedRowMatch: strict
        )
    }
}
