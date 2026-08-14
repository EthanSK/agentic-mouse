@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class KeysModeActionExecutorTests: XCTestCase {
    func testEveryKeyPostsExactlyOneNativeDownUpCycle() {
        var events: [(CGKeyCode, Bool)] = []
        var modifiedEvents: [(CGKeyCode, CGEventFlags, Bool)] = []
        var systemEvents: [(Int32, Bool)] = []
        let executor = KeysModeActionExecutor(
            postEvent: { keyCode, isDown in
                events.append((keyCode, isDown))
                return true
            },
            postModifiedEvent: { keyCode, flags, isDown in
                modifiedEvents.append((keyCode, flags, isDown))
                return true
            },
            postSystemEvent: { keyType, isDown in
                systemEvents.append((keyType, isDown))
                return true
            },
            postText: { _ in true },
            accessibilityTrusted: { true },
            passwordProvider: { "not-a-real-secret" }
        )

        for action in KeysModeAction.allCases {
            if action == .pasteStoredPassword { continue }
            guard case .success = executor.perform(action) else {
                return XCTFail("\(action) should post")
            }
        }

        XCTAssertEqual(
            events.map(\.0),
            [126, 126, 125, 125, 123, 123, 124, 124, 49, 49, 51, 51]
        )
        XCTAssertEqual(
            events.map(\.1),
            [
                true, false,
                true, false,
                true, false,
                true, false,
                true, false,
                true, false,
            ]
        )
        XCTAssertEqual(modifiedEvents.map(\.0), [8, 8, 9, 9])
        XCTAssertEqual(
            modifiedEvents.map(\.1),
            [.maskCommand, .maskCommand, .maskCommand, .maskCommand]
        )
        XCTAssertEqual(modifiedEvents.map(\.2), [true, false, true, false])
        XCTAssertEqual(systemEvents.map(\.1), [true, false])
        XCTAssertEqual(Set(systemEvents.map(\.0)).count, 1)
    }

    func testPasswordUsesDirectTextWithoutPostingAKeyCode() {
        var postedText: [String] = []
        var postedKey = false
        let executor = KeysModeActionExecutor(
            postEvent: { _, _ in postedKey = true; return true },
            postText: { postedText.append($0); return true },
            accessibilityTrusted: { true },
            passwordProvider: { "not-a-real-secret" }
        )

        guard case .success = executor.perform(.pasteStoredPassword) else {
            return XCTFail("configured password should be typed")
        }
        XCTAssertEqual(postedText, ["not-a-real-secret"])
        XCTAssertFalse(postedKey)
    }

    func testMissingPasswordFailsWithoutPostingText() {
        var posted = false
        let executor = KeysModeActionExecutor(
            postText: { _ in posted = true; return true },
            accessibilityTrusted: { true },
            passwordProvider: { nil }
        )
        guard case .failure(.passwordNotConfigured) = executor.perform(.pasteStoredPassword) else {
            return XCTFail("missing password should fail closed")
        }
        XCTAssertFalse(posted)
    }

    func testLockedSessionFailsBeforeReadingPassword() {
        var readPassword = false
        let executor = KeysModeActionExecutor(
            accessibilityTrusted: { true },
            inputAllowed: { false },
            passwordProvider: { readPassword = true; return "not-a-real-secret" }
        )
        guard case .failure(.inputBlocked) = executor.perform(.pasteStoredPassword) else {
            return XCTFail("locked sessions should reject password entry")
        }
        XCTAssertFalse(readPassword)
    }

    func testKeyUpIsAttemptedEvenWhenKeyDownFails() {
        var phases: [Bool] = []
        let executor = KeysModeActionExecutor(
            postEvent: { _, isDown in
                phases.append(isDown)
                return !isDown
            },
            accessibilityTrusted: { true }
        )

        guard case .failure(.eventCreationFailed) = executor.perform(.arrowUp) else {
            return XCTFail("failed key-down must report failure")
        }
        XCTAssertEqual(phases, [true, false])
    }

    func testMissingAccessibilityFailsBeforePosting() {
        var posted = false
        let executor = KeysModeActionExecutor(
            postEvent: { _, _ in posted = true; return true },
            accessibilityTrusted: { false }
        )
        guard case .failure(.accessibilityPermissionMissing) = executor.perform(.arrowLeft) else {
            return XCTFail("missing Accessibility must fail closed")
        }
        XCTAssertFalse(posted)
    }
}
