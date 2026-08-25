import XCTest
@testable import ScimitarKit

/// The buffered (`commitOnly`) multi-tap state machine: cycling, timeout,
/// commit, case, digits, punctuation and the command keys.
final class MultiTapEngineTests: XCTestCase {

    private var engine: MultiTapEngine!
    private var target: TextTarget!
    private var resolution: TextTargetResolution!

    override func setUp() {
        super.setUp()
        engine = MultiTapEngine(
            keymap: .classic,
            configuration: MultiTapConfiguration(initialShiftState: .lower)
        )
        target = TextTarget(processIdentifier: 100, elementIdentity: "field-a", redactedApplication: "app:test")
        resolution = .ready(target)
    }

    // MARK: - Helpers

    /// Taps a key `count` times in quick succession, then waits past the
    /// timeout so the character commits. Returns the text produced.
    @discardableResult
    private func type(_ key: MultiTapKey, times: Int, startingAt start: TimeInterval = 0) -> [TextCommand] {
        var commands: [TextCommand] = []
        var now = start
        for _ in 0..<times {
            commands += engine.press(key, at: now, target: resolution).textCommands
            now += 0.05
            commands += engine.release(key, at: now, target: resolution).textCommands
            now += 0.1
        }
        commands += engine.tick(at: now + 1.0, target: resolution).textCommands
        return commands
    }

    private func inserted(_ commands: [TextCommand]) -> String {
        commands.reduce(into: "") { result, command in
            if case .insert(let text) = command { result += text }
        }
    }

    // MARK: - The default is buffered

    func testDefaultEchoPolicyIsBufferedCommitOnly() {
        XCTAssertEqual(MultiTapConfiguration.default.echoPolicy, .commitOnly)
        XCTAssertTrue(MultiTapConfiguration.default.echoPolicy.isBuffered)
        XCTAssertEqual(MultiTapConfiguration.default.focusChangePolicy, .cancelPending)
    }

    func testNothingIsTypedUntilTheCharacterCommits() {
        let first = engine.press(.k2, at: 0, target: resolution)
        XCTAssertTrue(first.textCommands.isEmpty, "buffered mode must not touch the app mid-cycle")
        XCTAssertEqual(engine.state.pendingCharacter, "a")

        let second = engine.press(.k2, at: 0.2, target: resolution)
        XCTAssertTrue(second.textCommands.isEmpty)
        XCTAssertEqual(engine.state.pendingCharacter, "b")

        let commit = engine.tick(at: 1.5, target: resolution)
        XCTAssertEqual(commit.textCommands, [.insert("b")])
        XCTAssertNil(engine.state.pendingCharacter)
    }

    func testTwoQuickKeyEightTapsPreviewThenCommitUExactlyOnce() {
        engine = MultiTapEngine(
            keymap: .modesKeypad,
            configuration: MultiTapConfiguration(initialShiftState: .lower)
        )

        var commands = engine.press(.k8, at: 0, target: resolution).textCommands
        commands += engine.release(.k8, at: 0.05, target: resolution).textCommands
        commands += engine.press(.k8, at: 0.15, target: resolution).textCommands
        commands += engine.release(.k8, at: 0.20, target: resolution).textCommands

        XCTAssertTrue(commands.isEmpty)
        XCTAssertEqual(engine.state.pendingCharacter, "u")

        commands += engine.tick(at: 1.2, target: resolution).textCommands
        XCTAssertEqual(commands, [.insert("u")])
        XCTAssertNil(engine.state.pendingCharacter)
    }

    func testBufferedModeNeverEmitsABackspaceWhileCycling() {
        var commands: [TextCommand] = []
        for index in 0..<4 {
            commands += engine.press(.k7, at: Double(index) * 0.1, target: resolution).textCommands
        }
        commands += engine.tick(at: 2, target: resolution).textCommands

        XCTAssertFalse(
            commands.contains { if case .deleteBackward = $0 { return true }; return false },
            "the safe default must never issue a backspace-and-replace loop"
        )
        XCTAssertEqual(inserted(commands), "s")
    }

    // MARK: - Cycling

    func testCyclesThroughTheClassicLetters() {
        XCTAssertEqual(inserted(type(.k2, times: 1)), "a")
        setUp(); XCTAssertEqual(inserted(type(.k2, times: 2)), "b")
        setUp(); XCTAssertEqual(inserted(type(.k2, times: 3)), "c")
        setUp(); XCTAssertEqual(inserted(type(.k7, times: 4)), "s")
        setUp(); XCTAssertEqual(inserted(type(.k9, times: 4)), "z")
    }

    func testCycleWrapsAround() {
        // 2 has three letters; a fourth tap returns to `a`.
        XCTAssertEqual(inserted(type(.k2, times: 4)), "a")
    }

    func testItuLetterMappingMatchesEveryPhoneEverMade() {
        let expected: [MultiTapKey: String] = [
            .k2: "abc", .k3: "def", .k4: "ghi", .k5: "jkl",
            .k6: "mno", .k7: "pqrs", .k8: "tuv", .k9: "wxyz"
        ]
        for (key, letters) in expected {
            XCTAssertEqual(
                String(MultiTapKeymap.classic[key]!.cycle),
                letters,
                "key \(key.rawValue) must carry \(letters.uppercased())"
            )
        }
    }

    func testTimeoutCommitsAndAFurtherTapStartsAFreshCharacter() {
        var commands = engine.press(.k2, at: 0, target: resolution).textCommands
        commands += engine.tick(at: 1.0, target: resolution).textCommands   // commits `a`
        commands += engine.press(.k2, at: 1.1, target: resolution).textCommands
        commands += engine.tick(at: 2.5, target: resolution).textCommands   // commits `a` again
        XCTAssertEqual(inserted(commands), "aa", "waiting out the timeout must allow a doubled letter")
    }

    func testPressingADifferentKeyCommitsTheOneInFlight() {
        var commands = engine.press(.k2, at: 0, target: resolution).textCommands
        commands += engine.press(.k3, at: 0.1, target: resolution).textCommands
        commands += engine.tick(at: 1.5, target: resolution).textCommands
        XCTAssertEqual(inserted(commands), "ad")
    }

    func testStaleTapOutsideTheWindowDoesNotContinueTheCycle() {
        _ = engine.press(.k2, at: 0, target: resolution)
        // A tap arriving after the timeout must start over at `a`, not go to `b`.
        let late = engine.press(.k2, at: 5.0, target: resolution)
        XCTAssertEqual(inserted(late.textCommands), "a", "the timed-out character commits")
        XCTAssertEqual(engine.state.pendingCharacter, "a", "and a brand new one begins")
        XCTAssertEqual(engine.state.pendingCycleIndex, 0)
    }

    // MARK: - Punctuation

    func testKeyOneIsThePunctuationKey() {
        XCTAssertEqual(inserted(type(.k1, times: 1)), ".")
        setUp(); XCTAssertEqual(inserted(type(.k1, times: 2)), ",")
        setUp(); XCTAssertEqual(inserted(type(.k1, times: 3)), "?")
        setUp(); XCTAssertEqual(inserted(type(.k1, times: 4)), "!")
    }

    // MARK: - Digits via long press

    func testLongPressOnALetterKeyTypesItsDigit() {
        _ = engine.press(.k7, at: 0, target: resolution)
        XCTAssertEqual(engine.state.pendingCharacter, "p")

        let held = engine.tick(at: 0.5, target: resolution) // past the 0.35s threshold
        XCTAssertTrue(held.textCommands.isEmpty, "still buffered")
        XCTAssertEqual(engine.state.pendingCharacter, "7")

        let released = engine.release(.k7, at: 0.6, target: resolution)
        XCTAssertEqual(released.textCommands, [.insert("7")])
    }

    func testLetterHoldReleasedBetweenTicksStillTypesItsDigit() {
        _ = engine.press(.k7, at: 0, target: resolution)
        let released = engine.release(.k7, at: 0.36, target: resolution)

        XCTAssertEqual(released.textCommands, [.insert("7")])
        XCTAssertNil(engine.state.pendingCharacter)
    }

    func testShortPressDoesNotProduceADigit() {
        _ = engine.press(.k7, at: 0, target: resolution)
        _ = engine.tick(at: 0.1, target: resolution)  // below the hold threshold
        _ = engine.release(.k7, at: 0.15, target: resolution)
        let commit = engine.tick(at: 1.5, target: resolution)
        XCTAssertEqual(commit.textCommands, [.insert("p")])
    }

    // MARK: - Command keys

    func testSpaceCommitsThePendingCharacterThenInsertsASpace() {
        _ = engine.press(.k2, at: 0, target: resolution)          // pending `a`
        _ = engine.press(.k11, at: 0.1, target: resolution)
        let outcome = engine.release(.k11, at: 0.15, target: resolution)
        XCTAssertEqual(outcome.textCommands, [.insert("a"), .insert(" ")])
    }

    func testBackspaceWithAPendingCharacterDiscardsItWithoutTouchingTheDocument() {
        _ = engine.press(.k2, at: 0, target: resolution)
        _ = engine.press(.k10, at: 0.1, target: resolution)
        let outcome = engine.release(.k10, at: 0.15, target: resolution)

        XCTAssertTrue(
            outcome.textCommands.isEmpty,
            "in buffered mode the pending letter was never typed, so nothing needs deleting"
        )
        XCTAssertNil(engine.state.pendingCharacter)
    }

    func testBackspaceWithNothingPendingDeletesInTheDocument() {
        _ = engine.press(.k10, at: 0, target: resolution)
        let outcome = engine.release(.k10, at: 0.05, target: resolution)
        XCTAssertEqual(outcome.textCommands, [.deleteBackward(1)])
    }

    func testHoldingSpaceGivesReturn() {
        _ = engine.press(.k11, at: 0, target: resolution)
        let held = engine.tick(at: 0.5, target: resolution)
        XCTAssertEqual(held.textCommands, [.newline])

        // The release must not then also insert a space.
        let released = engine.release(.k11, at: 0.6, target: resolution)
        XCTAssertTrue(released.textCommands.isEmpty)
    }

    func testCommandHoldReleasedBetweenTicksStillUsesTheHoldAction() {
        _ = engine.press(.k11, at: 0, target: resolution)
        let released = engine.release(.k11, at: 0.36, target: resolution)

        XCTAssertEqual(released.textCommands, [.newline])
    }

    func testButtonTwelveRequestsExit() {
        let outcome = engine.press(.k12, at: 0, target: resolution)
        XCTAssertTrue(outcome.exitRequested)
    }

    func testExitCommitsWhateverWasPending() {
        _ = engine.press(.k2, at: 0, target: resolution)
        let outcome = engine.press(.k12, at: 0.1, target: resolution)
        XCTAssertTrue(outcome.exitRequested)
        XCTAssertEqual(outcome.textCommands, [.insert("a")])
    }

    func testExitWorksEvenWhenTheTargetIsRefused() {
        let outcome = engine.press(.k12, at: 0, target: .refused(.notEditable))
        XCTAssertTrue(outcome.exitRequested, "the way out must never depend on being able to type")
    }

    // MARK: - Case

    func testShiftCycleWalksAbcAbcABC123() {
        XCTAssertEqual(engine.state.shift, .lower)
        for expected in [ShiftState.initialCaps, .upper, .numeric, .lower] {
            _ = engine.press(.k10, at: 0, target: resolution)
            _ = engine.tick(at: 0.5, target: resolution)
            _ = engine.release(.k10, at: 0.6, target: resolution)
            XCTAssertEqual(engine.state.shift, expected)
            engine = rebuild(shift: expected)
        }
    }

    func testModesKeypadCellElevenSpacesAndCellTwelveBackspacesOrReturns() {
        engine = MultiTapEngine(
            keymap: .modesKeypad,
            configuration: MultiTapConfiguration(initialShiftState: .lower)
        )

        _ = engine.press(.k11, at: 0, target: resolution)
        XCTAssertEqual(engine.release(.k11, at: 0.05, target: resolution).textCommands, [.insert(" ")])

        _ = engine.press(.k12, at: 0.2, target: resolution)
        XCTAssertEqual(engine.release(.k12, at: 0.25, target: resolution).textCommands, [.deleteBackward(1)])

        _ = engine.press(.k12, at: 0.4, target: resolution)
        XCTAssertEqual(engine.tick(at: 0.8, target: resolution).textCommands, [.newline])
        XCTAssertTrue(engine.release(.k12, at: 0.85, target: resolution).textCommands.isEmpty)
    }

    private func rebuild(shift: ShiftState) -> MultiTapEngine {
        let rebuilt = MultiTapEngine(
            keymap: .classic,
            configuration: MultiTapConfiguration(initialShiftState: shift)
        )
        return rebuilt
    }

    func testInitialCapsCapitalisesExactlyOneLetterThenReverts() {
        engine = MultiTapEngine(configuration: MultiTapConfiguration(initialShiftState: .initialCaps))
        var commands = engine.press(.k4, at: 0, target: resolution).textCommands       // G
        commands += engine.press(.k4, at: 0.1, target: resolution).textCommands        // H
        commands += engine.tick(at: 1.5, target: resolution).textCommands
        XCTAssertEqual(inserted(commands), "H")
        XCTAssertEqual(engine.state.shift, .lower, "Abc is a one-shot")

        commands = engine.press(.k4, at: 2.0, target: resolution).textCommands
        commands += engine.tick(at: 3.5, target: resolution).textCommands
        XCTAssertEqual(inserted(commands), "g", "the next letter is lower case again")
    }

    func testUpperCaseIsLockedUntilChanged() {
        engine = MultiTapEngine(configuration: MultiTapConfiguration(initialShiftState: .upper))
        var commands = type(.k2, times: 1)
        commands += type(.k3, times: 1, startingAt: 3)
        XCTAssertEqual(inserted(commands), "AD")
        XCTAssertEqual(engine.state.shift, .upper)
    }

    func testChangingCaseReCasesThePendingCharacterInPlace() {
        engine = MultiTapEngine(configuration: MultiTapConfiguration(initialShiftState: .lower))
        _ = engine.press(.k2, at: 0, target: resolution)
        XCTAssertEqual(engine.state.pendingCharacter, "a")

        _ = engine.press(.k10, at: 0.1, target: resolution)
        _ = engine.tick(at: 0.5, target: resolution)     // hold → shift cycle
        XCTAssertEqual(engine.state.shift, .initialCaps)
        XCTAssertEqual(engine.state.pendingCharacter, "A", "the half-typed letter follows the new case")
    }

    // MARK: - Numeric mode

    func testNumericModeTypesDigitsImmediatelyAndDoesNotCycle() {
        engine = MultiTapEngine(configuration: MultiTapConfiguration(initialShiftState: .numeric))
        var commands = engine.press(.k2, at: 0, target: resolution).textCommands
        commands += engine.press(.k2, at: 0.05, target: resolution).textCommands
        commands += engine.press(.k7, at: 0.1, target: resolution).textCommands
        XCTAssertEqual(inserted(commands), "227", "a repeated digit must not be swallowed by cycling")
        XCTAssertNil(engine.state.pendingCharacter)
    }

    func testNumericModeReachesZeroOnKeyEleven() {
        engine = MultiTapEngine(configuration: MultiTapConfiguration(initialShiftState: .numeric))
        let outcome = engine.press(.k11, at: 0, target: resolution)
        XCTAssertEqual(outcome.textCommands, [.insert("0")])
    }

    func testNumericModeKeepsBackspaceAndExitWorking() {
        engine = MultiTapEngine(configuration: MultiTapConfiguration(initialShiftState: .numeric))
        _ = engine.press(.k10, at: 0, target: resolution)
        XCTAssertEqual(engine.release(.k10, at: 0.05, target: resolution).textCommands, [.deleteBackward(1)])
        XCTAssertTrue(engine.press(.k12, at: 0.2, target: resolution).exitRequested)
    }

    // MARK: - Whole words

    func testTypingAWholeWord() {
        // "hi" — h is 4·4·(2nd), i is 4·4·4·(3rd)
        var commands = type(.k4, times: 2, startingAt: 0)
        commands += type(.k4, times: 3, startingAt: 5)
        XCTAssertEqual(inserted(commands), "hi")
    }

    func testTypingAShortSentenceWithSpaceAndPunctuation() {
        var commands: [TextCommand] = []
        commands += type(.k6, times: 3, startingAt: 0)      // o
        commands += type(.k5, times: 3, startingAt: 5)      // l
        commands += type(.k3, times: 1, startingAt: 10)     // d

        var now = 15.0
        commands += engine.press(.k11, at: now, target: resolution).textCommands
        now += 0.05
        commands += engine.release(.k11, at: now, target: resolution).textCommands  // space

        commands += type(.k1, times: 1, startingAt: 20)     // .
        XCTAssertEqual(inserted(commands), "old .")
    }

    // MARK: - State / reset

    func testResetClearsPendingAndBumpsTheGeneration() {
        _ = engine.press(.k2, at: 0, target: resolution)
        let before = engine.currentGeneration
        _ = engine.reset()
        XCTAssertNil(engine.state.pendingCharacter)
        XCTAssertEqual(engine.state.lastCancellation, .modeExited)
        XCTAssertNotEqual(engine.currentGeneration, before)
    }

    func testAReleaseFromAPreviousActivationIsIgnored() {
        _ = engine.press(.k2, at: 0, target: resolution)
        _ = engine.reset()
        let stale = engine.release(.k2, at: 0.2, target: resolution)
        XCTAssertTrue(stale.textCommands.isEmpty)
        XCTAssertNil(engine.state.pendingCharacter)
    }

    func testPendingProgressDrainsTowardsTheDeadline() {
        _ = engine.press(.k2, at: 10, target: resolution)
        let state = engine.state
        XCTAssertEqual(state.pendingProgress(now: 10.0, timeout: 0.9)!, 1.0, accuracy: 0.001)
        XCTAssertEqual(state.pendingProgress(now: 10.45, timeout: 0.9)!, 0.5, accuracy: 0.01)
        XCTAssertEqual(state.pendingProgress(now: 10.9, timeout: 0.9)!, 0.0, accuracy: 0.001)
    }
}
