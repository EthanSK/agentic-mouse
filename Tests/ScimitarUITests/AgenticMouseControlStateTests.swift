import XCTest
import ScimitarKit
@testable import ScimitarUI

/// The window must explain real runtime failures without calling a disconnected
/// second mouse a failure or reporting a locked session as ready.
final class AgenticMouseControlStateTests: XCTestCase {
    private func working() -> AgenticMouseControlSnapshot {
        var snapshot = AgenticMouseControlSnapshot()
        snapshot.sessionReady = true
        snapshot.accessibilityGranted = true
        snapshot.commandsReady = true
        snapshot.wheelReady = true
        snapshot.recovery = "enabled"
        snapshot.corsairConnected = true
        return snapshot
    }

    func testOneConnectedMouseIsWorking() {
        var snapshot = working()
        XCTAssertEqual(snapshot.health, .working)
        XCTAssertEqual(snapshot.summary, "Corsair connected")
        snapshot.corsairConnected = false
        snapshot.razerConnected = true
        XCTAssertEqual(snapshot.health, .working)
        XCTAssertEqual(snapshot.summary, "Razer connected")
        snapshot.razerConnected = false
        XCTAssertEqual(snapshot.health, .attention)
    }

    func testSessionGateAndPermissionTakePriority() {
        var snapshot = working()
        snapshot.accessibilityGranted = false
        snapshot.commandsReady = false
        XCTAssertEqual(snapshot.issue, "Accessibility is off")
        XCTAssertEqual(snapshot.health, .unavailable)
        snapshot.sessionReady = false
        XCTAssertEqual(snapshot.health, .paused)
    }

    func testSocketAndWheelFailuresCannotLookHealthy() {
        var snapshot = working()
        snapshot.commandsReady = false
        XCTAssertEqual(snapshot.issue, "Mouse commands unavailable")
        snapshot.commandsReady = true
        snapshot.wheelReady = false
        XCTAssertEqual(snapshot.issue, "Wheel actions unavailable")
        XCTAssertEqual(snapshot.health, .unavailable)
    }

    func testRecoveryNeedsAttentionWithoutClaimingMouseIsDead() {
        var snapshot = working()
        snapshot.recovery = "requires approval"
        XCTAssertEqual(snapshot.health, .attention)
        XCTAssertTrue(snapshot.issue?.contains("requires approval") == true)
    }
}
