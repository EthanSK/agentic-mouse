@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class RuntimeHealthMonitorTests: XCTestCase {
    func testStartsWithImmediateCheckAndThenRepeats() {
        let scheduler = ManualTickScheduler()
        var checks = 0
        let monitor = RuntimeHealthMonitor(scheduler: scheduler) { checks += 1 }

        monitor.start()
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(scheduler.interval, 2)

        scheduler.fire(times: 3)
        XCTAssertEqual(checks, 4)
    }

    func testRepeatedStartDoesNotDuplicateTheTimer() {
        let scheduler = ManualTickScheduler()
        var checks = 0
        let monitor = RuntimeHealthMonitor(scheduler: scheduler) { checks += 1 }

        monitor.start()
        monitor.start()
        XCTAssertEqual(checks, 1)
    }

    func testStopPreventsLaterChecks() {
        let scheduler = ManualTickScheduler()
        var checks = 0
        let monitor = RuntimeHealthMonitor(scheduler: scheduler) { checks += 1 }

        monitor.start()
        monitor.stop()
        scheduler.fire()
        XCTAssertEqual(checks, 1)
        XCTAssertFalse(monitor.isStarted)
    }
}
