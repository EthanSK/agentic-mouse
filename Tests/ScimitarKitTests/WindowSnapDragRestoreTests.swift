import CoreGraphics
import XCTest
@testable import ScimitarKit

final class WindowSnapDragRestoreTests: XCTestCase {
    let original = CGRect(x: 600, y: 200, width: 800, height: 600)
    let snapped = CGRect(x: 0, y: 30, width: 1720, height: 1410)

    func testDraggingAwayRestoresTheOriginalSizeInPlaceWithoutMovingTheWindow() {
        // macOS owns the drag; moving the window mid-drag makes it jump, so only
        // the size changes and the origin stays wherever the drag has it.
        let current = snapped.offsetBy(dx: 40, dy: 12)
        let frame = WindowSnapDragRestore.restoredFrame(current: current, accepted: snapped, original: original,
                                                        pointer: CGPoint(x: 900, y: 52))
        XCTAssertEqual(frame, CGRect(x: 40, y: 42, width: 800, height: 600))
    }

    func testFarEdgeGrabCorrectsOnlyAfterReadingTheAcceptedRestoredSize() {
        let current = snapped.offsetBy(dx: 40, dy: 0)
        let pointer = CGPoint(x: current.maxX - 20, y: current.minY + 10)
        let frame = WindowSnapDragRestore.restoredFrame(current: current, accepted: snapped,
                                                        original: original, pointer: pointer)
        XCTAssertEqual(frame?.origin, current.origin)
        XCTAssertEqual(frame?.size, original.size)
        XCTAssertGreaterThan(pointer.x, frame!.maxX)
        let down = CGPoint(x: snapped.maxX - 20, y: snapped.minY + 10)
        let origin = WindowSnapDragRestore.correctedOrigin(after: frame!, grabFrame: snapped,
                                                           grabPoint: down, pointer: pointer)
        XCTAssertNotNil(origin)
        XCTAssertTrue(CGRect(origin: origin!, size: frame!.size).contains(pointer))
        XCTAssertEqual((pointer.x - origin!.x) / frame!.width,
                       (down.x - snapped.minX) / snapped.width, accuracy: 0.0001)
    }

    func testPointerAlreadyInsideTheRestoredWindowNeedsNoPositionWrite() {
        XCTAssertNil(WindowSnapDragRestore.correctedOrigin(
            after: CGRect(x: 100, y: 50, width: 800, height: 600), grabFrame: snapped,
            grabPoint: CGPoint(x: 500, y: 44), pointer: CGPoint(x: 600, y: 64)))
    }

    func testCorrectionUsesOriginalGrabAndNewestPointerAfterWorkerDelay() {
        let after = CGRect(x: 100, y: 60, width: 800, height: 600)
        let down = CGPoint(x: 1600, y: 44)
        let pointer = CGPoint(x: 1820, y: 150)
        let origin = WindowSnapDragRestore.correctedOrigin(after: after, grabFrame: snapped,
                                                           grabPoint: down, pointer: pointer)!
        XCTAssertEqual(origin.x, pointer.x - (1600 / 1720) * 800, accuracy: 0.0001)
        XCTAssertTrue(CGRect(origin: origin, size: after.size).contains(pointer))
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
        // Frame drift or another app-owned resize must not replace the first size.
        XCTAssertEqual(WindowSnapDragRestore.originalForSnap(preSnap: hopped.offsetBy(dx: 100, dy: 0),
                                                             previousOriginal: original, previousAccepted: hopped),
                       original)
    }

    func testFirstSnapCapturesItsStartingFrameAndLaterDifferentSizesKeepIt() {
        XCTAssertEqual(WindowSnapDragRestore.originalForSnap(preSnap: original,
            previousOriginal: nil, previousAccepted: nil), original)
        let resizedAgain = CGRect(x: 10, y: 40, width: 1300, height: 900)
        XCTAssertEqual(WindowSnapDragRestore.originalForSnap(preSnap: resizedAgain,
            previousOriginal: original, previousAccepted: snapped), original)
    }
}
