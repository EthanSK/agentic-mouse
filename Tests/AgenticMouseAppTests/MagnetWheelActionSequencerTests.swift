@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class MagnetWheelActionSequencerTests: XCTestCase {
    func testRepeatedRatchetsArePostedInOrderWithOneIntervalBetweenCommands() {
        var performed: [MagnetWheelActionSequencer.Request] = []
        var delays: [TimeInterval] = []
        var scheduled: [@Sendable @MainActor () -> Void] = []
        let sequencer = MagnetWheelActionSequencer(
            minimumInterval: 0.4,
            perform: { performed.append($0) },
            schedule: { delay, action in
                delays.append(delay)
                scheduled.append(action)
            }
        )
        let first = MagnetWheelActionSequencer.Request(
            action: .moveWindowRightWithMagnet,
            source: .corsair,
            detentCount: 1
        )
        let second = MagnetWheelActionSequencer.Request(
            action: .moveWindowRightWithMagnet,
            source: .corsair,
            detentCount: 2
        )
        let third = MagnetWheelActionSequencer.Request(
            action: .moveWindowLeftWithMagnet,
            source: .corsair,
            detentCount: 3
        )

        sequencer.enqueue(first)
        sequencer.enqueue(second)
        sequencer.enqueue(third)

        XCTAssertEqual(performed, [first])
        XCTAssertEqual(sequencer.pendingCount, 2)
        XCTAssertEqual(delays, [0.4])

        scheduled.removeFirst()()
        XCTAssertEqual(performed, [first, second])
        XCTAssertEqual(sequencer.pendingCount, 1)
        XCTAssertEqual(delays, [0.4, 0.4])

        scheduled.removeFirst()()
        XCTAssertEqual(performed, [first, second, third])
        XCTAssertEqual(sequencer.pendingCount, 0)
        XCTAssertEqual(delays, [0.4, 0.4, 0.4])

        scheduled.removeFirst()()
        XCTAssertEqual(performed, [first, second, third])
    }

    func testLockCancelsQueuedCommandsAndStaleScheduledDrain() {
        var allowed = true
        var performed: [MagnetWheelActionSequencer.Request] = []
        var scheduled: [@Sendable @MainActor () -> Void] = []
        let sequencer = MagnetWheelActionSequencer(
            perform: { performed.append($0) },
            inputAllowed: { allowed },
            schedule: { _, action in scheduled.append(action) }
        )
        let first = MagnetWheelActionSequencer.Request(
            action: .moveWindowRightWithMagnet,
            source: .razer,
            detentCount: 1
        )
        let second = MagnetWheelActionSequencer.Request(
            action: .moveWindowLeftWithMagnet,
            source: .razer,
            detentCount: 2
        )

        sequencer.enqueue(first)
        sequencer.enqueue(second)
        allowed = false
        sequencer.cancelAll()
        scheduled.removeFirst()()

        XCTAssertEqual(performed, [first])
        XCTAssertEqual(sequencer.pendingCount, 0)
    }

    func testSourceCancellationRemovesOnlyThatMousesQueuedCommands() {
        var performed: [MagnetWheelActionSequencer.Request] = []
        var scheduled: [@Sendable @MainActor () -> Void] = []
        let sequencer = MagnetWheelActionSequencer(
            perform: { performed.append($0) },
            schedule: { _, action in scheduled.append(action) }
        )
        let corsair = MagnetWheelActionSequencer.Request(
            action: .moveWindowRightWithMagnet,
            source: .corsair,
            detentCount: 1
        )
        let cancelledCorsair = MagnetWheelActionSequencer.Request(
            action: .moveWindowLeftWithMagnet,
            source: .corsair,
            detentCount: 2
        )
        let razer = MagnetWheelActionSequencer.Request(
            action: .moveWindowLeftWithMagnet,
            source: .razer,
            detentCount: 1
        )

        sequencer.enqueue(corsair)
        sequencer.enqueue(cancelledCorsair)
        sequencer.enqueue(razer)
        sequencer.cancel(source: .corsair)
        scheduled.removeFirst()()

        XCTAssertEqual(performed, [corsair, razer])
    }

    func testDisallowedInputNeverPostsTheFirstCommand() {
        let sequencer = MagnetWheelActionSequencer(
            perform: { _ in XCTFail("locked input must never post Magnet") },
            inputAllowed: { false },
            schedule: { _, _ in XCTFail("locked input must not schedule") }
        )

        sequencer.enqueue(.init(
            action: .moveWindowRightWithMagnet,
            source: .corsair,
            detentCount: 1
        ))

        XCTAssertEqual(sequencer.pendingCount, 0)
    }

    func testQueueDepthIsBoundedWhileMagnetIsCoolingDown() {
        var performed: [MagnetWheelActionSequencer.Request] = []
        var scheduled: [@Sendable @MainActor () -> Void] = []
        let sequencer = MagnetWheelActionSequencer(
            maximumPendingCount: 2,
            perform: { performed.append($0) },
            schedule: { _, action in scheduled.append(action) }
        )
        func request(_ count: Int) -> MagnetWheelActionSequencer.Request {
            .init(
                action: .moveWindowRightWithMagnet,
                source: .corsair,
                detentCount: count
            )
        }

        XCTAssertTrue(sequencer.enqueue(request(1)))
        XCTAssertTrue(sequencer.enqueue(request(2)))
        XCTAssertTrue(sequencer.enqueue(request(3)))
        XCTAssertFalse(sequencer.enqueue(request(4)))
        XCTAssertEqual(performed, [request(1)])
        XCTAssertEqual(sequencer.pendingCount, 2)

        scheduled.removeFirst()()
        XCTAssertEqual(performed, [request(1), request(2)])
    }
}
