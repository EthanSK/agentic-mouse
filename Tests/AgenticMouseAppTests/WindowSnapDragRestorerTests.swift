import CoreGraphics
import XCTest
import ScimitarKit
@testable import AgenticMouseApp

private final class RestoreWindow: WindowResizeTarget {
    var current: CGRect?
    var writes: [String] = []
    var allowSize = true
    var ignoreSize = false
    var onWrite: (() -> Void)?
    var onRead: (() -> Void)?
    var reportedOrigin: CGPoint?
    init(_ current: CGRect) { self.current = current }
    func frame() -> CGRect? {
        onRead?()
        guard var frame = current else { return nil }
        if let reportedOrigin { frame.origin = reportedOrigin }
        return frame
    }
    func setSize(_ size: CGSize) -> Bool {
        writes.append("size"); onWrite?()
        guard allowSize else { return false }
        if !ignoreSize { current?.size = size }
        return true
    }
    func setPosition(_ position: CGPoint) -> Bool {
        writes.append("position"); onWrite?(); current?.origin = position; return true
    }
}

private struct RestoreAccess: WindowSnapAccess {
    let window: RestoreWindow
    let key: WindowSnapKey
    func focusedWindow(pid: pid_t) -> (target: WindowResizeTarget, key: WindowSnapKey)? { (window, key) }
}

final class WindowSnapDragRestorerTests: XCTestCase {
    private let key = WindowSnapKey(testID: 991)
    private let original = CGRect(x: 600, y: 200, width: 800, height: 600)
    private let snapped = CGRect(x: 0, y: 30, width: 1720, height: 1410)
    private var down: CGPoint { CGPoint(x: snapped.minX + 600, y: snapped.minY + 14) }
    private var movedPoint: CGPoint { CGPoint(x: down.x + 40, y: down.y + 12) }

    private func makeRestorer(_ window: RestoreWindow, _ queue: DispatchQueue,
                              now: @escaping () -> TimeInterval = { 0 }) -> WindowSnapDragRestorer {
        WindowSnapDragRestorer(queue: queue, windows: {
            guard let frame = window.current else { return [] }
            return [WindowSnapPointerWindow(id: 991, pid: 0, frame: frame)]
        }, now: now)
    }

    private func startDrag(_ restorer: WindowSnapDragRestorer, window: RestoreWindow, release: Bool = false) {
        restorer.mouseEvent(.leftMouseDown, point: down)
        window.current = snapped.offsetBy(dx: 40, dy: 12)
        restorer.mouseEvent(.leftMouseDragged, point: movedPoint)
        if release { restorer.mouseEvent(.leftMouseUp, point: movedPoint) }
    }

    func testQuickReleaseBeforeQueuedAXWorkStillRestoresOnceInPlace() {
        let queue = DispatchQueue(label: "restore-quick-release")
        let window = RestoreWindow(snapped)
        let restorer = makeRestorer(window, queue)
        var restored: [CGRect] = []
        restorer.onRestore = { restored.append($0) }
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        queue.suspend()
        startDrag(restorer, window: window, release: true)
        restorer.changed(key)
        queue.resume(); queue.sync {}
        XCTAssertEqual(restored, [CGRect(x: 40, y: 42, width: 800, height: 600)])
        XCTAssertEqual(window.writes, ["size"])
    }

    func testAXMoveArrivingOnlyAfterMouseUpUsesObservedDrag() {
        let queue = DispatchQueue(label: "restore-late-ax")
        let window = RestoreWindow(snapped)
        let restorer = makeRestorer(window, queue)
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        restorer.mouseEvent(.leftMouseDown, point: down)
        restorer.mouseEvent(.leftMouseDragged, point: movedPoint)
        queue.sync {} // App has not moved yet; the drag alone must not resize content.
        restorer.mouseEvent(.leftMouseUp, point: movedPoint)
        queue.sync {}
        XCTAssertTrue(window.writes.isEmpty)
        window.current = snapped.offsetBy(dx: 40, dy: 12)
        restorer.changed(key); queue.sync {}
        XCTAssertEqual(window.current?.size, original.size)
    }

    func testFarEdgeRestoreUsesNewestPointerAfterQueuedWorkAndRelease() {
        let queue = DispatchQueue(label: "restore-edge-latest-pointer")
        let window = RestoreWindow(snapped)
        let restorer = makeRestorer(window, queue)
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        queue.suspend()
        let down = CGPoint(x: 1600, y: 44)
        let latest = CGPoint(x: 1720, y: 84)
        restorer.mouseEvent(.leftMouseDown, point: down)
        window.current = snapped.offsetBy(dx: 40, dy: 12)
        restorer.mouseEvent(.leftMouseDragged, point: CGPoint(x: 1640, y: 56))
        restorer.mouseEvent(.leftMouseDragged, point: latest)
        restorer.mouseEvent(.leftMouseUp, point: latest)
        queue.resume(); queue.sync {}
        XCTAssertEqual(window.current?.size, original.size)
        XCTAssertTrue(window.current!.contains(latest))
        XCTAssertEqual(window.current!.minX, latest.x - (1600 / 1720) * original.width, accuracy: 0.0001)
        XCTAssertEqual(window.writes, ["size", "position"])
    }

    func testPermissionLossAfterSizeWritePreventsFarEdgePositionWrite() {
        let queue = DispatchQueue(label: "restore-edge-permission")
        let window = RestoreWindow(snapped)
        let restorer = makeRestorer(window, queue)
        var allowed = true
        var restored = false
        restorer.onRestore = { _ in restored = true }
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped,
                         inputAllowed: { allowed })
        window.onWrite = { allowed = false }
        restorer.mouseEvent(.leftMouseDown, point: CGPoint(x: 1600, y: 44))
        window.current = snapped.offsetBy(dx: 40, dy: 12)
        restorer.mouseEvent(.leftMouseDragged, point: CGPoint(x: 1640, y: 56))
        queue.sync {}
        XCTAssertEqual(window.writes, ["size"])
        XCTAssertFalse(restored)
    }

    func testOngoingDragOriginMayChangeDuringResize() {
        let queue = DispatchQueue(label: "restore-moving-origin")
        let window = RestoreWindow(snapped)
        let restorer = makeRestorer(window, queue)
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        window.onWrite = { window.current?.origin = CGPoint(x: 65, y: 50) }
        startDrag(restorer, window: window); queue.sync {}
        XCTAssertEqual(window.current, CGRect(x: 65, y: 50, width: 800, height: 600))
        XCTAssertEqual(window.writes, ["size"])
    }

    func testVisibleMoveRestoresWhenAccessibilityPositionIsStaleWithoutUnnecessaryNudge() {
        let queue = DispatchQueue(label: "restore-stale-ax-position")
        let window = RestoreWindow(snapped)
        let restorer = makeRestorer(window, queue)
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        restorer.mouseEvent(.leftMouseDown, point: down)
        window.current = snapped.offsetBy(dx: 400, dy: 12)
        window.reportedOrigin = snapped.origin
        restorer.mouseEvent(.leftMouseDragged, point: CGPoint(x: down.x + 400, y: down.y + 12))
        queue.sync {}
        XCTAssertEqual(window.current, CGRect(x: 400, y: 42, width: 800, height: 600))
        XCTAssertEqual(window.writes, ["size"])
    }

    func testDelayedOlderAppKitEventsCannotRestoreOrCancelANewerGrab() {
        for older in [CGEventType.leftMouseDragged, .leftMouseUp, .keyDown, .rightMouseDown] {
            let queue = DispatchQueue(label: "restore-ordered-input")
            let window = RestoreWindow(snapped)
            let restorer = makeRestorer(window, queue, now: { 100.3 })
            restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
            restorer.mouseEvent(.leftMouseDown, point: down, time: 100)
            restorer.mouseEvent(.leftMouseDown, point: down, time: 100.2)
            window.current = snapped.offsetBy(dx: 40, dy: 12)
            restorer.mouseEvent(older, point: movedPoint, time: 100.1)
            queue.sync {}
            XCTAssertTrue(window.writes.isEmpty)
            restorer.mouseEvent(.leftMouseDragged, point: movedPoint, time: 100.25)
            queue.sync {}
            XCTAssertEqual(window.current?.size, original.size, "older event \(older)")
        }
    }

    func testDisabledTapCancelsEvenWhenItsTimestampIsInvalid() {
        let queue = DispatchQueue(label: "restore-disabled-timestamp")
        let window = RestoreWindow(snapped)
        let restorer = makeRestorer(window, queue, now: { 100 })
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        queue.suspend()
        startDrag(restorer, window: window)
        restorer.mouseEvent(.tapDisabledByTimeout, point: .zero, time: 0)
        queue.resume(); queue.sync {}
        XCTAssertTrue(window.writes.isEmpty)
    }

    func testRepeatedDifferentSnapsAndSettlingResizesKeepFirstOriginal() {
        let queue = DispatchQueue(label: "restore-first-original")
        let window = RestoreWindow(snapped)
        let restorer = makeRestorer(window, queue)
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        for index in 1...4 {
            let before = window.current!
            let next = CGRect(x: 0, y: 30, width: 1100 + index * 100, height: 850 + index * 20)
            window.current = next
            restorer.changed(key); queue.sync {} // Neither resize nor move is a drag.
            restorer.didSnap(key: key, target: window, preSnap: before, accepted: next)
        }
        let beforeDrag = window.current!
        restorer.mouseEvent(.leftMouseDown, point: CGPoint(x: 400, y: 44))
        window.current = beforeDrag.offsetBy(dx: 40, dy: 12)
        restorer.mouseEvent(.leftMouseDragged, point: CGPoint(x: 440, y: 56)); queue.sync {}
        XCTAssertEqual(window.current?.size, original.size)
    }

    func testPositionOnlyFirstSnapDoesNotPoisonTheOriginalForTheFirstResize() {
        let queue = DispatchQueue(label: "restore-first-actual-resize")
        let window = RestoreWindow(snapped.offsetBy(dx: snapped.width, dy: 0))
        let restorer = makeRestorer(window, queue)
        restorer.didSnap(key: key, target: window, preSnap: snapped, accepted: window.current!)
        // A user (or Magnet) returns it to a free size before our first resize.
        window.current = snapped
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        startDrag(restorer, window: window); queue.sync {}
        XCTAssertEqual(window.current?.size, original.size)
    }

    func testDragAtOriginalSizeEndsTheCycleBeforeTheNextResize() {
        let queue = DispatchQueue(label: "restore-original-size-cycle")
        let window = RestoreWindow(snapped)
        let restorer = makeRestorer(window, queue)
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        let originalSized = CGRect(origin: snapped.origin, size: original.size)
        window.current = originalSized
        restorer.didSnap(key: key, target: window, preSnap: snapped, accepted: originalSized)
        restorer.mouseEvent(.leftMouseDown, point: CGPoint(x: 400, y: 44))
        window.current = originalSized.offsetBy(dx: 40, dy: 12)
        restorer.mouseEvent(.leftMouseDragged, point: CGPoint(x: 440, y: 56)); queue.sync {}
        XCTAssertTrue(window.writes.isEmpty)
        let nextOriginal = CGRect(x: 40, y: 42, width: 1000, height: 700)
        window.current = snapped
        restorer.didSnap(key: key, target: window, preSnap: nextOriginal, accepted: snapped)
        startDrag(restorer, window: window); queue.sync {}
        XCTAssertEqual(window.current?.size, nextOriginal.size)
    }

    func testNewSnapSupersedesQueuedDragWithoutLosingFirstSize() {
        let queue = DispatchQueue(label: "restore-stale")
        let window = RestoreWindow(snapped)
        let restorer = makeRestorer(window, queue)
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        queue.suspend(); startDrag(restorer, window: window)
        restorer.snapRequested()
        queue.resume(); queue.sync {}
        XCTAssertTrue(window.writes.isEmpty)
        let preSnap = window.current!
        window.current = snapped
        restorer.didSnap(key: key, target: window, preSnap: preSnap, accepted: snapped)
        startDrag(restorer, window: window); queue.sync {}
        XCTAssertEqual(window.current?.size, original.size)
    }

    func testLockPermissionAndClosedWindowCancelQueuedWork() {
        for action in 0..<3 {
            let queue = DispatchQueue(label: "restore-cancel")
            let window = RestoreWindow(snapped)
            var allowed = true
            let restorer = makeRestorer(window, queue)
            restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped,
                             inputAllowed: { allowed })
            queue.suspend(); startDrag(restorer, window: window)
            switch action {
            case 0: allowed = false
            case 1: restorer.cancelAll()
            default: restorer.changed(key, destroyed: true)
            }
            queue.resume(); queue.sync {}
            XCTAssertTrue(window.writes.isEmpty, "case \(action)")
        }
    }

    func testUnlockAndNormalSnapButtonReleaseKeepOriginalForNextDrag() {
        let queue = DispatchQueue(label: "restore-unlock")
        let window = RestoreWindow(snapped)
        var allowed = false
        let restorer = makeRestorer(window, queue)
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped,
                         inputAllowed: { allowed })
        WindowSnapController(restorer: restorer).cancel(source: .corsair)
        restorer.cancelAll()
        allowed = true
        startDrag(restorer, window: window); queue.sync {}
        XCTAssertEqual(window.current?.size, original.size)
    }

    func testSourceModeReleaseAfterMouseDownDoesNotCancelTheIndependentWindowDrag() {
        let queue = DispatchQueue(label: "restore-late-mode-release")
        let window = RestoreWindow(original)
        let restorer = makeRestorer(window, queue)
        let controller = WindowSnapController(access: RestoreAccess(window: window, key: key), restorer: restorer)
        let display = WindowSnapDisplay(id: "desktop", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
                                       visibleFrame: CGRect(x: 0, y: 30, width: 3440, height: 1410))
        XCTAssertEqual(controller.snap(.left, pid: 0, displays: [display], source: .wand), .moved(snapped))
        window.writes.removeAll()
        restorer.mouseEvent(.leftMouseDown, point: down)
        controller.cancel(source: .wand) // Same hook as mode exit / Magnet-wheel release.
        window.current = snapped.offsetBy(dx: 40, dy: 12)
        restorer.mouseEvent(.leftMouseDragged, point: movedPoint)
        queue.sync {}
        XCTAssertEqual(window.current?.size, original.size)
        XCTAssertEqual(window.writes, ["size"])
    }

    func testResizeAndProgrammaticMoveDoNotRestoreOrEraseOriginal() {
        let queue = DispatchQueue(label: "restore-nodrag")
        let window = RestoreWindow(snapped)
        let restorer = makeRestorer(window, queue)
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        window.current = snapped.offsetBy(dx: 50, dy: 20)
        window.current?.size.width -= 100
        restorer.changed(key); queue.sync {}
        XCTAssertTrue(window.writes.isEmpty)
        // A later real drag uses its current frame as the movement baseline,
        // while the saved size remains the one before the first custom snap.
        let beforeDrag = window.current!
        let point = CGPoint(x: beforeDrag.midX, y: beforeDrag.minY + 14)
        restorer.mouseEvent(.leftMouseDown, point: point)
        window.current = beforeDrag.offsetBy(dx: 40, dy: 12)
        restorer.mouseEvent(.leftMouseDragged, point: CGPoint(x: point.x + 40, y: point.y + 12)); queue.sync {}
        XCTAssertEqual(window.current?.size, original.size)
    }

    func testCornerResizeAndContentDragDoNotRestore() {
        for resize in [false, true] {
            let queue = DispatchQueue(label: "restore-not-window-drag")
            let window = RestoreWindow(snapped)
            let restorer = makeRestorer(window, queue)
            restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
            restorer.mouseEvent(.leftMouseDown, point: down)
            if resize {
                window.current?.origin.x += 40
                window.current?.size.width -= 40
            }
            restorer.mouseEvent(.leftMouseDragged, point: movedPoint); queue.sync {}
            XCTAssertTrue(window.writes.isEmpty)
        }
    }

    func testFrontWindowIdentityPreventsRestoringWindowUnderAnotherApp() {
        let queue = DispatchQueue(label: "restore-overlap")
        let window = RestoreWindow(snapped)
        var list = [WindowSnapPointerWindow(id: 991, pid: 0, frame: snapped)]
        let restorer = WindowSnapDragRestorer(queue: queue, windows: { list })
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        list.insert(WindowSnapPointerWindow(id: 1000, pid: 2, frame: snapped), at: 0)
        startDrag(restorer, window: window); queue.sync {}
        XCTAssertTrue(window.writes.isEmpty)
    }

    func testNewInputAndExpiredCompletedDragCannotRestoreLaterProgrammaticMove() {
        for cancel in [CGEventType.leftMouseDown, .rightMouseDown, .keyDown,
                       .tapDisabledByTimeout, .tapDisabledByUserInput] {
            let queue = DispatchQueue(label: "restore-new-input")
            let window = RestoreWindow(snapped)
            let restorer = makeRestorer(window, queue)
            restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
            queue.suspend(); startDrag(restorer, window: window, release: true)
            restorer.mouseEvent(cancel, point: .zero)
            queue.resume(); queue.sync {}
            XCTAssertTrue(window.writes.isEmpty)
        }
        let queue = DispatchQueue(label: "restore-expired")
        let window = RestoreWindow(snapped)
        var time: TimeInterval = 0
        let restorer = makeRestorer(window, queue, now: { time })
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        queue.suspend(); startDrag(restorer, window: window, release: true)
        time = 2
        queue.resume(); queue.sync {}
        XCTAssertTrue(window.writes.isEmpty)
    }

    func testFailedIgnoredOrCancelledSizeWriteDoesNotReportSuccess() {
        for action in 0..<3 {
            let queue = DispatchQueue(label: "restore-write")
            let window = RestoreWindow(snapped)
            let restorer = makeRestorer(window, queue)
            var count = 0
            restorer.onRestore = { _ in count += 1 }
            restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
            if action == 0 { window.allowSize = false }
            if action == 1 { window.ignoreSize = true }
            if action == 2 { window.onWrite = { restorer.cancelAll() } }
            startDrag(restorer, window: window); queue.sync {}
            XCTAssertEqual(count, 0)
            XCTAssertEqual(window.writes, ["size"])
        }
    }

    func testSuccessfulRestoreStartsANewOriginalOnTheNextSnap() {
        let queue = DispatchQueue(label: "restore-next-cycle")
        let window = RestoreWindow(snapped)
        let restorer = makeRestorer(window, queue)
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        startDrag(restorer, window: window); queue.sync {}
        let newOriginal = CGRect(x: 30, y: 70, width: 1000, height: 700)
        window.current = snapped
        restorer.didSnap(key: key, target: window, preSnap: newOriginal, accepted: snapped)
        startDrag(restorer, window: window); queue.sync {}
        XCTAssertEqual(window.current?.size, newOriginal.size)
    }
}
