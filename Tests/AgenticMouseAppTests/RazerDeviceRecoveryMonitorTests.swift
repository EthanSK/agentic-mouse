@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class RazerDeviceRecoveryMonitorTests: XCTestCase {
    func testStableConnectedPollsNeverRewriteLighting() {
        let scheduler = ManualTickScheduler()
        var recoveryCount = 0
        let monitor = RazerDeviceRecoveryMonitor(
            initiallyPresent: true,
            initiallyRecovered: true,
            scheduler: scheduler,
            probePresence: { true },
            recover: {
                recoveryCount += 1
                return true
            },
            onLost: {},
            onRecovered: {}
        )

        monitor.start()
        scheduler.fire(times: 4)

        XCTAssertEqual(recoveryCount, 0)
        XCTAssertEqual(scheduler.interval, 2)
    }

    func testReconnectRetriesUntilIdleWhiteIsAcknowledgedOnce() {
        let scheduler = ManualTickScheduler()
        var present = false
        var recoveryResults = [false, true]
        var recoveries = 0
        let monitor = RazerDeviceRecoveryMonitor(
            initiallyPresent: false,
            initiallyRecovered: false,
            scheduler: scheduler,
            probePresence: { present },
            recover: {
                recoveries += 1
                return recoveryResults.removeFirst()
            },
            onLost: {},
            onRecovered: {}
        )

        monitor.start()
        scheduler.fire()
        XCTAssertEqual(recoveries, 0)

        present = true
        scheduler.fire(times: 4)

        XCTAssertEqual(recoveries, 2)
    }

    func testDisconnectTearsDownOnceAndNextPresenceRecovers() {
        let scheduler = ManualTickScheduler()
        var present = true
        var losses = 0
        var recoveries = 0
        let monitor = RazerDeviceRecoveryMonitor(
            initiallyPresent: true,
            initiallyRecovered: true,
            scheduler: scheduler,
            probePresence: { present },
            recover: { true },
            onLost: { losses += 1 },
            onRecovered: { recoveries += 1 }
        )

        monitor.start()
        present = false
        scheduler.fire(times: 3)
        XCTAssertEqual(losses, 1)

        present = true
        scheduler.fire(times: 3)
        XCTAssertEqual(recoveries, 1)
    }

    func testSynchronizeAfterWakePreventsDuplicateRecovery() {
        let scheduler = ManualTickScheduler()
        var recoveryCount = 0
        let monitor = RazerDeviceRecoveryMonitor(
            initiallyPresent: false,
            initiallyRecovered: false,
            scheduler: scheduler,
            probePresence: { true },
            recover: {
                recoveryCount += 1
                return true
            },
            onLost: {},
            onRecovered: {}
        )

        monitor.synchronize(present: true, recovered: true)
        monitor.start()
        scheduler.fire()

        XCTAssertEqual(recoveryCount, 0)
    }
}
