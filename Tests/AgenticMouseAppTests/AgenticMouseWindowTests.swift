import AppKit
import Carbon
import XCTest
import ScimitarUI
@testable import AgenticMouseApp

final class AgenticMouseWindowTests: XCTestCase {
    func testOnlySystemQuitKeepsRecoveryRegistered() {
        XCTAssertFalse(AgenticMouseTerminationPolicy.isSystemQuit(reason: nil))
        XCTAssertFalse(AgenticMouseTerminationPolicy.isSystemQuit(reason: UInt32(kAEQuitApplication)))
        for reason in [kAEQuitAll, kAEShutDown, kAERestart, kAEReallyLogOut] {
            XCTAssertTrue(AgenticMouseTerminationPolicy.isSystemQuit(reason: UInt32(reason)))
        }
    }

    @MainActor
    func testNormalWindowCanCloseWithoutBeingDestroyed() {
        let controller = AgenticMouseWindowController(state: AgenticMouseControlState())
        guard let window = controller.window else { return XCTFail("Missing app window") }
        XCTAssertFalse(window.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertEqual(window.title, "Agentic Mouse")
        window.close()
        XCTAssertNotNil(controller.window)
        XCTAssertFalse(window.isVisible)
    }
}
