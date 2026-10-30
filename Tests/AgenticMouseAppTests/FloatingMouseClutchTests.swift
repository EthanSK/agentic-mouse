import Foundation
@testable import AgenticMouseApp
import XCTest

final class FloatingMouseClutchTests: XCTestCase {
    private var wall = 1000.0
    private var monotonic = 100.0
    private var allowed = true
    private var messages: [Bool] = []
    private var expiries: [Int64] = []
    private var reacquisitions: [(String, TimeInterval)] = []
    private lazy var controller = FloatingMouseClutchController(
        wallTime: { self.wall }, monotonicTime: { self.monotonic },
        allowed: { self.allowed }, writeExpiry: { self.expiries.append($0) },
        publish: { self.messages.append($0) },
        publishReacquire: { self.reacquisitions.append(($0, $1)) }
    )
    private func context(_ active: Bool = true, detecting: Bool? = nil) {
        var info: [String: Any] = ["active": active, "sentAt": wall]
        if let detecting { info["detecting"] = detecting }
        controller.receiveContext(source: "corsair1", info: info)
    }
    private func advance(_ seconds: Double) { wall += seconds; monotonic += seconds }
    @discardableResult private func button(_ phase: String, time: Double? = nil) -> Bool {
        controller.handle(Data("{\"command\":\"agentic_mouse_floating_clutch\",\"source\":\"corsair1\",\"phase\":\"\(phase)\"}".utf8), inputTime: time ?? monotonic)
    }
    func testDownHeartbeatAndUpAreImmediateAndDoNotReplay() {
        context(); button("press"); XCTAssertEqual(messages, [true])
        button("press"); XCTAssertEqual(messages, [true])
        for _ in 0..<8 { advance(0.2); context(); controller.tick() }
        XCTAssertTrue(controller.isClutched)
        button("release"); XCTAssertEqual(messages.last, false)
        let count = messages.count; controller.tick(); button("release")
        XCTAssertEqual(messages.count, count)
    }
    func testDisarmConsumesOldHoldAndRequiresFreshDownOnRearm() {
        context(); button("press"); advance(0.1); context(false)
        XCTAssertEqual(messages, [true, false]); XCTAssertEqual(expiries.last, 0)
        advance(0.1); context(); button("press"); controller.tick()
        XCTAssertEqual(messages, [true, false])
        button("release"); button("press"); XCTAssertEqual(messages, [true, false, true])
    }
    func testContextExpiryReleasesDespiteContinuingTimerAndRejectsLatePress() {
        context(); button("press"); advance(0.651); controller.tick()
        XCTAssertFalse(controller.isActive); XCTAssertFalse(controller.isClutched)
        XCTAssertEqual(messages, [true, false]); XCTAssertEqual(expiries.last, 0)
        controller.tick(); XCTAssertEqual(messages, [true, false])
    }
    func testRenewalAfterUnobservedExpiryDoesNotResumeHeldClutch() {
        context(); button("press"); advance(0.8); context(); controller.tick()
        XCTAssertTrue(controller.isActive); XCTAssertFalse(controller.isClutched)
        XCTAssertEqual(messages, [true, false])
    }
    func testStaleMalformedOtherSourceAndReorderedContextAreIgnored() {
        controller.receiveContext(source: "razer1", info: ["active": true, "sentAt": wall])
        controller.receiveContext(source: "corsair1", info: ["active": true, "sentAt": wall - 2])
        controller.receiveContext(source: "corsair1", info: ["active": "true", "sentAt": wall])
        controller.receiveContext(source: "corsair1", info: ["active": true, "sentAt": true])
        XCTAssertFalse(controller.isActive); XCTAssertTrue(expiries.isEmpty)
        context(); advance(0.1); context(false)
        controller.receiveContext(source: "corsair1", info: ["active": true, "sentAt": wall - 0.05])
        XCTAssertFalse(controller.isActive)
    }
    func testContextNeverConvertsAnOlderQueuedDownIntoClutch() {
        context(); button("press", time: monotonic - 0.01)
        XCTAssertFalse(controller.isClutched); XCTAssertTrue(messages.isEmpty)
        button("release"); button("press"); XCTAssertEqual(messages, [true])
    }
    func testLockAndDisconnectCancelAndAllowNewPhysicalCycle() {
        context(); button("press"); allowed = false; controller.tick()
        XCTAssertEqual(messages, [true, false]); XCTAssertFalse(controller.isActive)
        allowed = true; controller.cancel(resetButton: true); advance(0.1)
        context(); button("press"); XCTAssertEqual(messages, [true, false, true])
        controller.stop(); XCTAssertEqual(messages.last, false)
    }
    func testUnrelatedCommandsAreNotConsumed() {
        XCTAssertFalse(controller.handle(Data("{}".utf8), inputTime: monotonic))
        XCTAssertFalse(button("bogus"))
        XCTAssertTrue(messages.isEmpty)
    }
    func testPassiveDetectionEmitsOncePerFreshDownWithoutClutchOrSuppressionLease() {
        context(false, detecting: true)
        button("press"); button("press"); controller.tick()
        XCTAssertTrue(controller.isDetecting)
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(controller.isClutched)
        XCTAssertTrue(messages.isEmpty)
        XCTAssertTrue(expiries.isEmpty)
        XCTAssertEqual(reacquisitions.count, 1)
        XCTAssertNotNil(UUID(uuidString: reacquisitions[0].0))
        XCTAssertEqual(reacquisitions[0].1, wall)
        button("release"); button("release"); controller.tick()
        XCTAssertEqual(reacquisitions.count, 1)
        button("press")
        XCTAssertEqual(reacquisitions.count, 2)
        XCTAssertNotEqual(reacquisitions[0].0, reacquisitions[1].0)
    }

    func testLegacyArmedContextReacquiresOnlyOnDownNotHeldHeartbeats() {
        context(); button("press")
        for _ in 0..<5 { advance(0.2); context(); controller.tick(); button("press") }
        XCTAssertEqual(reacquisitions.count, 1)
        XCTAssertTrue(controller.isClutched)
        button("release")
        XCTAssertEqual(messages.last, false)
        XCTAssertEqual(reacquisitions.count, 1)
    }

    func testPassiveDownBeforeDetectionEntryCannotBeReinterpreted() {
        button("press"); context(false, detecting: true); button("press"); controller.tick()
        XCTAssertTrue(reacquisitions.isEmpty)
        button("release"); button("press")
        XCTAssertEqual(reacquisitions.count, 1)
    }

    func testDetectionRejectsQueuedOldFutureAndNonFiniteEdges() {
        context(false, detecting: true)
        for input in [monotonic - 0.01, monotonic + 0.01, .nan, .infinity] {
            button("press", time: input); button("release")
        }
        XCTAssertTrue(reacquisitions.isEmpty)
        button("press")
        XCTAssertEqual(reacquisitions.count, 1)
    }

    func testDetectingLeaseExpiresOnPressEvenIfTimerHasNotRun() {
        context(false, detecting: true); advance(0.65); button("press")
        XCTAssertTrue(reacquisitions.isEmpty)
        XCTAssertFalse(controller.isDetecting)
        advance(0.1); context(false, detecting: true); button("press")
        XCTAssertTrue(reacquisitions.isEmpty)
        button("release"); button("press")
        XCTAssertEqual(reacquisitions.count, 1)
    }

    func testDisarmKeepsDetectionButEndsClutchAndDoesNotRepeatReset() {
        context(true, detecting: true); button("press")
        advance(0.1); context(false, detecting: true); controller.tick()
        XCTAssertEqual(messages, [true, false])
        XCTAssertEqual(expiries.last, 0)
        XCTAssertTrue(controller.isDetecting)
        XCTAssertFalse(controller.isActive)
        button("press"); XCTAssertEqual(reacquisitions.count, 1)
        button("release"); button("press"); XCTAssertEqual(reacquisitions.count, 2)
        XCTAssertEqual(messages, [true, false])
    }

    func testMalformedReorderedAndStoppedDetectionCannotRenewPassiveLease() {
        context(false, detecting: true); advance(0.5)
        for value: Any in ["true", 1, NSNull()] {
            controller.receiveContext(source: "corsair1", info: ["active": false, "detecting": value, "sentAt": wall])
        }
        controller.receiveContext(source: "corsair1", info: ["active": false, "detecting": true, "sentAt": wall - 0.5])
        advance(0.151); controller.tick(); button("press")
        XCTAssertFalse(controller.isDetecting)
        XCTAssertTrue(reacquisitions.isEmpty)
        button("release"); context(false, detecting: true)
        advance(0.1); context(false, detecting: false); button("press")
        XCTAssertTrue(reacquisitions.isEmpty)
    }

    func testLockAndCancellationEndBothLeasesWithoutReacquiringHeldButton() {
        context(false, detecting: true); button("press")
        allowed = false; controller.tick()
        XCTAssertFalse(controller.isDetecting)
        allowed = true; advance(0.1); context(false, detecting: true)
        button("press"); XCTAssertEqual(reacquisitions.count, 1)
        controller.stop(); XCTAssertFalse(controller.isDetecting)
    }

}
