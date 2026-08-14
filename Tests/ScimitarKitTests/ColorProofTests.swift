import Foundation
import XCTest
@testable import ScimitarKit

private enum FakeLeaseError: Error { case refused }

private final class FakeColorProofLease: ColorProofLeaseControlling {
    var activateError: Error?
    var renewError: Error?
    private(set) var activateCount = 0
    private(set) var renewCount = 0
    private(set) var deactivateCount = 0

    func activate() throws {
        activateCount += 1
        if let activateError { throw activateError }
    }

    func renew() throws {
        renewCount += 1
        if let renewError { throw renewError }
    }

    func deactivate() { deactivateCount += 1 }
}

final class PhysicalCellAndPaletteTests: XCTestCase {
    func testPaletteHasTwelveUniqueNamedColours() {
        XCTAssertEqual(ColorProofPalette.swatches.count, 12)
        XCTAssertEqual(Set(ColorProofPalette.swatches.map(\.cell)).count, 12)
        XCTAssertEqual(Set(ColorProofPalette.swatches.map(\.name)).count, 12)
        XCTAssertEqual(Set(ColorProofPalette.swatches.map(\.color)).count, 12)
        XCTAssertEqual(ColorProofPalette.swatches.map(\.cell), PhysicalCell.all)
    }

    func testRazerCrosswalkIsAnInvolutionAndCoversEveryCell() {
        XCTAssertEqual(Set(PhysicalCell.razerPrintedToPhysical.keys), Set(1...12))
        XCTAssertEqual(Set(PhysicalCell.razerPrintedToPhysical.values), Set(PhysicalCell.all))
        for printed in 1...12 {
            let physical = PhysicalCell.fromPrintedSide(printed, source: .razer)
            XCTAssertEqual(physical?.printedSide(on: .razer), printed)
        }
    }

    func testCommittedKarabinerCrosswalkMatchesSwift() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Karabiner/bindings/bindings.json"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let modes = try XCTUnwrap(document["modePicker"] as? [String: Any])
        let sources = try XCTUnwrap(modes["bindingsBySource"] as? [String: Any])
        let corsair = try XCTUnwrap(sources["corsair"] as? [String])
        let razer = try XCTUnwrap(sources["razer"] as? [String])
        let bindings = try XCTUnwrap(document["bindings"] as? [[String: Any]])
        let bindingsByID = Dictionary(
            uniqueKeysWithValues: try bindings.map {
                (try XCTUnwrap($0["id"] as? String), $0)
            }
        )

        XCTAssertEqual(corsair.count, 12)
        XCTAssertEqual(razer.count, 12)
        XCTAssertEqual(modes["entryPhysicalCell"] as? Int, PhysicalCell.modePickerEntry.rawValue)
        for (index, bindingID) in corsair.enumerated() {
            let binding = try XCTUnwrap(bindingsByID[bindingID])
            let from = try XCTUnwrap(binding["from"] as? [String: Any])
            let expected = index < 9
                ? "keypad_\(index + 1)"
                : ["keypad_0", "keypad_hyphen", "keypad_plus"][index - 9]
            XCTAssertEqual(from["key_code"] as? String, expected, bindingID)
        }
        for (index, bindingID) in razer.enumerated() {
            let binding = try XCTUnwrap(bindingsByID[bindingID])
            let from = try XCTUnwrap(binding["from"] as? [String: Any])
            let keyCode = try XCTUnwrap(from["key_code"] as? String)
            let printed = try XCTUnwrap([
                "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6,
                "7": 7, "8": 8, "9": 9, "0": 10,
                "hyphen": 11, "equal_sign": 12,
            ][keyCode])
            XCTAssertEqual(
                PhysicalCell.fromPrintedSide(printed, source: .razer)?.rawValue,
                index + 1,
                bindingID
            )
        }
    }

    func testCommandDecoderRejectsAnotherNamespace() throws {
        let valid = Data(
            #"{"command":"agentic_mouse_color_proof","action":"select","source":"razer","physical_cell":8}"#.utf8
        )
        XCTAssertEqual(
            try ColorProofCommand.decode(valid),
            ColorProofCommand(action: .select, source: .razer, physicalCell: PhysicalCell(rawValue: 8)!)
        )

        let unrelated = Data(
            #"{"command":"another_app","action":"select","source":"razer","physical_cell":8}"#.utf8
        )
        XCTAssertThrowsError(try ColorProofCommand.decode(unrelated))
    }

    func testCommandDecoderRejectsInvalidCellsAndMalformedPayloads() {
        for value in ["0", "13", "\"3\""] {
            let payload = Data(
                "{\"command\":\"agentic_mouse_color_proof\",\"action\":\"select\",\"source\":\"razer\",\"physical_cell\":\(value)}".utf8
            )
            XCTAssertThrowsError(try ColorProofCommand.decode(payload), value)
        }
        XCTAssertThrowsError(try ColorProofCommand.decode(Data("{".utf8)))
    }
}

final class ColorProofCoordinatorTests: XCTestCase {
    private var clock: ManualClock!
    private var scheduler: ManualTickScheduler!
    private var reservedHUDScheduler: ManualTickScheduler!
    private var lease: FakeColorProofLease!
    private var hud: RecordingModeHUDPresenter!
    private var coordinator: ColorProofCoordinator!
    private var colors: [ScimitarKit.RGBColor?] = []
    private var exits: [ColorProofExitReason] = []

    override func setUp() {
        super.setUp()
        clock = ManualClock()
        scheduler = ManualTickScheduler()
        reservedHUDScheduler = ManualTickScheduler()
        lease = FakeColorProofLease()
        hud = RecordingModeHUDPresenter()
        colors = []
        exits = []
        coordinator = ColorProofCoordinator(
            lease: lease,
            hud: hud,
            clock: clock,
            scheduler: scheduler,
            reservedHUDScheduler: reservedHUDScheduler,
            log: Log(category: "test", sink: NullLogSink()),
            idleTimeout: 10,
            absoluteTimeout: 60,
            heartbeatInterval: 2
        )
        coordinator.onColorChange = { [weak self] color in
            self?.colors.append(color)
            return color == nil ? [] : [.corsair, .razer]
        }
        coordinator.onExit = { [weak self] reason in self?.exits.append(reason) }
    }

    func testEntryShowsTheEntryCellsColourAndStartsTheLease() {
        coordinator.handle(
            ColorProofCommand(action: .enter, source: .razer, physicalCell: PhysicalCell(rawValue: 1)!)
        )

        XCTAssertTrue(coordinator.isActive)
        XCTAssertTrue(hud.isVisible)
        XCTAssertEqual(lease.activateCount, 1)
        XCTAssertEqual(hud.snapshots.last?.selection?.title, "Red")
        XCTAssertEqual(hud.snapshots.last?.source, .razer)
        XCTAssertEqual(colors.last!, RGBColor(hex: "#FF0000"))
        XCTAssertTrue(scheduler.isRunning)
        XCTAssertTrue(hud.snapshots.last?.showsOnAllDisplays == true)
    }

    func testEveryCellSelectsItsUniquePaletteColour() {
        XCTAssertTrue(coordinator.enter(source: .corsair, cell: PhysicalCell(rawValue: 1)!))
        for cell in PhysicalCell.all {
            coordinator.select(source: .corsair, cell: cell)
        }

        let selected = Array(hud.snapshots.suffix(12)).compactMap(\.selection)
        XCTAssertEqual(selected.map(\.cell), ColorProofPalette.swatches.map(\.cell))
        XCTAssertEqual(selected.map(\.title), ColorProofPalette.swatches.map(\.name))
        XCTAssertEqual(Set(selected.map(\.accent)).count, 12)
    }

    func testEitherMouseSelectsTheSamePhysicalCellColour() {
        XCTAssertTrue(coordinator.enter(source: .corsair, cell: PhysicalCell(rawValue: 1)!))
        coordinator.select(source: .corsair, cell: PhysicalCell(rawValue: 9)!)
        let corsair = hud.snapshots.last?.selection
        coordinator.select(source: .razer, cell: PhysicalCell(rawValue: 9)!)
        let razer = hud.snapshots.last?.selection
        XCTAssertEqual(corsair, razer)
    }

    func testReservedTopLeftDoubleClickTogglesTheActiveModeLegendWithoutSelectingIt() {
        XCTAssertTrue(coordinator.enter(source: .razer, cell: PhysicalCell(rawValue: 1)!))
        let colorCount = colors.count
        let selection = coordinator.selection

        coordinator.handle(
            ColorProofCommand(action: .select, source: .razer, physicalCell: .modeHUDToggle)
        )
        clock.advance(by: 0.1)
        coordinator.handle(
            ColorProofCommand(action: .select, source: .razer, physicalCell: .modeHUDToggle)
        )

        XCTAssertTrue(coordinator.isActive)
        XCTAssertFalse(coordinator.isHUDVisible)
        XCTAssertFalse(hud.isVisible)
        XCTAssertEqual(coordinator.selection, selection)
        XCTAssertEqual(colors.count, colorCount)

        clock.advance(by: 0.5)
        coordinator.handle(
            ColorProofCommand(action: .select, source: .corsair, physicalCell: .modeHUDToggle)
        )
        clock.advance(by: 0.1)
        coordinator.handle(
            ColorProofCommand(action: .select, source: .corsair, physicalCell: .modeHUDToggle)
        )

        XCTAssertTrue(coordinator.isHUDVisible)
        XCTAssertTrue(hud.isVisible)
        XCTAssertEqual(hud.snapshots.last?.source, .corsair)
        XCTAssertTrue(hud.snapshots.last?.showsOnAllDisplays == true)
        XCTAssertEqual(colors.count, colorCount)
    }

    func testOneReservedLegendPressKeepsTheModesExistingCellAction() {
        XCTAssertTrue(coordinator.enter(source: .corsair, cell: PhysicalCell(rawValue: 1)!))

        coordinator.handle(
            ColorProofCommand(action: .select, source: .corsair, physicalCell: .modeHUDToggle)
        )
        XCTAssertEqual(coordinator.selection?.cell, PhysicalCell(rawValue: 1))

        reservedHUDScheduler.fire()

        XCTAssertEqual(coordinator.selection?.cell, .modeHUDToggle)
        XCTAssertEqual(coordinator.selection?.name, "Yellow")
        XCTAssertTrue(coordinator.isHUDVisible)
    }

    func testReservedClicksFromDifferentMiceNeverCombine() {
        XCTAssertTrue(coordinator.enter(source: .corsair, cell: PhysicalCell(rawValue: 1)!))

        coordinator.handle(
            ColorProofCommand(action: .select, source: .razer, physicalCell: .modeHUDToggle)
        )
        clock.advance(by: 0.1)
        coordinator.handle(
            ColorProofCommand(action: .select, source: .corsair, physicalCell: .modeHUDToggle)
        )

        XCTAssertEqual(coordinator.selection?.cell, .modeHUDToggle)
        XCTAssertEqual(coordinator.source, .razer)
        XCTAssertTrue(coordinator.isHUDVisible)
        XCTAssertEqual(coordinator.reservedHUDPendingSource, .corsair)

        reservedHUDScheduler.fire()
        XCTAssertEqual(coordinator.source, .corsair)
        XCTAssertTrue(coordinator.isHUDVisible)
    }

    func testHiddenLegendStaysHiddenWhileModeStateAndLightingContinue() {
        XCTAssertTrue(coordinator.enter(source: .razer, cell: PhysicalCell(rawValue: 1)!))
        coordinator.handleReservedHUDPress(source: .razer, cell: .modeHUDToggle)
        coordinator.handleReservedHUDPress(source: .razer, cell: .modeHUDToggle)
        let snapshotCount = hud.snapshots.count

        coordinator.select(source: .razer, cell: PhysicalCell(rawValue: 7)!)

        XCTAssertFalse(coordinator.isHUDVisible)
        XCTAssertFalse(hud.isVisible)
        XCTAssertEqual(hud.snapshots.count, snapshotCount)
        XCTAssertEqual(coordinator.selection?.cell, PhysicalCell(rawValue: 7))
        XCTAssertEqual(colors.last!, RGBColor(hex: "#00FFFF"))
    }

    func testExitClearsLeaseHudAndLighting() {
        XCTAssertTrue(coordinator.enter(source: .corsair, cell: PhysicalCell(rawValue: 1)!))
        coordinator.exit()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertFalse(hud.isVisible)
        XCTAssertEqual(lease.deactivateCount, 1)
        XCTAssertNil(colors.last!)
        XCTAssertFalse(scheduler.isRunning)
        XCTAssertEqual(exits, [.userRequested])
    }

    func testRefusedLeaseLeavesNothingActive() {
        lease.activateError = FakeLeaseError.refused
        XCTAssertFalse(coordinator.enter(source: .razer, cell: PhysicalCell(rawValue: 1)!))
        XCTAssertFalse(coordinator.isActive)
        XCTAssertFalse(hud.isVisible)
        XCTAssertTrue(colors.isEmpty)
        XCTAssertFalse(hud.problems.isEmpty)
    }

    func testLeaseRenewalFailureExitsFailClosed() {
        XCTAssertTrue(coordinator.enter(source: .corsair, cell: PhysicalCell(rawValue: 1)!))
        lease.renewError = FakeLeaseError.refused
        scheduler.fire()

        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(lease.deactivateCount, 1)
        XCTAssertFalse(hud.isVisible)
        guard case .leaseFailure = exits.last else {
            return XCTFail("expected lease failure")
        }
    }

    func testIdleAndAbsoluteTimeoutsUseTheSameTeardown() {
        XCTAssertTrue(coordinator.enter(source: .corsair, cell: PhysicalCell(rawValue: 1)!))
        clock.advance(by: 11)
        scheduler.fire()
        XCTAssertEqual(exits, [.idleTimeout])
        XCTAssertEqual(lease.deactivateCount, 1)

        XCTAssertTrue(coordinator.enter(source: .razer, cell: PhysicalCell(rawValue: 1)!))
        for _ in 0..<7 {
            clock.advance(by: 9)
            coordinator.select(source: .razer, cell: PhysicalCell(rawValue: 2)!)
            scheduler.fire()
            if !coordinator.isActive { break }
        }
        XCTAssertEqual(exits.last, .absoluteTimeout)
        XCTAssertEqual(lease.deactivateCount, 2)
    }

    func testDisabledTimeoutsStayActiveUntilExplicitExit() {
        let persistent = ColorProofCoordinator(
            lease: lease,
            hud: hud,
            clock: clock,
            scheduler: scheduler,
            log: Log(category: "test-persistent", sink: NullLogSink()),
            idleTimeout: 0,
            absoluteTimeout: 0,
            heartbeatInterval: 2
        )

        XCTAssertTrue(
            persistent.enter(source: MouseSource.corsair, cell: PhysicalCell(rawValue: 3)!)
        )
        clock.advance(by: 86_400)
        scheduler.fire()

        XCTAssertTrue(persistent.isActive)
        XCTAssertTrue(hud.isVisible)

        persistent.exit()
        XCTAssertFalse(persistent.isActive)
        XCTAssertFalse(hud.isVisible)
    }

    func testSleepAndActiveDeviceLossExitButOtherDeviceLossDoesNot() {
        XCTAssertTrue(coordinator.enter(source: .razer, cell: PhysicalCell(rawValue: 1)!))
        coordinator.handleDeviceLost(.corsair)
        XCTAssertTrue(coordinator.isActive)
        coordinator.handleSystemSleep()
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(exits.last, .systemSleep)

        XCTAssertTrue(coordinator.enter(source: .corsair, cell: PhysicalCell(rawValue: 1)!))
        coordinator.handleDeviceLost(.corsair)
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(exits.last, .deviceLost)
    }

    func testSelectionWhileInactiveCannotActivateOrChangeLighting() {
        coordinator.handle(
            ColorProofCommand(action: .select, source: .razer, physicalCell: PhysicalCell(rawValue: 8)!)
        )
        XCTAssertFalse(coordinator.isActive)
        XCTAssertEqual(lease.deactivateCount, 1)
        XCTAssertTrue(colors.isEmpty)
        XCTAssertTrue(hud.snapshots.isEmpty)
    }

    func testAnotherModeIsClearedBeforeTheEntryColourIsWritten() {
        var events: [String] = []
        coordinator.onModeChange = { active in events.append(active ? "mode-on" : "mode-off") }
        coordinator.onColorChange = { color in
            events.append(color == nil ? "colour-off" : "colour-on")
            return color == nil ? [] : [.corsair]
        }

        XCTAssertTrue(
            coordinator.enter(source: .corsair, cell: PhysicalCell.colorProofEntry)
        )
        XCTAssertEqual(Array(events.prefix(2)), ["mode-on", "colour-on"])
    }

    func testSnapshotCarriesGenericModeLegendAndIndependentLightingTargets() {
        coordinator.onColorChange = { _ in [.razer] }
        XCTAssertTrue(coordinator.enter(source: .razer, cell: PhysicalCell(rawValue: 4)!))

        let snapshot = hud.snapshots.last
        XCTAssertEqual(snapshot?.modeTitle, "Colour Proof")
        XCTAssertEqual(snapshot?.legend, ColorProofPalette.legend)
        XCTAssertEqual(snapshot?.legend[3].actionTitle, "Solid Lime")
        XCTAssertEqual(snapshot?.lightingTargets, [.razer])
        XCTAssertTrue(snapshot?.lightingAvailable == true)
    }

    func testOneLightingAdapterFailureDoesNotSuppressTheOther() {
        coordinator.onColorChange = { _ in [.corsair, .razer] }
        XCTAssertTrue(coordinator.enter(source: .razer, cell: PhysicalCell(rawValue: 4)!))

        coordinator.handleLightingUnavailable(.corsair)

        XCTAssertEqual(coordinator.lightingTargets, [.razer])
        XCTAssertEqual(hud.snapshots.last?.lightingTargets, [.razer])
    }
}
