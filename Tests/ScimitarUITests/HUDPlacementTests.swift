import AppKit
import ScimitarKit
@testable import ScimitarUI
import XCTest

final class HUDPlacementTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "HUDPlacementTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testDefaultTopCornersClearTheToolbarOnAnOffsetDisplay() {
        let store = HUDPlacementStore(defaults: defaults)
        let visible = NSRect(x: -1920, y: 300, width: 1920, height: 1050)
        let size = NSSize(width: 352.5, height: 230)
        let right = store.frame(source: .corsair, size: size, visibleFrame: visible, margin: 0)
        let left = store.frame(source: .razer, size: size, visibleFrame: visible, margin: 0)
        XCTAssertEqual(visible.maxY - right.maxY, 88)
        XCTAssertEqual(visible.maxX - right.maxX, 12)
        XCTAssertEqual(left.minX - visible.minX, 12)
        XCTAssertEqual(right.minY, left.minY)
        XCTAssertEqual(store.edge, .top)
    }

    func testBottomRestoresBothFormerCornersAndPersistsAcrossLaunches() {
        let store = HUDPlacementStore(defaults: defaults)
        store.setEdge(.bottom)
        store.setTopSpacing(112)
        let reloaded = HUDPlacementStore(defaults: defaults)
        XCTAssertEqual(reloaded.edge, .bottom)
        XCTAssertEqual(reloaded.topSpacing, 112)
        let visible = NSRect(x: 100, y: -900, width: 1200, height: 800)
        let size = NSSize(width: 350, height: 220)
        XCTAssertEqual(reloaded.frame(source: .razer, size: size, visibleFrame: visible, margin: 0).origin,
                       NSPoint(x: 100, y: -900))
        XCTAssertEqual(reloaded.frame(source: .corsair, size: size, visibleFrame: visible, margin: 0).origin,
                       NSPoint(x: 950, y: -900))
    }

    func testTallHUDGivesUpSpacingBeforeLeavingUsableScreen() {
        let store = HUDPlacementStore(defaults: defaults)
        let visible = NSRect(x: 0, y: 40, width: 1200, height: 600)
        let frame = store.frame(source: .corsair, size: NSSize(width: 705, height: 570),
                                visibleFrame: visible, margin: 0)
        XCTAssertEqual(frame.minY, visible.minY)
        XCTAssertTrue(visible.contains(frame))
    }

    func testSpacingIsIndependentOfHUDSizeAndClampsInvalidSavedValues() {
        let store = HUDPlacementStore(defaults: defaults)
        store.setTopSpacing(120)
        let visible = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        for width in [250.0, 352.5, 705.0] {
            let frame = store.frame(source: .corsair, size: NSSize(width: width, height: 200),
                                    visibleFrame: visible, margin: 0)
            XCTAssertEqual(visible.maxY - frame.maxY, 120)
        }
        store.setTopSpacing(.nan)
        XCTAssertEqual(store.topSpacing, 88)
        store.setTopSpacing(999)
        XCTAssertEqual(store.topSpacing, 240)
        defaults.set(-10.0, forKey: "hudTopSpacing")
        defaults.set("invalid", forKey: "hudVerticalEdge")
        let recovered = HUDPlacementStore(defaults: defaults)
        XCTAssertEqual(recovered.topSpacing, 0)
        XCTAssertEqual(recovered.edge, .top)
    }

    func testWandCornerNeverFollowsMouseEdge() {
        for edge in AppConfiguration.HUDConfiguration.VerticalEdge.allCases {
            XCTAssertEqual(AppConfiguration.HUDConfiguration.sourceCorner(for: .wand, edge: edge), .bottomCenter)
        }
    }
}
