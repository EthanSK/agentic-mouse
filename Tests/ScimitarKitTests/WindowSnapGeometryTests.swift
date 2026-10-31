import CoreGraphics
import XCTest
@testable import ScimitarKit

/// Ethan's real three displays (2026-10-30) in top-left coordinates:
/// MacBook lower-left, 3440×1440 ultrawide primary, 1920×1080 Samsung
/// raised on the right.
private enum Layout {
    static let primaryHeight: CGFloat = 1440
    static func display(_ id: String, _ frame: CGRect, _ visible: CGRect) -> WindowSnapDisplay {
        WindowSnapDisplay(id: id, frame: WindowSnapDisplay.fromCocoa(frame, primaryHeight: primaryHeight),
                          visibleFrame: WindowSnapDisplay.fromCocoa(visible, primaryHeight: primaryHeight))
    }
    static let macbook = display("macbook", CGRect(x: -1728, y: -289, width: 1728, height: 1117),
                                 CGRect(x: -1728, y: -289, width: 1728, height: 1085))
    static let ultrawide = display("ultrawide", CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                   CGRect(x: 0, y: 0, width: 3440, height: 1410))
    static let samsung = display("samsung", CGRect(x: 3440, y: 1295, width: 1920, height: 1080),
                                 CGRect(x: 3440, y: 1295, width: 1920, height: 1080))
    static let all = [ultrawide, macbook, samsung]
}

final class WindowSnapGeometryTests: XCTestCase {
    func testFirstPressSnapsToTheHalfOfTheCurrentDisplay() {
        let plan = WindowSnapGeometry.plan(.left, window: CGRect(x: 900, y: 200, width: 800, height: 600),
                                           displays: Layout.all, memory: nil)
        XCTAssertEqual(plan?.frame, CGRect(x: 0, y: 30, width: 1720, height: 1410))
        XCTAssertEqual(plan?.traversedDisplay, false)
    }

    func testRepeatedRightWalksAcrossEveryDisplayThenStops() {
        var window = CGRect(x: -1500, y: 700, width: 600, height: 400)
        var visited: [String] = []
        while let plan = WindowSnapGeometry.plan(.right, window: window, displays: Layout.all, memory: nil) {
            visited.append("\(plan.display.id)-\(plan.side.rawValue)")
            window = plan.frame
            XCTAssertLessThan(visited.count, 10)
        }
        XCTAssertEqual(visited, ["macbook-right", "ultrawide-left", "ultrawide-right", "samsung-left", "samsung-right"])
    }

    func testLeftFromTheUltrawideLandsOnTheLowerLeftMacBooksRightHalf() {
        let plan = WindowSnapGeometry.plan(.left, window: CGRect(x: 0, y: 30, width: 1720, height: 1410),
                                           displays: Layout.all, memory: nil)
        XCTAssertEqual(plan?.display.id, "macbook")
        XCTAssertEqual(plan?.side, .right)
        XCTAssertEqual(plan?.frame, CGRect(x: -864, y: 644, width: 864, height: 1085))
    }

    func testAppSizeRoundingStillCountsAsAlreadyThere() {
        let almost = CGRect(x: 0, y: 30, width: 1712, height: 1404)
        XCTAssertEqual(WindowSnapGeometry.plan(.left, window: almost, displays: Layout.all, memory: nil)?.display.id, "macbook")
    }

    func testRememberedSnapHopsEvenWhenTheAppRefusedTheHalfSize() {
        // An app with a 1,100 pt minimum width can't fit the MacBook's 864 pt
        // half; the remembered placement still lets Right hop to the ultrawide.
        let refused = CGRect(x: -1100, y: 645, width: 1100, height: 1085)
        let memory = WindowSnapMemory(direction: .right, displayID: "macbook", acceptedFrame: refused)
        XCTAssertEqual(WindowSnapGeometry.plan(.right, window: refused, displays: Layout.all, memory: nil)?.traversedDisplay, false)
        let plan = WindowSnapGeometry.plan(.right, window: refused, displays: Layout.all, memory: memory)
        XCTAssertEqual(plan?.display.id, "ultrawide")
        XCTAssertEqual(plan?.side, .left)
    }

    func testStaleMemoryIsIgnoredAfterTheWindowMoved() {
        let memory = WindowSnapMemory(direction: .right, displayID: "macbook",
                                      acceptedFrame: CGRect(x: -1100, y: 645, width: 1100, height: 1085))
        let moved = CGRect(x: -1500, y: 700, width: 600, height: 400)
        XCTAssertEqual(WindowSnapGeometry.plan(.right, window: moved, displays: Layout.all, memory: memory)?.traversedDisplay, false)
    }

    func testCorrectionKeepsAnOversizedWindowFlushAndOnTheTargetDisplay() {
        guard let plan = WindowSnapGeometry.plan(.left, window: CGRect(x: 0, y: 30, width: 1720, height: 1410),
                                                 displays: Layout.all, memory: nil) else { return XCTFail() }
        // The app kept 1,100 pt width at the half's origin, straddling onto the ultrawide.
        let accepted = CGRect(x: -864, y: 645, width: 1100, height: 900)
        XCTAssertEqual(WindowSnapGeometry.correction(accepted: accepted, plan: plan),
                       CGRect(x: -1100, y: 645, width: 1100, height: 900))
        XCTAssertNil(WindowSnapGeometry.correction(accepted: plan.frame, plan: plan))
    }

    func testHalvesShareAnExactBoundary() {
        let left = WindowSnapGeometry.half(.left, of: Layout.samsung)
        let right = WindowSnapGeometry.half(.right, of: Layout.samsung)
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(left.width + right.width, 1920)
    }
}
