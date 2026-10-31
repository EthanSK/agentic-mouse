import CoreGraphics
import XCTest
@testable import ScimitarKit

final class WindowSnapDragRestoreTests: XCTestCase {
    let original = CGRect(x: 600, y: 200, width: 800, height: 600)
    let snapped = CGRect(x: 0, y: 30, width: 1720, height: 1410)

    func testDraggingAwayRestoresTheOriginalSizeUnderThePointer() {
        // Grabbed the title bar at its midpoint and moved 40 pt right.
        let current = snapped.offsetBy(dx: 40, dy: 0)
        let frame = WindowSnapDragRestore.restoredFrame(current: current, accepted: snapped, original: original,
                                                        pointer: CGPoint(x: 900, y: 40))
        XCTAssertEqual(frame, CGRect(x: 500, y: 30, width: 800, height: 600))
    }

    func testNoRestoreBeforeTheWindowLeavesItsSnappedPosition() {
        XCTAssertNil(WindowSnapDragRestore.restoredFrame(current: snapped.offsetBy(dx: 2, dy: 0), accepted: snapped,
                                                         original: original, pointer: CGPoint(x: 900, y: 40)))
    }

    func testResizingIsNotADragAway() {
        var resized = snapped
        resized.size.width -= 100
        XCTAssertNil(WindowSnapDragRestore.restoredFrame(current: resized, accepted: snapped, original: original,
                                                         pointer: CGPoint(x: 900, y: 40)))
        XCTAssertTrue(WindowSnapDragRestore.sizeChanged(current: resized, accepted: snapped))
    }

    func testSameSizeOriginalNeedsNoRestore() {
        XCTAssertNil(WindowSnapDragRestore.restoredFrame(current: snapped.offsetBy(dx: 50, dy: 0), accepted: snapped,
                                                         original: CGRect(x: 9, y: 9, width: 1720, height: 1410),
                                                         pointer: CGPoint(x: 900, y: 40)))
    }

    func testHoppingMonitorsKeepsTheFirstOriginal() {
        let hopped = CGRect(x: -864, y: 644, width: 864, height: 1085)
        // Second snap starts from where the first snap left it → keep the first original.
        XCTAssertEqual(WindowSnapDragRestore.originalForSnap(preSnap: snapped, previousOriginal: original,
                                                             previousAccepted: snapped), original)
        // Moved by hand in between → the hand-placed frame becomes the original.
        XCTAssertEqual(WindowSnapDragRestore.originalForSnap(preSnap: hopped.offsetBy(dx: 100, dy: 0),
                                                             previousOriginal: original, previousAccepted: hopped),
                       hopped.offsetBy(dx: 100, dy: 0))
    }
}
