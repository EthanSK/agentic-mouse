import XCTest
@testable import ScimitarKit

/// The receiver sends a final cumulative motion, park, then a fresh choose ID.
/// Test those real wire phases, including Utility (home and Utility share .modes).
final class WandReceiverReleaseContractTests: XCTestCase {
    func testHeldReleaseUsesEveryOrdinaryHomeActionOnce() throws {
        for cell in [PhysicalCell.wandPlayPause, PhysicalCell(rawValue: 5)!,
                     PhysicalCell(rawValue: 7)!, PhysicalCell(rawValue: 8)!] {
            let fixture = Fixture()
            fixture.select(cell)
            XCTAssertEqual(fixture.actions, [cell])
            // Ethan (2026-10-30): an action never dismisses the HUD.
            XCTAssertTrue(fixture.control.isOpen)
            fixture.chooseAgain()
            XCTAssertEqual(fixture.actions, [cell], "a repeated terminal command never acts twice")
        }
    }

    func testHeldReleaseOpensEachHomeSubmenuAndRetainsIt() throws {
        for (raw, page) in [(2, ModePickerPage.appSpecific), (9, .keys), (12, .modes)] {
            let fixture = Fixture()
            fixture.select(PhysicalCell(rawValue: raw)!)
            XCTAssertTrue(fixture.control.isOpen)
            XCTAssertEqual(fixture.target.page, page)
            XCTAssertFalse(fixture.target.isWandHome)
            let generation = fixture.target.pageGeneration
            fixture.chooseAgain()
            XCTAssertEqual(fixture.target.pageGeneration, generation)
            XCTAssertEqual(fixture.target.page, page)
            XCTAssertTrue(fixture.actions.isEmpty)
        }
    }

    func testASequenceOneChooseHasItsOwnIdentityAfterHighSequenceNavigation() {
        let fixture = Fixture()
        fixture.select(PhysicalCell(rawValue: 12)!, finalSequence: 900)
        XCTAssertTrue(fixture.control.isOpen)
        XCTAssertFalse(fixture.target.isWandHome)
        XCTAssertEqual(fixture.target.page, .modes)
    }

    private final class Fixture {
        let clock = ManualClock(now: 100)
        let tick = ManualTickScheduler()
        let target: ModePickerCoordinator
        let control: WandPersistentController
        var actions: [PhysicalCell] = []
        let chooseID = UUID().uuidString

        init() {
            target = ModePickerCoordinator(lease: WandModeLease(), hud: RecordingModeHUDPresenter(),
                scheduler: ManualTickScheduler(), log: Log(category: "test", sink: NullLogSink()))
            target.resolveFrontmostApp = {
                FrontmostAppModeContext(target: .chrome, displayName: "Chrome", bundleIdentifier: "com.google.Chrome")
            }
            control = WandPersistentController(target: target, scheduler: tick, clock: clock)
            target.onWandHomeInput = { [unowned self] in actions.append($0); return true }
        }

        func send(_ phase: String, id: String, sequence: Int, x: Double = 0, y: Double = 0) {
            let wire: [String: Any] = ["command": "agentic_mouse_wand_control", "version": 1,
                "phase": phase, "id": id, "seq": sequence, "x": x, "y": y]
            let data = try! JSONSerialization.data(withJSONObject: wire)
            control.handle(try! WandPersistentCommand.decodeIfPresent(data)!)
        }

        func select(_ cell: PhysicalCell, finalSequence: Int = 3) {
            let id = UUID().uuidString
            send("open", id: UUID().uuidString, sequence: 1)
            send("navigate", id: id, sequence: 1)
            send("qualify", id: id, sequence: 2)
            let point = WandRadialNavigator.restingPosition(of: cell, in: target.wandRadialLayout)
            send("motion", id: id, sequence: finalSequence, x: point.x, y: point.y)
            XCTAssertEqual(control.focusedCell, cell)
            send("motion", id: id, sequence: finalSequence + 1, x: point.x, y: point.y)
            send("park", id: id, sequence: finalSequence + 2)
            chooseAgain()
        }

        func chooseAgain() { send("choose", id: chooseID, sequence: 1) }
    }
}
