import XCTest
@testable import AgenticMouseApp
import ScimitarKit

final class WindowResizeControllerTests: XCTestCase {
    private final class Target: WindowResizeTarget {
        var rect = CGRect(x: 100, y: 100, width: 800, height: 600)
        var writes = 0
        var minimumWidth: CGFloat = 0
        var bottomLimit: CGFloat = .infinity
        var enhanced = true
        var animationTransactions = 0
        var rejectWrite = false
        func withoutAnimation(_ operation: () -> CGRect?) -> CGRect? {
            let before = enhanced
            enhanced = false
            animationTransactions += 1
            defer { enhanced = before }
            return operation()
        }
        func frame() -> CGRect? { rect }
        func setSize(_ size: CGSize) -> Bool {
            XCTAssertFalse(enhanced)
            if rejectWrite { return false }
            rect.size = CGSize(width: max(minimumWidth, size.width), height: min(size.height, bottomLimit - rect.minY))
            writes += 1
            return true
        }
        func setPosition(_ point: CGPoint) -> Bool { rect.origin = point; writes += 1; return true }
    }
    private final class Access: WindowResizeAccess {
        let target = Target()
        var captures = 0
        func window(at point: CGPoint) -> WindowResizeTarget? { captures += 1; return target }
    }
    private let bounds = CGRect(x: 0, y: 0, width: 1600, height: 1200)

    func testHeldTargetStaysCapturedAndReleaseCancelsQueuedSteps() {
        let access = Access()
        let queue = DispatchQueue(label: "resize-test")
        let controller = WindowResizeController(access: access, queue: queue)
        controller.begin(source: .corsair, axis: .width, pointer: CGPoint(x: 300, y: 250), bounds: bounds)
        queue.sync {}
        controller.step(source: .corsair, grow: true)
        queue.sync {}
        XCTAssertEqual(access.target.rect, CGRect(x: 70, y: 100, width: 920, height: 600))
        controller.step(source: .corsair, grow: false)
        queue.sync {}
        XCTAssertEqual(access.target.rect, CGRect(x: 100, y: 100, width: 800, height: 600))
        XCTAssertEqual(access.captures, 1)
        queue.suspend()
        controller.step(source: .corsair, grow: true)
        controller.cancel(source: .corsair)
        queue.resume(); queue.sync {}
        XCTAssertEqual(access.target.writes, 6)
    }

    func testExternalResizeCancelsRatherThanDraggingWindowBack() {
        let access = Access(); let queue = DispatchQueue(label: "resize-test")
        let controller = WindowResizeController(access: access, queue: queue)
        controller.begin(source: .razer, axis: .height, pointer: CGPoint(x: 300, y: 250), bounds: bounds)
        queue.sync {}
        access.target.rect.origin.x += 100
        controller.step(source: .razer, grow: true)
        queue.sync {}
        controller.step(source: .razer, grow: true)
        queue.sync {}
        XCTAssertEqual(access.target.writes, 0)
    }

    func testGrowingHeightMovesBeforeRetryingScreenConstrainedSize() {
        let access = Access(); let queue = DispatchQueue(label: "resize-test")
        access.target.bottomLimit = 800
        let controller = WindowResizeController(access: access, queue: queue)
        controller.begin(source: .corsair, axis: .height, pointer: CGPoint(x: 300, y: 250), bounds: bounds)
        queue.sync {}
        controller.step(source: .corsair, grow: true)
        queue.sync {}
        XCTAssertEqual(access.target.rect, CGRect(x: 100, y: 70, width: 800, height: 720))
        XCTAssertTrue(access.target.enhanced)
        XCTAssertEqual(access.target.animationTransactions, 1)
    }

    func testFailedResizeRestoresAnimationState() {
        let access = Access(); let queue = DispatchQueue(label: "resize-test")
        access.target.rejectWrite = true
        let controller = WindowResizeController(access: access, queue: queue)
        controller.begin(source: .corsair, axis: .width, pointer: CGPoint(x: 300, y: 250), bounds: bounds)
        queue.sync {}
        controller.step(source: .corsair, grow: true)
        queue.sync {}
        XCTAssertTrue(access.target.enhanced)
        XCTAssertEqual(access.target.writes, 0)
    }

    func testClampedAppMinimumDoesNotCauseAnchorDrift() {
        let access = Access(); let queue = DispatchQueue(label: "resize-test")
        access.target.minimumWidth = 790
        let controller = WindowResizeController(access: access, queue: queue)
        controller.begin(source: .corsair, axis: .width, pointer: CGPoint(x: 300, y: 250), bounds: bounds)
        queue.sync {}
        for _ in 0..<4 { controller.step(source: .corsair, grow: false); queue.sync {} }
        XCTAssertEqual(access.target.rect.width, 790)
        XCTAssertEqual(access.target.rect.minX, 102.5)
    }
}
