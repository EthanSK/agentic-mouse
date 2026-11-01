import XCTest
@testable import ScimitarKit

/// Ethan (2026-11-01): "I'm in utility mode and then I like move it slowly
/// over to the right. And then it jumps straight to keys mode instead of
/// chrome mode. It just skips one", and "make the animation of the liquid
/// outline thing not let me do it in any direction, but rather towards an
/// actual valid wedge so I can actually aim it while it's like midway
/// through committing that movement."
///
/// Motion is receiver-shaped: one sample per 30 ms, a slow sideways turn of
/// about 13°/s with the tip sagging about 3°/s, plus a small deterministic
/// hand tremor. A sideways turn moves the virtual stick in a straight line,
/// so between two top cards it cuts inside the ring.
final class WandSlowAimingTests: XCTestCase {
    private let tuning = WandRadialTuning()
    private var seed: UInt64 = 0x51DE_7A11

    private func coordinator(_ frontmost: AppSpecificTarget?, open: [Int] = []) -> ModePickerCoordinator {
        let coordinator = ModePickerCoordinator(lease: WandModeLease(), hud: RecordingModeHUDPresenter(),
                                                scheduler: ManualTickScheduler(), log: Log(category: "test", sink: NullLogSink()))
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(target: frontmost, displayName: frontmost?.displayName ?? "Finder",
                                    bundleIdentifier: frontmost?.bundleIdentifier)
        }
        coordinator.enterWandHome(source: .wand, pointerFocus: ModeHUDPointerFocus(cell: .switchApp))
        for raw in open {
            let cell = PhysicalCell(rawValue: raw)!
            coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .press))
            coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .release))
        }
        return coordinator
    }

    /// About ±0.03° per axis per sample.
    private func tremor() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return (Double(seed >> 11) / Double(1 << 53) - 0.5) * 0.06
    }

    private struct Run {
        var visited: [PhysicalCell]
        var samples: [PhysicalCell: Int] = [:]
        var smallestRadius = Double.infinity
    }

    /// `count` samples of (dx, dy) degrees each, plus tremor. Records every
    /// card the outline shows and how many samples it stays on each.
    @discardableResult
    private func drive(_ nav: inout WandRadialNavigator, dx: Double, dy: Double, samples count: Int, tremble: Bool = true) -> Run {
        var run = Run(visited: [nav.focusedCell])
        for _ in 0..<count {
            nav.apply(deltaX: dx + (tremble ? tremor() : 0), deltaY: dy + (tremble ? tremor() : 0))
            run.smallestRadius = min(run.smallestRadius, hypot(nav.positionX, nav.positionY))
            run.samples[nav.focusedCell, default: 0] += 1
            if run.visited.last != nav.focusedCell { run.visited.append(nav.focusedCell) }
        }
        return run
    }

    // MARK: Ethan's skipped card

    func testASlowLeftTurnFromUtilityShowsTheAppCardBeforeKeys() {
        for frontmost in [AppSpecificTarget.chrome, .vsCode] {
            let layout = coordinator(frontmost).wandRadialLayout
            var nav = WandRadialNavigator(layout: layout, start: .modePickerEntry)!
            let run = drive(&nav, dx: -0.4, dy: 0.09, samples: 17)
            XCTAssertLessThan(run.smallestRadius, tuning.reachDegrees,
                              "\(frontmost): the turn cuts inside the ring, where the card used to freeze")
            XCTAssertGreaterThan(run.smallestRadius, tuning.centerReturnDegrees, "\(frontmost): never back to the centre")
            XCTAssertEqual(run.visited, [.modePickerEntry, .frontmostAppModeSelector, .keysModeEntry],
                           "\(frontmost): Utility, then the app card, then Keys")
            XCTAssertGreaterThanOrEqual(run.samples[.frontmostAppModeSelector] ?? 0, 4,
                                        "\(frontmost): the app card stays long enough to stop on")
        }
    }

    func testTurningBackRetracesTheSameCards() {
        let layout = coordinator(.chrome).wandRadialLayout
        var nav = WandRadialNavigator(layout: layout, start: .modePickerEntry)!
        drive(&nav, dx: -0.4, dy: 0.09, samples: 17)
        XCTAssertEqual(nav.focusedCell, .keysModeEntry)
        let back = drive(&nav, dx: 0.4, dy: -0.09, samples: 17)
        XCTAssertEqual(back.visited, [.keysModeEntry, .frontmostAppModeSelector, .modePickerEntry])
        XCTAssertGreaterThanOrEqual(back.samples[.frontmostAppModeSelector] ?? 0, 4)
    }

    func testStoppingOnTheAppCardKeepsIt() {
        let layout = coordinator(.chrome).wandRadialLayout
        var nav = WandRadialNavigator(layout: layout, start: .modePickerEntry)!
        var turned = 0
        while nav.focusedCell != .frontmostAppModeSelector, turned < 30 {
            nav.apply(deltaX: -0.4 + tremor(), deltaY: 0.09 + tremor())
            turned += 1
        }
        XCTAssertEqual(nav.focusedCell, .frontmostAppModeSelector)
        let still = drive(&nav, dx: 0, dy: 0, samples: 60)
        XCTAssertEqual(still.visited, [.frontmostAppModeSelector], "a held-still wand stays where it stopped")
    }

    func testASlowLeftTurnOnTheUtilityPageShowsTheAppCardBeforeKeys() {
        let layout = coordinator(.chrome, open: [12]).wandRadialLayout
        XCTAssertEqual(layout.ring.first, .extraUtilitiesSelector)
        XCTAssertEqual(layout.ring.last, .appSpecificModeSelector)
        var nav = WandRadialNavigator(layout: layout, start: .extraUtilitiesSelector)!
        let run = drive(&nav, dx: -0.4, dy: 0.09, samples: 18)
        XCTAssertLessThan(run.smallestRadius, tuning.reachDegrees)
        XCTAssertEqual(run.visited, [.extraUtilitiesSelector, .appSpecificModeSelector, .keysModeSelector])
        XCTAssertGreaterThanOrEqual(run.samples[.appSpecificModeSelector] ?? 0, 4)
    }

    func testASlowLeftTurnOnTheCodexPageShowsTheTopCard() {
        let layout = coordinator(.codex, open: [2]).wandRadialLayout
        let count = layout.ring.count
        var nav = WandRadialNavigator(layout: layout, start: layout.ring[0])!
        let run = drive(&nav, dx: -0.4, dy: 0.09, samples: 20)
        XCTAssertLessThan(run.smallestRadius, tuning.reachDegrees)
        XCTAssertEqual(run.visited, [layout.ring[0], layout.ring[count - 1], layout.ring[count - 2]])
    }

    /// The general rule behind Ethan's report, on every page shape the wand
    /// shows: slow motion in any direction, from any card, steps between
    /// neighbouring cards. It may pass through the centre, never over a card.
    func testSlowMotionInAnyDirectionNeverSkipsACard() {
        let pages: [(String, WandRadialLayout)] = [
            ("home with Chrome", coordinator(.chrome).wandRadialLayout),
            ("home with VS Code", coordinator(.vsCode).wandRadialLayout),
            ("Utility", coordinator(.chrome, open: [12]).wandRadialLayout),
            ("Keys", coordinator(.chrome, open: [9]).wandRadialLayout),
            ("Codex", coordinator(.codex, open: [2]).wandRadialLayout),
        ]
        for (name, layout) in pages {
            let count = layout.ring.count
            XCTAssertGreaterThan(count, 2, name)
            func ringPosition(_ cell: PhysicalCell) -> Int? {
                if let index = layout.ringIndex(of: cell) { return index }
                if let outer = layout.outerIndex(of: cell) { return layout.parentRingIndex(ofOuter: outer) }
                return nil // the centre
            }
            for start in (layout.center.map { [$0] } ?? []) + layout.ring {
                for heading in stride(from: 0.0, to: 360, by: 30) {
                    for sag in [-0.08, 0.08] {
                        let radians = heading * .pi / 180
                        let along = (x: sin(radians), y: -cos(radians)), across = (x: cos(radians), y: sin(radians))
                        var nav = WandRadialNavigator(layout: layout, start: start)!
                        let run = drive(&nav, dx: along.x * 0.4 + across.x * sag, dy: along.y * 0.4 + across.y * sag, samples: 45)
                        for (from, to) in zip(run.visited, run.visited.dropFirst()) {
                            guard let a = ringPosition(from), let b = ringPosition(to) else { continue }
                            let apart = min((a - b + count) % count, (b - a + count) % count)
                            XCTAssertLessThanOrEqual(apart, 1, "\(name): from \(start) at \(heading)° skipped \(from) → \(to) in \(run.visited)")
                        }
                    }
                }
            }
        }
    }

    // MARK: The outline shows the card the wand is heading for

    func testTheCentreLeansOnlyAtTheCardTheReachWillChoose() throws {
        let layout = coordinator(.chrome).wandRadialLayout
        var nav = WandRadialNavigator(layout: layout, start: .switchApp)!
        // Up toward 8°, bending right toward 40°, then straight up: the
        // reach finally happens at about 17°, just past the app card's own
        // sector but inside its edge hysteresis.
        let path = Array(repeating: 8.0, count: 8) + Array(repeating: 40.0, count: 5) + Array(repeating: 0.0, count: 4)
        var shown: PhysicalCell?
        var stickBeforeReach = 0.0
        for heading in path {
            let radians = heading * .pi / 180
            nav.apply(deltaX: sin(radians) * 0.4, deltaY: -cos(radians) * 0.4)
            let focus = nav.pointerFocus
            guard focus.cell == .switchApp else {
                XCTAssertEqual(focus.cell, shown, "the reach chose the card the outline was leaning at")
                break
            }
            guard let aim = focus.aim else {
                // Right at the middle the angle is tremor: no lean at all.
                XCTAssertLessThan(hypot(nav.positionX, nav.positionY), tuning.centerReturnDegrees * WandRadialNavigator.aimFloor)
                XCTAssertEqual(focus.pullX, 0)
                XCTAssertEqual(focus.pullY, 0)
                continue
            }
            let direction = layout.direction(at: try XCTUnwrap(layout.ringIndex(of: aim)))
            XCTAssertEqual(focus.pullX * direction.y - focus.pullY * direction.x, 0, accuracy: 1e-9,
                           "leans straight at \(aim), never into the gap between two cards")
            XCTAssertGreaterThan(focus.pullX * direction.x + focus.pullY * direction.y, 0)
            shown = aim
            stickBeforeReach = WandRadialLayout.angle(x: nav.positionX, y: nav.positionY) * 180 / .pi
        }
        XCTAssertGreaterThan(stickBeforeReach, 15, "the raw stick was already past the app card's sector")
        XCTAssertEqual(nav.focusedCell, .frontmostAppModeSelector, "yet the wand chose what it showed")

        var decisive = WandRadialNavigator(layout: layout, start: .switchApp)!
        let utility = 30 * Double.pi / 180 - 0.05
        for _ in 0..<4 { decisive.apply(deltaX: sin(utility) * 0.8, deltaY: -cos(utility) * 0.8) }
        XCTAssertEqual(decisive.pointerFocus.aim, .modePickerEntry, "pointing clearly at Utility aims at Utility")
        decisive.apply(deltaX: sin(utility) * 3, deltaY: -cos(utility) * 3)
        XCTAssertEqual(decisive.focusedCell, .modePickerEntry)
    }

    func testTremorOnABoundaryAtTheCentreNeverFlickersTheAim() {
        let layout = coordinator(.chrome).wandRadialLayout
        var nav = WandRadialNavigator(layout: layout, start: .switchApp)!
        let boundary = 15 * Double.pi / 180, radius = 3.5
        var aims: [PhysicalCell] = []
        for _ in 0..<200 {
            let x = sin(boundary) * radius + tremor() * 5, y = -cos(boundary) * radius + tremor() * 5 // ±0.15°
            nav.apply(deltaX: x - nav.positionX, deltaY: y - nav.positionY)
            XCTAssertEqual(nav.focusedCell, .switchApp)
            if let aim = nav.pointerFocus.aim, aims.last != aim { aims.append(aim) }
        }
        XCTAssertEqual(aims.count, 1, "one aim, never flickering between the two cards: \(aims)")
    }

    func testReturningToTheCentreKeepsAimingAtTheCardItLeft() {
        let layout = coordinator(.chrome).wandRadialLayout
        let index = layout.ringIndex(of: .modePickerEntry)!
        let outward = layout.direction(at: index)
        var nav = WandRadialNavigator(layout: layout, start: .modePickerEntry)!
        for _ in 0..<26 { nav.apply(deltaX: -outward.x * 0.25, deltaY: -outward.y * 0.25) } // to 0.5° short of the middle
        XCTAssertEqual(nav.focusedCell, .switchApp)
        XCTAssertEqual(nav.pointerFocus.aim, .modePickerEntry, "the return keeps aiming at Utility, the card it left")
        // On through the middle and out the far side: the aim follows once
        // the angle means something, but aiming is not choosing.
        for _ in 0..<12 { nav.apply(deltaX: -outward.x * 0.25, deltaY: -outward.y * 0.25) }
        XCTAssertEqual(nav.pointerFocus.aim, layout.ring[(index + layout.ring.count / 2) % layout.ring.count])
        XCTAssertEqual(nav.focusedCell, .switchApp)
    }

    /// On a ring card the lean favours whichever card is closer to taking
    /// over, so a sagging sideways turn reads as travel to the neighbour and
    /// a wobbling return reads as a return.
    func testTheRingLeanPointsAtTheCardTheWandIsHeadingFor() {
        let layout = coordinator(.chrome, open: [12]).wandRadialLayout
        let start = layout.ringIndex(of: .extraUtilitiesSelector)!
        let angle = layout.angle(at: start)
        let outward = (x: sin(angle), y: -cos(angle)), clockwise = (x: cos(angle), y: sin(angle))
        func parts(_ focus: ModeHUDPointerFocus) -> (along: Double, inward: Double) {
            (focus.pullX * clockwise.x + focus.pullY * clockwise.y, -(focus.pullX * outward.x + focus.pullY * outward.y))
        }
        var nav = WandRadialNavigator(layout: layout, start: .extraUtilitiesSelector)!
        var last = nav.pointerFocus
        var deepest = Double.infinity
        for _ in 0..<30 {
            nav.apply(deltaX: -0.4, deltaY: 0.09)
            guard nav.focusedCell == .extraUtilitiesSelector else { break }
            last = nav.pointerFocus
            deepest = min(deepest, hypot(nav.positionX, nav.positionY))
        }
        XCTAssertEqual(nav.focusedCell, .appSpecificModeSelector)
        XCTAssertLessThan(deepest, tuning.reachDegrees, "the stick was drifting toward the centre")
        let sideways = parts(last)
        XCTAssertLessThan(sideways.along, -0.7, "just before the switch it leans hard toward the app card")
        XCTAssertLessThan(abs(sideways.inward), abs(sideways.along) * 0.1, "not toward the centre it drifted toward")

        var returning = WandRadialNavigator(layout: layout, start: .extraUtilitiesSelector)!
        returning.apply(deltaX: -outward.x * 3 + clockwise.x * 0.4, deltaY: -outward.y * 3 + clockwise.y * 0.4)
        XCTAssertEqual(returning.focusedCell, .extraUtilitiesSelector)
        let home = parts(returning.pointerFocus)
        XCTAssertGreaterThan(home.inward, 0.4, "a return leans home")
        XCTAssertLessThan(abs(home.along), home.inward * 0.3, "its small wobble barely leans sideways")
    }

    // Advancing toward both the inward and sideways boundaries must not make
    // the preview shrink back onto the selected card just before it commits.
    func testDiagonalApproachDoesNotHideProgressNearTheBoundary() {
        var previous = 0.0
        for step in 0...99 {
            let amount = Double(step) / 100
            let lean = WandRadialNavigator.guided(along: amount, inward: amount)
            let visible = max(abs(lean.along), abs(lean.inward))
            XCTAssertGreaterThanOrEqual(visible + 1e-9, previous)
            previous = visible
        }
        XCTAssertGreaterThan(previous, 0.9)
        let completed = WandRadialNavigator.guided(along: 1, inward: 1)
        XCTAssertEqual(completed.along, 0)
        XCTAssertEqual(completed.inward, 1)
    }

    func testGuidedLeanIsContinuousAndPointsOnlyAtTheSwitchingCard() {
        XCTAssertEqual(WandRadialNavigator.guided(along: 1, inward: 0.4).inward, 0, "switching sideways: no inward lean")
        XCTAssertEqual(WandRadialNavigator.guided(along: 0.3, inward: 1).along, 0, "returning: no sideways lean")
        XCTAssertEqual(WandRadialNavigator.guided(along: -1, inward: -0.5).inward, 0, "the outward lean yields too")
        let lean = WandRadialNavigator.guided(along: 0.6, inward: 0)
        XCTAssertEqual(lean.along, 0.6, accuracy: 1e-12, "a lone lean is unchanged")
        // Small input changes make small lean changes: no jump.
        var previous = WandRadialNavigator.guided(along: 0, inward: 1)
        for step in 1...100 {
            let t = Double(step) / 100
            let next = WandRadialNavigator.guided(along: t, inward: 1 - t)
            XCTAssertLessThan(abs(next.along - previous.along) + abs(next.inward - previous.inward), 0.05)
            previous = next
        }
    }
}

/// The same report through the receiver's own commands: an unheld `hover`
/// stream carries cumulative offsets, and the held release uses the card the
/// outline stopped on.
final class WandSlowAimingControllerTests: XCTestCase {
    private var clock: ManualClock!
    private var tick: ManualTickScheduler!
    private var target: ModePickerCoordinator!
    private var control: WandPersistentController!
    private var homeActions: [PhysicalCell] = []

    override func setUp() {
        super.setUp()
        clock = ManualClock(now: 100)
        tick = ManualTickScheduler()
        target = ModePickerCoordinator(lease: WandModeLease(), hud: RecordingModeHUDPresenter(), scheduler: ManualTickScheduler(),
                                       log: Log(category: "test", sink: NullLogSink()))
        target.resolveFrontmostApp = {
            FrontmostAppModeContext(target: .chrome, displayName: "Chrome", bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier)
        }
        target.onWandHomeInput = { [unowned self] cell in homeActions.append(cell); return true }
        control = WandPersistentController(target: target, scheduler: tick, clock: clock)
        control.handle(.init(.open, id: "open-0001-wand"))
    }

    func testAnUnheldSlowTurnFromUtilityStopsOnTheAppCardAndUsesIt() {
        let layout = target.wandRadialLayout
        let utility = WandRadialNavigator.restingPosition(of: .modePickerEntry, in: layout)
        let hover = "hover-0001-wand"
        control.handle(.init(.hover, id: hover))
        control.handle(.init(.motion, id: hover, sequence: 1, x: utility.x, y: utility.y))
        XCTAssertEqual(control.focusedCell, .modePickerEntry)
        var visited = [PhysicalCell.modePickerEntry]
        var offset = utility
        var sequence = 1
        while control.focusedCell != .frontmostAppModeSelector, sequence < 40 {
            sequence += 1
            clock.advance(by: 0.03)
            offset = (x: offset.x - 0.4, y: offset.y + 0.09)
            control.handle(.init(.motion, id: hover, sequence: sequence, x: offset.x, y: offset.y))
            if let cell = control.focusedCell, visited.last != cell { visited.append(cell) }
        }
        XCTAssertEqual(visited, [.modePickerEntry, .frontmostAppModeSelector], "the app card, not Keys")
        // Ethan stops there; a few more identical samples change nothing.
        for _ in 0..<5 {
            sequence += 1
            control.handle(.init(.motion, id: hover, sequence: sequence, x: offset.x, y: offset.y))
        }
        XCTAssertEqual(control.focusedCell, .frontmostAppModeSelector)
        XCTAssertTrue(homeActions.isEmpty, "aiming never acts")
        // A held press and release on it opens the app's mode.
        let held = "navigate-0002-wand"
        control.handle(.init(.navigate, id: held))
        control.handle(.init(.park, id: held, sequence: 1))
        control.handle(.init(.choose, id: "choose-0003-wand"))
        XCTAssertEqual(target.page, .appSpecific)
        XCTAssertEqual(target.appSpecificTarget, .chrome)
    }
}
