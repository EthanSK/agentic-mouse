import AppKit
import Carbon
import XCTest
import ScimitarUI
@testable import AgenticMouseApp

final class AgenticMouseWindowTests: XCTestCase {
    @MainActor
    func testBackgroundReopenDoesNotCreateOrActivateSettings() throws {
        guard ProcessInfo.processInfo.environment["AGENTIC_MOUSE_ALLOW_VISIBLE_UI_TESTS"] == "1" else {
            throw XCTSkip("Reopen regression checks require an isolated desktop")
        }
        let app = NSApplication.shared
        guard !app.isActive else { throw XCTSkip("The test host must start in the background") }
        let originalWindows = Set(app.windows.map(ObjectIdentifier.init))
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let delegate = AppDelegate()
        defer {
            // Also clean up the deliberately broken pre-fix variant.
            app.windows.filter { !originalWindows.contains(ObjectIdentifier($0)) }.forEach { $0.close() }
        }
        for hasVisibleWindows in [false, true, false] {
            XCTAssertFalse(delegate.applicationShouldHandleReopen(app, hasVisibleWindows: hasVisibleWindows))
        }
        XCTAssertEqual(Set(app.windows.map(ObjectIdentifier.init)), originalWindows)
        XCTAssertFalse(app.isActive)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmostPID)
    }

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
