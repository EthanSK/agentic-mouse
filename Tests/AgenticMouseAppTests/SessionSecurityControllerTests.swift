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
        var availableCount = 0
        observer.onSessionBecameActive = { activeCount += 1 }
        observer.onSessionResignedActive = { resignedCount += 1 }
        observer.onSessionMayBeAvailable = { availableCount += 1 }
        observer.start()

        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        XCTAssertEqual(resignedCount, 1)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        XCTAssertEqual(activeCount, 0)
        XCTAssertEqual(availableCount, 1)

        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        XCTAssertEqual(activeCount, 0, "screen wake must not unlock a resigned session")
        XCTAssertEqual(availableCount, 1)

        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        XCTAssertEqual(activeCount, 1)
        observer.stop()
    }

    func testLaunchStartsClosedAndInactiveLaunchCannotBeConfirmedOpen() {
        let observer = RecordingSessionObserver()
        let lease = RecordingSessionLease()
        let scheduler = ManualTickScheduler()
        let proof = RecordingLaunchSessionUnlockProof()
        let controller = makeController(
            observer: observer,
            lease: lease,
            scheduler: scheduler,
            proof: proof
        )
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
        proof.emit()
        XCTAssertEqual(lease.activateCount, 0, "input proof after session resign must stay inert")
    }

    func testActiveSessionRenewsAndLockClearsImmediately() {
        let observer = RecordingSessionObserver()
        let lease = RecordingSessionLease()
        let scheduler = ManualTickScheduler()
        let proof = RecordingLaunchSessionUnlockProof()
        let controller = makeController(
            observer: observer,
            lease: lease,
            scheduler: scheduler,
            proof: proof
        )
        var unlocks = 0
        var lockdowns = 0
        controller.onUnlock = { unlocks += 1 }
        controller.onLockdown = { lockdowns += 1 }

        controller.start()
        controller.confirmActiveSessionAfterLaunch()
        XCTAssertEqual(controller.state, .awaitingLaunchConfirmation)
        XCTAssertEqual(lease.activateCount, 0)
        proof.emit()
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

    func testDisplayWakeRemainsLockedUntilUnlockedInputProofArrives() {
        let observer = RecordingSessionObserver()
        let lease = RecordingSessionLease()
        let scheduler = ManualTickScheduler()
        let proof = RecordingLaunchSessionUnlockProof()
        let controller = makeController(
            observer: observer,
            lease: lease,
            scheduler: scheduler,
            proof: proof
        )

        controller.start()
        controller.confirmActiveSessionAfterLaunch()
        proof.emit()
        XCTAssertTrue(controller.isUnlocked)

        observer.resign()
        observer.mayBeAvailable()
        XCTAssertFalse(controller.isUnlocked)
        XCTAssertTrue(proof.isStarted)
        XCTAssertEqual(lease.activateCount, 1)

        proof.emit()
        XCTAssertTrue(controller.isUnlocked)
        XCTAssertEqual(lease.activateCount, 2)
    }

    func testLoginWindowActivationLocksImmediatelyAndRequiresProofAfterLeaving() {
        let center = NotificationCenter()
        let observer = WorkspaceSessionActivityObserver(center: center)
        var resignedCount = 0
        var availableCount = 0
        observer.onSessionResignedActive = { resignedCount += 1 }
        observer.onSessionMayBeAvailable = { availableCount += 1 }
        observer.start()

        observer.handleActivatedBundleIdentifier("com.apple.loginwindow")
        XCTAssertEqual(resignedCount, 1)
        XCTAssertEqual(availableCount, 0)

        observer.handleActivatedBundleIdentifier("com.apple.dt.Xcode")
        XCTAssertEqual(availableCount, 1)
        observer.stop()
    }

    func testLeaseFailureFailsClosedAndDoesNotResumeItself() {
        let observer = RecordingSessionObserver()
        let lease = RecordingSessionLease()
        let scheduler = ManualTickScheduler()
        let proof = RecordingLaunchSessionUnlockProof()
        let controller = makeController(
            observer: observer,
            lease: lease,
            scheduler: scheduler,
            proof: proof
        )
        var lockdowns = 0
        controller.onLockdown = { lockdowns += 1 }

        controller.start()
        controller.confirmActiveSessionAfterLaunch()
        proof.emit()
        lease.renewError = TestError.failed
        scheduler.fire()

        XCTAssertEqual(controller.state, .locked)
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(lockdowns, 1)
        XCTAssertEqual(lease.deactivateCount, 2)
    }

    func testUnavailableKarabinerCLIRecoversWithoutAReopen() {
        let observer = RecordingSessionObserver()
        let lease = RecordingSessionLease()
        lease.activateError = KarabinerModeBridgeError.commandLineUnavailable
        let scheduler = ManualTickScheduler()
        let proof = RecordingLaunchSessionUnlockProof()
        let controller = makeController(
            observer: observer,
            lease: lease,
            scheduler: scheduler,
            proof: proof
        )
        var unlocks = 0
        controller.onUnlock = { unlocks += 1 }

        controller.start()
        controller.confirmActiveSessionAfterLaunch()
        proof.emit()

        XCTAssertEqual(controller.state, .locked)
        XCTAssertEqual(scheduler.interval, 1)
        XCTAssertEqual(unlocks, 0)

        lease.activateError = nil
        scheduler.fire()

        XCTAssertEqual(controller.state, .unlocked)
        XCTAssertEqual(scheduler.interval, 1, "successful recovery returns to the heartbeat")
        XCTAssertEqual(unlocks, 1)
        XCTAssertEqual(lease.activateCount, 2)
    }

    func testRecoverableFailuresBackOffWhileRemainingLocked() {
        let observer = RecordingSessionObserver()
        let lease = RecordingSessionLease()
        lease.activateError = KarabinerModeBridgeError.commandLineUnavailable
        let scheduler = ManualTickScheduler()
        let proof = RecordingLaunchSessionUnlockProof()
        let controller = makeController(
            observer: observer,
            lease: lease,
            scheduler: scheduler,
            proof: proof
        )

        controller.start()
        controller.confirmActiveSessionAfterLaunch()
        proof.emit()
        XCTAssertEqual(scheduler.interval, 1)

        scheduler.fire()
        XCTAssertEqual(controller.state, .locked)
        XCTAssertEqual(scheduler.interval, 2)

        scheduler.fire()
        XCTAssertEqual(controller.state, .locked)
        XCTAssertEqual(scheduler.interval, 5)
    }

    func testStopAlwaysClearsTheLease() {
        let observer = RecordingSessionObserver()
        let lease = RecordingSessionLease()
        let scheduler = ManualTickScheduler()
        let proof = RecordingLaunchSessionUnlockProof()
        let controller = makeController(
            observer: observer,
            lease: lease,
            scheduler: scheduler,
            proof: proof
        )

        controller.start()
        controller.confirmActiveSessionAfterLaunch()
        proof.emit()
        controller.stop()

        XCTAssertEqual(controller.state, .locked)
        XCTAssertFalse(controller.isUnlocked)
        XCTAssertEqual(observer.stopCount, 1)
        XCTAssertEqual(lease.deactivateCount, 2)
    }

    private func makeController(
        observer: RecordingSessionObserver,
        lease: RecordingSessionLease,
        scheduler: ManualTickScheduler,
        proof: RecordingLaunchSessionUnlockProof
    ) -> SessionSecurityController {
        SessionSecurityController(
            observer: observer,
            lease: lease,
            scheduler: scheduler,
            launchUnlockProof: proof,
            log: Log(category: "session-security-test", sink: RecordingLogSink())
        )
    }
}

@MainActor
private final class RecordingLaunchSessionUnlockProof: LaunchSessionUnlockProofObserving {
    var onUnlockedInput: (() -> Void)?
    var canStart = true
    private(set) var isStarted = false
    private(set) var stopCount = 0

    func start() -> Bool {
        isStarted = canStart
        return canStart
    }

    func stop() {
        if isStarted { stopCount += 1 }
        isStarted = false
    }

    func emit() {
        guard isStarted else { return }
        onUnlockedInput?()
    }
}

@MainActor
private final class RecordingSessionObserver: SessionActivityObserving {
    var onSessionBecameActive: (() -> Void)?
    var onSessionResignedActive: (() -> Void)?
    var onSessionMayBeAvailable: (() -> Void)?
    private(set) var stopCount = 0

    func start() {}
    func stop() { stopCount += 1 }
    func becomeActive() { onSessionBecameActive?() }
    func resign() { onSessionResignedActive?() }
    func mayBeAvailable() { onSessionMayBeAvailable?() }
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
