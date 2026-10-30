import AppKit
import ScimitarKit
import SwiftUI
@testable import ScimitarUI
import XCTest

/// Renders the wand's weapon wheel through the real coordinator snapshots
/// and the real view, at representative card counts and outline states.
/// Set WAND_RADIAL_VISUAL_OUTPUT to a directory to keep the PNGs.
final class WandRadialHUDTests: XCTestCase {
    private func coordinator(frontmost: AppSpecificTarget?) -> (ModePickerCoordinator, RecordingModeHUDPresenter) {
        let hud = RecordingModeHUDPresenter()
        let coordinator = ModePickerCoordinator(
            lease: WandModeLease(),
            hud: hud,
            scheduler: ManualTickScheduler(),
            log: Log(category: "test", sink: NullLogSink())
        )
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(
                target: frontmost,
                displayName: frontmost?.displayName ?? "Finder",
                bundleIdentifier: frontmost?.bundleIdentifier
            )
        }
        return (coordinator, hud)
    }

    private func homeSnapshot(frontmost: AppSpecificTarget?, focus: ModeHUDPointerFocus? = nil) throws -> ModeHUDSnapshot {
        let (coordinator, hud) = coordinator(frontmost: frontmost)
        coordinator.enterWandHome(source: .wand, pointerFocus: ModeHUDPointerFocus(cell: .switchApp))
        if let focus { coordinator.setPointerFocus(focus) }
        return try XCTUnwrap(hud.snapshots.last)
    }

    private func childSnapshot(
        open: (ModePickerCoordinator) -> Void,
        frontmost: AppSpecificTarget? = .chrome,
        focus: ((WandRadialLayout) -> ModeHUDPointerFocus?)? = nil
    ) throws -> ModeHUDSnapshot {
        let (coordinator, hud) = coordinator(frontmost: frontmost)
        coordinator.enterWandHome(source: .wand, pointerFocus: ModeHUDPointerFocus(cell: .switchApp))
        open(coordinator)
        if let focus, let value = focus(coordinator.wandRadialLayout) { coordinator.setPointerFocus(value) }
        return try XCTUnwrap(hud.snapshots.last)
    }

    private func select(_ coordinator: ModePickerCoordinator, _ raw: Int) {
        let cell = PhysicalCell(rawValue: raw)!
        coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .press))
        coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .release))
    }

    @MainActor
    private func render(_ snapshot: ModeHUDSnapshot) throws -> NSImage {
        let model = ModeHUDViewModel(source: .wand, appIconProvider: NoRadialIconProvider())
        model.apply(snapshot)
        let renderer = ImageRenderer(content: ModeHUDView(model: model).background(Color(white: 0.16)))
        renderer.scale = 1
        return try XCTUnwrap(renderer.nsImage)
    }

    private func navigatorFocus(
        _ layout: WandRadialLayout,
        from start: PhysicalCell,
        moves: [(Double, Double)]
    ) -> ModeHUDPointerFocus {
        var navigator = WandRadialNavigator(layout: layout, start: start)!
        for move in moves { navigator.apply(deltaX: move.0, deltaY: move.1) }
        return navigator.pointerFocus
    }

    // MARK: Layout contract

    func testHomeWheelCentresSwitchAppAndKeepsEveryOtherCardInOrder() throws {
        let home = try homeSnapshot(frontmost: .chrome)
        let layout = try XCTUnwrap(home.wandRadialLayout)
        XCTAssertEqual(layout.center, .switchApp)
        let others = home.legend.map(\.cell).filter { $0 != .switchApp && !WandOuterLayer.cells.contains($0) }
        XCTAssertEqual(Set(layout.ring), Set(others), "every other home card, once")
        XCTAssertEqual(layout.ring.count, others.count)
        // Ethan's grouped order (2026-10-30), from one definition.
        XCTAssertEqual(layout.ring, WandRingOrder.home)
        XCTAssertEqual(layout.ring.last, .frontmostAppModeSelector, "the app card at 12 o'clock")
        XCTAssertEqual(layout.ring.firstIndex(of: .wandPlayPause), layout.ring.firstIndex(of: .modePickerEntry).map { $0 + 1 },
                       "Play/Pause stays immediately after Utility, clockwise")
        XCTAssertEqual(layout.outer.map(\.cell), [.wandZoom, .wandCodexNewChat, .wandSpace, .wandUndo].sorted {
            layout.outerIndex(of: $0)! < layout.outerIndex(of: $1)!
        }, "outer cards follow their parents clockwise")
        XCTAssertEqual(Set(layout.outer.map(\.cell)), [.wandSpace, .wandUndo, .wandCodexNewChat, .wandZoom])

        // Ethan: "you don't want to break your muscle memory of like where
        // exactly the normal wedge stuff is." VS Code adds outer cards only.
        let vsCode = try XCTUnwrap(homeSnapshot(frontmost: .vsCode).wandRadialLayout)
        XCTAssertEqual(vsCode.ring, layout.ring, "the twelve ring cards keep their exact clock positions")
        for index in layout.ring.indices {
            XCTAssertEqual(vsCode.angle(at: index), layout.angle(at: index), accuracy: 1e-12)
        }
        XCTAssertEqual(Set(vsCode.outer.map(\.cell)), [.wandReviewChanges, .wandReviewFiles, .wandSpace, .wandUndo, .wandCodexNewChat, .wandZoom])
        let app = try XCTUnwrap(vsCode.ringIndex(of: .frontmostAppModeSelector))
        let review = try XCTUnwrap(vsCode.outerIndex(of: .wandReviewChanges))
        let stage = try XCTUnwrap(vsCode.outerIndex(of: .wandReviewFiles))
        XCTAssertEqual(vsCode.outerHalfWidth(at: review) * 2, vsCode.sectorWidth / 2, accuracy: 1e-12, "they share the app wedge")
        XCTAssertLessThan(vsCode.outerAngle(at: review), vsCode.angle(at: app), "Review changes first, clockwise")
        XCTAssertGreaterThan(vsCode.outerAngle(at: stage), vsCode.angle(at: app))
        let keys = try XCTUnwrap(vsCode.outerIndex(of: .wandUndo))
        XCTAssertEqual(vsCode.outerAngle(at: keys), vsCode.angle(at: try XCTUnwrap(vsCode.ringIndex(of: .keysModeEntry))), accuracy: 1e-12)
        XCTAssertEqual(vsCode.outer[keys].height, .thin, "Undo is a very thin card")
        XCTAssertEqual(vsCode.outer[review].height, .large, "the review pair is bigger")
    }

    func testWandHomeShowsCloseAndCopyPasteWithoutSpaceOrHoldCommand() throws {
        let home = try homeSnapshot(frontmost: .chrome)
        let close = try XCTUnwrap(home.legend.first { $0.cell == .modeExit })
        XCTAssertEqual(close.actionTitle, "Close")
        XCTAssertFalse(home.legend.contains { $0.actionTitle.contains("⌘") }, "no Hold Command on the wand HUD")
        let clip = try XCTUnwrap(home.legend.first { $0.cell == .clipboardWheelControl })
        XCTAssertNil(clip.gesture?.click, "Space is its own outer card on the wand")
        XCTAssertFalse(clip.actionTitle.contains("Space"))
        XCTAssertEqual(home.legend.first { $0.cell == .wandSpace }?.actionTitle, "Space")
        XCTAssertEqual(home.legend.first { $0.cell == .wandUndo }?.actionTitle, "Undo")
        // The wand sends plain Forward; the 5 + 6 volume chord is physical only.
        XCTAssertEqual(home.legend.first { $0.cell == YouTubeVolumeModifierCommand.triggerCell }?.actionTitle, "Forward")
        // Ethan: "Make it taller and the text bigger so I can read it."
        let layout = try XCTUnwrap(home.wandRadialLayout)
        let geometry = WandWheelGeometry(layout: layout)
        for cell in [PhysicalCell.wandUndo, .wandSpace] {
            let index = try XCTUnwrap(layout.outerIndex(of: cell))
            let wedge = geometry.outerWedge(at: index)
            XCTAssertGreaterThanOrEqual(wedge.outer - wedge.inner, 50)
            let text = try XCTUnwrap(WandOuterCardText.layout(title: cell == .wandUndo ? "Undo" : "Space", wedge: wedge, lines: 1))
            XCTAssertGreaterThanOrEqual(text.titleSize, 20, "readable outer text")
            XCTAssertLessThanOrEqual(wedge.outer + WandCardLift.rise, WandWheelMetrics.wheelSize / 2, "stays inside the fixed wheel frame")
        }
        // The physical mice keep Legend toggle · Hold ⌘ and Copy / Paste's Space click.
        for source in MouseSource.allCases where source != .wand {
            let mouse = DefaultMapLegend.snapshot(source: source)
            XCTAssertEqual(mouse.legend.first { $0.cell == DefaultMapHintCommand.triggerCell(for: source) }?.actionTitle,
                           ModeHUDCopy.legendToggleTitle)
            XCTAssertEqual(mouse.legend.first { $0.cell == .clipboardWheelControl }?.gesture?.click, "Space")
            XCTAssertTrue(mouse.legend.first { $0.cell == YouTubeVolumeModifierCommand.triggerCell }?.actionTitle.contains("Volume") == true,
                          "the physical mice keep the Forward / Hold + 6 for Volume chord")
            XCTAssertFalse(mouse.legend.contains { $0.cell.isWandOnlySlot })
        }
    }

    func testChildPagesCentreTheirOwnExitAndDropSparesAndDuplicateExits() throws {
        let keys = try childSnapshot(open: { self.select($0, 9) })
        let keysLayout = try XCTUnwrap(keys.wandRadialLayout)
        XCTAssertEqual(keysLayout.center, .modeExit)
        XCTAssertEqual(keysLayout.ring.count % 2, 1, "Keys is an odd-count wheel: \(keysLayout.ring.count)")

        let codex = try childSnapshot(open: { self.select($0, 2) }, frontmost: .codex)
        let codexLayout = try XCTUnwrap(codex.wandRadialLayout)
        XCTAssertEqual(codexLayout.center, .frontmostAppModeSelector)
        XCTAssertFalse(codexLayout.contains(.modeExit), "cell 10 is the same exit as the centre")
        for item in codex.legend where item.isUnassignedSpare {
            XCTAssertFalse(codexLayout.contains(item.cell), "a Spare never takes a wand slot")
        }
    }

    @MainActor
    func testPhysicalMiceNeverDrawTheWheelAndKeepTheirGridWidth() throws {
        for source in MouseSource.allCases {
            let hud = RecordingModeHUDPresenter()
            let mouse = ModePickerCoordinator(lease: WandModeLease(), hud: hud, scheduler: ManualTickScheduler(),
                                              log: Log(category: "test", sink: NullLogSink()))
            mouse.enterKeys(source: source)
            let snapshot = try XCTUnwrap(hud.snapshots.last)
            XCTAssertNil(snapshot.wandRadialLayout)
            let model = ModeHUDViewModel(source: source, appIconProvider: NoRadialIconProvider())
            model.apply(snapshot)
            let renderer = ImageRenderer(content: ModeHUDView(model: model))
            renderer.scale = 1
            XCTAssertEqual(try XCTUnwrap(renderer.nsImage).size.width, 705, accuracy: 1, "\(source) keeps its grid")
        }
    }

    func testReduceMotionRemovesEveryWheelAnimation() {
        XCTAssertNil(WandRadialFocusStyle.slideAnimation(reduceMotion: true))
        XCTAssertNil(WandRadialFocusStyle.pullAnimation(reduceMotion: true))
        XCTAssertNotNil(WandRadialFocusStyle.slideAnimation(reduceMotion: false))
        XCTAssertNotNil(WandRadialFocusStyle.pullAnimation(reduceMotion: false))
    }

    func testOutlineSlidesTheShortWayRoundTheWheel() {
        let model = ModeHUDViewModel(source: .wand, appIconProvider: NoRadialIconProvider())
        var home = ModeHUDSnapshot(isActive: true, modeTitle: "Default mode", source: .wand, selection: nil,
                                   legend: DefaultMapLegend.snapshot(source: .wand).legend
                                       + [ModeHUDLegendItem(cell: .wandPlayPause, actionTitle: "Play/Pause", accent: ModeHUDActionFamilyPalette.media)],
                                   accent: DefaultMapLegend.accent, footerTitle: "Default mode")
        home.wandRadialLayout = .wandMenu(legend: home.legend, page: .modes, isHome: true)
        let layout = home.wandRadialLayout!
        let twelve = layout.ring.last!, one = layout.ring[0]
        home.pointerFocus = ModeHUDPointerFocus(cell: twelve) // 12 o'clock, 2π
        model.apply(home)
        let top = model.wandFocusAngle
        home.pointerFocus = ModeHUDPointerFocus(cell: one) // 1 o'clock
        XCTAssertTrue(model.apply(home))
        XCTAssertEqual(model.wandFocusAngle - top, layout.sectorWidth, accuracy: 1e-9,
                       "12 o'clock → 1 o'clock moves one sector clockwise, not eleven back")
        home.pointerFocus = ModeHUDPointerFocus(cell: twelve)
        XCTAssertTrue(model.apply(home))
        XCTAssertEqual(model.wandFocusAngle, top, accuracy: 1e-9)
    }

    /// The angle each card is drawn at is the angle the navigator selects.
    func testDrawnCardsSitExactlyWhereSelectionAimsForThem() {
        let layout = WandRadialLayout(center: .modeExit, ring: PhysicalCell.all.filter { $0 != .modeExit })
        let geometry = WandWheelGeometry(layout: layout)
        for (index, cell) in layout.ring.enumerated() {
            let wedge = geometry.wedge(at: index)
            XCTAssertEqual(wedge.centerAngle, layout.angle(at: index))
            let rest = WandRadialNavigator.restingPosition(of: cell, in: layout)
            XCTAssertEqual(WandRadialLayout.angularDifference(WandRadialLayout.angle(x: rest.x, y: rest.y), wedge.centerAngle),
                           0, accuracy: 1e-9)
            let mid = (wedge.inner + wedge.outer) / 2
            let direction = WandWedge.radial(wedge.centerAngle)
            XCTAssertTrue(wedge.contains(CGPoint(x: direction.x * mid, y: direction.y * mid), margin: 0))
            for anchor in geometry.textAnchors(at: index) {
                XCTAssertTrue(wedge.contains(anchor, margin: 0), "text for \(cell) is laid out in its own card")
            }
        }
    }

    func testLiquidOutlineIsExactAtRestAndMovesItsCornersWhenPulled() {
        let wedge = WandWheelGeometry(layout: WandRadialLayout(center: .modeExit, ring: PhysicalCell.all.filter { $0 != .modeExit }))
            .wedge(at: 2).expanded(by: WandWheelMetrics.focusOutset)
        XCTAssertEqual(wedge.liquidOutline(along: 0, inward: 0), wedge.outline(), "rest is the card's own shape")
        let rest = wedge.outline()
        let pulled = wedge.liquidOutline(along: 0.8, inward: 0)
        func bounds(_ points: [CGPoint]) -> CGRect {
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }
        // Every part of the silhouette travels: the leading and trailing
        // ends both move clockwise, the leading end further.
        func angularExtent(_ points: [CGPoint]) -> (Double, Double) {
            let offsets = points.map { WandRadialLayout.angularDifference(WandRadialLayout.angle(x: Double($0.x), y: Double($0.y)), wedge.centerAngle) }
            return (offsets.min()!, offsets.max()!)
        }
        let (restStart, restEnd) = angularExtent(rest)
        let (pulledStart, pulledEnd) = angularExtent(pulled)
        XCTAssertGreaterThan(pulledEnd - restEnd, pulledStart - restStart, "the leading end reaches further")
        XCTAssertGreaterThan(pulledStart - restStart, 0, "the trailing end follows rather than staying pinned")
        XCTAssertTrue(pulled.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        XCTAssertNotEqual(bounds(pulled), bounds(rest))
        let disc = WandLiquidDisc.outline(radius: 100, pull: .zero)
        XCTAssertEqual(disc.map { hypot($0.x, $0.y) }.max()!, 100, accuracy: 1e-9)
        let drop = WandLiquidDisc.outline(radius: 100, pull: CGPoint(x: 0.8, y: 0))
        XCTAssertGreaterThan(drop.map(\.x).max()!, 120, "the drop reaches toward the pull")
        XCTAssertGreaterThan(drop.map(\.x).min()!, -100, "and its trailing side follows")
    }

    // MARK: Renders

    @MainActor
    func testWheelRendersInOneFixedFrameForEveryCountAndOutlineState() throws {
        let home = try homeSnapshot(frontmost: .chrome)
        let layout = try XCTUnwrap(home.wandRadialLayout)
        let utility = PhysicalCell.modePickerEntry
        var states: [(String, ModeHUDSnapshot)] = [("home-rest", home)]

        var centrePull = home
        centrePull.pointerFocus = navigatorFocus(layout, from: .switchApp, moves: [(3.2, -2.4)])
        states.append(("home-centre-pull", centrePull))

        var ring = home
        ring.pointerFocus = navigatorFocus(layout, from: .switchApp, moves: [(0, -10)])
        states.append(("home-ring-arrival", ring))

        var along = home
        along.pointerFocus = navigatorFocus(layout, from: utility, moves: [(1.4, 0)])
        states.append(("ring-partial-along", along))

        var nearBoundary = home
        nearBoundary.pointerFocus = navigatorFocus(layout, from: utility, moves: [(3.1, 0.5)])
        states.append(("ring-near-boundary", nearBoundary))

        var inward = home
        inward.pointerFocus = navigatorFocus(layout, from: utility, moves: [(0, 5.2)])
        states.append(("ring-inward", inward))

        var diagonal = home
        diagonal.pointerFocus = navigatorFocus(layout, from: PhysicalCell(rawValue: 4)!, moves: [(-2.2, -2.6)])
        states.append(("ring-diagonal", diagonal))

        var armed = home
        armed.pointerFocus = ModeHUDPointerFocus(cell: PhysicalCell(rawValue: 1)!, isArmed: true)
        states.append(("ring-armed", armed))

        var adjusting = home
        adjusting.pointerFocus = ModeHUDPointerFocus(
            cell: PhysicalCell(rawValue: 1)!,
            adjustment: ModeHUDWheelAdjustment(pull: -0.7, netSteps: 2, sentSteps: 2, lastStepWasUp: true)
        )
        states.append(("ring-adjusting", adjusting))

        let vsCode = try homeSnapshot(frontmost: .vsCode)
        var vsCodeReview = vsCode
        vsCodeReview.wandReviewSelection = .wandReviewChanges
        vsCodeReview.pointerFocus = ModeHUDPointerFocus(cell: .wandReviewFiles, pullX: -0.35, pullY: 0)
        states.append(("home-vscode-outer-review", vsCodeReview))

        var vsCodeRest = vsCode
        vsCodeRest.pointerFocus = ModeHUDPointerFocus(cell: .switchApp)
        states.append(("home-vscode-rest", vsCodeRest))

        let vsLayout = try XCTUnwrap(vsCode.wandRadialLayout)
        var leanOut = vsCode
        leanOut.pointerFocus = navigatorFocus(vsLayout, from: .frontmostAppModeSelector,
                                              moves: [(sin(vsLayout.angle(at: 1)) * 4.5, -cos(vsLayout.angle(at: 1)) * 4.5)])
        states.append(("home-vscode-app-lean-out", leanOut))

        var undo = home
        undo.pointerFocus = navigatorFocus(layout, from: .keysModeEntry, moves: [(-8.5, 0)])
        states.append(("home-outer-undo", undo))

        var space = home
        space.pointerFocus = ModeHUDPointerFocus(cell: .wandSpace)
        states.append(("home-outer-space", space))

        var armedSwitch = home
        armedSwitch.pointerFocus = ModeHUDPointerFocus(cell: .switchApp, isArmed: true)
        states.append(("home-switch-app-armed", armedSwitch))

        var switchChoosing = home
        switchChoosing.pointerFocus = ModeHUDPointerFocus(
            cell: .switchApp, adjustment: ModeHUDWheelAdjustment(pull: 0.4, netSteps: 2, sentSteps: 2, lastStepWasUp: false))
        states.append(("home-switch-app-held-choosing", switchChoosing))

        var clipboardDotted = home
        clipboardDotted.pointerFocus = ModeHUDPointerFocus(
            cell: .clipboardWheelControl, adjustment: ModeHUDWheelAdjustment(pull: -0.3, netSteps: 1, sentSteps: 1, lastStepWasUp: true))
        states.append(("home-copy-paste-dotted", clipboardDotted))

        let keys = try childSnapshot(open: { self.select($0, 9) }, focus: { layout in
            self.navigatorFocus(layout, from: .modeExit, moves: [(-6.8, 2.4)])
        })
        states.append(("keys-odd", keys))

        let codex = try childSnapshot(open: { self.select($0, 2) }, frontmost: .codex)
        states.append(("codex-child", codex))

        // Utility submenu: Zoom (cell 11 on a child page, never Switch App)
        // in dotted mode, and plain unheld wedge selection on the same page.
        let zoomCell = try XCTUnwrap(WheelChordControl.zoom.utilityCell)
        let utilityZoom = try childSnapshot(open: { self.select($0, 12) }, focus: { _ in
            ModeHUDPointerFocus(cell: zoomCell, adjustment: ModeHUDWheelAdjustment(pull: 0.5, netSteps: -1, sentSteps: 1, lastStepWasUp: false))
        })
        states.append(("utility-zoom-dotted", utilityZoom))
        let utilityAim = try childSnapshot(open: { self.select($0, 12) }, focus: { layout in
            self.navigatorFocus(layout, from: .modeExit, moves: [(5, -6)])
        })
        states.append(("utility-wedge-selection", utilityAim))

        var chromeHome = home
        chromeHome.pointerFocus = ModeHUDPointerFocus(cell: .frontmostAppModeSelector)
        states.append(("home-app-artwork", chromeHome))

        // Ethan's third-layer Zoom beyond New Codex chat, aimed and adjusting.
        var zoomAimed = home
        zoomAimed.pointerFocus = navigatorFocus(layout, from: .modePickerEntry,
                                                moves: [(sin(layout.outerAngle(at: layout.outerIndex(of: .wandZoom)!)) * 17,
                                                         -cos(layout.outerAngle(at: layout.outerIndex(of: .wandZoom)!)) * 17)])
        states.append(("home-outer-zoom-aimed", zoomAimed))
        var zoomAdjusting = home
        zoomAdjusting.pointerFocus = ModeHUDPointerFocus(
            cell: .wandZoom, adjustment: ModeHUDWheelAdjustment(pull: 0.6, netSteps: 2, sentSteps: 2, lastStepWasUp: true))
        states.append(("home-outer-zoom-adjusting", zoomAdjusting))
        // Spaces moves left and right on the wand: ↔ title and arrows.
        let spacesAdjusting = try childSnapshot(open: { self.select($0, 12) }, focus: { _ in
            ModeHUDPointerFocus(cell: .spacesWheelControl, adjustment: ModeHUDWheelAdjustment(
                pull: 0.5, netSteps: 1, sentSteps: 1, lastStepWasUp: false, isHorizontal: true))
        })
        states.append(("utility-spaces-adjusting", spacesAdjusting))

        var sizes: Set<String> = []
        var images: [(String, NSImage)] = []
        for (name, snapshot) in states {
            let image = try render(snapshot)
            sizes.insert("\(image.size.width)x\(image.size.height)")
            images.append((name, image))
        }
        XCTAssertEqual(sizes.count, 1, "no count or outline state may change the panel: \(sizes)")
        let size = try XCTUnwrap(images.first?.1.size)
        XCTAssertEqual(size.width, WandWheelMetrics.panelWidth, accuracy: 1)

        if let directory = ProcessInfo.processInfo.environment["WAND_RADIAL_VISUAL_OUTPUT"] {
            // ImageRenderer cannot draw AppKit's native glass, so inspection
            // renders show the wheel and footer over a dark stand-in.
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            // Each case's fitted text, beside its PNG, so the shared fitting
            // rules can be judged card by card (size, rows, tilt, arrows).
            var report = ""
            for (name, snapshot) in states {
                report += Self.typographyReport(name: name, snapshot: snapshot)
            }
            try report.write(toFile: (directory as NSString).appendingPathComponent("typography.txt"), atomically: true, encoding: .utf8)
            // The wand footer (notification / mode / gesture hint) under the wheel.
            for (name, feedback) in [("footer-home-rest", nil), ("footer-feedback", ModeHUDFeedback(message: "Copied", tone: .confirmed))] {
                let model = ModeHUDViewModel(source: .wand, appIconProvider: NoRadialIconProvider())
                model.apply(home)
                model.feedback = feedback
                let renderer = ImageRenderer(content: ModeHUDView(model: model, usesNativeGlass: false).background(Color(white: 0.11)))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
            for (name, snapshot) in states {
                let icons: ModeHUDAppIconProviding = name.contains("artwork") ? SystemIconProvider() : NoRadialIconProvider()
                let model = ModeHUDViewModel(source: .wand, appIconProvider: icons)
                model.apply(snapshot)
                let content = WandRadialWheel(model: model, reduceMotion: false, usesNativeGlass: false)
                    .padding(WandWheelMetrics.panelPadding)
                    .background(RoundedRectangle(cornerRadius: 27).fill(Color(white: 0.11)))
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.nsImage)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
        }
    }
}

extension WandRadialHUDTests {
    /// One line per drawn card: slot, size, rows and tilt, plus the arrow
    /// pair for an adjusting card, exactly as the wheel plans them.
    static func typographyReport(name: String, snapshot: ModeHUDSnapshot) -> String {
        guard let layout = snapshot.wandRadialLayout else { return "" }
        let geometry = WandWheelGeometry(layout: layout)
        let cards = Dictionary(snapshot.legend.map {
            ($0.cell, WandWheelPlan.Entry(title: $0.displayTitle(on: .wand), label: WandRadialWheel.caption(for: $0.cell, in: layout) ?? "",
                                          labelStyle: .caption, reservesArrows: $0.gesture?.isAvailable(on: .wand) == true))
        }, uniquingKeysWith: { first, _ in first })
        let plan = WandWheelPlan.plan(for: geometry, cards: cards)
        func describe(_ slot: String, _ cell: PhysicalCell, _ text: WandCardText?) -> String {
            guard let text else { return "  \(slot) \(cell.rawValue): no layout\n" }
            let rows = text.lines.map(\.text).joined(separator: " | ")
            let caption = text.label.text.isEmpty ? "" : " [caption: \(text.label.text)]"
            return String(format: "  %@ %d: %.1f pt, %d row(s), tilt %.0f°: %@%@\n", slot, cell.rawValue, text.titleSize,
                          text.lines.count, text.rotation * 180 / .pi, rows, caption)
        }
        var out = "\(name) (shared \(plan.sharedSize) pt)\n"
        if let center = layout.center { out += describe("centre", center, plan.center?.text) }
        for (index, cell) in layout.ring.enumerated() { out += describe("ring\(index)", cell, plan.ring[index].text) }
        for (index, card) in layout.outer.enumerated() where index < plan.outer.count {
            out += describe("outer\(index)", card.cell, plan.outer[index].text)
        }
        if let focus = snapshot.pointerFocus, let adjustment = focus.adjustment, let slot = geometry.slot(for: focus.cell) {
            if let arrows = WandAdjustArrowPlacement.points(for: slot, horizontal: adjustment.isHorizontal, in: geometry,
                                                            avoiding: plan.text(for: slot)) {
                out += String(format: "  arrows %d: (%.0f, %.0f) (%.0f, %.0f)\n", focus.cell.rawValue,
                              arrows.negative.x, arrows.negative.y, arrows.positive.x, arrows.positive.y)
            }
        }
        return out
    }
}

private final class NoRadialIconProvider: ModeHUDAppIconProviding {
    func icon(for backdrop: ModeHUDAppBackdrop) -> NSImage? { nil }
}

/// Inspection only: a real installed system icon stands in for the app.
private final class SystemIconProvider: ModeHUDAppIconProviding {
    func icon(for backdrop: ModeHUDAppBackdrop) -> NSImage? {
        NSWorkspace.shared.icon(forFile: "/System/Applications/Calculator.app")
    }
}

final class WandWheelPlanTimingTests: XCTestCase {
    /// First use of a new card count must not hitch the main thread.
    func testPlanningANewWheelIsCheap() {
        for count in [9, 13, 15, 16] {
            let cells = PhysicalCell.all.filter { $0 != .modeExit } + [.wandPlayPause, .wandReviewChanges, .wandReviewFiles, .switchApp]
            let layout = WandRadialLayout(center: .modeExit, ring: Array(cells.prefix(count)))
            let cards = Dictionary(uniqueKeysWithValues: layout.cells.map {
                ($0, WandWheelPlan.Entry(title: "Horizontal Scroll + Wheel \(count)", label: "CORSAIR 12"))
            })
            let start = ProcessInfo.processInfo.systemUptime
            _ = WandWheelPlan.plan(for: WandWheelGeometry(layout: layout), cards: cards)
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            XCTAssertLessThan(elapsed, 0.25, "\(count) cards took \(elapsed) s")
        }
    }
}

/// Ethan: "make the text bigger in the HUD". Larger whole-word titles laid
/// out in each card's real shape, at a size most cards share.
final class WandWheelTypographyTests: XCTestCase {
    private func snapshot(_ frontmost: AppSpecificTarget?, open: [Int] = []) -> ModeHUDSnapshot {
        let hud = RecordingModeHUDPresenter()
        let coordinator = ModePickerCoordinator(lease: WandModeLease(), hud: hud, scheduler: ManualTickScheduler(),
                                                log: Log(category: "test", sink: NullLogSink()))
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(target: frontmost, displayName: frontmost?.displayName ?? "Finder", bundleIdentifier: frontmost?.bundleIdentifier)
        }
        coordinator.enterWandHome(source: .wand, pointerFocus: ModeHUDPointerFocus(cell: .switchApp))
        for raw in open {
            let cell = PhysicalCell(rawValue: raw)!
            coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .press))
            coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .release))
        }
        return hud.snapshots.last!
    }

    private func opened(_ frontmost: AppSpecificTarget?, open: [Int] = []) -> (ModePickerCoordinator, ModeHUDSnapshot) {
        let hud = RecordingModeHUDPresenter()
        let coordinator = ModePickerCoordinator(lease: WandModeLease(), hud: hud, scheduler: ManualTickScheduler(),
                                                log: Log(category: "test", sink: NullLogSink()))
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(target: frontmost, displayName: frontmost?.displayName ?? "Finder", bundleIdentifier: frontmost?.bundleIdentifier)
        }
        coordinator.enterWandHome(source: .wand, pointerFocus: ModeHUDPointerFocus(cell: .switchApp))
        for raw in open {
            let cell = PhysicalCell(rawValue: raw)!
            coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .press))
            coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .release))
        }
        return (coordinator, hud.snapshots.last!)
    }

    private func entries(_ snapshot: ModeHUDSnapshot) -> [PhysicalCell: WandWheelPlan.Entry] {
        Dictionary(snapshot.legend.map {
            // Plan exactly what the wheel draws, motion arrow included.
            ($0.cell, WandWheelPlan.Entry(title: $0.displayTitle(on: .wand), label: $0.printedControlLabel(on: .wand).uppercased(),
                                          reservesArrows: $0.gesture?.isAvailable(on: .wand) == true))
        }, uniquingKeysWith: { first, _ in first })
    }

    private func plan(
        _ snapshot: ModeHUDSnapshot,
        tilt: WandCardTypography.TiltPolicy = .whenLarger
    ) -> (WandWheelGeometry, WandWheelPlan) {
        let geometry = WandWheelGeometry(layout: snapshot.wandRadialLayout!)
        return (geometry, WandWheelPlan.plan(for: geometry, cards: entries(snapshot), tilt: tilt))
    }

    private var everyPage: [(String, ModeHUDSnapshot)] {
        [("home", snapshot(.chrome)), ("VS Code home", snapshot(.vsCode)), ("Finder home", snapshot(nil)),
         ("Keys", snapshot(.chrome, open: [9])), ("Codex", snapshot(.codex, open: [2])),
         ("Utility", snapshot(.chrome, open: [12])), ("Extra Utilities", snapshot(.chrome, open: [12, 12])),
         ("Chrome", snapshot(.chrome, open: [2])), ("VS Code", snapshot(.vsCode, open: [2])),
         ("Spotify", snapshot(.spotify, open: [2]))]
    }

    func testTitlesAreAsLargeAsTheirCardsAllow() {
        // The first wheel capped every ring title at 13 pt, and the crowded
        // VS Code home fell to 9.5 pt; the level-only planner reached 18 and
        // 17.5. Ethan: "make it as big as possible".
        let pages: [(String, ModeHUDSnapshot, CGFloat, CGFloat)] = [
            ("home", snapshot(.chrome), 21.5, 16.5),
            ("VS Code home", snapshot(.vsCode), 19.5, 13),
            ("Keys", snapshot(.chrome, open: [9]), 25.5, 21.5),
            ("Codex", snapshot(.codex, open: [2]), 25.5, 22),
            ("Utility", snapshot(.chrome, open: [12]), 20.5, 18.5),
            ("Chrome", snapshot(.chrome, open: [2]), 25.5, 24),
        ]
        for (name, page, sharedFloor, cardFloor) in pages {
            let (_, plan) = plan(page)
            XCTAssertGreaterThanOrEqual(plan.sharedSize, sharedFloor, name)
            for card in plan.ring { XCTAssertGreaterThanOrEqual(card.titleSize, cardFloor, "\(name) card") }
            XCTAssertGreaterThanOrEqual(plan.center?.titleSize ?? 0, 28, "\(name) centre")
            XCTAssertLessThanOrEqual(plan.sharedSize, WandCardTypography.maximumRingSize)
        }
    }

    func testOneLongTitleNeverShrinksTheRestOfTheWheel() {
        let page = snapshot(.vsCode)
        let geometry = WandWheelGeometry(layout: page.wandRadialLayout!)
        let normal = WandWheelPlan.plan(for: geometry, cards: entries(page))
        var cards = entries(page)
        let victim = page.wandRadialLayout!.ring[3]
        cards[victim] = .init(title: "An extraordinarily long hypothetical action name that cannot fit comfortably", label: "WAND")
        let long = WandWheelPlan.plan(for: geometry, cards: cards)
        XCTAssertGreaterThanOrEqual(long.sharedSize, normal.sharedSize - WandCardTypography.step,
                                    "one outlier moves the shared size by at most one step")
        XCTAssertLessThan(long.ring[3].titleSize, long.sharedSize - 2, "the long title shrinks on its own")
        for index in long.ring.indices where index != 3 {
            XCTAssertGreaterThanOrEqual(long.ring[index].titleSize, normal.ring[index].titleSize - WandCardTypography.step)
        }
    }

    func testEveryTitleKeepsWholeWordsInsideItsOwnCard() {
        for (_, page) in everyPage {
            let (geometry, plan) = plan(page)
            for (index, cell) in geometry.layout.ring.enumerated() {
                let item = page.legend.first { $0.cell == cell }!
                guard let text = plan.ring[index].text else { return XCTFail("\(item.actionTitle) has no layout") }
                // Whole words in order; a slash compound may wrap just after its slash.
                func unwrapped(_ value: String) -> String { value.replacingOccurrences(of: "/ ", with: "/") }
                let normalized = item.displayTitle(on: .wand).split(separator: " ").joined(separator: " ")
                XCTAssertEqual(unwrapped(text.lines.map(\.text).joined(separator: " ")), unwrapped(normalized), "whole words, in order")
                XCTAssertLessThanOrEqual(text.lines.count, WandCardTypography.maximumLines)
                for line in text.lines {
                    XCTAssertLessThanOrEqual(line.measured, line.room + 0.01, "\(line.text) fits its line")
                    XCTAssertFalse(["·", "/", "+"].contains(String(line.text.prefix(1))), "no line starts with a separator: \(line.text)")
                }
                XCTAssertEqual(text.label.text, item.printedControlLabel(on: .wand).uppercased(), "the printed label stays underneath")
                XCTAssertGreaterThan(text.label.center.y, text.lines.last!.center.y)
                // Where it is drawn, including any tilt.
                let wedge = geometry.wedge(at: index)
                for corners in text.drawnCorners {
                    for corner in corners {
                        XCTAssertTrue(wedge.contains(corner, margin: 0), "\(item.actionTitle) stays inside its card")
                    }
                }
                for (a, b) in zip(text.rows, text.rows.dropFirst()) {
                    XCTAssertLessThanOrEqual(a.maxY, b.minY + 0.01, "rows never overlap")
                }
            }
        }
        let codex = plan(snapshot(.codex, open: [2]))
        let voice = codex.0.layout.ring.firstIndex { $0.rawValue == 12 }!
        XCTAssertFalse(codex.1.ring[voice].text!.label.text.contains("❌"), "accepted Voice control has no stale repair marker")
    }

    // MARK: Tilt

    /// Ethan: "make the text be like angled correctly so it has more space ...
    /// although it's easier to read [level]". A card tilts only to follow its
    /// own shape, and only where that makes its title clearly larger.
    func testTiltFollowsItsCardExactlyAndAlwaysReadsUpright() {
        for (name, page) in everyPage {
            let (geometry, plan) = plan(page)
            for (index, card) in plan.ring.enumerated() {
                guard let text = card.text, text.rotation != 0 else { continue }
                XCTAssertLessThanOrEqual(abs(text.rotation), WandCardTypography.maximumTilt + 1e-9,
                                         "\(name): never steeper than the limit, never upside down")
                let theta = geometry.layout.angle(at: index)
                let along = WandWheelGeometry.upright(theta - .pi / 2), across = WandWheelGeometry.upright(theta)
                XCTAssertTrue(abs(text.rotation - along) < 1e-9 || abs(text.rotation - across) < 1e-9,
                              "\(name): exactly along or across its card, never a random slant")
                XCTAssertLessThanOrEqual(text.lines.count, WandCardTypography.maximumTiltedLines,
                                         "\(name): a tilted block stays short")
                // Its lines read left to right.
                let start = text.drawn(CGPoint(x: -10, y: 0)), end = text.drawn(CGPoint(x: 10, y: 0))
                XCTAssertGreaterThan(end.x, start.x)
            }
        }
    }

    func testTiltIsUsedOnlyWhereItMakesTheTitleClearlyLarger() {
        XCTAssertFalse(WandCardTypography.tiltEarnsSpace(tilted: 22, flat: 21), "1 pt is not worth a tilt")
        XCTAssertFalse(WandCardTypography.tiltEarnsSpace(tilted: 26, flat: 24.5), "nor 6% on a roomy card")
        XCTAssertTrue(WandCardTypography.tiltEarnsSpace(tilted: 22, flat: 15.5))
        XCTAssertTrue(WandCardTypography.tiltEarnsSpace(tilted: 12, flat: nil), "level text that cannot fit at all")
        // The tilted search starts at the first size that could win.
        XCTAssertEqual(WandCardTypography.smallestWorthwhileTilt(flat: 21), 23.5)
        XCTAssertTrue(WandCardTypography.tiltEarnsSpace(tilted: 23.5, flat: 21))
        XCTAssertFalse(WandCardTypography.tiltEarnsSpace(tilted: 23, flat: 21))
        for (name, page) in everyPage {
            let (geometry, plan) = plan(page)
            let cards = entries(page)
            for (index, card) in plan.ring.enumerated() {
                guard let text = card.text, text.rotation != 0, let entry = cards[geometry.layout.ring[index]] else { continue }
                let flat = WandCardTextLayout(title: entry.title, label: entry.label, lock: false,
                                              room: WandCardRoom(shape: .wedge(geometry.wedge(at: index))),
                                              anchors: geometry.textAnchors(at: index))
                    .readableSize(maximum: WandCardTypography.maximumRingSize)
                XCTAssertGreaterThanOrEqual(text.titleSize - min(flat ?? 0, text.titleSize), WandCardTypography.tiltGain,
                                            "\(name): \(entry.title) tilts to \(text.titleSize) pt only because level text reaches \(flat ?? 0) pt")
            }
            let (_, level) = self.plan(page, tilt: .never)
            XCTAssertTrue(level.ring.allSatisfy { ($0.text?.rotation ?? 0) == 0 })
        }
    }

    func testTiltNeverShrinksACardAndKeepsMostOfTheWheelLevel() {
        for (name, page) in everyPage {
            let (_, tilted) = plan(page)
            let (_, level) = plan(page, tilt: .never)
            XCTAssertGreaterThanOrEqual(tilted.sharedSize, level.sharedSize, name)
            for (a, b) in zip(tilted.ring, level.ring) {
                XCTAssertGreaterThanOrEqual(a.titleSize, b.titleSize, "\(name): no card is smaller for its neighbours tilting")
            }
            let count = tilted.ring.filter { ($0.text?.rotation ?? 0) != 0 }.count
            XCTAssertLessThanOrEqual(count * 2, tilted.ring.count, "\(name): most cards stay level")
        }
        // The amount of improvement depends on the authored labels. Every
        // page above still proves tilt never shrinks a card or the shared size.
    }

    func testTiltedTextIsDrawnTurnedAboutTheWheelCentre() {
        let line = WandCardText.Line(text: "A", center: CGPoint(x: 0, y: -200), room: 50, measured: 10)
        var text = WandCardText(titleSize: 20, lineHeight: 24, lines: [line], label: line, lock: nil)
        XCTAssertEqual(text.drawn(line.center), line.center, "level text is drawn where it was laid out")
        text.rotation = .pi / 6
        let drawn = text.drawn(line.center)
        // 12 o'clock turned 30° clockwise lands at 1 o'clock.
        XCTAssertEqual(drawn.x, 200 * sin(.pi / 6), accuracy: 1e-9)
        XCTAssertEqual(drawn.y, -200 * cos(.pi / 6), accuracy: 1e-9)
        XCTAssertEqual(WandWheelGeometry.upright(.pi * 5 / 6), -.pi / 6, accuracy: 1e-9, "never upside down")
        XCTAssertEqual(WandWheelGeometry.upright(-.pi * 2 / 3), .pi / 3, accuracy: 1e-9)
    }

    func testSeparatorsStayWithTheWordBeforeThem() {
        XCTAssertEqual(WandCardTextLayout.breakableWords("YouTube · Hold 2× / Scrub + Wheel"),
                       ["YouTube ·", "Hold", "2× /", "Scrub +", "Wheel"])
        XCTAssertEqual(WandCardTextLayout.breakableWords("⌘S Save"), ["⌘S", "Save"])
    }

    /// A slash compound may wrap after its slash, which stays on the first
    /// row; spaced separators, short halves and symbols never split.
    func testSlashCompoundsMayWrapAfterTheSlash() {
        func tokens(_ title: String) -> [String] {
            WandCardTextLayout.breakableTokens(title).map { ($0.attached ? "+" : "") + $0.text }
        }
        XCTAssertEqual(tokens("Play/Pause"), ["Play/", "+Pause"])
        XCTAssertEqual(tokens("Pin/Unpin + Hold 2"), ["Pin/", "+Unpin +", "Hold", "2"])
        XCTAssertEqual(tokens("Copy / Paste ↕"), ["Copy /", "Paste ↕"])
        XCTAssertEqual(tokens("1/2 A/B"), ["1/2", "A/B"])
    }

    /// Ethan (2026-10-30) uses the wand lounging back from the screen. The
    /// narrow 12 o'clock wedge's Play/Pause used one small row; it now wraps
    /// at its slash and matches its neighbours.
    func testNarrowSlashCompoundWrapsToReachTheSharedSize() {
        // Play/Pause in the narrow 12 o'clock wedge, where it used to sit.
        let page = snapshot(.chrome)
        let home = page.wandRadialLayout!
        let layout = WandRadialLayout(center: home.center, ring: home.ring.filter { $0 != .wandPlayPause } + [.wandPlayPause])
        let geometry = WandWheelGeometry(layout: layout)
        let plan = WandWheelPlan.plan(for: geometry, cards: entries(page))
        let index = layout.ring.firstIndex(of: .wandPlayPause)!
        let text = plan.ring[index].text!
        XCTAssertEqual(text.lines.map(\.text), ["Play/", "Pause"])
        XCTAssertEqual(text.titleSize, plan.sharedSize, "no longer an outlier")
        XCTAssertEqual(text.rotation, 0)
    }

    /// Outer cards use the ring's fitting rules: inside their own band,
    /// upright, level unless following the band clearly earns space, and
    /// siblings on one parent wedge share a size.
    func testOuterCardsFitTheirBandsUprightAndSiblingsShareOneSize() {
        for (name, page) in [("home", snapshot(.chrome)), ("VS Code home", snapshot(.vsCode))] {
            let (geometry, plan) = plan(page)
            let layout = geometry.layout
            XCTAssertEqual(plan.outer.count, layout.outer.count, name)
            for (index, card) in layout.outer.enumerated() {
                let text = try! XCTUnwrap(plan.outer[index].text, "\(name) \(card.cell)")
                let wedge = geometry.outerWedge(at: index)
                for corners in text.drawnCorners where corners[0] != corners[1] {
                    for corner in corners { XCTAssertTrue(wedge.contains(corner, margin: 0), "\(name): \(card.cell) stays in its band") }
                }
                XCTAssertGreaterThan(text.rotation, -.pi / 2 - 1e-9)
                XCTAssertLessThanOrEqual(text.rotation, .pi / 2 + 1e-9, "never upside down")
                let start = text.drawn(CGPoint(x: -10, y: 0)), end = text.drawn(CGPoint(x: 10, y: 0))
                XCTAssertTrue(end.x > start.x || (abs(end.x - start.x) < 1e-6 && end.y > start.y), "\(name): reads forward")
                XCTAssertLessThanOrEqual(text.lines.count, card.height == .large ? 2 : 1)
                // Undo and Space reach 26+ pt; New Codex chat and the review
                // pair are limited by their narrow sectors.
                XCTAssertGreaterThanOrEqual(text.titleSize, card.height == .large ? 15 : 18, "\(name): \(card.cell) readable")
                if [.wandUndo, .wandSpace].contains(card.cell) { XCTAssertGreaterThanOrEqual(text.titleSize, 26, "\(name): \(card.cell)") }
                if text.rotation != 0 {
                    let options = WandOuterCardText.candidates(title: page.legend.first { $0.cell == card.cell }!.displayTitle(on: .wand),
                                                               wedge: wedge, lines: card.height == .large ? 2 : 1)
                    XCTAssertLessThan(options.flatBest ?? 0, text.titleSize, "\(name): \(card.cell) tilts only where level text cannot reach its size")
                }
                for sibling in layout.outer.indices where layout.outer[sibling].parent == card.parent
                    && layout.outer[sibling].layer == card.layer {
                    XCTAssertEqual(plan.outer[sibling].titleSize, plan.outer[index].titleSize, "\(name): siblings match")
                }
            }
        }
    }

    /// Adjustment arrows never print over a title, on every card the wand
    /// can adjust, along that control's own axis (and Switch App choosing).
    func testAdjustmentArrowsKeepClearOfEveryTitle() {
        let pages: [(String, AppSpecificTarget?, [Int])] = [
            ("home", .chrome, []), ("VS Code home", .vsCode, []), ("Keys", .chrome, [9]), ("Codex", .codex, [2]),
            ("Utility", .chrome, [12]), ("Extra Utilities", .chrome, [12, 12]), ("Chrome", .chrome, [2]),
            ("VS Code", .vsCode, [2]), ("Spotify", .spotify, [2]),
        ]
        var checked = 0
        for (name, frontmost, open) in pages {
            let (coordinator, page) = opened(frontmost, open: open)
            let (geometry, plan) = plan(page)
            var axes: [(PhysicalCell, Bool)] = geometry.layout.cells.compactMap { cell in
                coordinator.wandAdjustableControl(for: cell).map { (cell, $0.wandAxis == .horizontal) }
            }
            if open.isEmpty { axes.append((.switchApp, true)) }
            for (cell, horizontal) in axes {
                guard let slot = geometry.slot(for: cell), let text = plan.text(for: slot) else { continue }
                let arrows = WandAdjustArrowPlacement.points(for: slot, horizontal: horizontal, in: geometry, avoiding: text)
                guard let arrows else { XCTFail("\(name): \(cell.rawValue) has no arrows"); continue }
                let rows = WandAdjustArrowPlacement.drawnRows(text)
                for point in [arrows.negative, arrows.positive] {
                    let local = CGPoint(x: point.x - geometry.center.x, y: point.y - geometry.center.y)
                    let distance = rows.map { $0.distance(to: local) }.min() ?? .infinity
                    XCTAssertGreaterThanOrEqual(distance, WandAdjustArrowPlacement.textClearance,
                                                "\(name): \(cell.rawValue) \(horizontal ? "↔" : "↕") arrow overlaps its title")
                }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 10, "the adjustable cards were found")
    }
}

/// Ethan: the liquid outline should travel between cards, not fade out and
/// reappear.
final class WandLiquidMorphTests: XCTestCase {
    private let geometry = WandWheelGeometry(layout: WandRadialLayout(center: .switchApp, ring: PhysicalCell.all.filter { $0 != .switchApp }))
    private var wedge: WandWedge { geometry.wedge(at: 1).expanded(by: WandWheelMetrics.focusOutset) }
    private let radius = WandWheelMetrics.centerRadius + WandWheelMetrics.focusOutset

    private func area(_ points: [CGPoint]) -> CGFloat {
        abs(points.indices.reduce(CGFloat(0)) { sum, index in
            let p = points[index], q = points[(index + 1) % points.count]
            return sum + p.x * q.y - q.x * p.y
        }) / 2
    }

    func testTheEndsAreExactlyTheExistingOutlines() {
        let pull = CGPoint(x: 0.2, y: -0.3)
        XCTAssertEqual(WandLiquidMorph.outline(progress: 0, angle: wedge.centerAngle, pull: pull, towardCenter: true, wedge: wedge, discRadius: radius),
                       WandLiquidDisc.outline(radius: radius, pull: pull))
        let parts = wedge.components(ofPull: pull)
        XCTAssertEqual(WandLiquidMorph.outline(progress: 1, angle: wedge.centerAngle, pull: pull, towardCenter: false, wedge: wedge, discRadius: radius),
                       wedge.liquidOutline(along: parts.along, inward: parts.inward))
    }

    func testReturningToCenterDoesNotJumpAtDeparture() {
        let start = WandLiquidMorph.centroid(WandLiquidMorph.outline(progress: 1, angle: wedge.centerAngle,
            pull: .zero, towardCenter: true, wedge: wedge, discRadius: radius))
        let next = WandLiquidMorph.centroid(WandLiquidMorph.outline(progress: 0.999, angle: wedge.centerAngle,
            pull: .zero, towardCenter: true, wedge: wedge, discRadius: radius))
        XCTAssertLessThan(hypot(next.x - start.x, next.y - start.y), 1,
                          "a tiny animation step must not snap the outline inward")
    }

    func testTheMorphTravelsAsOneSolidBlobNeverFading() {
        let direction = WandWedge.radial(wedge.centerAngle)
        var previous: CGFloat = -1
        let smallest = min(area(WandLiquidDisc.outline(radius: radius, pull: .zero)), area(wedge.outline()))
        for towardCenter in [false, true] {
            previous = -1
            for step in 0...20 {
                let progress = Double(step) / 20
                let points = WandLiquidMorph.outline(progress: progress, angle: wedge.centerAngle, pull: .zero,
                                                     towardCenter: towardCenter, wedge: wedge, discRadius: radius)
                XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                XCTAssertGreaterThan(area(points), smallest * 0.5, "the outline never shrinks away")
                let centre = WandLiquidMorph.centroid(points)
                let travel = centre.x * direction.x + centre.y * direction.y
                XCTAssertGreaterThanOrEqual(travel, previous - 0.5, "it moves steadily toward the card")
                previous = travel
            }
        }
    }
}

/// Frames of the centre-to-card morph and a card-to-card slide, rendered at
/// fixed progress because ImageRenderer cannot capture a running animation.
/// Set WAND_RADIAL_VISUAL_OUTPUT to keep them.
final class WandMorphRenderTests: XCTestCase {
    @MainActor
    func testMorphFramesRender() throws {
        let hud = RecordingModeHUDPresenter()
        let coordinator = ModePickerCoordinator(lease: WandModeLease(), hud: hud, scheduler: ManualTickScheduler(),
                                                log: Log(category: "test", sink: NullLogSink()))
        coordinator.resolveFrontmostApp = { FrontmostAppModeContext(target: .chrome, displayName: "Chrome", bundleIdentifier: AppSpecificTarget.chrome.bundleIdentifier) }
        coordinator.enterWandHome(source: .wand, pointerFocus: nil)
        var home = try XCTUnwrap(hud.snapshots.last)
        home.pointerFocus = nil
        let layout = try XCTUnwrap(home.wandRadialLayout)
        let geometry = WandWheelGeometry(layout: layout)
        let target = try XCTUnwrap(layout.ringIndex(of: .frontmostAppModeSelector))
        let next = try XCTUnwrap(layout.ringIndex(of: .screenshotToggle))
        let model = ModeHUDViewModel(source: .wand, appIconProvider: NoMorphIconProvider())
        model.apply(home)

        func frame(progress: Double, angle: Double, towardCenter: Bool) -> some View {
            ZStack {
                WandRadialWheel(model: model, reduceMotion: true, usesNativeGlass: false)
                WandLiquidMorphOutline(progress: progress, angle: angle, pullX: 0, pullY: 0, towardCenter: towardCenter,
                                       wedge: geometry.wedge(at: target).expanded(by: WandWheelMetrics.focusOutset),
                                       discRadius: WandWheelMetrics.centerRadius + WandWheelMetrics.focusOutset)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: ModeHUDPointerFocusMetrics.lineWidth, lineJoin: .round))
                    .frame(width: geometry.size, height: geometry.size)
                    .shadow(color: .white.opacity(0.75), radius: 6)
            }
            .padding(WandWheelMetrics.panelPadding)
            .background(RoundedRectangle(cornerRadius: 27).fill(Color(white: 0.11)))
        }

        var frames: [(String, AnyView)] = []
        for (index, progress) in [0, 0.2, 0.35, 0.5, 0.65, 0.8, 1].enumerated() {
            frames.append(("morph-out-\(index)", AnyView(frame(progress: progress, angle: layout.angle(at: target), towardCenter: false))))
        }
        for (index, progress) in [0.75, 0.5, 0.25].enumerated() {
            frames.append(("morph-back-\(index)", AnyView(frame(progress: progress, angle: layout.angle(at: target), towardCenter: true))))
        }
        let a = layout.angle(at: target), b = layout.angle(at: next)
        frames.append(("slide-half", AnyView(frame(progress: 1, angle: a + (b - a) / 2, towardCenter: false))))
        for (name, view) in frames {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, name)
            guard let directory = ProcessInfo.processInfo.environment["WAND_RADIAL_VISUAL_OUTPUT"] else { continue }
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
}

private final class NoMorphIconProvider: ModeHUDAppIconProviding {
    func icon(for backdrop: ModeHUDAppBackdrop) -> NSImage? { nil }
}

/// Root's 2026-10-30 visual QA on the final 029 renders.
final class WandFinalVisualQATests: XCTestCase {
    private func page(_ frontmost: AppSpecificTarget?, open: [Int] = []) -> ModeHUDSnapshot {
        let hud = RecordingModeHUDPresenter()
        let coordinator = ModePickerCoordinator(lease: WandModeLease(), hud: hud, scheduler: ManualTickScheduler(),
                                                log: Log(category: "test", sink: NullLogSink()))
        coordinator.resolveFrontmostApp = {
            FrontmostAppModeContext(target: frontmost, displayName: frontmost?.displayName ?? "Finder", bundleIdentifier: frontmost?.bundleIdentifier)
        }
        coordinator.enterWandHome(source: .wand, pointerFocus: ModeHUDPointerFocus(cell: .switchApp))
        for raw in open {
            let cell = PhysicalCell(rawValue: raw)!
            coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .press))
            coordinator.handle(.init(action: .select, source: .wand, physicalCell: cell, phase: .release))
        }
        return hud.snapshots.last!
    }

    private func plan(_ snapshot: ModeHUDSnapshot) -> (WandWheelGeometry, WandWheelPlan) {
        let geometry = WandWheelGeometry(layout: snapshot.wandRadialLayout!)
        let cards = Dictionary(snapshot.legend.map {
            ($0.cell, WandWheelPlan.Entry(title: $0.displayTitle(on: .wand),
                                          label: WandRadialWheel.caption(for: $0.cell, in: geometry.layout) ?? "",
                                          labelStyle: .caption, reservesArrows: $0.gesture?.isAvailable(on: .wand) == true))
        }, uniquingKeysWith: { first, _ in first })
        return (geometry, WandWheelPlan.plan(for: geometry, cards: cards))
    }

    /// The title block's centre, as drawn, relative to the wheel centre.
    private func blockCentre(_ text: WandCardText) -> CGPoint {
        let points = text.lines.map { text.drawn($0.center) }
        return CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                       y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
    }

    /// Ethan asked earlier for text "more centered in the wedges". Codex's
    /// bottom-wedge New chat fit on one row only against the outer arc.
    func testAnExtraRowWinsOnlyWhereItClearlyCentresTheTitle() {
        let codex = page(.codex, open: [2])
        let (geometry, plan) = plan(codex)
        let index = geometry.layout.ringIndex(of: CodexModeAction.newTask.cell)!
        let text = plan.ring[index].text!
        XCTAssertEqual(text.lines.map(\.text), ["New", "chat"])
        XCTAssertEqual(text.titleSize, plan.sharedSize, "centred at the same size, not shrunk")
        let centroid = geometry.textCenter(for: geometry.wedge(at: index))
        let centre = blockCentre(text)
        XCTAssertLessThan(hypot(centre.x - centroid.x, centre.y - centroid.y), 12, "the block sits at the wedge's visual centre")
        // Placement never splits a two-row phrase further.
        let keys = page(.chrome, open: [9])
        let (keysGeometry, keysPlan) = self.plan(keys)
        let shift = keysGeometry.layout.ringIndex(of: KeysModeAction.holdShift.cell)!
        XCTAssertEqual(keysPlan.ring[shift].text!.lines.count, 2, "⇧ Hold | Shift, not ⇧ | Hold | Shift")
        // Near-centred one-row titles keep one row everywhere.
        for (name, snapshot) in [("home", page(.chrome)), ("Keys", page(.chrome, open: [9]))] {
            let (g, p) = self.plan(snapshot)
            for (i, cell) in g.layout.ring.enumerated() {
                guard let t = p.ring[i].text, let item = snapshot.legend.first(where: { $0.cell == cell }),
                      !item.displayTitle(on: .wand).contains(" "), !item.displayTitle(on: .wand).contains("/") else { continue }
                XCTAssertEqual(t.lines.count, 1, "\(name): \(item.displayTitle(on: .wand)) stays one word on one row")
            }
        }
    }

    func testEveryOpenPageCentreSaysHowToClose() {
        for snapshot in [page(.chrome), page(.chrome, open: [9]), page(.chrome, open: [12]), page(.codex, open: [2])] {
            let (geometry, plan) = plan(snapshot)
            let centre = geometry.layout.center!
            XCTAssertEqual(WandRadialWheel.caption(for: centre, in: geometry.layout), "Double click to close")
            let text = plan.center!.text!
            XCTAssertEqual(text.label.text, "Double click to close")
            XCTAssertEqual(text.labelStyle, .caption)
            XCTAssertLessThanOrEqual(text.label.measured, text.label.room + 0.01, "the caption fits unshrunk")
            for corner in text.drawnCorners.joined() {
                XCTAssertLessThanOrEqual(hypot(corner.x, corner.y), WandWheelMetrics.centerRadius, "inside the centre disc")
            }
            for cell in geometry.layout.ring { XCTAssertNil(WandRadialWheel.caption(for: cell, in: geometry.layout)) }
        }
    }

    /// The wand footer floats over the desktop: its version and gesture text
    /// must read over both a dark and a light desktop. The mice keep theirs.
    @MainActor
    func testWandFooterTextReadsOverDarkAndLightDesktops() throws {
        XCTAssertTrue(ModeHUDFooterType(source: .wand).floatsOverDesktop)
        for source in MouseSource.allCases where source != .wand {
            XCTAssertEqual(ModeHUDFooterType(source: source), ModeHUDFooterType(source: .corsair))
            XCTAssertFalse(ModeHUDFooterType(source: source).floatsOverDesktop)
        }
        let snapshot = page(.chrome)
        for (name, background) in [("dark", Color(white: 0.08)), ("light", Color(white: 0.96))] {
            let model = ModeHUDViewModel(source: .wand)
            model.apply(snapshot)
            let renderer = ImageRenderer(content: ModeHUDView(model: model, usesNativeGlass: false).background(background))
            renderer.scale = 2
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(renderer.nsImage?.tiffRepresentation)))
            // The right half of the footer row holds the gesture key and version.
            var brightest: CGFloat = 0, darkest: CGFloat = 1
            for y in stride(from: bitmap.pixelsHigh - 90, to: bitmap.pixelsHigh - 40, by: 2) {
                for x in stride(from: bitmap.pixelsWide / 2, to: bitmap.pixelsWide - 40, by: 2) {
                    guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let luminance = 0.2126 * colour.redComponent + 0.7152 * colour.greenComponent + 0.0722 * colour.blueComponent
                    brightest = max(brightest, luminance); darkest = min(darkest, luminance)
                }
            }
            if name == "dark" { XCTAssertGreaterThan(brightest, 0.75, "light text over a dark desktop") }
            else { XCTAssertLessThan(darkest, 0.35, "a dark halo edges the text over a light desktop") }
            if let directory = ProcessInfo.processInfo.environment["WAND_RADIAL_VISUAL_OUTPUT"] {
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("footer-over-\(name).png"))
            }
        }
    }
}
