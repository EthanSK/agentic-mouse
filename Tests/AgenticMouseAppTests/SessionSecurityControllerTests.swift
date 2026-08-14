@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class SessionSecurityControllerTests: XCTestCase {
    func testScreenWakeRestoresOnlyAStillActiveSession() {
        let center = NotificationCenter()
        let observer = WorkspaceSessionActivityObserver(center: center)
        var activeCount = 0
        var resignedCount = 0
        observer.onSessionBecameActive = { activeCount += 1 }
        observer.onSessionResignedActive = { resignedCount += 1 }
        observer.start()

        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        XCTAssertEqual(resignedCount, 1)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        XCTAssertEqual(activeCount, 1)

        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        XCTAssertEqual(activeCount, 1, "screen wake must not unlock a resigned session")

        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        XCTAssertEqual(activeCount, 2)
        observer.stop()
    }

    func testLaunchStartsClosedAndInactiveLaunchCannotBeConfirmedOpen() {
        let observer = RecordingSessionObserver()
        let lease = RecordingSessionLease()
        let scheduler = ManualTickScheduler()
        let controller = makeController(observer: observer, lease: lease, scheduler: scheduler)
        var lockdowns = 0
        controller.onLockdown = { lockdowns += 1 }

        controller.start()
        XCTAssertEqual(controller.state, .awaitingLaunchConfirmation)
        XCTAssertFalse(controller.isUnlocked)
        XCTAssertEqual(lease.deactivateCount, 1)

        observer.resign()
        controller.confirmActiveSessionAfterLaunch()

        XCTAssertEqual(controller.state, .locked)
        XCTAssertFalse(controller.isUnlocked)
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(lockdowns, 1)
        XCTAssertEqual(lease.activateCount, 0)
    }

    func testActiveSessionRenewsAndLockClearsImmediately() {
        let observer = RecordingSessionObserver()
        let lease = RecordingSessionLease()
        let scheduler = ManualTickScheduler()
        let controller = makeController(observer: observer, lease: lease, scheduler: scheduler)
        var unlocks = 0
        var lockdowns = 0
        controller.onUnlock = { unlocks += 1 }
        controller.onLockdown = { lockdowns += 1 }

        controller.start()
        controller.confirmActiveSessionAfterLaunch()
        XCTAssertTrue(controller.isUnlocked)
        XCTAssertEqual(lease.activateCount, 1)
        XCTAssertEqual(scheduler.interval, 1)
        XCTAssertEqual(unlocks, 1)

        scheduler.fire(times: 3)
        XCTAssertEqual(lease.renewCount, 3)

        observer.resign()
        XCTAssertFalse(controller.isUnlocked)
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(lockdowns, 1)
        XCTAssertEqual(lease.deactivateCount, 2)

        observer.becomeActive()
        XCTAssertTrue(controller.isUnlocked)
        XCTAssertEqual(unlocks, 2)
        XCTAssertEqual(lease.activateCount, 2)
    }

    func testLeaseFailureFailsClosedAndDoesNotResumeItself() {
        let observer = RecordingSessionObserver()
        let lease = RecordingSessionLease()
        let scheduler = ManualTickScheduler()
        let controller = makeController(observer: observer, lease: lease, scheduler: scheduler)
        var lockdowns = 0
        controller.onLockdown = { lockdowns += 1 }

        controller.start()
        controller.confirmActiveSessionAfterLaunch()
        lease.renewError = TestError.failed
        scheduler.fire()

        XCTAssertEqual(controller.state, .locked)
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(lockdowns, 1)
        XCTAssertEqual(lease.deactivateCount, 2)
    }

    func testStopAlwaysClearsTheLease() {
        let observer = RecordingSessionObserver()
        let lease = RecordingSessionLease()
        let scheduler = ManualTickScheduler()
        let controller = makeController(observer: observer, lease: lease, scheduler: scheduler)

        controller.start()
        controller.confirmActiveSessionAfterLaunch()
        controller.stop()

        XCTAssertEqual(controller.state, .locked)
        XCTAssertFalse(controller.isUnlocked)
        XCTAssertEqual(observer.stopCount, 1)
        XCTAssertEqual(lease.deactivateCount, 2)
    }

    private func makeController(
        observer: RecordingSessionObserver,
        lease: RecordingSessionLease,
        scheduler: ManualTickScheduler
    ) -> SessionSecurityController {
        SessionSecurityController(
            observer: observer,
            lease: lease,
            scheduler: scheduler,
            log: Log(category: "session-security-test", sink: RecordingLogSink())
        )
    }
}

@MainActor
private final class RecordingSessionObserver: SessionActivityObserving {
    var onSessionBecameActive: (() -> Void)?
    var onSessionResignedActive: (() -> Void)?
    private(set) var stopCount = 0

    func start() {}
    func stop() { stopCount += 1 }
    func becomeActive() { onSessionBecameActive?() }
    func resign() { onSessionResignedActive?() }
}

private final class RecordingSessionLease: ColorProofLeaseControlling {
    private(set) var activateCount = 0
    private(set) var renewCount = 0
    private(set) var deactivateCount = 0
    var activateError: Error?
    var renewError: Error?

    func activate() throws {
        activateCount += 1
        if let activateError { throw activateError }
    }

    func renew() throws {
        renewCount += 1
        if let renewError { throw renewError }
    }

    func deactivate() { deactivateCount += 1 }
}

private enum TestError: Error {
    case failed
}
