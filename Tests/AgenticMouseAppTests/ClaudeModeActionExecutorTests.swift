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
            (.chooseEffort, .init(keyCode: 14, flags: [.maskCommand, .maskShift], character: "e")),
            (.toggleDictation, .init(keyCode: 2, flags: .maskCommand, character: "d")),
        ]

        for (action, shortcut) in expected {
            XCTAssertEqual(ClaudeModeActionExecutor.shortcut(for: action), shortcut)
        }
        XCTAssertEqual(ClaudeModeActionExecutor.togglePinShortcut,
                       .init(keyCode: 35, flags: [.maskCommand, .maskAlternate], character: "p"))
        XCTAssertEqual(ClaudeModeActionExecutor.tabShortcut(for: .up),
                       .init(keyCode: 30, flags: [.maskCommand, .maskShift]))
        XCTAssertEqual(ClaudeModeActionExecutor.tabShortcut(for: .down),
                       .init(keyCode: 33, flags: [.maskCommand, .maskShift]))
    }

    func testClaudeAccessibilityActionsStayExactAndSeparateFromKeyboardShortcuts() {
        let actions: [ClaudeModeAction] = [
            .openSideChat, .closePane,
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
        guard case .failure(let lockedError) = locked.perform(.openSideChat) else {
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
        guard case .failure(let permissionError) = untrusted.perform(.closePane) else {
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

        guard case .failure(let error) = executor.perform(.openSideChat) else {
            return XCTFail("a missing exact Claude control must fail")
        }
        XCTAssertEqual(
            error.description,
            "Claude does not currently expose the Open side chat control"
        )
    }

    func testCharacterShortcutsStayTargetedToClaude() {
        var posted: [ApplicationShortcutDispatcher.Shortcut] = []
        var inputAllowed = false
        let dispatcher = ApplicationShortcutDispatcher(
            targetProcessResolver: { bundle in
                XCTAssertEqual(bundle, ClaudeMode.bundleIdentifier)
                return 42
            },
            postEvent: { _, _, _, _ in
                XCTFail("Claude character shortcuts need a complete modifier and key sequence")
                return false
            },
            postCharacterShortcut: { pid, shortcut in
                XCTAssertEqual(pid, 42)
                posted.append(shortcut)
                return true
            },
            accessibilityTrusted: { true },
            inputAllowed: { inputAllowed }
        )
        let executor = ClaudeModeActionExecutor(shortcutDispatcher: dispatcher)
        guard case .failure = executor.performTogglePin() else {
            return XCTFail("Pin must not post while input is disabled")
        }
        XCTAssertTrue(posted.isEmpty)

        inputAllowed = true
        XCTAssertNoThrow(try executor.performTogglePin().get())
        XCTAssertNoThrow(try executor.perform(.chooseEffort).get())
        XCTAssertNoThrow(try executor.perform(.toggleDictation).get())
        XCTAssertEqual(posted.compactMap(\.character), ["p", "e", "d"])
        for shortcut in posted {
            let events = ApplicationShortcutDispatcher.hardwareSystemKeyboardEvents(for: shortcut) ?? []
            XCTAssertEqual(events.filter { $0.type != .flagsChanged }.map(\.character),
                           [shortcut.character, shortcut.character])
        }
    }
}
