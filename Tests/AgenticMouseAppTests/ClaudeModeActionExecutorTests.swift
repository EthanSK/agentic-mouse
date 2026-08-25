import CoreGraphics
@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class ClaudeModeActionExecutorTests: XCTestCase {
    func testVerifiedClaudeMenuActionsUseTheirNativeShortcuts() {
        let expected: [(ClaudeModeAction, ApplicationShortcutDispatcher.Shortcut)] = [
            (.settings, .init(keyCode: 43, flags: .maskCommand)),
            (.newChat, .init(keyCode: 45, flags: .maskCommand)),
            (.pressEnter, .init(keyCode: 36, flags: [])),
            (.reload, .init(keyCode: 15, flags: .maskCommand)),
            (.previousTab, .init(keyCode: 123, flags: [.maskCommand, .maskAlternate])),
            (.nextTab, .init(keyCode: 124, flags: [.maskCommand, .maskAlternate])),
        ]

        for (action, shortcut) in expected {
            XCTAssertEqual(ClaudeModeActionExecutor.shortcut(for: action), shortcut)
        }
    }

    func testClaudeAccessibilityActionsStayExactAndSeparateFromKeyboardShortcuts() {
        let actions: [ClaudeModeAction] = [
            .search, .toggleVoiceMode, .toggleMicrophoneMute, .toggleSidebar,
        ]
        var performed: [ClaudeModeAction] = []
        let executor = ClaudeModeActionExecutor(
            accessibilityTrusted: { true },
            inputAllowed: { true },
            performAccessibilityAction: { action in performed.append(action); return true }
        )

        for action in actions {
            XCTAssertNil(ClaudeModeActionExecutor.shortcut(for: action))
            guard case .success = executor.perform(action) else {
                return XCTFail("\(action) should use Claude's exact AX control")
            }
        }
        XCTAssertEqual(performed, actions)
    }

    func testClaudeAccessibilityActionsFailClosedWhileLockedOrUntrusted() {
        var actionCount = 0
        let locked = ClaudeModeActionExecutor(
            accessibilityTrusted: { true },
            inputAllowed: { false },
            performAccessibilityAction: { _ in actionCount += 1; return true }
        )
        guard case .failure(let lockedError) = locked.perform(.search) else {
            return XCTFail("locked Claude control must fail")
        }
        XCTAssertEqual(
            lockedError.description,
            "Mouse commands are disabled while macOS is locked"
        )

        let untrusted = ClaudeModeActionExecutor(
            accessibilityTrusted: { false },
            inputAllowed: { true },
            performAccessibilityAction: { _ in actionCount += 1; return true }
        )
        guard case .failure(let permissionError) = untrusted.perform(.toggleSidebar) else {
            return XCTFail("untrusted Claude control must fail")
        }
        XCTAssertEqual(
            permissionError.description,
            "Accessibility permission is required for Claude shortcuts"
        )
        XCTAssertEqual(actionCount, 0)
    }

    func testMissingClaudeAccessibilityControlNamesTheRequestedAction() {
        let executor = ClaudeModeActionExecutor(
            accessibilityTrusted: { true },
            inputAllowed: { true },
            performAccessibilityAction: { _ in false }
        )

        guard case .failure(let error) = executor.perform(.toggleVoiceMode) else {
            return XCTFail("a missing exact Claude control must fail")
        }
        XCTAssertEqual(
            error.description,
            "Claude does not currently expose the Voice mode control"
        )
    }

    func testClaudeMatcherAcceptsOnlyExactEnabledPressableButtons() {
        XCTAssertTrue(ClaudeModeActionExecutor.isExactPressableControl(
            .toggleVoiceMode,
            role: kAXButtonRole as String,
            labels: ["start voice mode"],
            isEnabled: true,
            supportsPress: true
        ))
        XCTAssertFalse(ClaudeModeActionExecutor.isExactPressableControl(
            .toggleVoiceMode,
            role: kAXButtonRole as String,
            labels: ["start voice mode later"],
            isEnabled: true,
            supportsPress: true
        ))
        XCTAssertFalse(ClaudeModeActionExecutor.isExactPressableControl(
            .search,
            role: kAXStaticTextRole as String,
            labels: ["search"],
            isEnabled: true,
            supportsPress: true
        ))
        XCTAssertFalse(ClaudeModeActionExecutor.isExactPressableControl(
            .toggleMicrophoneMute,
            role: kAXButtonRole as String,
            labels: ["mute microphone"],
            isEnabled: false,
            supportsPress: true
        ))
    }
}
