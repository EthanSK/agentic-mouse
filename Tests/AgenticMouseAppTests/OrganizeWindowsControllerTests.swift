import XCTest
import ScimitarKit
@testable import AgenticMouseApp

@MainActor
final class OrganizeWindowsControllerTests: XCTestCase {
    func testDestinationUsesWindowDisplayRatherThanFirstDisplay() throws {
        func space(_ id: Int, _ type: Int = 0) -> [String: Any] { ["ManagedSpaceID": id, "type": type] }
        let displays: [[String: Any]] = [
            ["Spaces": [space(1), space(2)], "Current Space": space(2)],
            ["Spaces": [space(3), space(4)], "Current Space": space(4)]
        ]
        XCTAssertEqual(try ChromeSpaceRestorer.target(window: 9, membership: [3], displays: displays), .init(window: 9, source: 3, destination: 4))
        XCTAssertNil(try ChromeSpaceRestorer.target(window: 9, membership: [4], displays: displays))
        XCTAssertThrowsError(try ChromeSpaceRestorer.target(window: 9, membership: [1, 3], displays: displays))
        XCTAssertThrowsError(try ChromeSpaceRestorer.target(window: 9, membership: [99], displays: displays))
        XCTAssertThrowsError(try ChromeSpaceRestorer.target(window: 9, membership: [3], displays: [["Spaces": [space(3)], "Current Space": space(4, 4)]]))
    }

    func testRestoresOnlyAfterMoveMembershipIsConfirmed() async {
        let target = ChromeSpaceRestorer.Target(window: 9, source: 3, destination: 4)
        var events: [String] = []
        var reads = 0
        let done = expectation(description: "finished")
        let controller = OrganizeWindowsController(operations: .init(
            capture: { target }, move: { _ in events.append("move") },
            membership: { _ in reads += 1; events.append("read"); return reads < 2 ? [3] : [4] },
            destinationStillVisible: { _ in true }, restore: { events.append("restore"); return true }
        ), inputAllowed: { true })
        controller.onCompletion = { _, success in XCTAssertTrue(success); done.fulfill() }
        XCTAssertTrue(controller.start(source: .corsair))
        XCTAssertFalse(controller.start(source: .razer))
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(events, ["move", "read", "read", "restore"])
    }

    func testEveryTerminalOutcomeAllowsAnotherExplicitRequest() async {
        for failsCapture in [false, true] {
            for restores in [false, true] {
                var attempts = 0
                var outcomes: [Bool] = []
                let controller = OrganizeWindowsController(operations: .init(
                    capture: {
                        attempts += 1
                        if failsCapture { throw ChromeSpaceRestorer.Failure.unavailable }
                        return nil
                    },
                    move: { _ in XCTFail("no move needed") },
                    membership: { _ in XCTFail("no membership needed"); return [] },
                    destinationStillVisible: { _ in true },
                    restore: { restores }
                ), inputAllowed: { true })
                controller.onCompletion = { _, success in outcomes.append(success) }

                for source in [MouseSource.corsair, .razer] {
                    let completed = expectation(description: "explicit request completed")
                    controller.onCompletion = { _, success in
                        outcomes.append(success)
                        completed.fulfill()
                    }
                    XCTAssertTrue(controller.start(source: source))
                    XCTAssertFalse(controller.start(source: source), "Never overlap requests")
                    await fulfillment(of: [completed], timeout: 2)
                }
                XCTAssertEqual(attempts, 2)
                XCTAssertEqual(outcomes, [!failsCapture && restores, !failsCapture && restores])
            }
        }
    }

    func testChangedSpaceDoesNotRestoreLayout() async {
        let done = expectation(description: "failed")
        var restored = false
        let controller = OrganizeWindowsController(operations: .init(
            capture: { .init(window: 9, source: 3, destination: 4) }, move: { _ in },
            membership: { _ in [4] }, destinationStillVisible: { _ in false },
            restore: { restored = true; return true }
        ), inputAllowed: { true })
        controller.onCompletion = { _, success in XCTAssertFalse(success); done.fulfill() }
        controller.start(source: .corsair)
        await fulfillment(of: [done], timeout: 2)
        XCTAssertFalse(restored)
    }

    func testCancelDuringMovePreventsLateRestoreOrFeedback() async {
        var moved = false
        var restored = false
        var completed = false
        let controller = OrganizeWindowsController(operations: .init(
            capture: { .init(window: 9, source: 3, destination: 4) }, move: { _ in moved = true },
            membership: { _ in [3] }, destinationStillVisible: { _ in true },
            restore: { restored = true; return true }
        ), inputAllowed: { true })
        controller.onCompletion = { _, _ in completed = true }
        controller.start(source: .corsair)
        await Task.yield()
        controller.cancel(source: .corsair)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(moved)
        XCTAssertFalse(restored)
        XCTAssertFalse(completed)
    }

    func testAlreadyCurrentSpaceStillRestoresAndBlockedInputNeverStarts() async {
        let done = expectation(description: "restored")
        var allowed = false
        let controller = OrganizeWindowsController(operations: .init(
            capture: { nil }, move: { _ in XCTFail("no move needed") },
            membership: { _ in XCTFail("no read needed"); return [] },
            destinationStillVisible: { _ in true }, restore: { true }
        ), inputAllowed: { allowed })
        controller.onCompletion = { _, success in XCTAssertTrue(success); done.fulfill() }
        XCTAssertFalse(controller.start(source: .razer))
        allowed = true
        XCTAssertTrue(controller.start(source: .razer))
        await fulfillment(of: [done], timeout: 2)
    }

    func testAmbiguousChromeWindowsStillRequestStayWithoutMovingEitherWindow() async {
        let done = expectation(description: "Stay requested")
        var events: [String] = []
        let controller = OrganizeWindowsController(operations: .init(
            capture: { throw ChromeSpaceRestorer.Failure.ambiguousWindow },
            move: { _ in XCTFail("must not guess which Chrome window to move") },
            membership: { _ in XCTFail("must not inspect an uncaptured window"); return [] },
            destinationStillVisible: { _ in XCTFail("must not inspect an uncaptured Space"); return false },
            restore: { events.append("restore"); return true }
        ), inputAllowed: { true })
        controller.onDiagnostic = { events.append($0) }
        controller.onCompletion = { _, success in XCTAssertTrue(success); done.fulfill() }
        XCTAssertTrue(controller.start(source: .corsair))
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.first, "Organize Windows requested")
        XCTAssertTrue(events.contains { $0.contains("Multiple off-Space Chrome windows") })
        XCTAssertEqual(Array(events.suffix(2)), ["restore", "Stay restore shortcut posted"])
    }

    func testUnavailableChromeInventoryDoesNotRequestStay() async {
        let done = expectation(description: "failure reported")
        var diagnostics: [String] = []
        let controller = OrganizeWindowsController(operations: .init(
            capture: { throw ChromeSpaceRestorer.Failure.unavailable },
            move: { _ in XCTFail("capture failed") },
            membership: { _ in []; },
            destinationStillVisible: { _ in false },
            restore: { XCTFail("unsupported Space state must stay fail-closed"); return true }
        ), inputAllowed: { true })
        controller.onDiagnostic = { diagnostics.append($0) }
        controller.onCompletion = { _, success in XCTAssertFalse(success); done.fulfill() }
        controller.start(source: .razer)
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(diagnostics.count, 2)
        XCTAssertEqual(diagnostics.first, "Organize Windows requested")
        XCTAssertTrue(diagnostics.last?.contains("unavailable") == true)
    }
}
