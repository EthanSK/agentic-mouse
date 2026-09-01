import CoreGraphics
@testable import AgenticMouseApp
import ScimitarKit
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

    func testSystemShortcutUsesTheSupportedSystemEventsKeyboardBoundary() {
        XCTAssertEqual(
            ApplicationShortcutDispatcher.systemEventsAppleScript(
                for: .init(keyCode: 41, flags: [.maskCommand, .maskAlternate])
            ),
            "tell application \"System Events\" to key code 41 using {command down, option down}"
        )
        XCTAssertEqual(
            ApplicationShortcutDispatcher.systemEventsAppleScript(
                for: .init(keyCode: 47, flags: [.maskControl, .maskShift])
            ),
            "tell application \"System Events\" to key code 47 using {control down, shift down}"
        )
        XCTAssertNil(
            ApplicationShortcutDispatcher.systemEventsAppleScript(
                for: .init(keyCode: 123, flags: .maskSecondaryFn)
            )
        )
    }

    func testIPhoneMirroringNotificationsResolveSemanticNForTheActiveLayout() {
        var requestedCharacters: [Character] = []
        XCTAssertEqual(
            IPhoneMirroringModeShortcutResolver.shortcut(
                for: .notifications,
                keyCodeForSemanticCharacter: { character in
                    requestedCharacters.append(character)
                    return 37
                }
            ),
            .init(keyCode: 37, flags: .maskSecondaryFn)
        )
        XCTAssertEqual(requestedCharacters, ["n"])
    }

    func testSemanticKeyResolverDoesNotAssumeThePhysicalQwertyPosition() {
        let translatedCharacters: [CGKeyCode: String] = [
            37: "n", // DVORAK-QWERTYCMD physical L position
            45: "b", // physical QWERTY N position under Dvorak
        ]

        XCTAssertEqual(
            CurrentKeyboardLayoutKeyCodeResolver.keyCode(
                for: "n",
                translating: { translatedCharacters[$0] }
            ),
            37
        )
    }

    func testIPhoneMirroringNotificationsFailWhenSemanticNDoesNotResolve() {
        XCTAssertNil(
            IPhoneMirroringModeShortcutResolver.shortcut(
                for: .notifications,
                keyCodeForSemanticCharacter: { _ in nil }
            )
        )
    }

    func testForegroundHardwareShortcutRequiresActiveTargetAndPostsOnce() {
        var posted: [ApplicationShortcutDispatcher.Shortcut] = []
        let dispatcher = ApplicationShortcutDispatcher(
            targetProcessResolver: { bundleIdentifier in
                XCTAssertEqual(bundleIdentifier, "com.apple.ScreenContinuity")
                return 86
            },
            targetProcessIsActive: { $0 == 86 },
            postHardwareSystemShortcut: { posted.append($0); return true },
            accessibilityTrusted: { true },
            inputAllowed: { true }
        )
        let shortcut = IPhoneMirroringModeShortcutResolver.shortcut(
            for: .notifications,
            keyCodeForSemanticCharacter: { _ in 37 }
        )!

        guard case .success = dispatcher.performForegroundHardwareShortcut(
            shortcut,
            targetBundleIdentifier: "com.apple.ScreenContinuity",
            targetDisplayName: "iPhone Mirroring"
        ) else {
            return XCTFail("the frontmost iPhone Mirroring app should allow Fn-N")
        }
        XCTAssertEqual(posted, [shortcut])
    }

    func testFnSystemShortcutUsesACompleteHardwareLifecycle() {
        let events = ApplicationShortcutDispatcher.hardwareSystemKeyboardEvents(
            for: .init(keyCode: 37, flags: .maskSecondaryFn)
        )

        XCTAssertEqual(events?.map(\.type), [
            .flagsChanged, .keyDown, .keyUp, .flagsChanged,
        ])
        XCTAssertEqual(events?.map(\.keyCode), [63, 37, 37, 63])
        XCTAssertEqual(events?.map(\.flags), [
            .maskSecondaryFn, .maskSecondaryFn, .maskSecondaryFn, [],
        ])
        XCTAssertEqual(events?.count, 4)
        for (actual, expected) in zip(
            events?.map(\.timestampOffset) ?? [],
            [0, 0.006, 0.026, 0.032]
        ) {
            XCTAssertEqual(actual, expected, accuracy: 0.000_001)
        }
    }

    func testHardwareSystemShortcutSupportsComposedModifiersAndRejectsUnknownFlags() {
        let controlShift = ApplicationShortcutDispatcher.hardwareSystemKeyboardEvents(
            for: .init(keyCode: 9, flags: [.maskControl, .maskShift])
        )
        XCTAssertEqual(controlShift?.map(\.type), [
            .flagsChanged, .flagsChanged, .keyDown, .keyUp, .flagsChanged, .flagsChanged,
        ])
        XCTAssertEqual(controlShift?.map(\.keyCode), [59, 56, 9, 9, 56, 59])
        XCTAssertEqual(controlShift?.map(\.flags), [
            .maskControl,
            [.maskControl, .maskShift],
            [.maskControl, .maskShift],
            [.maskControl, .maskShift],
            .maskControl,
            [],
        ])
        XCTAssertNil(ApplicationShortcutDispatcher.hardwareSystemKeyboardEvents(
            for: .init(keyCode: 37, flags: [])
        ))
        XCTAssertNil(ApplicationShortcutDispatcher.hardwareSystemKeyboardEvents(
            for: .init(keyCode: 37, flags: .maskAlphaShift)
        ))
    }

    func testForegroundHardwareShortcutFailsClosedWhenTargetIsNotFrontmost() {
        var postCount = 0
        let dispatcher = ApplicationShortcutDispatcher(
            targetProcessResolver: { _ in 86 },
            targetProcessIsActive: { _ in false },
            postHardwareSystemShortcut: { _ in postCount += 1; return true },
            accessibilityTrusted: { true },
            inputAllowed: { true }
        )

        guard case .failure(let error) = dispatcher.performForegroundHardwareShortcut(
            IPhoneMirroringModeShortcutResolver.shortcut(
                for: .notifications,
                keyCodeForSemanticCharacter: { _ in 37 }
            )!,
            targetBundleIdentifier: "com.apple.ScreenContinuity",
            targetDisplayName: "iPhone Mirroring"
        ) else {
            return XCTFail("a global Fn-N must not fire when iPhone Mirroring is not frontmost")
        }
        XCTAssertEqual(error.description, "iPhone Mirroring must be frontmost for this shortcut")
        XCTAssertEqual(postCount, 0)
    }

    func testVSCodeTerminalHasNoFocusSensitiveKeyboardFallback() {
        XCTAssertNil(VSCodeModeShortcutResolver.shortcut(for: .toggleTerminal))
    }

    func testVSCodeCloseTabUsesCommandW() {
        XCTAssertEqual(
            VSCodeModeShortcutResolver.shortcut(for: .closeTab),
            .init(keyCode: 13, flags: .maskCommand)
        )
    }

    func testVSCodeGoToDefinitionUsesF12() {
        XCTAssertEqual(
            VSCodeModeShortcutResolver.shortcut(for: .goToDefinition),
            .init(keyCode: 111, flags: [])
        )
    }

    func testVSCodeCursorHistoryHasNoSyntheticKeyboardFallback() {
        var requestedCharacters: [Character] = []
        let resolver: TerminalModeShortcutResolver.SemanticKeyCodeResolver = { character in
            requestedCharacters.append(character)
            return nil
        }

        XCTAssertNil(
            VSCodeModeShortcutResolver.shortcut(
                for: .navigateBack,
                keyCodeForSemanticCharacter: resolver
            )
        )
        XCTAssertNil(
            VSCodeModeShortcutResolver.shortcut(
                for: .navigateForward,
                keyCodeForSemanticCharacter: resolver
            )
        )
        XCTAssertEqual(requestedCharacters, [])
    }

    func testTerminalInterruptResolvesSemanticCInsteadOfPhysicalQwertyC() {
        var requestedCharacters: [Character] = []
        let resolveDvorakC: TerminalModeShortcutResolver.SemanticKeyCodeResolver = {
            requestedCharacters.append($0)
            return $0 == "c" ? 34 : nil
        }

        let terminal = TerminalModeShortcutResolver.shortcut(
            for: .interruptTerminal,
            keyCodeForSemanticCharacter: resolveDvorakC
        )
        let vsCode = VSCodeModeShortcutResolver.shortcut(
            for: .interruptTerminal,
            keyCodeForSemanticCharacter: resolveDvorakC
        )

        XCTAssertEqual(requestedCharacters, ["c", "c"])
        XCTAssertEqual(terminal, .init(keyCode: 34, flags: .maskControl))
        XCTAssertEqual(vsCode, terminal)
        XCTAssertNotEqual(terminal, .init(keyCode: 8, flags: .maskControl))
    }

    func testTerminalInterruptFailsClosedWhenSemanticCCannotResolve() {
        XCTAssertNil(TerminalModeShortcutResolver.shortcut(
            for: .interruptTerminal,
            keyCodeForSemanticCharacter: { _ in nil }
        ))
        XCTAssertNil(VSCodeModeShortcutResolver.shortcut(
            for: .interruptTerminal,
            keyCodeForSemanticCharacter: { _ in nil }
        ))
    }

    func testChromeOnePressActionsUseNativeBrowserShortcuts() {
        XCTAssertEqual(
            ChromeModeShortcutResolver.shortcut(for: .closeCurrentTab),
            .init(keyCode: 13, flags: .maskCommand)
        )
        XCTAssertEqual(
            ChromeModeShortcutResolver.shortcut(for: .reloadCurrentTab),
            .init(keyCode: 15, flags: .maskCommand)
        )
        XCTAssertEqual(
            ChromeModeShortcutResolver.shortcut(for: .newTab),
            .init(keyCode: 17, flags: .maskCommand)
        )
        XCTAssertNil(ChromeModeShortcutResolver.shortcut(for: .holdYouTubeDoubleSpeed))
        XCTAssertNil(ChromeModeShortcutResolver.shortcut(for: .cycleTabsWithWheel))
    }

    func testStandardAppShortcutResolverPreservesEveryModifier() {
        let action = StandardAppModeAction(
            cell: PhysicalCell(rawValue: 1)!,
            title: "Test",
            keyCode: 33,
            modifiers: [.command, .shift, .option, .control]
        )

        XCTAssertEqual(
            StandardAppModeShortcutResolver.shortcut(for: action),
            .init(
                keyCode: 33,
                flags: [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            )
        )
    }

    func testSpotifyAndNotionShortcutsMatchTheirCanonicalActions() {
        let spotifySearch = StandardAppMode.action(
            for: .spotify,
            cell: PhysicalCell(rawValue: 1)!
        )!
        XCTAssertEqual(
            StandardAppModeShortcutResolver.shortcut(for: spotifySearch),
            .init(keyCode: 40, flags: .maskCommand)
        )

        let spotifyNext = StandardAppMode.action(
            for: .spotify,
            cell: PhysicalCell(rawValue: 4)!
        )!
        XCTAssertEqual(
            StandardAppModeShortcutResolver.shortcut(for: spotifyNext),
            .init(keyCode: 124, flags: .maskCommand)
        )

        XCTAssertEqual(
            StandardAppModeShortcutResolver.shortcut(
                for: StandardAppMode.spotifyVolumeAction(for: .up)
            ),
            .init(keyCode: 126, flags: .maskCommand)
        )
        XCTAssertEqual(
            StandardAppModeShortcutResolver.shortcut(
                for: StandardAppMode.spotifyVolumeAction(for: .down)
            ),
            .init(keyCode: 125, flags: .maskCommand)
        )

        let notionNewTab = StandardAppMode.action(
            for: .notion,
            cell: PhysicalCell(rawValue: 3)!
        )!
        XCTAssertEqual(
            StandardAppModeShortcutResolver.shortcut(for: notionNewTab),
            .init(keyCode: 17, flags: .maskCommand)
        )
    }

    func testSafariOpenDevToolsUsesNativeWebInspectorShortcut() {
        let action = StandardAppMode.action(
            for: .safari,
            cell: PhysicalCell(rawValue: 6)!
        )!

        XCTAssertEqual(action.title, "Open DevTools")
        XCTAssertEqual(
            StandardAppModeShortcutResolver.shortcut(for: action),
            .init(keyCode: 34, flags: [.maskCommand, .maskAlternate])
        )
    }

    func testExpandedSpecializedPagesUseNativeShortcuts() {
        XCTAssertEqual(
            ChromeModeShortcutResolver.shortcut(for: .reopenClosedTab),
            .init(keyCode: 17, flags: [.maskCommand, .maskShift])
        )
        XCTAssertEqual(
            VSCodeModeShortcutResolver.shortcut(for: .commandPalette),
            .init(keyCode: 35, flags: [.maskCommand, .maskShift])
        )
        XCTAssertEqual(
            TerminalModeShortcutResolver.shortcut(for: .newTab),
            .init(keyCode: 17, flags: .maskCommand)
        )
    }
}
