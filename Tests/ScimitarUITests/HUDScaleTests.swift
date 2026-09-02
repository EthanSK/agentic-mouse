import AppKit
import SwiftUI
@testable import ScimitarUI
import XCTest

@MainActor
final class HUDScaleTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HUDScaleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultScaleMakesTheHUDOneQuarterOfItsOriginalArea() {
        let store = HUDScaleStore(defaults: defaults)
        let original = ScaledHUDHostingView(
            rootView: Color.clear.frame(width: 200, height: 100),
            scale: 1
        )
        let scaled = ScaledHUDHostingView(
            rootView: Color.clear.frame(width: 200, height: 100),
            scale: CGFloat(store.scale)
        )

        XCTAssertEqual(store.scale, 0.5)
        XCTAssertEqual(scaled.fittingSize.width, original.fittingSize.width / 2, accuracy: 0.01)
        XCTAssertEqual(scaled.fittingSize.height, original.fittingSize.height / 2, accuracy: 0.01)
    }

    func testScaledHostingViewMapsTheFullContentIntoTheSmallerFrame() {
        let scaled = ScaledHUDHostingView(
            rootView: Color.clear.frame(width: 200, height: 100),
            scale: 0.5
        )
        scaled.frame = NSRect(origin: .zero, size: scaled.fittingSize)

        scaled.layoutSubtreeIfNeeded()
        guard let renderedHUD = scaled.subviews.first else {
            return XCTFail("the scaled host must keep its complete rendered HUD")
        }

        XCTAssertEqual(scaled.frame.width, 100, accuracy: 0.01)
        XCTAssertEqual(scaled.frame.height, 50, accuracy: 0.01)
        XCTAssertEqual(scaled.bounds.width, 200, accuracy: 0.01)
        XCTAssertEqual(scaled.bounds.height, 100, accuracy: 0.01)
        XCTAssertEqual(renderedHUD.frame.width, 200, accuracy: 0.01)
        XCTAssertEqual(renderedHUD.frame.height, 100, accuracy: 0.01)
    }

    func testScalePersistsAcrossStoreInstances() {
        let firstStore = HUDScaleStore(defaults: defaults)
        firstStore.setScale(0.73)

        let relaunchedStore = HUDScaleStore(defaults: defaults)

        XCTAssertEqual(relaunchedStore.scale, 0.73)
    }

    func testScaleIsBoundedAndInvalidValuesRestoreTheDefault() {
        let store = HUDScaleStore(defaults: defaults)

        store.setScale(0.1)
        XCTAssertEqual(store.scale, HUDScaleStore.minimumScale)
        store.setScale(2)
        XCTAssertEqual(store.scale, HUDScaleStore.maximumScale)
        store.setScale(.nan)
        XCTAssertEqual(store.scale, HUDScaleStore.defaultScale)
    }

    func testScaleControlIsTheOnlyMouseInteractiveHUDPanel() {
        let store = HUDScaleStore(defaults: defaults)
        let hudPanel = HUDPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))
        let controlPanel = HUDScaleControlPanel(scaleStore: store)

        XCTAssertTrue(hudPanel.ignoresMouseEvents)
        XCTAssertFalse(controlPanel.ignoresMouseEvents)
        XCTAssertTrue(controlPanel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(controlPanel.canBecomeKey)
        XCTAssertFalse(controlPanel.canBecomeMain)

        controlPanel.close()
        hudPanel.close()
    }
}
