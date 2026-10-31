import CoreGraphics
import XCTest
import ScimitarKit
@testable import AgenticMouseApp

private final class RestoreWindow: WindowResizeTarget {
    var current: CGRect?
    var writes: [String] = []
    var allowSize = true
    var ignorePosition = false
    var onWrite: (() -> Void)?
    init(_ current: CGRect) { self.current = current }
    func frame() -> CGRect? { current }
    func setSize(_ size: CGSize) -> Bool {
        writes.append("size"); onWrite?()
        guard allowSize else { return false }
        current?.size = size; return true
    }
    func setPosition(_ position: CGPoint) -> Bool {
        writes.append("position"); onWrite?()
        if !ignorePosition { current?.origin = position }
        return true
    }
}

final class WindowSnapDragRestorerTests: XCTestCase {
    private let key = WindowSnapKey(testID: 991)
    private let original = CGRect(x: 600, y: 200, width: 800, height: 600)
    private let snapped = CGRect(x: 0, y: 30, width: 1720, height: 1410)

    func testImmediateDragRestoresOnceAndKeepsPointerFraction() {
        let queue = DispatchQueue(label: "restore-test")
        let restorer = WindowSnapDragRestorer(queue: queue, dragging: { true }, pointer: { CGPoint(x: 900, y: 40) })
        let window = RestoreWindow(snapped)
        var restored: [CGRect] = []
        restorer.onRestore = { restored.append($0) }
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        window.current = snapped.offsetBy(dx: 40, dy: 0)
        queue.suspend(); restorer.changed(key); restorer.changed(key); queue.resume(); queue.sync {}
        XCTAssertEqual(restored, [CGRect(x: 500, y: 30, width: 800, height: 600)])
        restorer.changed(key); queue.sync {}
        XCTAssertEqual(window.writes, ["size", "position"])
    }

    func testRepeatedSnapsAndMonitorHopsKeepFirstOriginal() {
        let queue = DispatchQueue(label: "restore-hops")
        let restorer = WindowSnapDragRestorer(queue: queue, dragging: { true }, pointer: { CGPoint(x: -400, y: 660) })
        let window = RestoreWindow(snapped)
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        let hopped = CGRect(x: -864, y: 644, width: 864, height: 1085)
        restorer.didSnap(key: key, target: window, preSnap: snapped, accepted: hopped)
        window.current = hopped.offsetBy(dx: 40, dy: 0)
        restorer.changed(key); queue.sync {}
        XCTAssertEqual(window.current?.size, original.size)
    }

    func testQueuedRestoreCannotOverwriteNewSnapOrNewEntry() {
        for newEntry in [false, true] {
            let queue = DispatchQueue(label: "restore-stale")
            let restorer = WindowSnapDragRestorer(queue: queue, dragging: { true })
            let window = RestoreWindow(snapped)
            restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
            window.current = snapped.offsetBy(dx: 40, dy: 0)
            queue.suspend(); restorer.changed(key)
            if newEntry {
                restorer.didSnap(key: key, target: window, preSnap: snapped, accepted: snapped)
            } else { restorer.snapRequested() }
            queue.resume(); queue.sync {}
            XCTAssertTrue(window.writes.isEmpty)
        }
    }

    func testReleasePermissionLossShutdownAndSourceCancelBeforeQueuedWork() {
        for action in 0..<5 {
            let queue = DispatchQueue(label: "restore-cancel")
            var held = true; var allowed = true
            let restorer = WindowSnapDragRestorer(queue: queue, dragging: { held })
            let window = RestoreWindow(snapped)
            restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped,
                             source: .corsair, inputAllowed: { allowed })
            window.current = snapped.offsetBy(dx: 40, dy: 0)
            queue.suspend(); restorer.changed(key)
            switch action {
            case 0: held = false
            case 1: allowed = false
            case 2: restorer.cancelAll()
            case 3: restorer.cancel(source: .corsair)
            default: restorer.changed(key, destroyed: true)
            }
            queue.resume(); queue.sync {}
            XCTAssertTrue(window.writes.isEmpty, "case \(action)")
        }
    }

    func testOtherSourceCancelDoesNotCancelRestoreAndNormalReleaseKeepsMemory() {
        let queue = DispatchQueue(label: "restore-source")
        let restorer = WindowSnapDragRestorer(queue: queue, dragging: { true })
        let window = RestoreWindow(snapped)
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped, source: .corsair)
        restorer.cancel(source: .corsair) // Releasing the snapping button must keep the remembered size.
        window.current = snapped.offsetBy(dx: 40, dy: 0)
        queue.suspend(); restorer.changed(key); restorer.cancel(source: .razer); queue.resume(); queue.sync {}
        XCTAssertEqual(window.current?.size, original.size)
    }

    func testResizeWithoutMoveForgetsBeforeLaterDrag() {
        let queue = DispatchQueue(label: "restore-resize")
        let restorer = WindowSnapDragRestorer(queue: queue, dragging: { false })
        let window = RestoreWindow(snapped)
        restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
        window.current?.size.width -= 100
        restorer.changed(key); queue.sync {}
        window.current = snapped.offsetBy(dx: 40, dy: 0)
        restorer.changed(key); queue.sync {}
        XCTAssertTrue(window.writes.isEmpty)
    }

    func testFailedOrIgnoredWritesDoNotReportSuccessAndCancellationStopsSecondWrite() {
        for action in 0..<3 {
            let queue = DispatchQueue(label: "restore-write")
            let restorer = WindowSnapDragRestorer(queue: queue, dragging: { true }, pointer: { CGPoint(x: 900, y: 40) })
            let window = RestoreWindow(snapped)
            var count = 0; restorer.onRestore = { _ in count += 1 }
            restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
            window.current = snapped.offsetBy(dx: 40, dy: 0)
            if action == 0 { window.allowSize = false }
            if action == 1 { window.ignorePosition = true }
            if action == 2 { window.onWrite = { restorer.cancelAll() } }
            restorer.changed(key); queue.sync {}
            XCTAssertEqual(count, 0)
            if action != 1 { XCTAssertEqual(window.writes, ["size"]) }
        }
    }

    func testClosedOrProgrammaticallyMovedWindowDoesNotRestore() {
        for closed in [false, true] {
            let queue = DispatchQueue(label: "restore-nodrag")
            let restorer = WindowSnapDragRestorer(queue: queue, dragging: { false })
            let window = RestoreWindow(snapped)
            restorer.didSnap(key: key, target: window, preSnap: original, accepted: snapped)
            window.current = closed ? nil : snapped.offsetBy(dx: 40, dy: 0)
            restorer.changed(key); queue.sync {}
            XCTAssertTrue(window.writes.isEmpty)
        }
    }
}
