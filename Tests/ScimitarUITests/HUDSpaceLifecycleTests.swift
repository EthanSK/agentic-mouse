import AppKit
import ScimitarKit
@testable import ScimitarUI
import XCTest

@MainActor
final class HUDSpaceLifecycleTests: XCTestCase {
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

    func testActiveModeHUDRecreatesEveryDisplayPanelAfterSpaceChange() async throws {
        let workspaceNotificationCenter = NotificationCenter()
        let presenter = AppKitModeHUDPresenter(
            source: .corsair,
            workspaceNotificationCenter: workspaceNotificationCenter
        )
        let baselinePanels = visibleHUDPanels()
        presenter.show(DefaultMapLegend.snapshot(source: .corsair))
        await waitForMainQueueTurns()
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
        try await Task.sleep(nanoseconds: 800_000_000)

        let refreshedPanels = visibleHUDPanels().subtracting(baselinePanels)
        XCTAssertEqual(refreshedPanels.count, NSScreen.screens.count)
        XCTAssertTrue(originalPanels.isDisjoint(with: refreshedPanels))
        XCTAssertTrue(presenter.isVisible)
        presenter.hide()
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
        let originalPanels = visibleHUDPanels().subtracting(baselinePanels)

        presenter.reattachToCurrentSpaces()
        try await Task.sleep(nanoseconds: 800_000_000)

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
