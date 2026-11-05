// Verifies native command routing, monitor-hop memory and cancellation without
// writing window geometry or installing an original-size/drag listener.
import CoreGraphics
import XCTest
import ScimitarKit
@testable import AgenticMouseApp

private final class FakeNativeWindow: WindowResizeTarget {
    var current: CGRect
    var writes: [String] = []
    init(_ frame: CGRect) { current = frame }
    func frame() -> CGRect? { current }
    func setSize(_ size: CGSize) -> Bool { writes.append("size"); return false }
    func setPosition(_ point: CGPoint) -> Bool { writes.append("position"); return false }
}

private final class FakeNativeAccess: WindowSnapAccess {
    let window: FakeNativeWindow?
    var plans: [WindowSnapPlan] = []
    var allowed = true
    var isTiled = true
    var accepted: ((WindowSnapPlan) -> CGRect)?
    var onNativeSnap: (() -> Void)?
    init(_ window: FakeNativeWindow?) { self.window = window }
    func focusedWindow(pid: pid_t) -> (target: WindowResizeTarget, key: WindowSnapKey)? {
        window.map { ($0, WindowSnapKey(testID: 1)) }
    }
    func nativeWindowIsTiled(_ window: WindowSnapKey, permitted: () -> Bool) -> Bool { permitted() && isTiled }
    func snapNatively(_ side: WindowSnapDirection, window key: WindowSnapKey,
                      target: WindowResizeTarget, plan: WindowSnapPlan,
                      permitted: @escaping () -> Bool) -> CGRect? {
        guard permitted(), let window else { return nil }
        plans.append(plan)
        onNativeSnap?()
        guard allowed, permitted() else { return nil }
        window.current = accepted?(plan) ?? plan.frame
        return window.current
    }
}

final class WindowSnapControllerTests: XCTestCase {
    private let macbook = WindowSnapDisplay(id: "macbook", frame: CGRect(x: -1728, y: 612, width: 1728, height: 1117),
        visibleFrame: CGRect(x: -1728, y: 644, width: 1728, height: 1085), name: "Built-in Retina Display")
    private let ultrawide = WindowSnapDisplay(id: "ultrawide", frame: CGRect(x: 0, y: 0, width: 3440, height: 1440),
        visibleFrame: CGRect(x: 0, y: 30, width: 3440, height: 1410), name: "External")
    private let original = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testNativePlacementDoesNotWriteAccessibilityGeometry() {
        let window = FakeNativeWindow(original)
        let access = FakeNativeAccess(window)
        let controller = WindowSnapController(access: access)
        XCTAssertEqual(controller.snap(.left, pid: 1, displays: [ultrawide]), .moved(access.plans[0].frame))
        XCTAssertEqual(access.plans[0].side, .left)
        XCTAssertTrue(window.writes.isEmpty, "native tiling must own size, position and restoration")
    }

    func testRepeatedSideHopsToOppositeHalfUsingNativeAcceptedFrame() {
        let window = FakeNativeWindow(original)
        let access = FakeNativeAccess(window)
        // Native margins need not match our ideal half. Remember what macOS
        // accepted solely to recognize the next monitor-hop request.
        access.accepted = { $0.frame.insetBy(dx: 8, dy: 8) }
        let controller = WindowSnapController(access: access)
        guard case .moved = controller.snap(.left, pid: 1, displays: [ultrawide, macbook]),
              case .traversed = controller.snap(.left, pid: 1, displays: [ultrawide, macbook])
        else { return XCTFail("second Left should traverse using the accepted native frame") }
        XCTAssertEqual(access.plans.map(\.display.id), ["ultrawide", "macbook"])
        XCTAssertEqual(access.plans.map(\.side), [.left, .right])
        XCTAssertTrue(window.writes.isEmpty)
    }

    func testUnavailableNativeActionFailsWithoutCustomFallback() {
        let window = FakeNativeWindow(original)
        let access = FakeNativeAccess(window)
        access.allowed = false
        XCTAssertEqual(WindowSnapController(access: access).snap(.left, pid: 1, displays: [ultrawide]), .failed)
        XCTAssertEqual(window.current, original)
        XCTAssertTrue(window.writes.isEmpty)
    }

    func testSettledNativeMarginsStillPermitMonitorHopping() {
        let window = FakeNativeWindow(original)
        let access = FakeNativeAccess(window)
        access.accepted = { $0.frame.insetBy(dx: 8, dy: 8) }
        let controller = WindowSnapController(access: access)
        _ = controller.snap(.left, pid: 1, displays: [ultrawide, macbook])
        window.current.origin.x += 4
        guard case .traversed = controller.snap(.left, pid: 1, displays: [ultrawide, macbook])
        else { return XCTFail("native tiling state must reconcile the final animation frame") }
    }

    func testNormalManualResizeDoesNotAcquireNativeHopMemory() {
        let window = FakeNativeWindow(original)
        let access = FakeNativeAccess(window)
        access.accepted = { $0.frame.insetBy(dx: 8, dy: 8) }
        let controller = WindowSnapController(access: access)
        _ = controller.snap(.left, pid: 1, displays: [ultrawide, macbook])
        window.current.origin.x += 4
        access.isTiled = false
        guard case .moved = controller.snap(.left, pid: 1, displays: [ultrawide, macbook])
        else { return XCTFail("manual geometry changes must not pretend the window is natively tiled") }
    }

    func testPermissionLossStopsNativeTransaction() {
        let window = FakeNativeWindow(original)
        let access = FakeNativeAccess(window)
        let controller = WindowSnapController(access: access)
        XCTAssertEqual(controller.snap(.left, pid: 1, displays: [ultrawide], permitted: { false }), .cancelled)
        XCTAssertTrue(access.plans.isEmpty)
        var allowed = true
        access.onNativeSnap = { allowed = false }
        XCTAssertEqual(controller.snap(.left, pid: 1, displays: [ultrawide], permitted: { allowed }), .cancelled)
        XCTAssertEqual(window.current, original)
    }

    func testQueuedWorkIsCancelledPerSourceBeforeAccessibilityStarts() {
        let window = FakeNativeWindow(original)
        let access = FakeNativeAccess(window)
        let queue = DispatchQueue(label: "native-snap-cancel-test")
        let controller = WindowSnapController(access: access, queue: queue)
        var outcomes: [WindowSnapDirection] = []
        controller.onOutcome = { side, _ in outcomes.append(side) }
        queue.suspend()
        controller.enqueue(.left, pid: 1, displays: [ultrawide], source: .corsair, inputAllowed: { true })
        controller.enqueue(.right, pid: 1, displays: [ultrawide], source: .razer, inputAllowed: { true })
        controller.cancel(source: .corsair)
        queue.resume()
        queue.sync {}
        XCTAssertEqual(outcomes, [.right])
        queue.suspend()
        controller.enqueue(.left, pid: 1, displays: [ultrawide], source: .razer, inputAllowed: { true })
        controller.cancelAll()
        queue.resume()
        queue.sync {}
        XCTAssertEqual(outcomes, [.right])
    }

    func testReleaseFinishesStartedTransactionButGlobalTeardownStopsIt() {
        let window = FakeNativeWindow(original)
        let access = FakeNativeAccess(window)
        let queue = DispatchQueue(label: "native-snap-transaction-test")
        let controller = WindowSnapController(access: access, queue: queue)
        access.onNativeSnap = { controller.cancel(source: .corsair) }
        controller.enqueue(.left, pid: 1, displays: [ultrawide], source: .corsair, inputAllowed: { true })
        queue.sync {}
        XCTAssertEqual(window.current, WindowSnapGeometry.half(.left, of: ultrawide))
        access.onNativeSnap = { controller.cancelAll() }
        controller.enqueue(.right, pid: 1, displays: [ultrawide], source: .corsair, inputAllowed: { true })
        queue.sync {}
        XCTAssertEqual(window.current, WindowSnapGeometry.half(.left, of: ultrawide))
    }

    func testNoWindowAndOutermostEdgeHaveNoNativeSideEffect() {
        let absent = FakeNativeAccess(nil)
        XCTAssertEqual(WindowSnapController(access: absent).snap(.left, pid: 1, displays: [ultrawide]), .noWindow)
        let window = FakeNativeWindow(WindowSnapGeometry.half(.right, of: ultrawide))
        let access = FakeNativeAccess(window)
        XCTAssertEqual(WindowSnapController(access: access).snap(.right, pid: 1, displays: [ultrawide]), .unchanged)
        XCTAssertTrue(access.plans.isEmpty)
    }
}

final class NativeWindowSnapMenuTests: XCTestCase {
    private func item(_ id: String, _ title: String = "", enabled: Bool = true) -> NativeWindowSnapMenu.Item {
        .init(identifier: id, title: title, enabled: enabled)
    }

    func testDesktopCommandsCannotSelectFullScreenTile() {
        let items = [item("_tileLeft:", "Left"), item("_tileRight:", "Right"),
                     item("_zoomLeft:", "Links"), item("_zoomRight:", "Rechts")]
        XCTAssertEqual(NativeWindowSnapMenu.commands(side: .left, movingTo: nil, items: items), [.tile(.left)])
        XCTAssertEqual(NativeWindowSnapMenu.index(of: .tile(.left), in: items), 2)
        XCTAssertNil(NativeWindowSnapMenu.index(of: .tile(.left), in: Array(items.prefix(2))))
    }

    func testMonitorHopRestoresBeforeMovingAndRetiling() {
        let items = [item("_zoomRight:"), item("_zoomUntile:"), item("_moveToDisplay:", "Déplacer vers External")]
        XCTAssertEqual(NativeWindowSnapMenu.commands(side: .right, movingTo: "External", items: items),
                       [.restore, .move("External"), .tile(.right)])
    }

    func testUntiledWindowMovesWithoutInventingRestoreState() {
        let items = [item("_zoomLeft:"), item("_zoomUntile:", enabled: false),
                     item("_moveToDisplay:", "Move to External")]
        XCTAssertEqual(NativeWindowSnapMenu.commands(side: .left, movingTo: "External", items: items),
                       [.move("External"), .tile(.left)])
    }

    func testUnavailableAndAmbiguousActionsFailBeforeAnyCommand() {
        XCTAssertNil(NativeWindowSnapMenu.commands(side: .left, movingTo: nil,
            items: [item("_zoomLeft:", enabled: false)]))
        XCTAssertNil(NativeWindowSnapMenu.commands(side: .left, movingTo: nil,
            items: [item("_zoomLeft:"), item("_zoomLeft:")]))
        let items = [item("_zoomLeft:"), item("_zoomUntile:"), item("_moveToDisplay:", "Move to Other")]
        XCTAssertNil(NativeWindowSnapMenu.commands(side: .left, movingTo: "External", items: items))
        XCTAssertNil(NativeWindowSnapMenu.commands(side: .left, movingTo: "", items: items))
    }

    func testDuplicateDisplayNamesCannotSelectTheWrongMonitor() {
        let items = [item("_zoomLeft:"), item("_moveToDisplay:", "Move to Display"),
                     item("_moveToDisplay:", "Move to Built-in Display")]
        XCTAssertNil(NativeWindowSnapMenu.commands(side: .left, movingTo: "Display", items: items))
    }
}
