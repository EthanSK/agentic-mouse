import AppKit
import ScimitarKit
@testable import ScimitarUI
import XCTest

@MainActor
final class HUDSpaceLifecycleTests: XCTestCase {
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
