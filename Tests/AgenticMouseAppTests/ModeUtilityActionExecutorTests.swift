@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class ModeUtilityActionExecutorTests: XCTestCase {
    func testDispatcherWiresEveryNativeUtilityToItsRealExecutor() {
        var brightnessEvents: [(Int32, Bool)] = []
        var zoomEvents: [(CGKeyCode, CGEventFlags, Bool)] = []
        var spaceEvents: [DesktopSpaceActionExecutor.KeyEvent] = []
        var overviewEvents: [SystemOverviewActionExecutor.KeyEvent] = []
        let executor = ModeUtilityActionExecutor(
            brightness: DisplayBrightnessActionExecutor {
                brightnessEvents.append(($0, $1)); return true
            },
            zoom: ApplicationZoomActionExecutor {
                zoomEvents.append(($0, $1, $2)); return true
            },
            spaces: DesktopSpaceActionExecutor {
                spaceEvents.append(contentsOf: $0); return true
            },
            systemOverview: SystemOverviewActionExecutor {
                overviewEvents.append(contentsOf: $0); return true
            }
        )

        for action in [
            ModeUtilityAction.increaseDisplayBrightness,
            .decreaseDisplayBrightness,
            .zoomIn,
            .zoomOut,
            .moveToSpaceLeft,
            .moveToSpaceRight,
            .showDesktop,
            .missionControl,
            .showApplicationWindows,
        ] {
            guard case .success = executor.perform(action) else {
                return XCTFail("\(action) should reach its native executor")
            }
        }

        XCTAssertEqual(brightnessEvents.count, 4)
        XCTAssertEqual(zoomEvents.count, 4)
        XCTAssertEqual(spaceEvents.count, 8)
        XCTAssertEqual(overviewEvents.count, 10)
    }

    func testYouTubeRewindPostsOnlyTheBridgeNotificationPath() {
        var notifications: [YouTubeSeekAction] = []
        let executor = ModeUtilityActionExecutor(
            notifyYouTube: { action in
                notifications.append(action)
                return true
            }
        )

        guard case .success = executor.perform(.rewindYouTubeFiveSeconds) else {
            return XCTFail("YouTube bridge notification should succeed")
        }
        guard case .success = executor.performYouTubeSeek(.forwardFiveSeconds) else {
            return XCTFail("YouTube bridge forward notification should succeed")
        }
        XCTAssertEqual(notifications, [.backwardFiveSeconds, .forwardFiveSeconds])
        XCTAssertEqual(
            ModeUtilityActionExecutor.youtubeSeekBackwardFiveSecondsNotification.rawValue,
            "com.ethansk.agenticmouse.youtube.seekBackwardFiveSeconds"
        )
        XCTAssertEqual(
            ModeUtilityActionExecutor.youtubeSeekForwardFiveSecondsNotification.rawValue,
            "com.ethansk.agenticmouse.youtube.seekForwardFiveSeconds"
        )
    }

    func testYouTubeVolumePostsOnlyTheFixedFivePercentBridgeNotificationPath() {
        var notifications: [YouTubeVolumeAction] = []
        let executor = ModeUtilityActionExecutor(
            notifyYouTubeVolume: { action in
                notifications.append(action)
                return true
            }
        )

        guard case .success = executor.performYouTubeVolume(.increaseFivePercent),
              case .success = executor.performYouTubeVolume(.decreaseFivePercent)
        else { return XCTFail("both YouTube volume directions should reach the bridge") }
        XCTAssertEqual(notifications, [.increaseFivePercent, .decreaseFivePercent])
        XCTAssertEqual(
            ModeUtilityActionExecutor.youtubeVolumeIncreaseFivePercentNotification.rawValue,
            "com.ethansk.agenticmouse.youtube.volumeIncreaseFivePercent"
        )
        XCTAssertEqual(
            ModeUtilityActionExecutor.youtubeVolumeDecreaseFivePercentNotification.rawValue,
            "com.ethansk.agenticmouse.youtube.volumeDecreaseFivePercent"
        )

        let failed = ModeUtilityActionExecutor(notifyYouTubeVolume: { _ in false })
        guard case .failure(.youtubeBridgeNotificationFailed) =
            failed.performYouTubeVolume(.increaseFivePercent)
        else { return XCTFail("a failed YouTube volume notification should be surfaced") }
    }

    func testChromeTabHistoryPostsOnlyTheStrictBackForwardBridgeNotifications() {
        var notifications: [ChromeTabHistoryAction] = []
        let executor = ModeUtilityActionExecutor(
            notifyChromeTabHistory: { action in
                notifications.append(action)
                return true
            }
        )

        guard case .success = executor.performChromeTabHistory(.back),
              case .success = executor.performChromeTabHistory(.forward)
        else { return XCTFail("both Chrome tab-history directions should reach the bridge") }
        XCTAssertEqual(notifications, [.back, .forward])
        XCTAssertEqual(
            ModeUtilityActionExecutor.chromeTabHistoryBackNotification.rawValue,
            "com.ethansk.agenticmouse.chrome.tabHistoryBack"
        )
        XCTAssertEqual(
            ModeUtilityActionExecutor.chromeTabHistoryForwardNotification.rawValue,
            "com.ethansk.agenticmouse.chrome.tabHistoryForward"
        )

        let failed = ModeUtilityActionExecutor(notifyChromeTabHistory: { _ in false })
        guard case .failure(.chromeTabHistoryBridgeNotificationFailed) =
            failed.performChromeTabHistory(.back)
        else { return XCTFail("a failed Chrome tab-history notification should be surfaced") }
    }

    func testChromeWebsitePostsOnlyTheAllowListedWebsiteIdentifier() {
        var notifications: [ChromeWebsiteAction] = []
        let executor = ModeUtilityActionExecutor(
            notifyChromeWebsite: { action in
                notifications.append(action)
                return true
            }
        )

        for action in ChromeWebsiteAction.allCases {
            guard case .success = executor.performChromeWebsite(action) else {
                return XCTFail("\(action) should reach the Chrome website bridge")
            }
        }

        XCTAssertEqual(notifications, ChromeWebsiteAction.allCases)
        XCTAssertEqual(
            ModeUtilityActionExecutor.chromeWebsiteOpenNotification.rawValue,
            "com.ethansk.agenticmouse.chrome.openWebsite"
        )
        XCTAssertEqual(ModeUtilityActionExecutor.chromeWebsiteKey, "website")

        let failed = ModeUtilityActionExecutor(notifyChromeWebsite: { _ in false })
        guard case .failure(.chromeWebsiteBridgeNotificationFailed) =
            failed.performChromeWebsite(.youtube)
        else { return XCTFail("a failed Chrome website notification should be surfaced") }
    }

    func testYouTubeBridgeFailureIsReported() {
        let executor = ModeUtilityActionExecutor(notifyYouTube: { _ in false })

        guard case .failure(.youtubeBridgeNotificationFailed) =
            executor.perform(.rewindYouTubeFiveSeconds)
        else {
            return XCTFail("bridge notification failure should be surfaced")
        }
    }

    func testIntelligenceOnDemandPostsOneHardwareShapedOptionSpaceCycle() {
        var submitted: [[SyntheticKeyboardChordPoster.Event]] = []
        let executor = ModeUtilityActionExecutor(
            postKeyboardChord: { events in
                submitted.append(events)
                return true
            },
            accessibilityTrusted: { true }
        )

        guard case .success = executor.perform(.openIntelligenceOnDemand) else {
            return XCTFail("Intelligence on demand should post Option-Space")
        }
        XCTAssertEqual(submitted, [ModeUtilityActionExecutor.intelligenceOnDemandChord()])
        XCTAssertEqual(submitted[0].map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        XCTAssertEqual(submitted[0].map(\.keyCode), [58, 49, 49, 58])
        XCTAssertEqual(submitted[0].map(\.flags), [
            [.maskAlternate], [.maskAlternate], [.maskAlternate], [],
        ])
    }

    func testIntelligenceOnDemandFailsClosedWhenLockedUntrustedOrPostingFails() {
        let blocked = ModeUtilityActionExecutor(
            postKeyboardChord: { _ in XCTFail("locked input must not post"); return true },
            accessibilityTrusted: { true },
            inputAllowed: { false }
        )
        guard case .failure(.intelligenceOnDemandInputBlocked) =
            blocked.perform(.openIntelligenceOnDemand)
        else { return XCTFail("locked input should reject Intelligence on demand") }

        let untrusted = ModeUtilityActionExecutor(
            postKeyboardChord: { _ in XCTFail("untrusted input must not post"); return true },
            accessibilityTrusted: { false }
        )
        guard case .failure(.intelligenceOnDemandAccessibilityPermissionMissing) =
            untrusted.perform(.openIntelligenceOnDemand)
        else { return XCTFail("untrusted input should reject Intelligence on demand") }

        let failed = ModeUtilityActionExecutor(
            postKeyboardChord: { _ in false },
            accessibilityTrusted: { true }
        )
        guard case .failure(.intelligenceOnDemandEventCreationFailed) =
            failed.perform(.openIntelligenceOnDemand)
        else { return XCTFail("failed Option-Space lifecycle should be surfaced") }
    }

    func testOrganizeWindowsPostsExactlyOneReservedStayShortcutCycle() {
        var submitted: [[SyntheticKeyboardChordPoster.Event]] = []
        let executor = ModeUtilityActionExecutor(
            postKeyboardChord: { events in
                submitted.append(events)
                return true
            },
            accessibilityTrusted: { true }
        )

        guard case .success = executor.perform(.organizeWindows) else {
            return XCTFail("Stay restore hotkey should be posted")
        }

        XCTAssertEqual(submitted.count, 1)
        XCTAssertEqual(submitted[0].map(\.keyCode), [59, 58, 56, 55, 0, 0, 55, 56, 58, 59])
        XCTAssertEqual(
            submitted[0].map(\.type),
            [
                .flagsChanged, .flagsChanged, .flagsChanged, .flagsChanged,
                .keyDown, .keyUp,
                .flagsChanged, .flagsChanged, .flagsChanged, .flagsChanged,
            ]
        )
        XCTAssertEqual(
            submitted[0].map(\.flags),
            [
                [.maskControl],
                [.maskControl, .maskAlternate],
                [.maskControl, .maskAlternate, .maskShift],
                [.maskControl, .maskAlternate, .maskShift, .maskCommand],
                [.maskControl, .maskAlternate, .maskShift, .maskCommand],
                [.maskControl, .maskAlternate, .maskShift, .maskCommand],
                [.maskControl, .maskAlternate, .maskShift],
                [.maskControl, .maskAlternate],
                [.maskControl],
                [],
            ]
        )
        XCTAssertEqual(
            submitted[0].map(\.timestampOffset),
            [0, 0.006, 0.012, 0.018, 0.024, 0.050, 0.056, 0.062, 0.068, 0.074]
        )
        XCTAssertEqual(ModeUtilityActionExecutor.stayRestoreKeyCode, 0)
        XCTAssertEqual(
            ModeUtilityActionExecutor.stayRestoreModifierFlags,
            [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        )
    }

    func testOrganizeWindowsFailsClosedWhenLockedUntrustedOrPostingFails() {
        let blocked = ModeUtilityActionExecutor(
            postKeyboardChord: { _ in XCTFail("locked input must not post Stay shortcut"); return true },
            accessibilityTrusted: { true },
            inputAllowed: { false }
        )
        guard case .failure(.organizeWindowsInputBlocked) =
            blocked.perform(.organizeWindows)
        else { return XCTFail("locked input should reject Stay restore") }

        let untrusted = ModeUtilityActionExecutor(
            postKeyboardChord: { _ in XCTFail("untrusted input must not post Stay shortcut"); return true },
            accessibilityTrusted: { false }
        )
        guard case .failure(.organizeWindowsAccessibilityPermissionMissing) =
            untrusted.perform(.organizeWindows)
        else { return XCTFail("untrusted input should reject Stay restore") }

        let failed = ModeUtilityActionExecutor(
            postKeyboardChord: { _ in false },
            accessibilityTrusted: { true }
        )
        guard case .failure(.organizeWindowsEventCreationFailed) =
            failed.perform(.organizeWindows)
        else { return XCTFail("failed Stay shortcut lifecycle should be surfaced") }
    }

    func testQuitAppPostsCommandQOnlyToTheResolvedFrontmostProcess() {
        var postedPIDs: [pid_t] = []
        var postedEvents: [SyntheticKeyboardChordPoster.Event] = []
        let executor = ModeUtilityActionExecutor(
            accessibilityTrusted: { true },
            quitApplicationTarget: {
                .init(processIdentifier: 4242, displayName: "Preview")
            },
            postQuitApplication: { pid, events in
                postedPIDs.append(pid)
                postedEvents = events
                return true
            }
        )

        guard case .success = executor.perform(.quitApp) else {
            return XCTFail("Quit App should target the resolved frontmost process")
        }
        XCTAssertEqual(postedPIDs, [4242])
        XCTAssertEqual(postedEvents, ModeUtilityActionExecutor.quitApplicationChord())
        XCTAssertEqual(postedEvents.map(\.type), [
            .flagsChanged, .keyDown, .keyUp, .flagsChanged,
        ])
        XCTAssertEqual(postedEvents.map(\.keyCode), [55, 12, 12, 55])
        XCTAssertEqual(postedEvents.map(\.flags), [
            [.maskCommand], [.maskCommand], [.maskCommand], [],
        ])
    }

    func testQuitAppFailsClosedWhenLockedUntrustedTargetlessOrPostingFails() {
        let blocked = ModeUtilityActionExecutor(
            accessibilityTrusted: { true },
            inputAllowed: { false },
            quitApplicationTarget: { XCTFail("locked input must not resolve a target"); return nil },
            postQuitApplication: { _, _ in XCTFail("locked input must not post"); return true }
        )
        guard case .failure(.quitAppInputBlocked) = blocked.perform(.quitApp) else {
            return XCTFail("locked input should reject Quit App")
        }

        let untrusted = ModeUtilityActionExecutor(
            accessibilityTrusted: { false },
            quitApplicationTarget: { XCTFail("untrusted input must not resolve a target"); return nil },
            postQuitApplication: { _, _ in XCTFail("untrusted input must not post"); return true }
        )
        guard case .failure(.quitAppAccessibilityPermissionMissing) =
            untrusted.perform(.quitApp)
        else { return XCTFail("untrusted input should reject Quit App") }

        let targetless = ModeUtilityActionExecutor(
            accessibilityTrusted: { true },
            quitApplicationTarget: { nil },
            postQuitApplication: { _, _ in XCTFail("missing target must not post"); return true }
        )
        guard case .failure(.quitAppTargetUnavailable) = targetless.perform(.quitApp) else {
            return XCTFail("Quit App should fail closed without a frontmost target")
        }

        let failed = ModeUtilityActionExecutor(
            accessibilityTrusted: { true },
            quitApplicationTarget: {
                .init(processIdentifier: 4242, displayName: "Preview")
            },
            postQuitApplication: { _, _ in false }
        )
        guard case .failure(.quitAppEventCreationFailed) = failed.perform(.quitApp) else {
            return XCTFail("failed Quit App delivery should be surfaced")
        }
    }

    func testQuitAppExcludesBothAgenticMouseProcesses() {
        XCTAssertTrue(ModeUtilityActionExecutor.isExcludedQuitTarget(
            bundleIdentifier: "com.ethan.agentic-mouse",
            processIdentifier: 42,
            currentProcessIdentifier: 42,
            mainBundleIdentifier: "com.ethan.agentic-mouse"
        ))
        XCTAssertTrue(ModeUtilityActionExecutor.isExcludedQuitTarget(
            bundleIdentifier: LaunchAtLoginController.supervisorBundleIdentifier,
            processIdentifier: 43,
            currentProcessIdentifier: 42,
            mainBundleIdentifier: "com.ethan.agentic-mouse"
        ))
        XCTAssertFalse(ModeUtilityActionExecutor.isExcludedQuitTarget(
            bundleIdentifier: "com.apple.Preview",
            processIdentifier: 44,
            currentProcessIdentifier: 42,
            mainBundleIdentifier: "com.ethan.agentic-mouse"
        ))
    }

    func testClipboardActionsPostExactlyOneCommandKeyCycle() {
        var events: [SyntheticKeyboardChordPoster.Event] = []
        let executor = ModeUtilityActionExecutor(
            postKeyboardChord: { chord in
                events.append(contentsOf: chord)
                return true
            },
            accessibilityTrusted: { true }
        )

        for action in [ModeUtilityAction.copy, .paste] {
            guard case .success = executor.perform(action) else {
                return XCTFail("\(action) should post one Command key cycle")
            }
        }

        XCTAssertEqual(events.map(\.keyCode), [55, 8, 8, 55, 55, 9, 9, 55])
        XCTAssertEqual(
            events.map(\.type),
            [
                .flagsChanged, .keyDown, .keyUp, .flagsChanged,
                .flagsChanged, .keyDown, .keyUp, .flagsChanged,
            ]
        )
        XCTAssertEqual(
            events.map(\.flags),
            [
                [.maskCommand], [.maskCommand], [.maskCommand], [],
                [.maskCommand], [.maskCommand], [.maskCommand], [],
            ]
        )
    }

    func testClipboardActionsFailClosedWithSpecificErrors() {
        let blocked = ModeUtilityActionExecutor(
            postKeyboardChord: { _ in XCTFail("blocked input must not post"); return true },
            accessibilityTrusted: { true },
            inputAllowed: { false }
        )
        guard case .failure(.clipboardInputBlocked) = blocked.perform(.copy) else {
            return XCTFail("locked input should reject Copy")
        }

        let untrusted = ModeUtilityActionExecutor(
            postKeyboardChord: { _ in XCTFail("untrusted input must not post"); return true },
            accessibilityTrusted: { false }
        )
        guard case .failure(.clipboardAccessibilityPermissionMissing) =
            untrusted.perform(.paste)
        else { return XCTFail("untrusted input should reject Paste") }

        let failed = ModeUtilityActionExecutor(
            postKeyboardChord: { _ in false },
            accessibilityTrusted: { true }
        )
        guard case .failure(.clipboardEventCreationFailed) = failed.perform(.copy) else {
            return XCTFail("failed clipboard events should be surfaced")
        }
    }

    func testClipboardChordIsSubmittedAsOneAllOrNothingLifecycle() {
        var submitted: [[SyntheticKeyboardChordPoster.Event]] = []
        let executor = ModeUtilityActionExecutor(
            postKeyboardChord: { events in
                submitted.append(events)
                return false
            },
            accessibilityTrusted: { true }
        )

        guard case .failure(.clipboardEventCreationFailed) = executor.perform(.copy) else {
            return XCTFail("clipboard chord failure should be surfaced")
        }
        XCTAssertEqual(submitted.count, 1)
        XCTAssertEqual(submitted[0].map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
    }

    func testMagnetWheelActionsSendTheConfiguredGlobalKeyboardShortcuts() {
        var chords: [[MagnetWindowActionExecutor.KeyEvent]] = []
        let executor = ModeUtilityActionExecutor(
            magnet: MagnetWindowActionExecutor {
                chords.append($0)
                return true
            },
            accessibilityTrusted: { true }
        )

        guard case .success = executor.perform(.moveWindowRightWithMagnet),
              case .success = executor.perform(.moveWindowLeftWithMagnet)
        else { return XCTFail("both configured Magnet commands should run") }

        XCTAssertEqual(chords.count, 2)
        XCTAssertEqual(
            chords[0],
            MagnetWindowActionExecutor.keyEvents(for: .moveWindowRightWithMagnet)
        )
        XCTAssertEqual(
            chords[1],
            MagnetWindowActionExecutor.keyEvents(for: .moveWindowLeftWithMagnet)
        )
    }

    func testMagnetShortcutIsACompletePhysicalControlOptionArrowLifecycle() {
        guard let events = MagnetWindowActionExecutor.keyEvents(
            for: .moveWindowRightWithMagnet
        ) else { return XCTFail("right shortcut should exist") }

        XCTAssertEqual(events.map(\.keyCode), [59, 58, 124, 124, 58, 59])
        XCTAssertEqual(
            events.map(\.type),
            [.flagsChanged, .flagsChanged, .keyDown, .keyUp, .flagsChanged, .flagsChanged]
        )
        XCTAssertEqual(events.map(\.timestampOffset), [0, 0.006, 0.012, 0.032, 0.038, 0.044])
        XCTAssertEqual(
            events.map(\.flags),
            [
                .maskControl,
                [.maskControl, .maskAlternate],
                [.maskControl, .maskAlternate, .maskSecondaryFn, .maskNumericPad],
                [.maskControl, .maskAlternate, .maskSecondaryFn, .maskNumericPad],
                .maskControl,
                [],
            ]
        )
    }

    func testMagnetWheelActionsFailClosedWithSpecificErrors() {
        let blocked = ModeUtilityActionExecutor(
            magnet: MagnetWindowActionExecutor(
                postChord: { _ in XCTFail("blocked input must not invoke Magnet"); return true },
                accessibilityTrusted: { true },
                inputAllowed: { false }
            ),
            accessibilityTrusted: { true },
            inputAllowed: { true }
        )
        guard case .failure(.magnetInputBlocked) =
            blocked.perform(.moveWindowRightWithMagnet)
        else { return XCTFail("locked input should reject Magnet") }

        let untrusted = ModeUtilityActionExecutor(
            magnet: MagnetWindowActionExecutor(
                postChord: { _ in XCTFail("untrusted input must not invoke Magnet"); return true },
                accessibilityTrusted: { false },
                inputAllowed: { true }
            ),
            accessibilityTrusted: { false }
        )
        guard case .failure(.magnetAccessibilityPermissionMissing) =
            untrusted.perform(.moveWindowLeftWithMagnet)
        else { return XCTFail("untrusted input should reject Magnet") }

        let failed = ModeUtilityActionExecutor(
            magnet: MagnetWindowActionExecutor { _ in false },
            accessibilityTrusted: { true }
        )
        guard case .failure(.magnetEventCreationFailed) =
            failed.perform(.moveWindowRightWithMagnet)
        else { return XCTFail("failed Magnet events should be surfaced") }
    }

    func testStoredPasswordUsesTheSecurityCheckedTextPath() {
        var invocationCount = 0
        let executor = ModeUtilityActionExecutor(
            typeStoredPassword: {
                invocationCount += 1
                return .success(())
            }
        )

        guard case .success = executor.perform(.pasteStoredPassword) else {
            return XCTFail("configured password should reach the secure text path")
        }
        XCTAssertEqual(invocationCount, 1)
    }

    func testStoredPasswordErrorsRemainSpecific() {
        let expected: [(KeysModeActionError, ModeUtilityActionError)] = [
            (.inputBlocked, .storedPasswordInputBlocked),
            (.accessibilityPermissionMissing, .storedPasswordAccessibilityPermissionMissing),
            (.passwordNotConfigured, .storedPasswordNotConfigured),
            (.eventCreationFailed, .storedPasswordEventCreationFailed),
        ]

        for (sourceError, expectedError) in expected {
            let executor = ModeUtilityActionExecutor(
                typeStoredPassword: { .failure(sourceError) }
            )
            guard case .failure(let actualError) = executor.perform(.pasteStoredPassword) else {
                return XCTFail("stored password failure should be preserved")
            }
            XCTAssertEqual(actualError, expectedError)
        }
    }
}
