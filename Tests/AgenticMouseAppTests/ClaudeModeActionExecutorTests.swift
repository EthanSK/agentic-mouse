import CoreGraphics
@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class ClaudeModeActionExecutorTests: XCTestCase {
    func testVerifiedClaudeMenuActionsUseTheirNativeShortcuts() {
        let expected: [(ClaudeModeAction, ApplicationShortcutDispatcher.Shortcut)] = [
            (.newChat, .init(keyCode: 45, flags: .maskCommand)),
            (.pressEnter, .init(keyCode: 36, flags: [])),
            (.toggleFastMode, .init(keyCode: 3, flags: [.maskCommand, .maskAlternate])),
            (.chooseEffort, .init(keyCode: 14, flags: [.maskCommand, .maskShift])),
        ]

        for (action, shortcut) in expected {
            XCTAssertEqual(ClaudeModeActionExecutor.shortcut(for: action), shortcut)
        }
        XCTAssertEqual(ClaudeModeActionExecutor.togglePinShortcut,
                       .init(keyCode: 35, flags: [.maskCommand, .maskAlternate]))
        XCTAssertEqual(ClaudeModeActionExecutor.tabShortcut(for: .up),
                       .init(keyCode: 30, flags: [.maskCommand, .maskShift]))
        XCTAssertEqual(ClaudeModeActionExecutor.tabShortcut(for: .down),
                       .init(keyCode: 33, flags: [.maskCommand, .maskShift]))
    }

    func testClaudeAccessibilityActionsStayExactAndSeparateFromKeyboardShortcuts() {
        let actions: [ClaudeModeAction] = [
            .toggleVoiceMode, .toggleMicrophoneMute, .openSideChat, .closePane,
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
        guard case .failure(let lockedError) = locked.perform(.toggleVoiceMode) else {
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
        guard case .failure(let permissionError) = untrusted.perform(.toggleMicrophoneMute) else {
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
        XCTAssertTrue(ClaudeModeActionExecutor.isExactPressableControl(
            .toggleVoiceMode,
            role: kAXButtonRole as String,
            labels: ["use voice mode"],
            isEnabled: true,
            supportsPress: true
        ))
        XCTAssertTrue(ClaudeModeActionExecutor.isExactPressableControl(
            .toggleMicrophoneMute,
            role: kAXButtonRole as String,
            labels: ["turn off microphone"],
            isEnabled: true,
            supportsPress: true
        ))
        XCTAssertTrue(ClaudeModeActionExecutor.isExactPressableControl(
            .toggleMicrophoneMute,
            role: kAXButtonRole as String,
            labels: ["turn on microphone"],
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
            .toggleVoiceMode,
            role: kAXStaticTextRole as String,
            labels: ["start voice mode"],
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
