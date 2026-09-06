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
        executor.perform(.pin) { message, _ in messages.append(message) }
        executor.perform(.pin) { message, _ in messages.append(message) }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(menu.presses, ["Pin"])
        executor.perform(.pin) { message, _ in messages.append(message) }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(menu.presses, ["Pin"])
        XCTAssertEqual(messages.last, "Already pinned")
        executor.perform(.unpin) { _, _ in }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(menu.presses, ["Pin", "Unpin"])
    }

    func testFocusLossLockAndCancellationPreventPendingPin() async {
        for reason in 0..<3 {
            let menu = PinMenu()
            var allowed = true
            let executor = CodexPinActionExecutor(inputAllowed: { allowed }, makeSession: { menu })
            executor.perform(.pin) { _, _ in }
            await Task.yield()
            if reason == 0 { menu.isCurrent = false }
            if reason == 1 { allowed = false }
            if reason == 2 { executor.cancel() }
            try? await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(menu.presses.isEmpty)
        }
    }

    func testAmbiguousMenuCannotSendAStateChange() async {
        let menu = PinMenu()
        menu.labels = ["Pin", "Unpin"]
        let executor = CodexPinActionExecutor(inputAllowed: { true }, makeSession: { menu })
        var failed = false
        executor.perform(.unpin) { _, error in failed = error }
        try? await Task.sleep(for: .milliseconds(100))
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
