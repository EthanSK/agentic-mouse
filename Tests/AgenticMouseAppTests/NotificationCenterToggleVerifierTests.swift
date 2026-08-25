@testable import AgenticMouseApp
import CoreGraphics
import XCTest

@MainActor
final class NotificationCenterToggleVerifierTests: XCTestCase {
    func testDetectorIgnoresDesktopWidgetsAndNotificationBanners() {
        XCTAssertFalse(NotificationCenterWindowDetector.isVisible(in: [
            window(owner: "Notification Centre", layer: -2_147_483_601, width: 400, height: 700),
            window(owner: "Notification Centre", layer: 25, width: 420, height: 110),
            window(owner: "Finder", layer: 0, width: 900, height: 700),
        ]))
    }

    func testDetectorAcceptsTheVisibleNotificationCenterPanel() {
        XCTAssertTrue(NotificationCenterWindowDetector.isVisible(in: [
            window(owner: "Notification Center", layer: 25, width: 420, height: 760),
        ]))
    }

    func testVerifierConfirmsOpenAndCloseTransitions() {
        var visible = false
        var scheduled: [@MainActor () -> Void] = []
        let verifier = NotificationCenterToggleVerifier(
            visibility: { visible },
            scheduler: { _, action in scheduled.append(action) }
        )

        let beforeOpen = verifier.captureBeforeToggle()
        var openOutcome: NotificationCenterToggleVerifier.Outcome?
        verifier.verifyToggle(from: beforeOpen) { openOutcome = $0 }
        visible = true
        scheduled.removeFirst()()
        XCTAssertEqual(openOutcome, .opened)

        let beforeClose = verifier.captureBeforeToggle()
        var closeOutcome: NotificationCenterToggleVerifier.Outcome?
        verifier.verifyToggle(from: beforeClose) { closeOutcome = $0 }
        visible = false
        scheduled.removeFirst()()
        XCTAssertEqual(closeOutcome, .closed)
    }

    func testVerifierRetriesBeforeReportingNoChange() {
        var scheduled: [@MainActor () -> Void] = []
        let verifier = NotificationCenterToggleVerifier(
            visibility: { false },
            scheduler: { _, action in scheduled.append(action) }
        )
        var outcome: NotificationCenterToggleVerifier.Outcome?

        verifier.verifyToggle(from: false) { outcome = $0 }
        scheduled.removeFirst()()
        XCTAssertNil(outcome)
        scheduled.removeFirst()()
        XCTAssertEqual(outcome, .unchanged)
    }

    func testVerifierReportsUnavailableWithoutScheduling() {
        var scheduleCount = 0
        let verifier = NotificationCenterToggleVerifier(
            visibility: { nil },
            scheduler: { _, _ in scheduleCount += 1 }
        )
        var outcome: NotificationCenterToggleVerifier.Outcome?

        verifier.verifyToggle(from: verifier.captureBeforeToggle()) { outcome = $0 }

        XCTAssertEqual(outcome, .unavailable)
        XCTAssertEqual(scheduleCount, 0)
    }

    private func window(
        owner: String,
        layer: Int,
        width: CGFloat,
        height: CGFloat
    ) -> NotificationCenterWindowDetector.WindowInfo {
        [
            kCGWindowOwnerName as String: owner,
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: 1),
            kCGWindowBounds as String: [
                "X": 0,
                "Y": 0,
                "Width": width,
                "Height": height,
            ] as CFDictionary,
        ]
    }
}
