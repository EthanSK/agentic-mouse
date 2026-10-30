import XCTest
@testable import AgenticMouseApp

@MainActor
private final class FakeClaudePinMenuSession: ClaudePinMenuSession {
    var isCurrent = true
    var action: ClaudePinMenuAction
    var menuOpen = false
    var pressed: [ClaudePinMenuAction] = []
    var canOpen = true
    var canPress = true

    init(action: ClaudePinMenuAction) { self.action = action }

    func open() -> Bool {
        guard isCurrent, canOpen, !menuOpen else { return false }
        menuOpen = true
        return true
    }

    func availableAction() -> ClaudePinMenuAction? {
        menuOpen ? action : nil
    }

    func press(_ action: ClaudePinMenuAction) -> Bool {
        guard isCurrent, canPress, menuOpen, self.action == action else { return false }
        pressed.append(action)
        self.action = action.opposite
        menuOpen = false
        return true
    }

    func dismiss() { menuOpen = false }
}

@MainActor
final class ClaudePinActionExecutorTests: XCTestCase {
    func testLiveClaudeMenuRoundTripOnlyWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["AGENTIC_MOUSE_CLAUDE_PIN_LIVE_TEST"] == "1" else {
            throw XCTSkip("Live Claude chat changes require an explicit opt-in")
        }
        let executor = ClaudePinActionExecutor(inputAllowed: { true })
        var firstResult: String?

        let first = expectation(description: "first live Claude pin change")
        XCTAssertTrue(executor.toggle { message, failed in
            XCTAssertFalse(failed, message)
            firstResult = message
            first.fulfill()
        })
        await fulfillment(of: [first], timeout: 3)
        XCTAssertTrue(firstResult == "Pinned" || firstResult == "Unpinned")

        let second = expectation(description: "restore original Claude pin state")
        XCTAssertTrue(executor.toggle { message, failed in
            XCTAssertFalse(failed, message)
            XCTAssertEqual(message, firstResult == "Pinned" ? "Unpinned" : "Pinned")
            second.fulfill()
        })
        await fulfillment(of: [second], timeout: 3)
    }

    func testPinAndUnpinAreConfirmedOnlyAfterTheCurrentMenuFlips() async {
        let session = FakeClaudePinMenuSession(action: .pin)
        let executor = ClaudePinActionExecutor(inputAllowed: { true }, makeSession: { session })

        let first = expectation(description: "pin confirmation")
        XCTAssertTrue(executor.toggle { message, failed in
            XCTAssertEqual(message, "Pinned")
            XCTAssertFalse(failed)
            first.fulfill()
        })
        await fulfillment(of: [first], timeout: 2)
        XCTAssertEqual(session.pressed, [.pin])
        XCTAssertEqual(session.action, .unpin)
        XCTAssertFalse(session.menuOpen)

        let second = expectation(description: "unpin confirmation")
        XCTAssertTrue(executor.toggle { message, failed in
            XCTAssertEqual(message, "Unpinned")
            XCTAssertFalse(failed)
            second.fulfill()
        })
        await fulfillment(of: [second], timeout: 2)
        XCTAssertEqual(session.pressed, [.pin, .unpin])
        XCTAssertEqual(session.action, .pin)
        XCTAssertFalse(session.menuOpen)
    }

    func testMissingOrChangedMenuFailsWithoutBlindShortcut() async {
        let missing = FakeClaudePinMenuSession(action: .pin)
        missing.canOpen = false
        let executor = ClaudePinActionExecutor(inputAllowed: { true }, makeSession: { missing })
        let result = expectation(description: "missing menu failure")
        XCTAssertTrue(executor.toggle { message, failed in
            XCTAssertEqual(message, "Could not read Claude pin state")
            XCTAssertTrue(failed)
            result.fulfill()
        })
        await fulfillment(of: [result], timeout: 2)
        XCTAssertTrue(missing.pressed.isEmpty)

        let stale = FakeClaudePinMenuSession(action: .pin)
        stale.canPress = false
        let staleExecutor = ClaudePinActionExecutor(inputAllowed: { true }, makeSession: { stale })
        let rejected = expectation(description: "stale action failure")
        XCTAssertTrue(staleExecutor.toggle { message, failed in
            XCTAssertEqual(message, "Could not change Claude pin state")
            XCTAssertTrue(failed)
            rejected.fulfill()
        })
        await fulfillment(of: [rejected], timeout: 2)
        XCTAssertTrue(stale.pressed.isEmpty)
    }
}
