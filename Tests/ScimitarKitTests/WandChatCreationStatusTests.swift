import XCTest
@testable import ScimitarKit

final class WandChatCreationStatusTests: XCTestCase {
    private var clock: ManualClock!
    private var tick: ManualTickScheduler!
    private var controller: WandChatCreationStatusController!
    private var changes: [Bool] = []
    private var allowed = true

    override func setUp() {
        clock = ManualClock(now: 100)
        tick = ManualTickScheduler()
        controller = WandChatCreationStatusController(scheduler: tick, clock: clock,
            allowed: { [unowned self] in allowed })
        controller.onVisibilityChange = { [unowned self] in changes.append($0) }
    }

    func testShowRenewAndMatchingHideUseOneVisibilityLifecycle() {
        let id = UUID()
        controller.handle(.init(id: id, phase: .show))
        XCTAssertEqual(changes, [true])
        clock.advance(by: 9)
        controller.handle(.init(id: id, phase: .show))
        clock.advance(by: 9)
        tick.fire()
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(changes, [true], "renewal never recreates or flashes the panel")
        controller.handle(.init(id: id, phase: .hide))
        controller.handle(.init(id: id, phase: .hide))
        XCTAssertEqual(changes, [true, false])
        XCTAssertFalse(tick.isRunning)
    }

    func testOldCompletionCannotHideNewerOperation() {
        let old = UUID(), current = UUID()
        controller.handle(.init(id: old, phase: .show))
        controller.handle(.init(id: current, phase: .show))
        controller.handle(.init(id: old, phase: .hide))
        controller.handle(.init(id: old, phase: .show))
        XCTAssertEqual(controller.currentID, current)
        XCTAssertEqual(changes, [true])
    }

    func testCompletionBeforeShowAndLateRetriesNeverResurrectStatus() {
        let id = UUID()
        controller.handle(.init(id: id, phase: .hide))
        controller.handle(.init(id: id, phase: .show))
        XCTAssertFalse(controller.isVisible)
        XCTAssertTrue(changes.isEmpty)
    }

    func testSenderLossExpiresAndRetiresTheOperation() {
        let id = UUID()
        controller.handle(.init(id: id, phase: .show))
        clock.advance(by: WandChatCreationStatusController.leaseDuration)
        tick.fire()
        XCTAssertEqual(changes, [true, false])
        XCTAssertFalse(tick.isRunning)
        controller.handle(.init(id: id, phase: .show))
        XCTAssertFalse(controller.isVisible)
    }

    func testExpiredLeaseCannotBeRevivedBeforeTheNextTimerTick() {
        let id = UUID()
        controller.handle(.init(id: id, phase: .show))
        clock.advance(by: 11)
        controller.handle(.init(id: id, phase: .show))
        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(changes, [true, false])
    }

    func testLockAndExplicitResetHideWithoutReplaying() {
        let id = UUID()
        controller.handle(.init(id: id, phase: .show))
        allowed = false
        tick.fire()
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(tick.isRunning)
        controller.handle(.init(id: UUID(), phase: .show))
        XCTAssertFalse(controller.isVisible)
        allowed = true
        controller.handle(.init(id: id, phase: .show))
        XCTAssertFalse(controller.isVisible)
        controller.handle(.init(id: UUID(), phase: .show))
        controller.reset()
        XCTAssertEqual(changes, [true, false, true, false])
    }

    func testStrictWireContractRejectsExpandedAndMalformedPackets() throws {
        let valid = #"{"command":"agentic_mouse_wand_chat_creation_status","version":1,"id":"24EE96E1-744B-474F-875B-68D2D85736AA","phase":"show"}"#
        let parsed = try WandChatCreationStatusCommand.decode(Data(valid.utf8))
        XCTAssertEqual(parsed.phase, .show)
        for bad in [valid.replacingOccurrences(of: ":1,", with: ":true,"),
                    valid.replacingOccurrences(of: ":1,", with: ":2,"),
                    valid.replacingOccurrences(of: "24EE96E1-744B-474F-875B-68D2D85736AA", with: "bad-id"),
                    valid.replacingOccurrences(of: "\"show\"", with: "\"startRecording\""),
                    String(valid.dropLast()) + ",\"text\":\"unexpected\"}",
                    valid + String(repeating: " ", count: 257)] {
            XCTAssertThrowsError(try WandChatCreationStatusCommand.decode(Data(bad.utf8)))
        }
    }
}
