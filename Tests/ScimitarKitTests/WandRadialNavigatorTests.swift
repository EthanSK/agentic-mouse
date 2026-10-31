import XCTest
@testable import ScimitarKit

/// The wand's weapon wheel: one layout places the cards and selects them.
final class WandRadialNavigatorTests: XCTestCase {
    private func cell(_ raw: Int) -> PhysicalCell { PhysicalCell(rawValue: raw)! }
    private let tuning = WandRadialTuning()

    /// Default home without VS Code: twelve ring cards around Switch App.
    private var home: WandRadialLayout {
        let ring: [PhysicalCell] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12].map { PhysicalCell(rawValue: $0)! } + [.wandPlayPause]
        return WandRadialLayout(center: .switchApp, ring: ring)
    }

    private func layout(ringCount: Int) -> WandRadialLayout {
        let cells = PhysicalCell.all.filter { $0 != .modeExit } + [.wandPlayPause, .wandReviewChanges, .wandReviewFiles]
        return WandRadialLayout(center: .modeExit, ring: Array(cells.prefix(ringCount)))
    }

    private func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    /// Moves the stick by `distance` degrees toward `angle` (clockwise from
    /// up) in small receiver-sized samples, returning every card visited.
    @discardableResult
    private func drive(_ nav: inout WandRadialNavigator, toward angle: Double, distance: Double, step: Double = 0.3) -> [PhysicalCell] {
        let radians = angle * .pi / 180
        var visited = [nav.focusedCell]
        var travelled = 0.0
        while travelled < distance {
            let d = min(step, distance - travelled)
            nav.apply(deltaX: sin(radians) * d, deltaY: -cos(radians) * d)
            travelled += d
            if visited.last != nav.focusedCell { visited.append(nav.focusedCell) }
        }
        return visited
    }

    // MARK: Layout

    func testTwelveCardHomePutsEachNumberedCardAtItsClockHour() {
        let layout = home
        for raw in 1...10 {
            let index = layout.ringIndex(of: cell(raw))!
            XCTAssertEqual(degrees(layout.angle(at: index)), Double(raw) * 30, accuracy: 1e-9, "Corsair \(raw)")
        }
        XCTAssertEqual(degrees(layout.angle(at: layout.ringIndex(of: .modePickerEntry)!)), 330, accuracy: 1e-9)
        XCTAssertEqual(degrees(layout.angle(at: layout.ringIndex(of: .wandPlayPause)!)), 360, accuracy: 1e-9)
        XCTAssertFalse(layout.ring.contains(.switchApp), "the centre is not repeated on the ring")
    }

    func testOddAndEvenCountsAreEvenlySpacedAndEverySectorIsReachable() {
        for count in [1, 2, 5, 11, 12, 13, 14] {
            let layout = layout(ringCount: count)
            XCTAssertEqual(layout.ring.count, count)
            for index in 0..<count {
                // Pointing straight at a card's centre selects exactly it.
                XCTAssertEqual(layout.nearestIndex(toAngle: layout.angle(at: index)), index, "\(count) cards")
                var nav = WandRadialNavigator(layout: layout, start: .modeExit)!
                let direction = layout.direction(at: index)
                nav.apply(deltaX: direction.x * 9, deltaY: direction.y * 9)
                XCTAssertEqual(nav.focusedCell, layout.ring[index], "\(count) cards, index \(index)")
            }
            // Neighbouring centres are exactly one sector apart.
            if count > 1 {
                XCTAssertEqual(layout.angle(at: 1) - layout.angle(at: 0), 2 * .pi / Double(count), accuracy: 1e-12)
            }
        }
    }

    func testDuplicatesCollapseAndTheCentreIsNeverOnTheRing() {
        let layout = WandRadialLayout(center: .modeExit, ring: [cell(1), .modeExit, cell(1), cell(3)])
        XCTAssertEqual(layout.ring, [cell(1), cell(3)])
        XCTAssertEqual(layout.cells, [.modeExit, cell(1), cell(3)])
    }

    // MARK: Centre and radial hysteresis

    func testCentreDeadZoneHoldsUntilADeliberateReach() {
        var nav = WandRadialNavigator(layout: home, start: .switchApp)!
        XCTAssertFalse(nav.apply(deltaX: tuning.reachDegrees - 0.5, deltaY: 0), "short of the reach")
        XCTAssertEqual(nav.focusedCell, .switchApp)
        XCTAssertTrue(nav.apply(deltaX: 0.6, deltaY: 0))
        XCTAssertEqual(nav.focusedCell, cell(3), "straight right is 3 o'clock")
    }

    func testReturningToTheCentreNeedsTheInnerRadius() {
        var nav = WandRadialNavigator(layout: home, start: cell(3))!
        XCTAssertFalse(nav.apply(deltaX: -(tuning.restingDegrees - tuning.centerReturnDegrees - 0.5), deltaY: 0), "inside the return band, still the card")
        XCTAssertEqual(nav.focusedCell, cell(3))
        XCTAssertTrue(nav.apply(deltaX: -1, deltaY: 0), "crossing the inner radius returns to centre")
        XCTAssertEqual(nav.focusedCell, .switchApp)
        XCTAssertFalse(nav.apply(deltaX: tuning.reachDegrees - tuning.centerReturnDegrees, deltaY: 0), "the centre holds until the reach again")
        XCTAssertEqual(nav.focusedCell, .switchApp)
    }

    func testInsideTheBandTheAngleCannotSwapRingCards() {
        var nav = WandRadialNavigator(layout: home, start: .modePickerEntry)! // 11 o'clock
        // Straight down from 11 o'clock passes close to the centre, where the
        // angle swings through 10 o'clock; the card must not change.
        let visited = drive(&nav, toward: 180, distance: 5.2)
        XCTAssertEqual(visited, [.modePickerEntry])
        XCTAssertGreaterThan(nav.pointerFocus.pullY, 0.1, "the outline leans toward the centre")
    }

    // MARK: Ring and angular hysteresis

    func testNeighbourNeedsTheEdgePlusHysteresis() {
        var nav = WandRadialNavigator(layout: home, start: cell(12))!
        nav.apply(deltaX: 0, deltaY: -5) // out to the rim (11°)
        let rim = tuning.maximumDegrees
        // Sweep clockwise along the rim one degree of arc at a time.
        var angle = 330.0
        var switchedAt: Double?
        while angle < 375, switchedAt == nil {
            angle += 0.5
            let target = (sin(angle * .pi / 180) * rim, -cos(angle * .pi / 180) * rim)
            nav.apply(deltaX: target.0 - nav.positionX, deltaY: target.1 - nav.positionY)
            if nav.focusedCell != cell(12) { switchedAt = angle }
        }
        let edge = 330 + 15 + min(0.22 * 30, 9)
        XCTAssertEqual(switchedAt ?? 0, edge, accuracy: 0.6, "the neighbour takes over just past the band")
        XCTAssertEqual(nav.focusedCell, .wandPlayPause)
        XCTAssertLessThan(nav.pointerFocus.pullX, 0, "just after the change it leans back toward Utility")
    }

    func testTremorOnABoundaryNeverFlickers() {
        var seed: UInt64 = 0x5EED_1234
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (Double(seed >> 11) / Double(1 << 53) - 0.5) * 0.7
        }
        var nav = WandRadialNavigator(layout: home, start: cell(3))!
        // Park on the 3/4 boundary (105°) at the rim.
        let rim = 10.0
        nav.apply(deltaX: sin(105 * .pi / 180) * rim - nav.positionX, deltaY: -cos(105 * .pi / 180) * rim - nav.positionY)
        var visited = [nav.focusedCell]
        for _ in 0..<200 {
            nav.apply(deltaX: noise(), deltaY: noise())
            if visited.last != nav.focusedCell { visited.append(nav.focusedCell) }
        }
        XCTAssertLessThanOrEqual(visited.count, 2, "at most one deliberate crossing: \(visited)")

        var resting = WandRadialNavigator(layout: home, start: .switchApp)!
        var changes = 0
        for _ in 0..<200 where resting.apply(deltaX: noise(), deltaY: noise()) { changes += 1 }
        XCTAssertEqual(changes, 0, "tremor at the centre never leaves it")
    }

    func testCircularSweepVisitsCardsInClockwiseOrderWithoutBacktracking() {
        var nav = WandRadialNavigator(layout: home, start: cell(12))!
        var visited = [nav.focusedCell]
        let rim = 10.5
        for step in 1...240 {
            let angle = (330 + Double(step) * 1.5) * .pi / 180
            nav.apply(deltaX: sin(angle) * rim - nav.positionX, deltaY: -cos(angle) * rim - nav.positionY)
            if visited.last != nav.focusedCell { visited.append(nav.focusedCell) }
        }
        let expected = Array((home.ring + home.ring).drop { $0 != cell(12) }.prefix(visited.count))
        XCTAssertEqual(visited, expected, "one full lap, every card once, in ring order")
        XCTAssertGreaterThanOrEqual(visited.count, 12)
    }

    // MARK: Slow intent, large sweeps and saturation

    func testSlowDeliberateMotionStillSelects() {
        var nav = WandRadialNavigator(layout: home, start: .switchApp)!
        for _ in 0..<160 { nav.apply(deltaX: -0.05, deltaY: 0) } // 8° in tiny samples
        XCTAssertEqual(nav.focusedCell, cell(9), "no speed threshold: slow intent counts in full")
    }

    func testOneLargeSweepLandsOnTheFarCardAndDoesNotWindUp() {
        var nav = WandRadialNavigator(layout: home, start: cell(3))!
        XCTAssertTrue(nav.apply(deltaX: -40, deltaY: 0), "one huge update across the wheel")
        XCTAssertEqual(nav.focusedCell, cell(9))
        XCTAssertEqual((nav.positionX * nav.positionX + nav.positionY * nav.positionY).squareRoot(),
                       tuning.maximumDegrees, accuracy: 1e-9, "saturated on the rim")
        nav.apply(deltaX: 7.5, deltaY: 0)
        XCTAssertEqual(nav.focusedCell, .switchApp, "the reversal acts at once: no hidden overshoot")
    }

    func testNonFiniteMotionAndBadTuningAreSafe() {
        var nav = WandRadialNavigator(layout: home, start: .switchApp,
                                      tuning: WandRadialTuning(reachDegrees: .nan, centerReturnDegrees: 99, maximumDegrees: -1))!
        XCTAssertFalse(nav.apply(deltaX: .infinity, deltaY: 0))
        XCTAssertFalse(nav.apply(deltaX: .nan, deltaY: 1))
        XCTAssertLessThan(nav.tuning.centerReturnDegrees, nav.tuning.reachDegrees)
        XCTAssertGreaterThan(nav.tuning.maximumDegrees, nav.tuning.reachDegrees)
        XCTAssertNil(WandRadialNavigator(layout: .empty, start: .switchApp))
        let ringOnly = WandRadialLayout(center: nil, ring: [cell(1), cell(2)])
        var noCentre = WandRadialNavigator(layout: ringOnly, start: .switchApp)!
        XCTAssertEqual(noCentre.focusedCell, cell(1), "without a centre the first card holds")
        noCentre.apply(deltaX: -8, deltaY: 0)
        noCentre.apply(deltaX: 8, deltaY: 0)
        XCTAssertNotEqual(noCentre.focusedCell, .switchApp)
    }

    // MARK: Liquid pull

    func testCentrePullPointsWhereTheStickPoints() {
        var nav = WandRadialNavigator(layout: home, start: .switchApp)!
        nav.apply(deltaX: tuning.reachDegrees * 0.3, deltaY: -tuning.reachDegrees * 0.4) // half a reach toward 1 o'clock-ish
        let pull = nav.pointerFocus
        XCTAssertEqual(pull.cell, .switchApp)
        XCTAssertEqual(pull.pullX, 0.3, accuracy: 1e-9)
        XCTAssertEqual(pull.pullY, -0.4, accuracy: 1e-9)
    }

    func testRingPullGrowsTowardTheNeighbourAndTowardTheCentre() {
        var nav = WandRadialNavigator(layout: home, start: cell(12))!
        XCTAssertEqual(nav.pointerFocus.pullX, 0, accuracy: 1e-9)
        XCTAssertEqual(nav.pointerFocus.pullY, 0, accuracy: 1e-9, "a fresh hold starts at rest")
        nav.apply(deltaX: 1.5, deltaY: 0)
        let along = nav.pointerFocus
        XCTAssertEqual(along.cell, cell(12))
        XCTAssertGreaterThan(along.pullX, 0.2, "pulled clockwise toward Play/Pause")
        var inward = WandRadialNavigator(layout: home, start: cell(3))!
        let midway = (tuning.reachDegrees + tuning.centerReturnDegrees) / 2
        inward.apply(deltaX: midway - tuning.restingDegrees, deltaY: 0)
        XCTAssertEqual(inward.pointerFocus.pullX, -0.5, accuracy: 1e-9, "halfway toward the centre")
        XCTAssertEqual(inward.pointerFocus.pullY, 0, accuracy: 1e-9)
    }

    // MARK: Outer layer (Ethan: "you have to go up twice to get there")

    private var outerHome: WandRadialLayout {
        WandRadialLayout(center: .switchApp, ring: home.ring, outer: [
            WandOuterCard(cell: .wandUndo, parent: .keysModeEntry, height: .thin),
            WandOuterCard(cell: .wandReviewChanges, parent: .frontmostAppModeSelector, height: .large),
            WandOuterCard(cell: .wandReviewFiles, parent: .frontmostAppModeSelector, height: .large),
        ])
    }

    func testOuterCardsNeverMoveTheRingAndSplitTheirParentWedge() {
        let layout = outerHome
        XCTAssertEqual(layout.ring, home.ring)
        XCTAssertEqual(layout.sectorWidth, home.sectorWidth)
        let review = layout.outerIndex(of: .wandReviewChanges)!, stage = layout.outerIndex(of: .wandReviewFiles)!
        XCTAssertEqual(degrees(layout.outerAngle(at: review)), 52.5, accuracy: 1e-9, "left half of the 2 o'clock wedge")
        XCTAssertEqual(degrees(layout.outerAngle(at: stage)), 67.5, accuracy: 1e-9, "right half")
        XCTAssertEqual(degrees(layout.outerAngle(at: layout.outerIndex(of: .wandUndo)!)), 270, accuracy: 1e-9, "Keys at 9 o'clock")
        // An outer card without its parent on the ring, or a duplicate, is dropped.
        let orphan = WandRadialLayout(center: .switchApp, ring: [cell(1), cell(2)],
                                      outer: [WandOuterCard(cell: .wandUndo, parent: .keysModeEntry, height: .thin),
                                              WandOuterCard(cell: cell(1), parent: cell(2), height: .thin)])
        XCTAssertTrue(orphan.outer.isEmpty)
    }

    func testSecondReachOutwardChoosesTheOuterCardAndComingBackReturns() {
        var nav = WandRadialNavigator(layout: outerHome, start: .switchApp)!
        drive(&nav, toward: 270, distance: tuning.restingDegrees)
        XCTAssertEqual(nav.focusedCell, .keysModeEntry, "the first reach is the ring card")
        drive(&nav, toward: 270, distance: tuning.outerReachDegrees - tuning.restingDegrees - 0.5)
        XCTAssertEqual(nav.focusedCell, .keysModeEntry, "short of the second reach stays on Keys")
        drive(&nav, toward: 270, distance: 1)
        XCTAssertEqual(nav.focusedCell, .wandUndo, "the second reach chooses Undo")
        drive(&nav, toward: 270, distance: 30)
        XCTAssertEqual(nav.focusedCell, .wandUndo, "an over-long sweep saturates, never winds up")
        drive(&nav, toward: 90, distance: tuning.outerMaximumDegrees - tuning.outerReturnDegrees - 0.5)
        XCTAssertEqual(nav.focusedCell, .wandUndo, "the return band absorbs tremor")
        drive(&nav, toward: 90, distance: 2)
        XCTAssertEqual(nav.focusedCell, .keysModeEntry, "coming back drops to the ring card")
    }

    func testCardsWithoutOuterCardsKeepTheRingSaturation() {
        var nav = WandRadialNavigator(layout: outerHome, start: cell(8))!
        drive(&nav, toward: 240, distance: 40)
        XCTAssertEqual(nav.focusedCell, cell(8), "Back has no outer card: overshoot is harmless")
        let before = nav.focusedCell
        drive(&nav, toward: 60, distance: 7.5)
        XCTAssertNotEqual(nav.focusedCell, before, "a reversal acts at once, as before")
    }

    func testOuterSiblingsSwapWithHysteresisAndLeavingTheWedgeReturnsToTheRing() {
        var nav = WandRadialNavigator(layout: outerHome, start: .wandReviewChanges)!
        XCTAssertEqual(nav.focusedCell, .wandReviewChanges, "a hold may start on an outer card")
        drive(&nav, toward: 150, distance: 4)
        XCTAssertEqual(nav.focusedCell, .wandReviewFiles, "clockwise along the band reaches Stage files")
        var tremor = WandRadialNavigator(layout: outerHome, start: .wandReviewChanges)!
        for _ in 0..<40 { tremor.apply(deltaX: 0.4, deltaY: 0.2); tremor.apply(deltaX: -0.4, deltaY: -0.2) }
        XCTAssertEqual(tremor.focusedCell, .wandReviewChanges, "tremor on the edge never flickers")
        var away = WandRadialNavigator(layout: outerHome, start: .wandReviewFiles)!
        drive(&away, toward: 160, distance: 12)
        XCTAssertNotNil(outerHome.ringIndex(of: away.focusedCell), "beyond the app wedge the ring takes over")
        XCTAssertNotEqual(away.focusedCell, .frontmostAppModeSelector)
    }

    func testRingCardWithOuterCardsLeansOutBeforeTheSecondReach() {
        var nav = WandRadialNavigator(layout: outerHome, start: .keysModeEntry)!
        let rest = nav.pointerFocus
        XCTAssertEqual(rest.pullX, 0, accuracy: 1e-9, "at rest it looks exactly as before")
        drive(&nav, toward: 270, distance: 4)
        XCTAssertEqual(nav.focusedCell, .keysModeEntry)
        XCTAssertLessThan(nav.pointerFocus.pullX, -0.3, "leans outward toward Undo")
        var plain = WandRadialNavigator(layout: outerHome, start: cell(8))!
        drive(&plain, toward: 240, distance: 4)
        XCTAssertEqual(plain.pointerFocus.pullX, 0, accuracy: 1e-9, "no lean where there is no outer card")
        XCTAssertEqual(plain.pointerFocus.pullY, 0, accuracy: 1e-9)
    }
}
