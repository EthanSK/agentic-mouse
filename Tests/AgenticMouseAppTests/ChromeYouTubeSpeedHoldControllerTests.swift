@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class ChromeYouTubeSpeedHoldControllerTests: XCTestCase {
    func testFirstPressBeginsAndRenewsUntilLastExactMouseReleases() {
        let scheduler = ManualTickScheduler()
        var events: [(Notification.Name, String, Double?)] = []
        let controller = ChromeYouTubeSpeedHoldController(
            scheduler: scheduler,
            renewalInterval: 0.75,
            notify: { name, token, rate in events.append((name, token, rate)); return true },
            makeToken: { "hold-token" }
        )

        XCTAssertTrue(controller.press(source: .corsair))
        XCTAssertEqual(scheduler.interval, 0.75)
        scheduler.fire()
        XCTAssertTrue(controller.press(source: .razer))
        controller.release(source: .corsair)
        XCTAssertTrue(scheduler.isRunning)
        controller.release(source: .razer)

        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(events.map(\.0), [
            ChromeYouTubeSpeedHoldController.beginNotification,
            ChromeYouTubeSpeedHoldController.renewNotification,
            ChromeYouTubeSpeedHoldController.endNotification,
        ])
        XCTAssertEqual(events.map(\.1), ["hold-token", "hold-token", "hold-token"])
        XCTAssertEqual(events.compactMap(\.2), [])
    }

    func testLockDuringRenewalEndsTheLeaseInsteadOfLeavingDoubleSpeedStranded() {
        let scheduler = ManualTickScheduler()
        var allowed = true
        var events: [Notification.Name] = []
        let controller = ChromeYouTubeSpeedHoldController(
            scheduler: scheduler,
            notify: { name, _, _ in events.append(name); return true },
            inputAllowed: { allowed },
            makeToken: { "lock-token" }
        )

        XCTAssertTrue(controller.press(source: .corsair))
        allowed = false
        scheduler.fire()

        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(events, [
            ChromeYouTubeSpeedHoldController.beginNotification,
            ChromeYouTubeSpeedHoldController.endNotification,
        ])
    }

    func testRejectedBeginDoesNotStartRenewing() {
        let scheduler = ManualTickScheduler()
        let controller = ChromeYouTubeSpeedHoldController(
            scheduler: scheduler,
            notify: { _, _, _ in false }
        )

        XCTAssertFalse(controller.press(source: .razer))
        XCTAssertFalse(scheduler.isRunning)
    }

    func testNotificationContractIsStableAndNamespaced() {
        XCTAssertEqual(
            ChromeYouTubeSpeedHoldController.beginNotification.rawValue,
            "com.ethansk.agenticmouse.youtube.doubleSpeedHoldBegan"
        )
        XCTAssertEqual(
            ChromeYouTubeSpeedHoldController.renewNotification.rawValue,
            "com.ethansk.agenticmouse.youtube.doubleSpeedHoldRenewed"
        )
        XCTAssertEqual(
            ChromeYouTubeSpeedHoldController.endNotification.rawValue,
            "com.ethansk.agenticmouse.youtube.doubleSpeedHoldEnded"
        )
        XCTAssertEqual(ChromeYouTubeSpeedHoldController.tokenKey, "holdToken")
        XCTAssertEqual(
            ChromeYouTubeSpeedHoldController.restorePlaybackRateKey,
            "restorePlaybackRate"
        )
        XCTAssertEqual(ChromeYouTubeSpeedHoldController.normalPlaybackRate, 1.0)
    }

    func testDoubleClickLocksTwoTimesUntilNextDoubleClickRequestsOneTimes() {
        let scheduler = ManualTickScheduler()
        let clock = ManualClock(now: 10)
        var nextToken = 0
        var events: [(Notification.Name, String, Double?)] = []
        var lockChanges: [(MouseSource, Bool)] = []
        let controller = ChromeYouTubeSpeedHoldController(
            scheduler: scheduler,
            clock: clock,
            notify: { name, token, rate in
                events.append((name, token, rate))
                return true
            },
            makeToken: {
                nextToken += 1
                return "token-\(nextToken)"
            }
        )
        controller.onStickyLockChange = { source, locked in
            lockChanges.append((source, locked))
        }

        XCTAssertTrue(controller.press(source: .corsair))
        clock.advance(by: 0.05)
        controller.release(source: .corsair)
        clock.advance(by: 0.08)
        XCTAssertTrue(controller.press(source: .corsair))
        controller.release(source: .corsair)

        XCTAssertTrue(controller.isStickyLocked)
        XCTAssertTrue(scheduler.isRunning)
        scheduler.fire()

        clock.advance(by: 0.05)
        XCTAssertTrue(controller.press(source: .corsair))
        clock.advance(by: 0.05)
        controller.release(source: .corsair)
        clock.advance(by: 0.08)
        XCTAssertTrue(controller.press(source: .corsair))
        controller.release(source: .corsair)

        XCTAssertFalse(controller.isStickyLocked)
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(events.map(\.0), [
            ChromeYouTubeSpeedHoldController.beginNotification,
            ChromeYouTubeSpeedHoldController.endNotification,
            ChromeYouTubeSpeedHoldController.beginNotification,
            ChromeYouTubeSpeedHoldController.renewNotification,
            ChromeYouTubeSpeedHoldController.endNotification,
        ])
        XCTAssertEqual(events.map(\.1), [
            "token-1", "token-1", "token-2", "token-2", "token-2",
        ])
        XCTAssertEqual(events.map(\.2), [nil, nil, nil, nil, 1.0])
        XCTAssertEqual(lockChanges.map(\.0), [.corsair, .corsair])
        XCTAssertEqual(lockChanges.map(\.1), [true, false])
    }

    func testLongHoldDoesNotSeedAStickyDoubleClick() {
        let scheduler = ManualTickScheduler()
        let clock = ManualClock(now: 1)
        var events: [Notification.Name] = []
        let controller = ChromeYouTubeSpeedHoldController(
            scheduler: scheduler,
            clock: clock,
            notify: { name, _, _ in events.append(name); return true }
        )

        XCTAssertTrue(controller.press(source: .razer))
        clock.advance(by: 0.5)
        controller.release(source: .razer)
        clock.advance(by: 0.05)
        XCTAssertTrue(controller.press(source: .razer))

        XCTAssertFalse(controller.isStickyLocked)
        XCTAssertEqual(events, [
            ChromeYouTubeSpeedHoldController.beginNotification,
            ChromeYouTubeSpeedHoldController.endNotification,
            ChromeYouTubeSpeedHoldController.beginNotification,
        ])
    }

    func testDifferentMiceCannotCombineClicksIntoAStickyLock() {
        let scheduler = ManualTickScheduler()
        let clock = ManualClock(now: 1)
        let controller = ChromeYouTubeSpeedHoldController(
            scheduler: scheduler,
            clock: clock,
            notify: { _, _, _ in true }
        )

        XCTAssertTrue(controller.press(source: .corsair))
        clock.advance(by: 0.05)
        controller.release(source: .corsair)
        clock.advance(by: 0.05)
        XCTAssertTrue(controller.press(source: .razer))

        XCTAssertFalse(controller.isStickyLocked)
    }

    func testOwningModeExitEndsStickyLockAtExactPriorRateContract() {
        let scheduler = ManualTickScheduler()
        let clock = ManualClock(now: 1)
        var events: [(Notification.Name, Double?)] = []
        let controller = ChromeYouTubeSpeedHoldController(
            scheduler: scheduler,
            clock: clock,
            notify: { name, _, rate in events.append((name, rate)); return true }
        )

        XCTAssertTrue(controller.press(source: .razer))
        clock.advance(by: 0.05)
        controller.release(source: .razer)
        clock.advance(by: 0.05)
        XCTAssertTrue(controller.press(source: .razer))
        controller.release(source: .razer)
        XCTAssertTrue(controller.isStickyLocked)

        controller.cancel(source: .razer)

        XCTAssertFalse(controller.isStickyLocked)
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(events.last?.0, ChromeYouTubeSpeedHoldController.endNotification)
        XCTAssertNil(events.last?.1)
    }

    func testOtherMouseModeExitDoesNotCancelTheOwningMouseStickyLock() {
        let scheduler = ManualTickScheduler()
        let clock = ManualClock(now: 1)
        var events: [Notification.Name] = []
        let controller = ChromeYouTubeSpeedHoldController(
            scheduler: scheduler,
            clock: clock,
            notify: { name, _, _ in events.append(name); return true }
        )

        XCTAssertTrue(controller.press(source: .corsair))
        clock.advance(by: 0.05)
        controller.release(source: .corsair)
        clock.advance(by: 0.05)
        XCTAssertTrue(controller.press(source: .corsair))
        controller.release(source: .corsair)

        controller.cancel(source: .razer)

        XCTAssertTrue(controller.isStickyLocked)
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertEqual(events.last, ChromeYouTubeSpeedHoldController.beginNotification)
    }

    func testLockLossRestoresPriorRateInsteadOfForcingOneTimes() {
        let scheduler = ManualTickScheduler()
        let clock = ManualClock(now: 1)
        var allowed = true
        var events: [(Notification.Name, Double?)] = []
        let controller = ChromeYouTubeSpeedHoldController(
            scheduler: scheduler,
            clock: clock,
            notify: { name, _, rate in events.append((name, rate)); return true },
            inputAllowed: { allowed }
        )

        XCTAssertTrue(controller.press(source: .corsair))
        clock.advance(by: 0.05)
        controller.release(source: .corsair)
        clock.advance(by: 0.05)
        XCTAssertTrue(controller.press(source: .corsair))
        controller.release(source: .corsair)
        XCTAssertTrue(controller.isStickyLocked)

        allowed = false
        scheduler.fire()

        XCTAssertFalse(controller.isStickyLocked)
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(events.last?.0, ChromeYouTubeSpeedHoldController.endNotification)
        XCTAssertNil(events.last?.1)
    }
}
