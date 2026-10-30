import XCTest
import ApplicationServices
@testable import AgenticMouseApp
import ScimitarKit

final class ChromeVSCodeLayoutTests: XCTestCase {
    private final class Target: WindowResizeTarget {
        var rect = CGRect(x: 100, y: 100, width: 800, height: 600)
        var writes = 0
        var reject = false
        var animated = true
        func frame() -> CGRect? { rect }
        func setSize(_ size: CGSize) -> Bool {
            XCTAssertFalse(animated)
            guard !reject else { return false }
            rect.size = size; writes += 1; return true
        }
        func setPosition(_ point: CGPoint) -> Bool { rect.origin = point; writes += 1; return true }
        func withoutAnimation(_ operation: () -> CGRect?) -> CGRect? {
            animated = false; defer { animated = true }; return operation()
        }
    }
    private final class Access: ChromeVSCodeLayoutAccess {
        let code = Target(), chrome = Target()
        var missingCode = false
        var captures = 0
        func window(bundleID: String, on display: CGRect) -> WindowResizeTarget? {
            captures += 1
            return bundleID == "com.google.Chrome" ? chrome : (missingCode ? nil : code)
        }
    }
    private let display = ChromeVSCodeLayoutDisplay(uuid: "test",
        bounds: CGRect(x: -3440, y: -500, width: 3440, height: 1440),
        visibleFrame: CGRect(x: -3440, y: -470, width: 3440, height: 1410))

    func testBothDirectionsUseVisibleHalfFramesAndRestoreAnimation() {
        let access = Access(), queue = DispatchQueue(label: "layout-test")
        let controller = ChromeVSCodeLayoutController(access: access, queue: queue, allowed: { _, _ in true })
        for right in [true, false, true] {
            controller.request(source: .corsair, codeOnRight: right, display: display); queue.sync {}
            XCTAssertEqual(access.code.rect, display.frames(codeOnRight: right).code)
            XCTAssertEqual(access.chrome.rect, display.frames(codeOnRight: right).chrome)
            XCTAssertTrue(access.chrome.animated); XCTAssertTrue(access.code.animated)
        }
        let writes = access.chrome.writes + access.code.writes
        controller.request(source: .razer, codeOnRight: true, display: display); queue.sync {}
        XCTAssertEqual(access.chrome.writes + access.code.writes, writes, "Repeated direction is idempotent")
    }

    func testRapidRequestsKeepOnlyLatestLayout() {
        let access = Access(), queue = DispatchQueue(label: "layout-test")
        let controller = ChromeVSCodeLayoutController(access: access, queue: queue, allowed: { _, _ in true })
        queue.suspend()
        for i in 0..<101 { controller.request(source: .razer, codeOnRight: i % 2 == 0, display: display) }
        queue.resume(); queue.sync {}
        XCTAssertEqual(access.captures, 2)
        XCTAssertEqual(access.code.rect, display.frames(codeOnRight: true).code)
    }

    func testCancellationAndLockedSessionDoNotMoveWindows() {
        let access = Access(), queue = DispatchQueue(label: "layout-test")
        var allowed = true
        let controller = ChromeVSCodeLayoutController(access: access, queue: queue, allowed: { _, _ in allowed })
        queue.suspend()
        controller.request(source: .corsair, codeOnRight: true, display: display)
        controller.cancel(source: .corsair)
        queue.resume(); queue.sync {}
        allowed = false
        controller.request(source: .razer, codeOnRight: true, display: display); queue.sync {}
        XCTAssertEqual(access.captures, 0)
        XCTAssertEqual(access.code.writes + access.chrome.writes, 0)
    }

    func testMissingSecondWindowDoesNotMoveFirst() {
        let access = Access(), queue = DispatchQueue(label: "layout-test")
        access.missingCode = true
        let controller = ChromeVSCodeLayoutController(access: access, queue: queue, allowed: { _, _ in true })
        controller.request(source: .corsair, codeOnRight: true, display: display); queue.sync {}
        XCTAssertEqual(access.chrome.writes, 0)
    }

    func testSecondResizeFailureRestoresFirstWindow() {
        let access = Access(), queue = DispatchQueue(label: "layout-test")
        let original = access.code.rect
        access.chrome.reject = true
        let controller = ChromeVSCodeLayoutController(access: access, queue: queue, allowed: { _, _ in true })
        controller.request(source: .corsair, codeOnRight: true, display: display); queue.sync {}
        XCTAssertEqual(access.code.rect, original)
        XCTAssertTrue(access.chrome.animated); XCTAssertTrue(access.code.animated)
    }

    func testSpareCellIsExtraUtilitiesOnlyAndBothWheelDirectionsAreAccepted() {
        let control = WheelChordControl.chromeVSCodeLayout
        XCTAssertEqual(WheelChordControl.extraUtilitiesControl(for: PhysicalCell(rawValue: 6)!), control)
        XCTAssertNil(control.utilityCell); XCTAssertNil(control.topLevelCell)
        XCTAssertTrue(control.accepts(.up)); XCTAssertTrue(control.accepts(.down))
        XCTAssertNil(control.feedbackActionTitle(for: .up), "Only verified native frames produce feedback")
        for source in MouseSource.allCases {
            XCTAssertEqual(ModePickerCoordinator.extraUtilitiesLegend(for: source).first { $0.cell.rawValue == 6 }?.actionTitle,
                           "Split Chrome / VS Code")
            XCTAssertEqual(ModePickerCoordinator.extraUtilitiesLegend(for: source).first { $0.cell.rawValue == 6 }?.controlStatus,
                           .normal, "Ethan physically accepted Split after the monitor-role fix")
        }
    }

    func testRestoredWindowsWithIdenticalFramesSelectByTitle() {
        let frame = CGRect(x: 1720, y: 30, width: 1720, height: 1410)
        let windows: [ChromeVSCodeLayoutWindowMatcher.Candidate] = [
            .init(frame: frame, title: "Background project", isMain: false),
            .init(frame: frame, title: "Current project", isMain: true)
        ]
        XCTAssertEqual(ChromeVSCodeLayoutWindowMatcher.index(
            frame: frame, title: "Current project", candidates: windows), 1)
        XCTAssertEqual(ChromeVSCodeLayoutWindowMatcher.index(
            frame: frame, title: "Background project", candidates: windows), 0)
        XCTAssertEqual(ChromeVSCodeLayoutWindowMatcher.index(
            frame: frame, title: "", candidates: windows), 1,
            "Accessibility main window resolves hidden WindowServer titles")
        XCTAssertEqual(ChromeVSCodeLayoutWindowMatcher.index(
            frame: frame, title: "Stale browser tab title", candidates: windows), 1,
            "A nonempty stale/decorated title must not discard the main-window identity")
    }

    func testWindowMatchingDoesNotGuessBetweenUnidentifiedDuplicates() {
        let frame = CGRect(x: 0, y: 30, width: 1720, height: 1410)
        let windows: [ChromeVSCodeLayoutWindowMatcher.Candidate] = [
            .init(frame: frame, title: "Same title", isMain: false),
            .init(frame: frame, title: "Same title", isMain: false)
        ]
        XCTAssertNil(ChromeVSCodeLayoutWindowMatcher.index(frame: frame, title: "Same title", candidates: windows))
        XCTAssertNil(ChromeVSCodeLayoutWindowMatcher.index(frame: frame, title: "Changed title", candidates: windows))
        XCTAssertNil(ChromeVSCodeLayoutWindowMatcher.index(frame: frame.offsetBy(dx: 2000, dy: 0), title: "Same title", candidates: windows))
    }

    private func candidate(_ id: String, builtIn: Bool = false, main: Bool = false,
                           size: CGSize = CGSize(width: 3440, height: 1440)) -> ChromeVSCodeLayoutDisplay.Candidate {
        .init(display: .init(uuid: id, bounds: CGRect(origin: .zero, size: size),
                             visibleFrame: CGRect(origin: .zero, size: size)),
              isBuiltIn: builtIn, isMain: main)
    }

    func testMainExternalRoleSurvivesIdentityResolutionAndEnumerationChanges() {
        let secondary = candidate("secondary") // Equal dimensions must not override the role.
        XCTAssertEqual(ChromeVSCodeLayoutDisplay.resolve([
            secondary, candidate("old-id", main: true), candidate("laptop", builtIn: true)
        ])?.uuid, "old-id")
        XCTAssertEqual(ChromeVSCodeLayoutDisplay.resolve([
            candidate("laptop", builtIn: true), candidate("new-id", main: true,
                size: CGSize(width: 2560, height: 1080)), secondary
        ])?.uuid, "new-id")
    }

    func testLaptopMainUsesOnlyAnUnambiguousExternalAndNeverTheLaptop() {
        let laptop = candidate("laptop", builtIn: true, main: true)
        XCTAssertNil(ChromeVSCodeLayoutDisplay.resolve([laptop]))
        XCTAssertEqual(ChromeVSCodeLayoutDisplay.resolve([laptop, candidate("external")])?.uuid, "external")
        XCTAssertNil(ChromeVSCodeLayoutDisplay.resolve([laptop, candidate("a"), candidate("b")]))
        XCTAssertNil(ChromeVSCodeLayoutDisplay.resolve([candidate("a", main: true), candidate("b", main: true)]))
    }

    func testNativeLayoutRoundTripWhenExplicitlyRequested() throws {
        guard ProcessInfo.processInfo.environment["AGENTIC_LAYOUT_LIVE_PROBE"] == "1" else {
            throw XCTSkip("Requires an attended native-window test")
        }
        let display = try XCTUnwrap(ChromeVSCodeLayoutDisplay.current())
        let access = AccessibilityChromeVSCodeLayoutAccess(diagnostic: { print($0) })
        print("Layout probe: trusted=\(AXIsProcessTrusted()) display=\(display.bounds)")
        let code = try XCTUnwrap(access.window(bundleID: "com.microsoft.VSCode", on: display.bounds))
        let chrome = try XCTUnwrap(access.window(bundleID: "com.google.Chrome", on: display.bounds))
        let codeBefore = try XCTUnwrap(code.frame()), chromeBefore = try XCTUnwrap(chrome.frame())
        defer {
            for (target, frame) in [(code, codeBefore), (chrome, chromeBefore)] {
                _ = target.withoutAnimation {
                    guard target.setSize(frame.size), target.setPosition(frame.origin), target.setSize(frame.size)
                    else { return nil }
                    return target.frame()
                }
                XCTAssertEqual(target.frame(), frame, "Restore the user's exact original frame")
            }
        }
        let queue = DispatchQueue(label: "native-layout-probe")
        let controller = ChromeVSCodeLayoutController(access: access, queue: queue, allowed: { _, _ in true })
        for right in [false, true, false, true] {
            controller.request(source: .corsair, codeOnRight: right, display: display)
            queue.sync {}
            XCTAssertEqual(code.frame(), display.frames(codeOnRight: right).code)
            XCTAssertEqual(chrome.frame(), display.frames(codeOnRight: right).chrome)
        }
    }

    func testOddWidthHasNoGapOrOverlap() {
        let display = ChromeVSCodeLayoutDisplay(uuid: "test", bounds: .zero,
            visibleFrame: CGRect(x: 42, y: 32, width: 1729, height: 1000))
        let frames = display.frames(codeOnRight: true)
        XCTAssertEqual(frames.chrome.maxX, frames.code.minX)
        XCTAssertEqual(frames.code.maxX, display.visibleFrame.maxX)
        XCTAssertEqual(frames.chrome.width + frames.code.width, 1729)
    }
}
