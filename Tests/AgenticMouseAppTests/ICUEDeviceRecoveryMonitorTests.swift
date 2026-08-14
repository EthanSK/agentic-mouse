@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class ICUEDeviceRecoveryMonitorTests: XCTestCase {
    func testEmitsOneRecoveryAfterMissingReceiverReturns() {
        let scheduler = ManualTickScheduler()
        var current = ICUEDevicePresenceSnapshot.absent
        var transitions: [ICUEDevicePresenceTransition] = []
        let monitor = ICUEDeviceRecoveryMonitor(
            initialSnapshot: .absent,
            scheduler: scheduler,
            probe: { current },
            onTransition: { transitions.append($0) }
        )

        monitor.start()
        scheduler.fire(times: 3)
        XCTAssertTrue(transitions.isEmpty)

        current = .init(identifier: "scimitar", lightingAvailable: true)
        scheduler.fire(times: 3)

        XCTAssertEqual(transitions, [.recovered(current)])
        XCTAssertEqual(scheduler.interval, 2)
    }

    func testEmitsLossAndReplacementWithoutRepeatingStableState() {
        let scheduler = ManualTickScheduler()
        let original = ICUEDevicePresenceSnapshot(identifier: "a", lightingAvailable: true)
        var current = original
        var transitions: [ICUEDevicePresenceTransition] = []
        let monitor = ICUEDeviceRecoveryMonitor(
            initialSnapshot: original,
            scheduler: scheduler,
            probe: { current },
            onTransition: { transitions.append($0) }
        )

        monitor.start()
        current = .absent
        scheduler.fire()
        scheduler.fire()
        current = .init(identifier: "b", lightingAvailable: true)
        scheduler.fire()

        XCTAssertEqual(
            transitions,
            [
                .lost(previousIdentifier: "a"),
                .recovered(.init(identifier: "b", lightingAvailable: true)),
            ]
        )
    }

    func testSynchronizePreventsDuplicateCallbackTransition() {
        let scheduler = ManualTickScheduler()
        var current = ICUEDevicePresenceSnapshot.absent
        var transitions: [ICUEDevicePresenceTransition] = []
        let monitor = ICUEDeviceRecoveryMonitor(
            initialSnapshot: .absent,
            scheduler: scheduler,
            probe: { current },
            onTransition: { transitions.append($0) }
        )

        monitor.start()
        current = .init(identifier: "scimitar", lightingAvailable: true)
        monitor.synchronize(current)
        scheduler.fire()

        XCTAssertTrue(transitions.isEmpty)
    }

    func testLightingCanRecoverWithoutChangingIdentifier() {
        let scheduler = ManualTickScheduler()
        let unavailable = ICUEDevicePresenceSnapshot(identifier: "scimitar", lightingAvailable: false)
        var current = unavailable
        var transitions: [ICUEDevicePresenceTransition] = []
        let monitor = ICUEDeviceRecoveryMonitor(
            initialSnapshot: unavailable,
            scheduler: scheduler,
            probe: { current },
            onTransition: { transitions.append($0) }
        )

        monitor.start()
        current = .init(identifier: "scimitar", lightingAvailable: true)
        scheduler.fire()

        XCTAssertEqual(transitions, [.recovered(current)])
    }
}
