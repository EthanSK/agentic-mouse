import Foundation
import XCTest

/// Real windows belong on an isolated test desktop, never on the user's Mac
/// merely because an agent ran `swift test` while their mice were unplugged.
class VisibleHUDTestCase: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["AGENTIC_MOUSE_ALLOW_VISIBLE_UI_TESTS"] == "1",
            "Visible HUD tests require an explicitly isolated test desktop."
        )
    }
}
