import CoreGraphics
@testable import AgenticMouseApp
import XCTest

@MainActor
final class ApplicationShortcutDispatcherTests: XCTestCase {
    func testPostsOneBoundedShortcutToTheResolvedApplicationProcess() {
        var resolvedBundleIdentifiers: [String] = []
        var events: [(pid_t, CGKeyCode, CGEventFlags, Bool)] = []
        let dispatcher = ApplicationShortcutDispatcher(
            targetProcessResolver: { bundleIdentifier in
                resolvedBundleIdentifiers.append(bundleIdentifier)
                return 73
            },
            postEvent: { events.append(($0, $1, $2, $3)); return true },
            accessibilityTrusted: { true },
            inputAllowed: { true }
        )

        let shortcut = ApplicationShortcutDispatcher.Shortcut(
            keyCode: 13,
            flags: .maskCommand
        )
        guard case .success = dispatcher.perform(
            shortcut,
            targetBundleIdentifier: "com.google.Chrome",
            targetDisplayName: "Chrome"
        ) else {
            return XCTFail("the resolved background app should receive its shortcut")
        }

        XCTAssertEqual(resolvedBundleIdentifiers, ["com.google.Chrome"])
        XCTAssertEqual(events.map(\.0), [73, 73])
        XCTAssertEqual(events.map(\.1), [13, 13])
        XCTAssertEqual(events.map(\.2), [.maskCommand, .maskCommand])
        XCTAssertEqual(events.map(\.3), [true, false])
    }

    func testLockedSessionAccessibilityAndMissingAppFailClosed() {
        var eventCount = 0
        let locked = ApplicationShortcutDispatcher(
            targetProcessResolver: { _ in 42 },
            postEvent: { _, _, _, _ in eventCount += 1; return true },
            accessibilityTrusted: { true },
            inputAllowed: { false }
        )
        guard case .failure(let lockedError) = locked.perform(
            .init(keyCode: 13, flags: .maskCommand),
            targetBundleIdentifier: "com.google.Chrome",
            targetDisplayName: "Chrome"
        ) else {
            return XCTFail("locked sessions must reject targeted shortcuts")
        }
        XCTAssertEqual(
            lockedError.description,
            "Mouse commands are disabled while macOS is locked"
        )

        let untrusted = ApplicationShortcutDispatcher(
            targetProcessResolver: { _ in 42 },
            postEvent: { _, _, _, _ in eventCount += 1; return true },
            accessibilityTrusted: { false },
            inputAllowed: { true }
        )
        guard case .failure(let permissionError) = untrusted.perform(
            .init(keyCode: 13, flags: .maskCommand),
            targetBundleIdentifier: "com.google.Chrome",
            targetDisplayName: "Chrome"
        ) else {
            return XCTFail("untrusted targeted shortcuts must fail")
        }
        XCTAssertEqual(
            permissionError.description,
            "Accessibility permission is required for Chrome shortcuts"
        )

        let missing = ApplicationShortcutDispatcher(
            targetProcessResolver: { _ in nil },
            postEvent: { _, _, _, _ in eventCount += 1; return true },
            accessibilityTrusted: { true },
            inputAllowed: { true }
        )
        guard case .failure(let missingError) = missing.perform(
            .init(keyCode: 13, flags: .maskCommand),
            targetBundleIdentifier: "com.google.Chrome",
            targetDisplayName: "Chrome"
        ) else {
            return XCTFail("a missing target must fail")
        }
        XCTAssertEqual(missingError.description, "Chrome is not running")
        XCTAssertEqual(eventCount, 0)
    }
}
