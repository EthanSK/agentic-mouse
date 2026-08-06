import XCTest
@testable import ScimitarKit

/// Events that arrive late, out of order, or not at all.
///
/// These are the cases that turn a small glitch into a stuck mode or a
/// character typed into the wrong place, so each one has its own test.
final class StaleEventTests: XCTestCase {

    private var engine: MultiTapEngine!
    private let target = TextTarget(
        processIdentifier: 100,
        elementIdentity: "field-a",
        redactedApplication: "app:test"
    )
    private var resolution: TextTargetResolution { .ready(target) }

    override func setUp() {
        super.setUp()
        engine = MultiTapEngine(configuration: MultiTapConfiguration(initialShiftState: .lower))
    }

    // MARK: - Dropped releases

    func testALostReleaseDoesNotTurnAnOldLetterIntoADigit() {
        _ = engine.press(.k7, at: 0, target: resolution)   // pending `p`
        // No release ever arrives. The next tick lands long afterwards.
        let outcome = engine.tick(at: 3.0, target: resolution)

        XCTAssertEqual(
            outcome.textCommands,
            [.insert("p")],
            "the timed-out letter must commit as the letter, not as `7`"
        )
        XCTAssertNil(engine.state.pendingCharacter)
    }

    func testALostReleaseDoesNotFireAStrayHoldActionMuchLater() {
        // Key 11 holds to Return. A press whose release was lost must not
        // produce a newline minutes later.
        _ = engine.press(.k11, at: 0, target: resolution)
        let outcome = engine.tick(at: 60.0, target: resolution)

        XCTAssertTrue(outcome.textCommands.isEmpty, "a stale hold must be retired silently")
        XCTAssertNil(engine.state.heldKey)
    }

    func testAGenuineHoldStillWorks() {
        _ = engine.press(.k11, at: 0, target: resolution)
        let outcome = engine.tick(at: 0.5, target: resolution)
        XCTAssertEqual(outcome.textCommands, [.newline])
    }

    func testHoldIsResolvedOnceAndOnlyOnce() {
        _ = engine.press(.k11, at: 0, target: resolution)
        let first = engine.tick(at: 0.5, target: resolution)
        let second = engine.tick(at: 0.6, target: resolution)
        let third = engine.tick(at: 0.7, target: resolution)

        XCTAssertEqual(first.textCommands, [.newline])
        XCTAssertTrue(second.textCommands.isEmpty, "a repeating tick must not repeat the action")
        XCTAssertTrue(third.textCommands.isEmpty)
    }

    // MARK: - Repeated ticks

    func testRepeatedTicksAfterACommitProduceNothing() {
        _ = engine.press(.k2, at: 0, target: resolution)
        let commit = engine.tick(at: 1.0, target: resolution)
        XCTAssertEqual(commit.textCommands, [.insert("a")])

        for time in stride(from: 1.1, through: 3.0, by: 0.1) {
            XCTAssertTrue(
                engine.tick(at: time, target: resolution).textCommands.isEmpty,
                "the commit must not repeat on every tick"
            )
        }
    }

    func testTickIsSafeWithNothingHappening() {
        for time in stride(from: 0.0, through: 5.0, by: 0.25) {
            XCTAssertEqual(engine.tick(at: time, target: resolution), .none)
        }
    }

    // MARK: - Generation guards

    func testAHoldStartedBeforeAResetCannotResolveAfterIt() {
        _ = engine.press(.k11, at: 0, target: resolution)
        _ = engine.reset()

        let outcome = engine.tick(at: 0.5, target: resolution)
        XCTAssertTrue(outcome.textCommands.isEmpty, "a hold from a previous activation is dead")
    }

    func testAReleaseArrivingAfterAResetIsIgnored() {
        _ = engine.press(.k11, at: 0, target: resolution)
        _ = engine.reset()

        let outcome = engine.release(.k11, at: 0.1, target: resolution)
        XCTAssertTrue(outcome.textCommands.isEmpty, "no space should be typed by a stale release")
    }

    func testGenerationAdvancesOnEveryReset() {
        var seen: Set<UInt64> = [engine.currentGeneration]
        for _ in 0..<5 {
            _ = engine.reset()
            XCTAssertTrue(seen.insert(engine.currentGeneration).inserted, "generations must be unique")
        }
    }

    // MARK: - Unmapped and duplicate input

    func testAnUnmappedKeyDoesNothingButIsStillConsumed() {
        var keymap = MultiTapKeymap.classic
        keymap = MultiTapKeymap(specs: keymap.specs.filter { $0.key != .k5 })
        engine.update(keymap: keymap)

        let outcome = engine.press(.k5, at: 0, target: resolution)
        XCTAssertTrue(outcome.textCommands.isEmpty)
        XCTAssertFalse(outcome.exitRequested)
        XCTAssertNil(engine.state.pendingCharacter)
    }

    func testReleaseWithoutAMatchingPressIsHarmless() {
        let outcome = engine.release(.k11, at: 0, target: resolution)
        XCTAssertTrue(outcome.textCommands.isEmpty, "an orphan release must not type a space")
    }

    func testPressingASecondKeyWhileTheFirstIsStillDownIsCoherent() {
        _ = engine.press(.k2, at: 0, target: resolution)     // pending `a`
        let second = engine.press(.k3, at: 0.1, target: resolution)
        XCTAssertEqual(second.textCommands, [.insert("a")], "the first letter commits")
        XCTAssertEqual(engine.state.pendingCharacter, "d")

        // The first key's release now arrives, out of order. It must not
        // disturb the character that is currently pending.
        let lateRelease = engine.release(.k2, at: 0.2, target: resolution)
        XCTAssertTrue(lateRelease.textCommands.isEmpty)
        XCTAssertEqual(engine.state.pendingCharacter, "d")
    }
}
