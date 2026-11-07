import CoreGraphics
import XCTest
import ScimitarKit
@testable import AgenticMouseApp

/// A fake window that behaves like a real app: it can enforce a minimum
/// width, and it clamps writes like an app confined to one display.
private final class FakeWindow: WindowResizeTarget {
    var current: CGRect
    var minimumWidth: CGFloat
    var maximumWidthBeforeMove: CGFloat?
    var writes: [String] = []
    var allowSize = true
    var ignoreSecondPosition = false
    var positionWrites = 0
    var onWrite: (() -> Void)?
    init(_ frame: CGRect, minimumWidth: CGFloat = 0) {
        current = frame
        self.minimumWidth = minimumWidth
    }
    func frame() -> CGRect? { current }
    func setSize(_ size: CGSize) -> Bool {
        writes.append("size")
        onWrite?()
        guard allowSize else { return false }
        current.size = CGSize(width: max(size.width, minimumWidth), height: size.height)
        if positionWrites == 0, let maximumWidthBeforeMove {
            current.size.width = min(current.width, maximumWidthBeforeMove)
        }
        return true
    }
    func setPosition(_ point: CGPoint) -> Bool {
        writes.append("position")
        onWrite?()
        positionWrites += 1
        if ignoreSecondPosition && positionWrites == 2 { return true }
        current.origin = point
        return true
    }
}

private struct FakeAccess: WindowSnapAccess {
    let window: FakeWindow?
    func focusedWindow(pid: pid_t) -> (target: WindowResizeTarget, key: WindowSnapKey)? {
        window.map { ($0, WindowSnapKey(testID: 1)) }
    }
}

final class WindowSnapControllerTests: XCTestCase {
    private let macbook = WindowSnapDisplay(id: "macbook", frame: CGRect(x: -1728, y: 612, width: 1728, height: 1117),
                                            visibleFrame: CGRect(x: -1728, y: 644, width: 1728, height: 1085))
    private let ultrawide = WindowSnapDisplay(id: "ultrawide", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                              visibleFrame: CGRect(x: 0, y: 30, width: 3440, height: 1410))

    func testOrdinarySnapResizesOnlyOnceAndStillTraverses() {
        let window = FakeWindow(CGRect(x: 100, y: 100, width: 800, height: 600))
        let controller = WindowSnapController(access: FakeAccess(window: window))
        XCTAssertEqual(controller.snap(.left, pid: 1, displays: [ultrawide, macbook]),
                       .moved(CGRect(x: 0, y: 30, width: 1720, height: 1410)))
        XCTAssertEqual(window.writes, ["size", "position"])
        guard case .traversed(let frame) = controller.snap(.left, pid: 1, displays: [ultrawide, macbook])
        else { return XCTFail("second Left should hop to the MacBook") }
        XCTAssertEqual(frame, CGRect(x: -864, y: 644, width: 864, height: 1085))
        XCTAssertEqual(controller.snap(.right, pid: 1, displays: [ultrawide, macbook]),
                       .traversed(CGRect(x: 0, y: 30, width: 1720, height: 1410)))
    }

    func testEqualSizedHalfChangeOnlyMovesTheWindow() {
        let window = FakeWindow(CGRect(x: 0, y: 30, width: 1720, height: 1410))
        let controller = WindowSnapController(access: FakeAccess(window: window))
        XCTAssertEqual(controller.snap(.right, pid: 1, displays: [ultrawide]),
                       .moved(CGRect(x: 1720, y: 30, width: 1720, height: 1410)))
        XCTAssertEqual(window.writes, ["position"])
    }

    func testSizeClampedOnTheOldDisplayIsRetriedAfterMoving() {
        let window = FakeWindow(CGRect(x: -864, y: 644, width: 864, height: 1085))
        window.maximumWidthBeforeMove = 1100
        let controller = WindowSnapController(access: FakeAccess(window: window))
        XCTAssertEqual(controller.snap(.right, pid: 1, displays: [ultrawide, macbook]),
                       .traversed(CGRect(x: 0, y: 30, width: 1720, height: 1410)))
        XCTAssertEqual(window.writes, ["size", "position", "size"])
    }

    func testMinimumWidthAppStaysOnTheDisplayAndStillHops() {
        let window = FakeWindow(CGRect(x: 0, y: 30, width: 1720, height: 1410), minimumWidth: 1100)
        let controller = WindowSnapController(access: FakeAccess(window: window))
        // Left from the ultrawide's left half → MacBook right half, but the
        // app insists on 1,100 pt: it must end flush right, fully on the MacBook.
        guard case .traversed(let frame) = controller.snap(.left, pid: 1, displays: [ultrawide, macbook])
        else { return XCTFail() }
        XCTAssertEqual(frame.maxX, 0)
        XCTAssertEqual(frame.width, 1100)
        // Remembered placement lets Right hop back even though the size never matched the half.
        guard case .traversed(let back) = controller.snap(.right, pid: 1, displays: [ultrawide, macbook])
        else { return XCTFail("remembered snap should hop back to the ultrawide") }
        XCTAssertEqual(back.minX, 0)
    }

    func testFailedWriteAndIgnoredCorrectionAreNotReportedAsSuccess() {
        let failed = FakeWindow(CGRect(x: 100, y: 100, width: 800, height: 600))
        failed.allowSize = false
        let controller = WindowSnapController(access: FakeAccess(window: failed))
        XCTAssertEqual(controller.snap(.left, pid: 1, displays: [ultrawide, macbook]), .failed)
        XCTAssertEqual(failed.writes, ["size"])

        let refused = FakeWindow(CGRect(x: 0, y: 30, width: 1720, height: 1410), minimumWidth: 1100)
        refused.ignoreSecondPosition = true
        let correction = WindowSnapController(access: FakeAccess(window: refused))
        XCTAssertEqual(correction.snap(.left, pid: 1, displays: [ultrawide, macbook]), .failed)
        refused.ignoreSecondPosition = false
        guard case .moved = correction.snap(.right, pid: 1, displays: [ultrawide, macbook])
        else { return XCTFail("failed placement must not install hop memory") }
    }

    func testCancellationAndPermissionLossStopWindowWrites() {
        let window = FakeWindow(CGRect(x: 100, y: 100, width: 800, height: 600))
        let controller = WindowSnapController(access: FakeAccess(window: window))
        XCTAssertEqual(controller.snap(.left, pid: 1, displays: [ultrawide], permitted: { false }), .cancelled)
        XCTAssertTrue(window.writes.isEmpty)
        var allowed = true
        window.onWrite = { allowed = false }
        XCTAssertEqual(controller.snap(.left, pid: 1, displays: [ultrawide], permitted: { allowed }), .cancelled)
        XCTAssertEqual(window.writes, ["size"], "no later AX writes after permission is revoked")
    }

    func testQueuedWorkIsCancelledPerSourceBeforeAccessibilityStarts() {
        let window = FakeWindow(CGRect(x: 100, y: 100, width: 800, height: 600))
        let queue = DispatchQueue(label: "window-snap-cancel-test")
        let controller = WindowSnapController(access: FakeAccess(window: window), queue: queue)
        var outcomes: [WindowSnapDirection] = []
        controller.onOutcome = { side, _ in outcomes.append(side) }
        queue.suspend()
        controller.enqueue(.left, pid: 1, displays: [ultrawide], source: .corsair, inputAllowed: { true })
        controller.enqueue(.right, pid: 1, displays: [ultrawide], source: .razer, inputAllowed: { true })
        controller.cancel(source: .corsair)
        queue.resume()
        queue.sync {}
        XCTAssertEqual(outcomes, [.right], "releasing one mouse never cancels the other mouse")
        XCTAssertEqual(window.current.minX, 1720)

        queue.suspend()
        controller.enqueue(.left, pid: 1, displays: [ultrawide], source: .razer, inputAllowed: { true })
        controller.cancelAll()
        queue.resume()
        queue.sync {}
        XCTAssertEqual(outcomes, [.right], "lock/shutdown cancels every queued source")
    }

    func testReleaseFinishesStartedFrameButGlobalTeardownStopsIt() {
        let queue = DispatchQueue(label: "window-snap-transaction-test")
        let window = FakeWindow(CGRect(x: 100, y: 100, width: 800, height: 600))
        let controller = WindowSnapController(access: FakeAccess(window: window), queue: queue)
        window.onWrite = { controller.cancel(source: .corsair) }
        controller.enqueue(.left, pid: 1, displays: [ultrawide], source: .corsair, inputAllowed: { true })
        queue.sync {}
        XCTAssertEqual(window.writes, ["size", "position"], "release does not leave half a frame transaction")
        window.writes.removeAll()
        window.current = CGRect(x: 100, y: 100, width: 800, height: 600)
        window.onWrite = { controller.cancelAll() }
        controller.enqueue(.right, pid: 1, displays: [ultrawide], source: .corsair, inputAllowed: { true })
        queue.sync {}
        XCTAssertEqual(window.writes, ["size"], "lock or global teardown stops subsequent writes")
    }

    func testNoFocusedWindowAndOutermostEdge() {
        XCTAssertEqual(WindowSnapController(access: FakeAccess(window: nil)).snap(.left, pid: 1, displays: [ultrawide]), .noWindow)
        let window = FakeWindow(CGRect(x: 1720, y: 30, width: 1720, height: 1410))
        XCTAssertEqual(WindowSnapController(access: FakeAccess(window: window)).snap(.right, pid: 1, displays: [ultrawide, macbook]),
                       .unchanged)
    }

    func testVerifiedSnapRegistersOriginalSizeAndQueuedNewSnapCancelsOldRestore() {
        let queue = DispatchQueue(label: "snap-restore-integration")
        let original = CGRect(x: 100, y: 100, width: 800, height: 600)
        let window = FakeWindow(original)
        let restorer = WindowSnapDragRestorer(queue: queue, windows: {
            [WindowSnapPointerWindow(id: 1, pid: 0, frame: window.current)]
        })
        let controller = WindowSnapController(access: FakeAccess(window: window), queue: queue, restorer: restorer)
        guard case .moved = controller.snap(.left, pid: 1, displays: [ultrawide]) else { return XCTFail() }
        restorer.mouseEvent(.leftMouseDown, point: CGPoint(x: 900, y: 44))
        window.current.origin.x += 40
        restorer.mouseEvent(.leftMouseDragged, point: CGPoint(x: 940, y: 44))
        restorer.changed(WindowSnapKey(testID: 1)); queue.sync {}
        XCTAssertEqual(window.current.size, original.size)

        _ = controller.snap(.left, pid: 1, displays: [ultrawide])
        window.writes.removeAll()
        queue.suspend()
        restorer.mouseEvent(.leftMouseDown, point: CGPoint(x: 900, y: 44))
        window.current.origin.x += 40
        restorer.mouseEvent(.leftMouseDragged, point: CGPoint(x: 940, y: 44))
        restorer.changed(WindowSnapKey(testID: 1))
        controller.enqueue(.right, pid: 1, displays: [ultrawide], source: .corsair, inputAllowed: { true })
        queue.resume(); queue.sync {}
        XCTAssertEqual(window.writes, ["position"], "stale restore must not run before the newer requested snap")
        XCTAssertEqual(window.current.minX, 1720)
    }

    func testFailedSnapDoesNotRegisterDragRestoration() {
        let queue = DispatchQueue(label: "snap-restore-failed")
        let restorer = WindowSnapDragRestorer(queue: queue, windows: { [] })
        let window = FakeWindow(CGRect(x: 100, y: 100, width: 800, height: 600))
        window.allowSize = false
        let controller = WindowSnapController(access: FakeAccess(window: window), queue: queue, restorer: restorer)
        XCTAssertEqual(controller.snap(.left, pid: 1, displays: [ultrawide]), .failed)
        window.allowSize = true; window.current.origin.x += 40; window.writes.removeAll()
        restorer.changed(WindowSnapKey(testID: 1)); queue.sync {}
        XCTAssertTrue(window.writes.isEmpty)
    }

}
