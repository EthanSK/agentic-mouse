@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class YouTubeScrubHoldControllerTests: XCTestCase {
    @MainActor private final class Harness {
        let clock = ManualClock()
        let scheduler = ManualTickScheduler()
        let renewal = ManualTickScheduler()
        var allowed = true
        var events: [Notification.Name] = []
        var overrides: [Double] = []
        lazy var speed = ChromeYouTubeSpeedHoldController(
            scheduler: renewal,
            clock: clock,
            notify: { [unowned self] name, _, rate in
                events.append(name)
                if let rate { overrides.append(rate) }
                return true
            },
            inputAllowed: { [unowned self] in allowed }
        )
        lazy var hold = YouTubeScrubHoldController(
            clock: clock,
            scheduler: scheduler,
            inputAllowed: { [unowned self] in allowed },
            beginSpeed: { [unowned self] in _ = speed.beginMomentaryHold(source: $0) },
            endSpeed: { [unowned self] in speed.cancel(source: $0) }
        )

        func press(_ source: MouseSource = .corsair, volume: Bool = false) {
            hold.press(source: source, volumeModifierActive: volume)
        }

        func advance(_ duration: Double) {
            clock.advance(by: duration)
            scheduler.fire()
        }
    }

    func testShortClickKeepsRewindWithoutAnySpeedCommand() {
        let h = Harness()
        h.press()
        h.advance(0.349)
        XCTAssertTrue(h.hold.release(source: .corsair))
        XCTAssertTrue(h.events.isEmpty)
        XCTAssertFalse(h.scheduler.isRunning)
    }

    func testLongHoldRenewsAndRestoresExactPriorRateWithoutClick() {
        let h = Harness()
        h.press()
        h.advance(0.35)
        h.renewal.fire()
        XCTAssertFalse(h.hold.release(source: .corsair))
        XCTAssertEqual(h.events, [
            ChromeYouTubeSpeedHoldController.beginNotification,
            ChromeYouTubeSpeedHoldController.renewNotification,
            ChromeYouTubeSpeedHoldController.endNotification,
        ])
        XCTAssertTrue(h.overrides.isEmpty)
        XCTAssertFalse(h.renewal.isRunning)
    }

    func testReleaseAfterThresholdSuppressesClickEvenBeforeDelayedTimerRuns() {
        let h = Harness()
        h.press()
        h.clock.advance(by: 0.5)
        XCTAssertFalse(h.hold.release(source: .corsair))
        h.scheduler.fire()
        XCTAssertTrue(h.events.isEmpty)
    }

    func testDuplicatePressDoesNotRestartThreshold() {
        let h = Harness()
        h.press()
        h.advance(0.3)
        h.press()
        h.advance(0.06)
        XCTAssertEqual(h.events, [ChromeYouTubeSpeedHoldController.beginNotification])
        XCTAssertFalse(h.hold.release(source: .corsair))
    }

    func testWheelBeforeThresholdPermanentlyInhibitsSpeedForThisHold() {
        let h = Harness()
        h.press()
        h.hold.inhibitSpeed(source: .corsair)
        h.advance(1)
        h.press()
        h.advance(1)
        XCTAssertTrue(h.events.isEmpty)
        XCTAssertFalse(h.hold.release(source: .corsair))
    }

    func testWheelAfterBoostRestoresImmediatelyAndDoesNotRearm() {
        let h = Harness()
        h.press()
        h.advance(0.4)
        h.hold.inhibitSpeed(source: .corsair)
        h.advance(2)
        XCTAssertFalse(h.hold.release(source: .corsair))
        XCTAssertEqual(h.events, [
            ChromeYouTubeSpeedHoldController.beginNotification,
            ChromeYouTubeSpeedHoldController.endNotification,
        ])
    }

    func testVolumeModifierBeforeScrubPreventsBoost() {
        let h = Harness()
        h.press(volume: true)
        h.advance(1)
        XCTAssertFalse(h.hold.release(source: .corsair))
        XCTAssertTrue(h.events.isEmpty)
    }

    func testTwoMiceShareLeaseAndLastReleaseRestores() {
        let h = Harness()
        h.press()
        h.press(.razer)
        h.advance(0.4)
        XCTAssertFalse(h.hold.release(source: .corsair))
        XCTAssertEqual(h.events, [ChromeYouTubeSpeedHoldController.beginNotification])
        XCTAssertFalse(h.hold.release(source: .razer))
        XCTAssertEqual(h.events.last, ChromeYouTubeSpeedHoldController.endNotification)
    }

    func testRepeatedDefaultHoldsNeverBecomeSticky() {
        let h = Harness()
        for _ in 0..<3 {
            h.press()
            h.advance(0.4)
            XCTAssertFalse(h.hold.release(source: .corsair))
            h.advance(0.03)
        }
        XCTAssertEqual(h.events.count, 6)
        XCTAssertFalse(h.speed.isStickyLocked)
        XCTAssertTrue(h.overrides.isEmpty)
    }

    func testTeardownCancelsPendingAndActiveHoldsWithoutClick() {
        let h = Harness()
        h.press()
        h.hold.cancel(source: .corsair)
        h.advance(1)
        XCTAssertTrue(h.events.isEmpty)
        XCTAssertFalse(h.hold.release(source: .corsair))
        h.press()
        h.advance(0.4)
        h.hold.cancel(source: .corsair)
        XCTAssertFalse(h.hold.release(source: .corsair))
        XCTAssertEqual(h.events.last, ChromeYouTubeSpeedHoldController.endNotification)
    }

    func testLockBeforeThresholdDoesNotStartSpeed() {
        let h = Harness()
        h.press()
        h.allowed = false
        h.advance(1)
        XCTAssertTrue(h.events.isEmpty)
        XCTAssertFalse(h.hold.release(source: .corsair))
    }
}
