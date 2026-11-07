import AppKit
import ScimitarKit
@testable import ScimitarUI
import XCTest

@MainActor
final class HUDSpaceLifecycleTests: VisibleHUDTestCase {
    func testMouseHUDsTouchTheirHandedBottomCornersOnEveryDisplay() async {
        let baselinePanels = visibleHUDPanels()
        let corsairPresenter = AppKitModeHUDPresenter(source: .corsair)
        let razerPresenter = AppKitModeHUDPresenter(source: .razer)
        corsairPresenter.show(DefaultMapLegend.snapshot(source: .corsair))
        razerPresenter.show(DefaultMapLegend.snapshot(source: .razer))
        await waitForMainQueueTurns()

        let panels = NSApplication.shared.windows.compactMap { window -> HUDPanel? in
            guard let panel = window as? HUDPanel,
                  panel.isVisible,
                  !baselinePanels.contains(ObjectIdentifier(panel)) else { return nil }
            return panel
        }
        XCTAssertEqual(panels.count, NSScreen.screens.count * 2)
        for screen in NSScreen.screens {
            let screenPanels = panels.filter { screen.frame.contains(NSPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            XCTAssertEqual(screenPanels.count, 2)
            XCTAssertTrue(screenPanels.contains { panel in
                abs(panel.frame.minX - screen.visibleFrame.minX) < 0.01
                    && abs(panel.frame.minY - screen.visibleFrame.minY) < 0.01
            })
            XCTAssertTrue(screenPanels.contains { panel in
                abs(panel.frame.maxX - screen.visibleFrame.maxX) < 0.01
                    && abs(panel.frame.minY - screen.visibleFrame.minY) < 0.01
            })
        }

        corsairPresenter.hide()
        razerPresenter.hide()
    }

    func testSpaceChangeKeepsHealthyModeHUDWindows() async throws {
        let workspaceNotificationCenter = NotificationCenter()
        let presenter = AppKitModeHUDPresenter(
            source: .corsair,
            workspaceNotificationCenter: workspaceNotificationCenter,
            panelIsOnActiveSpace: { _ in true }
        )
        let baselinePanels = visibleHUDPanels()
        presenter.show(DefaultMapLegend.snapshot(source: .corsair))
        await waitForMainQueueTurns()
        let originalWindows = NSApplication.shared.windows.filter { $0 is HUDPanel && $0.isVisible }
        defer { withExtendedLifetime(originalWindows) {} } // ObjectIdentifier is only unique while the original object remains alive.
        let originalPanels = visibleHUDPanels().subtracting(baselinePanels)
        XCTAssertEqual(originalPanels.count, NSScreen.screens.count)
        if ProcessInfo.processInfo.environment["AGENTIC_MOUSE_HUD_VISUAL_HOLD"] == "1" {
            for _ in 0 ..< 600 { // The clipped build passed geometry-only checks, so keep the real click-through presenter visible and refresh hover state for full-display pixel inspection when explicitly requested. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
                HUDScaleHoverCoordinator.shared.refresh()
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        workspaceNotificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        await waitForMainQueueTurns()
        XCTAssertEqual(visibleHUDPanels().subtracting(baselinePanels), originalPanels, "no immediate fade/reopen")
        try await Task.sleep(nanoseconds: 800_000_000)

        await waitForMainQueueTurns()
        let refreshedPanels = visibleHUDPanels().subtracting(baselinePanels)
        XCTAssertEqual(refreshedPanels, originalPanels, "no second fade/reopen after the settled check")
        XCTAssertTrue(presenter.isVisible)
        presenter.hide()
    }

    func testSpaceChangeRepairsOnlyStaleModePanelsOnce() async throws {
        let center = NotificationCenter()
        var stale = Set<ObjectIdentifier>()
        let presenter = AppKitModeHUDPresenter(
            source: .corsair, workspaceNotificationCenter: center,
            panelIsOnActiveSpace: { !stale.contains(ObjectIdentifier($0)) }
        )
        let baseline = visibleHUDPanels()
        presenter.show(DefaultMapLegend.snapshot(source: .corsair))
        await waitForMainQueueTurns()
        let originals = NSApplication.shared.windows.filter { $0 is HUDPanel && $0.isVisible }
        defer { withExtendedLifetime(originals) {} }
        let before = visibleHUDPanels().subtracting(baseline)
        stale = Set(before.prefix(1))
        XCTAssertFalse(stale.isEmpty)

        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        await waitForMainQueueTurns()
        XCTAssertEqual(visibleHUDPanels().subtracting(baseline), before)
        try await Task.sleep(nanoseconds: 800_000_000)
        await waitForMainQueueTurns()
        let repaired = visibleHUDPanels().subtracting(baseline)
        XCTAssertEqual(repaired.count, before.count)
        XCTAssertTrue(repaired.isDisjoint(with: stale))
        XCTAssertTrue(before.subtracting(stale).isSubset(of: repaired), "healthy displays keep their original windows")
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(visibleHUDPanels().subtracting(baseline), repaired, "recovery is bounded")
        presenter.hide()
    }

    func testSpaceChangeKeepsHealthyKeypadWindowsAndDoesNotReopenHiddenKeypad() async throws {
        let center = NotificationCenter()
        let presenter = AppKitHUDPresenter(
            source: .razer, workspaceNotificationCenter: center,
            panelIsOnActiveSpace: { _ in true }
        )
        let baseline = visibleHUDPanels()
        presenter.show(keypadSnapshot())
        await waitForMainQueueTurns()
        let originals = NSApplication.shared.windows.filter { $0 is HUDPanel && $0.isVisible }
        defer { withExtendedLifetime(originals) {} }
        let before = visibleHUDPanels().subtracting(baseline)
        XCTAssertEqual(before.count, NSScreen.screens.count)

        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        await waitForMainQueueTurns()
        XCTAssertEqual(visibleHUDPanels().subtracting(baseline), before)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(visibleHUDPanels().subtracting(baseline), before)

        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        presenter.hide()
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertFalse(presenter.isVisible)
        XCTAssertEqual(visibleHUDPanels(), baseline)
    }

    func testSpaceChangeStillRepairsStaleKeypadWindows() async throws {
        let center = NotificationCenter()
        var stale = Set<ObjectIdentifier>()
        let presenter = AppKitHUDPresenter(
            source: .corsair, workspaceNotificationCenter: center,
            panelIsOnActiveSpace: { !stale.contains(ObjectIdentifier($0)) }
        )
        let baseline = visibleHUDPanels()
        presenter.show(keypadSnapshot(source: .corsair))
        await waitForMainQueueTurns()
        let originals = NSApplication.shared.windows.filter { $0 is HUDPanel && $0.isVisible }
        defer { withExtendedLifetime(originals) {} }
        let before = visibleHUDPanels().subtracting(baseline)
        stale = Set(before.prefix(1))
        center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        await waitForMainQueueTurns()
        XCTAssertEqual(visibleHUDPanels().subtracting(baseline), before)
        try await Task.sleep(nanoseconds: 800_000_000)
        await waitForMainQueueTurns()
        let after = visibleHUDPanels().subtracting(baseline)
        XCTAssertEqual(after.count, before.count)
        XCTAssertTrue(after.isDisjoint(with: stale))
        XCTAssertTrue(before.subtracting(stale).isSubset(of: after))
        presenter.hide()
    }

    /// Run only on a reserved, isolated desktop with a Space to its right.
    /// This exercises real WindowServer transitions, not a posted test notification.
    func testRealSpaceRoundTripKeepsHUDWindowsVisible() async throws {
        guard ProcessInfo.processInfo.environment["AGENTIC_MOUSE_REAL_SPACE_TEST"] == "1" else {
            throw XCTSkip("Opt-in isolated real Space-switch fixture")
        }
        guard CGPreflightPostEventAccess() else {
            throw XCTSkip("The isolated XCTest host cannot post native Space-switch input")
        }
        NSApplication.shared.finishLaunching()
        let presenter = AppKitModeHUDPresenter(source: .corsair)
        let baseline = visibleHUDPanels()
        presenter.show(DefaultMapLegend.snapshot(source: .corsair))
        await waitForMainQueueTurns()
        let original = visibleHUDPanels().subtracting(baseline)
        let windows = NSApplication.shared.windows.filter { original.contains(ObjectIdentifier($0)) }
        let numbers = Set(windows.map { $0.windowNumber })
        XCTAssertFalse(numbers.isEmpty)
        var notifications = 0
        var pendingChange: XCTestExpectation?
        let center = NSWorkspace.shared.notificationCenter
        let observer = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            notifications += 1
            if let change = pendingChange {
                pendingChange = nil
                change.fulfill()
            }
        }
        var samples = 0
        var identityLosses = 0
        var visibilityLosses = 0
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { _ in
            while let event = NSApplication.shared.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                NSApplication.shared.sendEvent(event)
            }
            samples += 1
            if self.visibleHUDPanels().subtracting(baseline) != original { identityLosses += 1 }
            let visibleNumbers = Set((CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
                .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.intValue })
            if !numbers.isSubset(of: visibleNumbers) { visibilityLosses += 1 }
        }
        RunLoop.main.add(timer, forMode: .common)
        defer {
            timer.invalidate()
            center.removeObserver(observer)
            presenter.hide()
            withExtendedLifetime(windows) {}
        }

        let outbound = expectation(description: "macOS switched to the next Space")
        pendingChange = outbound
        postSpaceSwitch(keyCode: 124)
        await fulfillment(of: [outbound], timeout: 6)
        try await Task.sleep(nanoseconds: 800_000_000) // Observe the existing settled repair too.
        let outboundNotifications = notifications
        let inbound = expectation(description: "macOS restored the original Space")
        pendingChange = inbound
        postSpaceSwitch(keyCode: 123) // Restore the fixture's original Space.
        await fulfillment(of: [inbound], timeout: 6)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertGreaterThan(outboundNotifications, 0, "macOS must actually switch Spaces")
        XCTAssertGreaterThan(notifications, outboundNotifications)
        XCTAssertGreaterThan(samples, 0)
        XCTAssertEqual(identityLosses, 0)
        XCTAssertEqual(visibilityLosses, 0)
        if let path = ProcessInfo.processInfo.environment["AGENTIC_MOUSE_SPACE_RECEIPT"] {
            let receipt: [String: Any] = ["notifications": notifications, "samples": samples,
                "identityLosses": identityLosses, "visibilityLosses": visibilityLosses,
                "windowCount": numbers.count]
            try JSONSerialization.data(withJSONObject: receipt, options: .prettyPrinted).write(to: URL(fileURLWithPath: path))
        }
    }

    func testSpaceChangeDoesNotReopenExplicitlyHiddenModeHUD() async throws {
        let workspaceNotificationCenter = NotificationCenter()
        let presenter = AppKitModeHUDPresenter(
            source: .corsair,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
        presenter.show(DefaultMapLegend.snapshot(source: .corsair))
        presenter.hide()

        workspaceNotificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertFalse(presenter.isVisible)
    }

    func testExplicitSpaceReattachmentRecreatesActivePanelsAfterScreenshotOverlayCloses() async throws {
        let presenter = AppKitModeHUDPresenter(source: .razer)
        let baselinePanels = visibleHUDPanels()
        presenter.show(DefaultMapLegend.snapshot(source: .razer))
        await waitForMainQueueTurns()
        let originalWindows = NSApplication.shared.windows.filter { $0 is HUDPanel && $0.isVisible }
        defer { withExtendedLifetime(originalWindows) {} } // ObjectIdentifier is only unique while the original object remains alive.
        let originalPanels = visibleHUDPanels().subtracting(baselinePanels)

        presenter.reattachToCurrentSpaces()
        try await Task.sleep(nanoseconds: 800_000_000)

        await waitForMainQueueTurns() // The settled callback discards panels then enqueues recreation on the next main-queue turn.
        let refreshedPanels = visibleHUDPanels().subtracting(baselinePanels)
        XCTAssertEqual(refreshedPanels.count, NSScreen.screens.count)
        XCTAssertTrue(originalPanels.isDisjoint(with: refreshedPanels))
        XCTAssertTrue(presenter.isVisible)
        presenter.hide()
    }

    func testExplicitSpaceReattachmentDoesNotReopenHiddenPanels() async throws {
        let presenter = AppKitModeHUDPresenter(source: .razer)
        presenter.show(DefaultMapLegend.snapshot(source: .razer))
        presenter.hide()

        presenter.reattachToCurrentSpaces()
        try await Task.sleep(nanoseconds: 800_000_000)

        XCTAssertFalse(presenter.isVisible)
    }

    func testScreenshotRecoveryKeepsVisiblePanelIdentity() async throws {
        let presenter = AppKitModeHUDPresenter(source: .wand, panelIsOnActiveSpace: { _ in true })
        let baseline = visibleHUDPanels()
        presenter.show(DefaultMapLegend.snapshot(source: .wand))
        await waitForMainQueueTurns()
        let originalWindows = NSApplication.shared.windows.filter { $0 is HUDPanel && $0.isVisible }
        defer { withExtendedLifetime(originalWindows) {} }
        let original = visibleHUDPanels().subtracting(baseline)

        presenter.recoverAfterScreenshot()
        XCTAssertEqual(visibleHUDPanels().subtracting(baseline), original, "no immediate flash")
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(visibleHUDPanels().subtracting(baseline), original, "no second flash after 500 ms")
        presenter.hide()
    }

    func testScreenshotRecoveryStillRepairsAStaleSpaceOnce() async throws {
        let presenter = AppKitModeHUDPresenter(source: .wand, panelIsOnActiveSpace: { _ in false })
        let baseline = visibleHUDPanels()
        presenter.show(DefaultMapLegend.snapshot(source: .wand))
        await waitForMainQueueTurns()
        let originalWindows = NSApplication.shared.windows.filter { $0 is HUDPanel && $0.isVisible }
        defer { withExtendedLifetime(originalWindows) {} }
        let original = visibleHUDPanels().subtracting(baseline)

        presenter.recoverAfterScreenshot()
        XCTAssertEqual(visibleHUDPanels().subtracting(baseline), original, "keep the HUD until recovery is needed")
        try await Task.sleep(nanoseconds: 800_000_000)
        await waitForMainQueueTurns()
        let repaired = visibleHUDPanels().subtracting(baseline)
        XCTAssertEqual(repaired.count, original.count)
        XCTAssertTrue(repaired.isDisjoint(with: original))
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(visibleHUDPanels().subtracting(baseline), repaired, "recovery is bounded, never a recreation loop")
        presenter.hide()
    }

    func testScreenshotRecoveryCannotResurrectAnExplicitlyHiddenHUD() async throws {
        let presenter = AppKitModeHUDPresenter(source: .wand, panelIsOnActiveSpace: { _ in false })
        presenter.show(DefaultMapLegend.snapshot(source: .wand))
        presenter.recoverAfterScreenshot()
        presenter.hide()
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertFalse(presenter.isVisible)
    }

    func testFeedbackDoesNotReopenExplicitlyHiddenModeHUD() async {
        let presenter = AppKitModeHUDPresenter(source: .corsair)
        presenter.show(DefaultMapLegend.snapshot(source: .corsair))
        presenter.hide()

        presenter.flashFeedback(ModeHUDFeedback(
            message: "Paste screenshot sent",
            tone: .informational
        ))
        await waitForMainQueueTurns()

        XCTAssertFalse(presenter.isVisible)
    }

    func testRecreatedHUDPanelKeepsNonActivatingClickThroughContract() {
        let panel = HUDPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertEqual(panel.level, .statusBar)
        panel.close()
    }

    private func visibleHUDPanels() -> Set<ObjectIdentifier> {
        Set(NSApplication.shared.windows.compactMap { window in
            guard let panel = window as? HUDPanel, panel.isVisible else { return nil }
            return ObjectIdentifier(panel)
        })
    }

    private func keypadSnapshot(source: MouseSource = .razer) -> HUDSnapshot {
        HUDSnapshot(
            isActive: true, source: source, keymap: .modesKeypad,
            state: MultiTapEngine(keymap: .modesKeypad).state,
            multiTapTimeout: 0.8, now: 0
        )
    }

    private func postSpaceSwitch(keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        // Use the already-established DesktopSpaceActionExecutor lifecycle;
        // zero-dwell synthetic taps may be ignored by the system shortcut.
        let phases: [(CGEventType, CGKeyCode, CGEventFlags, TimeInterval)] = [
            (.flagsChanged, 59, [.maskControl], 0),
            (.keyDown, keyCode, [.maskControl, .maskSecondaryFn], 0.006),
            (.keyUp, keyCode, [.maskControl, .maskSecondaryFn], 0.026),
            (.flagsChanged, 59, [], 0.032)
        ]
        let start = DispatchTime.now().uptimeNanoseconds
        let events = phases.compactMap { type, key, flags, offset -> (CGEvent, TimeInterval)? in
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: type != .keyUp)
            event?.type = type
            event?.flags = flags
            event?.timestamp = start + UInt64(offset * 1_000_000_000)
            return event.map { ($0, offset) }
        }
        XCTAssertEqual(events.count, phases.count)
        var previousOffset: TimeInterval = 0
        for (event, offset) in events {
            if offset > previousOffset { Thread.sleep(forTimeInterval: offset - previousOffset) }
            event.post(tap: .cghidEventTap)
            previousOffset = offset
        }
    }

    private func waitForMainQueueTurns() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }
    }
}
