import XCTest
import ScimitarKit
@testable import AgenticMouseApp

@MainActor
final class CodexPinActionExecutorTests: XCTestCase {
    func testDirectionalStateActionsAndAmbiguity() {
        XCTAssertEqual(CodexPinActionExecutor.decision(.pin, labels: ["Pin", "Archive"]), .press("Pin"))
        XCTAssertEqual(CodexPinActionExecutor.decision(.unpin, labels: ["Unpin chat"]), .press("Unpin chat"))
        XCTAssertEqual(CodexPinActionExecutor.decision(.pin, labels: ["Unpin"]), .already)
        XCTAssertEqual(CodexPinActionExecutor.decision(.unpin, labels: ["Pin chat"]), .already)
        for labels in [[], ["Pin", "Unpin"], ["Pin", "Pin"], ["Pinned"], ["Pin another chat"]] {
            XCTAssertEqual(CodexPinActionExecutor.decision(.pin, labels: labels), .unavailable)
        }
    }

    func testRepeatedPinDoesNotToggleBackAndUnpinCanFollow() async {
        let menu = PinMenu()
        let executor = CodexPinActionExecutor(inputAllowed: { true }, makeSession: { menu })
        var messages: [String] = []
        let pinned = expectation(description: "Pin request completed")
        executor.perform(.pin) { message, _ in messages.append(message); pinned.fulfill() }
        executor.perform(.pin) { _, _ in XCTFail("Concurrent duplicate must be ignored") }
        await fulfillment(of: [pinned], timeout: 3)
        XCTAssertEqual(menu.presses, ["Pin"])
        let already = expectation(description: "Existing pin read")
        executor.perform(.pin) { message, _ in messages.append(message); already.fulfill() }
        await fulfillment(of: [already], timeout: 3)
        XCTAssertEqual(menu.presses, ["Pin"])
        XCTAssertEqual(messages.last, "Already pinned")
        let unpinned = expectation(description: "Unpin request completed")
        executor.perform(.unpin) { _, _ in unpinned.fulfill() }
        await fulfillment(of: [unpinned], timeout: 3)
        XCTAssertEqual(menu.presses, ["Pin", "Unpin"])
    }

    func testFocusLossLockAndCancellationPreventPendingPin() async {
        for reason in 0..<4 {
            let menu = PinMenu()
            var allowed = true
            var sourceModeActive = true
            let executor = CodexPinActionExecutor(inputAllowed: { allowed }, makeSession: { menu })
            executor.perform(.pin, requestAllowed: { sourceModeActive }) { _, _ in }
            await Task.yield()
            if reason == 0 { menu.isCurrent = false }
            if reason == 1 { allowed = false }
            if reason == 2 { executor.cancel() }
            if reason == 3 { sourceModeActive = false }
            try? await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(menu.presses.isEmpty)
        }
    }

    func testAmbiguousMenuCannotSendAStateChange() async {
        let menu = PinMenu()
        menu.labels = ["Pin", "Unpin"]
        let executor = CodexPinActionExecutor(inputAllowed: { true }, makeSession: { menu })
        var failed = false
        let completed = expectation(description: "Ambiguous menu rejected")
        executor.perform(.unpin) { _, error in failed = error; completed.fulfill() }
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertTrue(failed)
        XCTAssertTrue(menu.presses.isEmpty)
        XCTAssertEqual(menu.dismissals, 1)
    }
}

@MainActor
private final class PinMenu: CodexPinMenuSession {
    var isCurrent = true
    var labels = ["Pin"]
    var presses: [String] = []
    var dismissals = 0
    func open() -> Bool { true }
    func readItems() -> [String]? { labels }
    func press(_ label: String) -> Bool {
        presses.append(label)
        labels = label == "Pin" ? ["Unpin"] : ["Pin"]
        return true
    }
    func dismiss() { dismissals += 1 }
}
