import XCTest
@testable import ScimitarKit

/// The safety rule: a pending character belongs to exactly one PID *and* one
/// focused element, and if either moves the character is cancelled — never
/// typed into the new field, never deleted from the old one.
final class TextTargetAnchoringTests: XCTestCase {

    private var engine: MultiTapEngine!

    private let fieldA = TextTarget(processIdentifier: 100, elementIdentity: "field-a", redactedApplication: "app:one")
    private let fieldB = TextTarget(processIdentifier: 100, elementIdentity: "field-b", redactedApplication: "app:one")
    private let otherApp = TextTarget(processIdentifier: 200, elementIdentity: "field-a", redactedApplication: "app:two")

    override func setUp() {
        super.setUp()
        engine = MultiTapEngine(configuration: MultiTapConfiguration(initialShiftState: .lower))
    }

    // MARK: - Same app, different field

    func testFocusMovingToAnotherFieldInTheSameAppCancelsThePendingCharacter() {
        _ = engine.press(.k2, at: 0, target: .ready(fieldA))
        XCTAssertEqual(engine.state.pendingCharacter, "a")

        let outcome = engine.tick(at: 0.1, target: .ready(fieldB))

        XCTAssertTrue(outcome.textCommands.isEmpty, "nothing may be typed into either field")
        XCTAssertNil(engine.state.pendingCharacter)
        XCTAssertEqual(engine.state.lastCancellation, .targetChanged)
    }

    func testSameAppFieldChangeIsDetectedEvenThoughThePidIsUnchanged() {
        XCTAssertEqual(fieldA.processIdentifier, fieldB.processIdentifier)
        _ = engine.press(.k5, at: 0, target: .ready(fieldA))
        let outcome = engine.press(.k5, at: 0.1, target: .ready(fieldB))

        // The second press must not continue the cycle in a different field.
        XCTAssertTrue(outcome.textCommands.isEmpty)
        XCTAssertEqual(engine.state.pendingCharacter, "j", "a brand new character, anchored to the new field")
        XCTAssertEqual(engine.state.pendingCycleIndex, 0)
    }

    // MARK: - Different app

    func testSwitchingApplicationCancelsThePendingCharacter() {
        _ = engine.press(.k2, at: 0, target: .ready(fieldA))
        let outcome = engine.focusChanged(at: 0.2, to: .ready(otherApp))

        XCTAssertTrue(outcome.textCommands.isEmpty)
        XCTAssertNil(engine.state.pendingCharacter)
        XCTAssertEqual(engine.state.lastCancellation, .targetChanged)
    }

    func testCommittedTextIsAlwaysAddressedToTheAnchoredTarget() {
        _ = engine.press(.k2, at: 0, target: .ready(fieldA))
        let outcome = engine.tick(at: 1.5, target: .ready(fieldA))
        XCTAssertEqual(outcome.textCommands, [.insert("a")])
        XCTAssertEqual(outcome.textTarget, fieldA)
    }

    func testAlreadyCommittedTextIsNotAffectedByALaterFocusChange() {
        var commands = engine.press(.k2, at: 0, target: .ready(fieldA)).textCommands
        commands += engine.tick(at: 1.5, target: .ready(fieldA)).textCommands   // commits `a`
        XCTAssertEqual(commands, [.insert("a")])

        let afterSwitch = engine.focusChanged(at: 2.0, to: .ready(otherApp))
        XCTAssertTrue(
            afterSwitch.textCommands.isEmpty,
            "a committed character must never be chased across an app boundary"
        )
    }

    // MARK: - Fail-closed targets

    func testASecureFieldRefusesToAcceptAnything() {
        let outcome = engine.press(.k2, at: 0, target: .refused(.secureField))
        XCTAssertTrue(outcome.textCommands.isEmpty)
        XCTAssertNil(engine.state.pendingCharacter)
        XCTAssertEqual(engine.state.targetRefusal, .secureField)
    }

    func testANonEditableTargetRefusesToAcceptAnything() {
        let outcome = engine.press(.k4, at: 0, target: .refused(.notEditable))
        XCTAssertTrue(outcome.textCommands.isEmpty)
        XCTAssertNil(engine.state.pendingCharacter)
    }

    func testFocusMovingIntoASecureFieldCancelsPendingText() {
        _ = engine.press(.k2, at: 0, target: .ready(fieldA))
        let outcome = engine.tick(at: 0.1, target: .refused(.secureField))

        XCTAssertTrue(outcome.textCommands.isEmpty)
        XCTAssertNil(engine.state.pendingCharacter)
        XCTAssertEqual(engine.state.lastCancellation, .targetRefused(.secureField))
    }

    func testMissingAccessibilityPermissionRefusesEverything() {
        let outcome = engine.press(.k2, at: 0, target: .refused(.accessibilityPermissionMissing))
        XCTAssertTrue(outcome.textCommands.isEmpty)
        XCTAssertEqual(engine.state.targetRefusal, .accessibilityPermissionMissing)
    }

    func testSpaceIsAlsoRefusedWhenThereIsNoUsableTarget() {
        _ = engine.press(.k11, at: 0, target: .refused(.unknown))
        let outcome = engine.release(.k11, at: 0.05, target: .refused(.unknown))
        XCTAssertTrue(outcome.textCommands.isEmpty)
    }

    // MARK: - Exit-on-focus-change policy

    func testCancelPendingAndExitPolicyLeavesTheMode() {
        engine = MultiTapEngine(
            configuration: MultiTapConfiguration(focusChangePolicy: .cancelPendingAndExit)
        )
        _ = engine.press(.k2, at: 0, target: .ready(fieldA))
        let outcome = engine.focusChanged(at: 0.2, to: .ready(otherApp))
        XCTAssertTrue(outcome.exitRequested)
        XCTAssertTrue(outcome.textCommands.isEmpty)
    }

    func testCancelPendingAndExitPolicyAlsoAppliesToPolledSameAppFieldChanges() {
        engine = MultiTapEngine(
            configuration: MultiTapConfiguration(focusChangePolicy: .cancelPendingAndExit)
        )
        _ = engine.press(.k2, at: 0, target: .ready(fieldA))

        let outcome = engine.tick(at: 0.1, target: .ready(fieldB))

        XCTAssertTrue(outcome.exitRequested)
        XCTAssertTrue(outcome.textCommands.isEmpty)
        XCTAssertNil(engine.state.pendingCharacter)
        XCTAssertEqual(engine.state.lastCancellation, .targetChanged)
    }

    // MARK: - livePreview stays anchored too

    func testLivePreviewIsStillTargetAnchoredAndNeverCrossesAppBoundaries() {
        engine = MultiTapEngine(
            configuration: MultiTapConfiguration(echoPolicy: .livePreview, initialShiftState: .lower)
        )

        let first = engine.press(.k2, at: 0, target: .ready(fieldA))
        XCTAssertEqual(first.textCommands, [.insert("a")])
        XCTAssertEqual(first.textTarget, fieldA)

        let second = engine.press(.k2, at: 0.1, target: .ready(fieldA))
        XCTAssertEqual(second.textCommands, [.deleteBackward(1), .insert("b")])
        XCTAssertEqual(second.textTarget, fieldA, "the corrective backspace goes to the original field")

        // Now focus moves. The already-typed `b` stays where it is, and no
        // backspace is ever sent to the new field.
        let moved = engine.tick(at: 0.2, target: .ready(otherApp))
        XCTAssertTrue(
            moved.textCommands.isEmpty,
            "a rewrite must never follow the user into a different application"
        )
        XCTAssertEqual(engine.state.lastCancellation, .targetChanged)
    }

    func testRecordingTextOutputKeepsTargetsSeparate() throws {
        let output = RecordingTextOutput()
        try output.apply([.insert("a")], to: fieldA)
        try output.apply([.insert("z")], to: otherApp)

        XCTAssertEqual(output.buffer(for: fieldA), "a")
        XCTAssertEqual(output.buffer(for: otherApp), "z")
    }
}
