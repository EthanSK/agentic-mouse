import AppKit
@testable import AgenticMouseApp
import XCTest

final class WakeRecoveryGateTests: XCTestCase {
    func testCoalescesScreenAndSystemWakeForOneRecovery() {
        var gate = WakeRecoveryGate()

        XCTAssertTrue(gate.shouldRecover(at: 10))
        XCTAssertFalse(gate.shouldRecover(at: 10.1))
        XCTAssertTrue(gate.shouldRecover(at: 11))
    }

    func testAppObservesBothDisplayAndSystemWake() {
        XCTAssertEqual(
            Set(AppDelegate.wakeNotifications),
            Set([NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification])
        )
    }
}
