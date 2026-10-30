import XCTest
@testable import ScimitarKit

// MARK: - Back navigation and next-press state

/// Drives the real coordinator through the wand controller exactly as the
/// receiver does: one press, cumulative degrees, one release.
final class WandBackNavigationTests: XCTestCase {
    private var clock: ManualClock!
    private var watchdog: ManualTickScheduler!
    private var hud: RecordingModeHUDPresenter!
    private var coordinator: ModePickerCoordinator!
    private var controller: WandSelectionController!
    private var keysActions: [KeysModeAction] = []
    private var homeActions: [PhysicalCell] = []
    private var appInputs: [PhysicalCell] = []
    private var keypadAvailable = false
    private var gestureCounter = 0
    private var sequence = 0
    private var gestureOrigin: (x: Double, y: Double) = (0, 0)

    override func setUp() {
        super.setUp()
        clock = ManualClock(now: 100)
        watchdog = ManualTickScheduler()
        hud = RecordingModeHUDPresenter()
        coordinator = ModePickerCoordinator(
            lease: WandModeLease(),
            hud: hud,
            scheduler: ManualTickScheduler(),
            log: Log(category: "test", sink: NullLogSink())
        )
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(
                target: .chrome,
                displayName: "Chrome",
                bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier
            )
        }
        coordinator.onKeysInput = { [unowned self] _, action in keysActions.append(action); return true }
        coordinator.onWandHomeInput = { [unowned self] cell in homeActions.append(cell); return true }
        coordinator.onAppSpecificInput = { [unowned self] _, _, cell, _, _ in appInputs.append(cell); return true }
        coordinator.onUtilityAction = { _, _ in .performed }
        coordinator.onKeypadModeRequested = { [unowned self] _ in keypadAvailable }
        controller = WandSelectionController(
            target: coordinator,
            scheduler: watchdog,
            clock: clock,
            log: Log(category: "test", sink: NullLogSink()),
            inputTime: { [unowned self] in clock.now }
        )
    }

    // MARK: Helpers

    private var gestureID: String { "gesture-\(gestureCounter)" }

    /// Resting stick position of a card on the wheel the HUD is drawing.
    private func wheel(_ cell: PhysicalCell) -> (x: Double, y: Double) {
        let layout = coordinator.wandRadialLayout
        precondition(layout.contains(cell), "cell is not on the wheel")
        return WandRadialNavigator.restingPosition(of: cell, in: layout)
    }

    private func cell(_ raw: Int) -> PhysicalCell { PhysicalCell(rawValue: raw)! }

    private func hold() {
        gestureCounter += 1
        sequence = 0
        controller.handle(.init(phase: .begin, gestureID: gestureID, sequence: 0))
        gestureOrigin = wheel(controller.focusedCell ?? .frontmostAppModeSelector)
    }

    private func offset(_ x: Double, _ y: Double) {
        sequence += 1
        clock.advance(by: 0.03)
        controller.handle(.init(phase: .update, gestureID: gestureID, sequence: sequence, offset: .init(x: x, y: y)))
    }

    /// Straight travel from where the hold started to the card's resting
    /// stick position on the HUD's own wheel.
    private func walk(to target: Int) {
        let destination = wheel(cell(target))
        offset(destination.x - gestureOrigin.x, destination.y - gestureOrigin.y)
        XCTAssertEqual(controller.focusedCell?.rawValue, target, "walked to the wrong card")
    }

    private func release() {
        sequence += 1
        clock.advance(by: 0.03)
        controller.handle(.init(phase: .end, gestureID: gestureID, sequence: sequence))
    }

    private func select(_ target: Int) {
        hold()
        walk(to: target)
        release()
    }

    /// Every snapshot that changes page must already carry its outline, so
    /// the HUD never draws a frame without the cursor between pages.
    private func assertEveryPageChangeCarriesTheOutline(file: StaticString = #filePath, line: UInt = #line) {
        var previousTitle: String?
        for snapshot in hud.snapshots {
            if let previousTitle, previousTitle != snapshot.modeTitle {
                XCTAssertNotNil(snapshot.pointerFocus, "\(snapshot.modeTitle) appeared without its outline", file: file, line: line)
            }
            previousTitle = snapshot.modeTitle
        }
    }

    // MARK: Ethan's reported journey

    func testExitKeysReturnsToDefaultOnTheKeysCardAndTheNextPressIsClean() {
        hold()
        XCTAssertEqual(hud.snapshots.first?.pointerFocus?.cell, .switchApp,
                       "the first frame already shows the outline on Switch App")
        walk(to: 9) // Default: Keys mode
        release()
        XCTAssertEqual(coordinator.page, .keys)
        XCTAssertEqual(coordinator.pointerFocus?.cell, .modeExit, "Keys opens with Exit Keys outlined")

        hold()
        XCTAssertEqual(controller.focusedCell, .modeExit, "the hold starts where the outline already is")
        release() // Exit Keys mode
        XCTAssertTrue(coordinator.isActive, "Exit Keys must not dismiss the wand HUD")
        XCTAssertTrue(coordinator.isWandHome, "it returns to Default, the page that opened Keys")
        XCTAssertEqual(coordinator.pointerFocus?.cell.rawValue, 9, "back lands on the Keys card")
        XCTAssertEqual(hud.hideCount, 0, "the HUD never disappeared")
        XCTAssertEqual(homeActions, [], "the exit's release never reached Default cell 10")
        XCTAssertEqual(keysActions, [])
        XCTAssertEqual(controller.phase, .lingering)
        XCTAssertEqual(coordinator.wandBackDepth, 0)

        hold()
        XCTAssertEqual(controller.phase, .navigating)
        XCTAssertEqual(controller.focusedCell?.rawValue, 9, "the next press continues on the Keys card")
        XCTAssertEqual(coordinator.page, .modes)
        XCTAssertTrue(coordinator.isWandHome)
        release()
        XCTAssertEqual(coordinator.page, .keys, "a tap selects the restored card: re-entering Keys is only navigation")
        XCTAssertEqual(homeActions, [], "history replaced the fresh Switch App default")

        select(10) // back to Default again
        select(10) // Default's own exit is the deliberate close
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(homeActions, [])

        hold()
        XCTAssertTrue(coordinator.isWandHome)
        XCTAssertEqual(controller.focusedCell, .switchApp, "a fresh open has no stale parent")
        XCTAssertEqual(coordinator.wandBackDepth, 0)
        assertEveryPageChangeCarriesTheOutline()
    }

    func testUtilityChildrenEachReturnToTheirRealParent() {
        select(12) // Default → Utility
        XCTAssertEqual(coordinator.page, .modes)
        XCTAssertFalse(coordinator.isWandHome)
        XCTAssertEqual(coordinator.pointerFocus?.cell, .modeExit)

        select(9) // Utility → Keys
        XCTAssertEqual(coordinator.page, .keys)
        XCTAssertEqual(coordinator.wandBackDepth, 2)

        select(10) // Exit Keys → Utility, not Default
        XCTAssertEqual(coordinator.page, .modes)
        XCTAssertFalse(coordinator.isWandHome, "Utility and Default share a page value; back must not confuse them")
        XCTAssertEqual(coordinator.pointerFocus?.cell, .keysModeSelector)

        select(12) // Utility → Extra Utilities
        XCTAssertEqual(coordinator.page, .extraUtilities)
        select(10) // Exit Extra Utilities → Utility
        XCTAssertEqual(coordinator.page, .modes)
        XCTAssertEqual(coordinator.pointerFocus?.cell, .extraUtilitiesSelector)

        select(10) // Exit Utility → Default
        XCTAssertTrue(coordinator.isWandHome)
        XCTAssertEqual(coordinator.pointerFocus?.cell.rawValue, 12)

        select(10) // Default's own exit closes
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(hud.hideCount, 1)
        XCTAssertEqual(homeActions, [])
        assertEveryPageChangeCarriesTheOutline()
    }

    func testChosenAppReturnsToChooseAppThenUtility() {
        select(12) // Utility
        select(PhysicalCell.appSpecificModeSelector.rawValue) // Choose App
        XCTAssertEqual(coordinator.page, .appSelector)
        select(AppSpecificTarget.codex.selectorCell!.rawValue) // Codex
        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .codex)

        select(2) // Exit Codex mode (cell 2) → Choose App
        XCTAssertEqual(coordinator.page, .appSelector)
        XCTAssertEqual(coordinator.pointerFocus?.cell, AppSpecificTarget.codex.selectorCell)
        select(10) // Choose App reserves only cell 10 → Utility
        XCTAssertEqual(coordinator.page, .modes)
        XCTAssertEqual(coordinator.pointerFocus?.cell, .appSpecificModeSelector)
        XCTAssertEqual(appInputs, [], "exits never ran an app action")
    }

    func testAppChildAndItsWebsitesPageStepBackOneLevelAtATime() {
        hold()
        walk(to: 5)
        walk(to: 2) // leave and return to the app card to enter it
        release()
        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.appSpecificTarget, .chrome)

        select(8) // Chrome → websites
        XCTAssertEqual(coordinator.page, .chromeWebsites)
        XCTAssertFalse(coordinator.wandRadialLayout.contains(.modeExit), "cell 10 duplicates the centre exit")
        select(2) // the centre exit → Chrome, not Default
        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.pointerFocus?.cell.rawValue, 8)

        select(8)
        select(8) // the websites page's own "back to Chrome" card
        XCTAssertEqual(coordinator.page, .appSpecific)
        XCTAssertEqual(coordinator.wandBackDepth, 1, "an explicit parent card pops instead of stacking")

        select(2) // Exit Chrome mode → Default on the app card
        XCTAssertTrue(coordinator.isWandHome)
        XCTAssertEqual(coordinator.pointerFocus?.cell, .frontmostAppModeSelector)
        XCTAssertEqual(appInputs, [])
    }

    func testUnavailableKeypadKeepsTheWandOnKeys() {
        select(9)
        select(PhysicalCell.keypadModeSelector.rawValue)
        XCTAssertTrue(coordinator.isActive, "the wand menu stays open")
        XCTAssertEqual(coordinator.page, .keys)
        XCTAssertEqual(hud.problems.last, "Keypad mode could not start")
    }

    func testLockResetAndDisconnectStillCloseEverythingAndForgetTheParents() {
        select(9)
        XCTAssertEqual(coordinator.wandBackDepth, 1)
        controller.reset(reason: .systemSleep)
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(coordinator.wandBackDepth, 0)
        hold()
        XCTAssertTrue(coordinator.isWandHome, "never restores a pre-lock child page")
        release()

        select(9)
        hold()
        controller.handle(.init(phase: .cancel, gestureID: gestureID, sequence: 50, cancelReason: .disconnect))
        XCTAssertFalse(coordinator.isActive, "a cancel closes rather than going back")
        XCTAssertEqual(keysActions, [])
    }

    func testLostReleaseOnAChildPageClosesWithoutGoingBack() {
        select(9)
        hold()
        clock.advance(by: 1.1)
        watchdog.fire()
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(coordinator.wandBackDepth, 0)
    }

    func testPhysicalMiceKeepTheirExactExitAndNoCursor() {
        let mouseHUD = RecordingModeHUDPresenter()
        let mouse = ModePickerCoordinator(
            lease: WandModeLease(),
            hud: mouseHUD,
            scheduler: ManualTickScheduler(),
            log: Log(category: "test", sink: NullLogSink())
        )
        for source in MouseSource.allCases {
            mouse.enter(source: source)
            mouse.handle(.init(action: .select, source: source, physicalCell: .keysModeSelector, phase: .press))
            XCTAssertEqual(mouse.page, .keys)
            XCTAssertFalse(mouse.navigateBackForWand(), "mice have no wand back stack")
            mouse.handle(.init(action: .select, source: source, physicalCell: .modeExit, phase: .press))
            XCTAssertFalse(mouse.isActive, "a mouse's universal Exit still leaves the mode")
            XCTAssertTrue(mouseHUD.snapshots.allSatisfy { $0.pointerFocus == nil })
        }
        mouse.onKeypadModeRequested = { _ in false }
        mouse.enterKeys(source: .corsair)
        mouse.handle(.init(action: .select, source: .corsair, physicalCell: .keypadModeSelector, phase: .press))
        XCTAssertFalse(mouse.isActive, "a mouse still exits when Keypad cannot start")
    }
}

// MARK: - Diagonal navigation from deterministic motion traces

final class WandDiagonalNavigationTests: XCTestCase {
    /// One receiver sample every 30 ms, as the Puck HUD stream sends.
    private let sampleInterval = 0.03

    private func cell(_ raw: Int) -> PhysicalCell { PhysicalCell(rawValue: raw)! }

    private func navigator(from start: Int) -> WandGridNavigator {
        WandGridNavigator(rows: PhysicalCell.displayRowsTopToBottom(for: .wand), start: cell(start))!
    }

    /// `angle` follows the screen: 0° right, 90° up. Returns visited cards.
    @discardableResult
    private func drive(
        _ grid: inout WandGridNavigator,
        angle: Double,
        degreesPerSecond: Double,
        duration: Double
    ) -> [Int] {
        let radians = angle * .pi / 180
        let step = degreesPerSecond * sampleInterval
        var visited = [grid.focusedCell.rawValue]
        for _ in 0..<Int((duration / sampleInterval).rounded()) {
            grid.apply(deltaX: cos(radians) * step, deltaY: -sin(radians) * step)
            if visited.last != grid.focusedCell.rawValue { visited.append(grid.focusedCell.rawValue) }
        }
        return visited
    }

    private func position(of raw: Int) -> (column: Int, row: Int) {
        for (row, cells) in PhysicalCell.displayRowsTopToBottom(for: .wand).enumerated() {
            if let column = cells.firstIndex(of: cell(raw)) { return (column, row) }
        }
        preconditionFailure("cell is not in the grid")
    }

    private func assertDiagonalHops(_ visited: [Int], file: StaticString = #filePath, line: UInt = #line) {
        for (from, to) in zip(visited, visited.dropFirst()) {
            let a = position(of: from), b = position(of: to)
            let dc = abs(a.column - b.column), dr = abs(a.row - b.row)
            XCTAssertEqual(min(dc, 4 - dc), 1, "\(from)→\(to) is not a diagonal hop in \(visited)", file: file, line: line)
            XCTAssertEqual(min(dr, 3 - dr), 1, "\(from)→\(to) is not a diagonal hop in \(visited)", file: file, line: line)
        }
    }

    func testFortyFiveDegreeSweepGoesStraightAcrossTheDiagonal() {
        var grid = navigator(from: 1) // bottom-left
        // 25° of travel: two diagonal cards, stopping short of the top edge.
        let visited = drive(&grid, angle: 45, degreesPerSecond: 60, duration: 0.42)
        XCTAssertEqual(visited, [1, 5, 9], "no staircase through 2, 4 or 8")
        assertDiagonalHops(visited)
        // Past the top edge, motion continues right and stops at the corner.
        let bounded = drive(&grid, angle: 45, degreesPerSecond: 60, duration: 0.4)
        XCTAssertEqual(bounded, [9, 12])
    }

    func testNearDiagonalsAlsoTakeTheDiagonalNeighbour() {
        for angle in [33.0, 40, 50, 55] {
            XCTAssertEqual(firstHop(from: 1, angle: angle), 5, "\(angle)° should reach the diagonal neighbour directly")
        }
        // Beyond the dead band around the boundary, steep and shallow motion
        // deliberately lock to the nearer axis instead.
        XCTAssertEqual(firstHop(from: 1, angle: 66), 2)
        XCTAssertEqual(firstHop(from: 1, angle: 18), 4)
        var downLeft = navigator(from: 9)
        XCTAssertEqual(drive(&downLeft, angle: 225, degreesPerSecond: 60, duration: 0.42), [9, 5, 1])
    }

    private func firstHop(from start: Int, angle: Double) -> Int? {
        var grid = navigator(from: start)
        let radians = angle * .pi / 180
        for _ in 0..<200 {
            grid.apply(deltaX: cos(radians) * 1.5, deltaY: -sin(radians) * 1.5)
            if grid.focusedCell.rawValue != start { return grid.focusedCell.rawValue }
        }
        return nil
    }

    func testPureAxesStayOnTheirRowOrColumn() {
        var right = navigator(from: 2)
        XCTAssertEqual(drive(&right, angle: 0, degreesPerSecond: 40, duration: 0.8), [2, 5, 8, 11])
        var up = navigator(from: 1)
        XCTAssertEqual(drive(&up, angle: 90, degreesPerSecond: 40, duration: 0.5), [1, 2, 3])
        var left = navigator(from: 11)
        XCTAssertEqual(drive(&left, angle: 180, degreesPerSecond: 40, duration: 0.8), [11, 8, 5, 2])
    }

    func testShallowSweepsStillLockToTheAxis() {
        for angle in [8.0, 15, 20, 172] {
            var grid = navigator(from: angle > 90 ? 11 : 2)
            // About 25° of travel: enough to cross the whole row.
            let visited = drive(&grid, angle: angle, degreesPerSecond: 45, duration: 0.57)
            let rows = Set(visited.map { position(of: $0).row })
            XCTAssertEqual(rows, [1], "\(angle)° slipped a row: \(visited)")
            XCTAssertEqual(visited.count, 4, "\(angle)° should still cross the whole row: \(visited)")
        }
    }

    func testOneFastDiagonalUpdateCrossesSeveralCards() {
        var grid = navigator(from: 1)
        XCTAssertTrue(grid.apply(deltaX: 20, deltaY: -16))
        XCTAssertEqual(grid.focusedCell.rawValue, 9)
        var corner = navigator(from: 1)
        corner.apply(deltaX: 40, deltaY: -40)
        XCTAssertEqual(corner.focusedCell.rawValue, 12, "large travel stops at the far corner")
    }

    func testReversalAtACornerRespondsImmediately() {
        var grid = navigator(from: 1)
        grid.apply(deltaX: -8, deltaY: 7)
        XCTAssertEqual(grid.focusedCell.rawValue, 1)
        grid.apply(deltaX: 8, deltaY: -7)
        XCTAssertEqual(grid.focusedCell.rawValue, 5, "outward travel does not delay the diagonal reversal")
    }

    func testDeliberateTurnTakesOverQuickly() {
        var grid = navigator(from: 1)
        drive(&grid, angle: 0, degreesPerSecond: 40, duration: 0.25) // to 4
        XCTAssertEqual(grid.focusedCell.rawValue, 4)
        var travel = 0.0
        while grid.focusedCell.rawValue == 4 && travel < 20 {
            grid.apply(deltaX: 0, deltaY: -0.6)
            travel += 0.6
        }
        XCTAssertEqual(grid.focusedCell.rawValue, 5, "turning up moves straight up")
        XCTAssertLessThanOrEqual(travel, 6.6, "the old heading costs well under a card of travel")
    }

    func testTremorNeverMovesOrDiagonalisesTheOutline() {
        var seed: UInt64 = 0x5EED
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (Double(seed >> 11) / Double(1 << 53) - 0.5) * 0.7 // ±0.35° per sample
        }
        var resting = navigator(from: 5)
        var changes = 0
        for _ in 0..<100 where resting.apply(deltaX: noise(), deltaY: noise()) { changes += 1 }
        XCTAssertEqual(changes, 0, "3 s of tremor at rest")

        var nearBoundary = navigator(from: 5)
        nearBoundary.apply(deltaX: 4.9, deltaY: 0) // 0.61 of a card toward 8
        var visited = [nearBoundary.focusedCell.rawValue]
        for _ in 0..<100 {
            nearBoundary.apply(deltaX: noise(), deltaY: noise())
            if visited.last != nearBoundary.focusedCell.rawValue { visited.append(nearBoundary.focusedCell.rawValue) }
        }
        XCTAssertLessThanOrEqual(visited.count, 2, "at most one crossing, never a flicker: \(visited)")
        XCTAssertTrue(Set(visited).isSubset(of: [5, 8]), "tremor never takes a diagonal: \(visited)")
    }

    func testLiquidProgressFollowsTheDiagonalAndReversesAfterTheSnap() {
        var grid = navigator(from: 1)
        grid.apply(deltaX: 2.4, deltaY: -2.1)
        grid.apply(deltaX: 1.2, deltaY: -1.05)
        XCTAssertTrue(grid.isDiagonalHeading)
        XCTAssertEqual(grid.focusedCell.rawValue, 1)
        XCTAssertGreaterThan(grid.pointerFocus.pullX, 0.4)
        XCTAssertLessThan(grid.pointerFocus.pullY, -0.4, "pulled toward the card above as well")
        grid.apply(deltaX: 2.4, deltaY: -2.1)
        XCTAssertEqual(grid.focusedCell.rawValue, 5)
        XCTAssertLessThan(grid.pointerFocus.pullX, 0)
        XCTAssertGreaterThan(grid.pointerFocus.pullY, 0)
    }
}
