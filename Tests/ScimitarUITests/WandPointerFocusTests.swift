import AppKit
import Combine
import ScimitarKit
import SwiftUI
@testable import ScimitarUI
import XCTest

final class WandPointerFocusTests: VisibleHUDTestCase {
    func testViewModelCarriesTheWandOutlineAndClearsItWithTheNextSnapshot() {
        let model = ModeHUDViewModel(source: .wand, appIconProvider: NoIconProvider())
        let legend = AppSpecificTarget.chrome.definition.legend
        model.apply(snapshot(legend: legend, focus: ModeHUDPointerFocus(cell: .frontmostAppModeSelector)))
        XCTAssertEqual(model.pointerFocus, ModeHUDPointerFocus(cell: .frontmostAppModeSelector))
        XCTAssertEqual(model.source, .wand)

        model.apply(snapshot(legend: legend, focus: ModeHUDPointerFocus(cell: PhysicalCell(rawValue: 4)!, isArmed: true)))
        XCTAssertEqual(model.pointerFocus?.isArmed, true)

        model.apply(snapshot(legend: legend, focus: nil))
        XCTAssertNil(model.pointerFocus)
    }

    func testOutlineSitsInsideTheGridGutterWithoutChangingCardGeometry() {
        // Cards are separated by a 9-point gutter. The outline is an overlay
        // outside the card, so it must leave a visible gap to the neighbour.
        let outerEdge = ModeHUDPointerFocusMetrics.outset + ModeHUDPointerFocusMetrics.lineWidth / 2
        XCTAssertLessThanOrEqual(outerEdge, 9 - 2)
        XCTAssertFalse(ModeHUDPointerFocusMetrics.armedDash.isEmpty)
    }

    func testWandPresenterIgnoresSnapshotsFromAnyMouse() {
        let presenter = AppKitModeHUDPresenter(source: .wand)
        presenter.update(snapshot(legend: [], focus: nil, source: .corsair))
        XCTAssertFalse(presenter.isVisible)
    }

    func testPointerFastPathStillRestoresAHiddenModelAndClearsOldProblems() {
        let model = ModeHUDViewModel(source: .wand, appIconProvider: NoIconProvider())
        let active = snapshot(legend: AppSpecificTarget.chrome.definition.legend,
                              focus: ModeHUDPointerFocus(cell: .frontmostAppModeSelector))
        model.apply(active)
        model.isActive = false
        XCTAssertFalse(model.apply(active))
        XCTAssertTrue(model.isActive)
        model.problem = "Previous action failed"
        XCTAssertFalse(model.apply(active))
        XCTAssertNil(model.problem)
    }

    @MainActor
    func testWandFocusUpdatesPublishOnlyTheOutlineAndKeepPanelFramesStill() async throws {
        let model = ModeHUDViewModel(source: .wand, appIconProvider: NoIconProvider())
        let initial = snapshot(legend: AppSpecificTarget.chrome.definition.legend,
                               focus: ModeHUDPointerFocus(cell: .frontmostAppModeSelector))
        model.apply(initial)
        var publications = 0
        let subscription = model.objectWillChange.sink { publications += 1 }
        var next = initial
        next.pointerFocus = ModeHUDPointerFocus(cell: .frontmostAppModeSelector, pullX: 0.5)
        XCTAssertTrue(model.apply(next))
        XCTAssertEqual(publications, 1)
        withExtendedLifetime(subscription) {}

        let baseline = Set(NSApp.windows.map(ObjectIdentifier.init))
        let presenter = AppKitModeHUDPresenter(source: .wand)
        presenter.show(initial)
        await Task.yield()
        let panels = NSApp.windows.filter { $0 is HUDPanel && !baseline.contains(ObjectIdentifier($0)) }
        XCTAssertFalse(panels.isEmpty)
        let frames = panels.map(\.frame)
        for index in 1...12 {
            next.pointerFocus = ModeHUDPointerFocus(cell: .frontmostAppModeSelector, pullX: Double(index) / 12)
            presenter.update(next)
            try await Task.sleep(nanoseconds: 15_000_000)
            XCTAssertEqual(panels.map(\.frame), frames)
        }
        presenter.hide()
    }

    @MainActor
    func testLiquidOutlineRendersAtRestAndBetweenCards() throws {
        let offsets: [Double] = [0, 0.5, 0.95]
        let models = offsets.map { offset in
            let model = ModeHUDViewModel(source: .wand, appIconProvider: NoIconProvider())
            var home = DefaultMapLegend.snapshot(source: .wand, frontmostAppContext:
                FrontmostAppModeContext(target: .codex, displayName: "Codex", bundleIdentifier: AppSpecificTarget.codex.bundleIdentifier))
            home.pointerFocus = ModeHUDPointerFocus(cell: .frontmostAppModeSelector, pullX: offset)
            model.apply(home)
            return model
        }
        let content = HStack(spacing: 18) {
            ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                ModeHUDView(model: model)
            }
        }.padding(32).background(Color.black)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertGreaterThan(image.size.width, 2100)
        if let destination = ProcessInfo.processInfo.environment["WAND_VISUAL_OUTPUT"],
           let data = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: data),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: destination))
        }
    }

    @MainActor
    func testWandVSCodeReviewCardsJoinTheOuterLayerWithoutResizingIt() throws {
        let model = ModeHUDViewModel(source: .wand, appIconProvider: NoIconProvider())
        var home = DefaultMapLegend.snapshot(source:.wand, frontmostAppContext:
            FrontmostAppModeContext(target:.vsCode,displayName:"VS Code",bundleIdentifier:"com.microsoft.VSCode"))
        home.legend += [
            .init(cell:.wandReviewChanges,actionTitle:"Review changes",accent:.init(red:65,green:201,blue:122)),
            .init(cell:.wandReviewFiles,actionTitle:"Stage files",accent:.init(red:180,green:105,blue:235))
        ]
        home.pointerFocus = .init(cell:.switchApp,pullX:0.3)
        home.wandReviewSelection = .wandReviewChanges
        home.wandRadialLayout = .wandMenu(legend:home.legend,page:.modes,isHome:true)
        // Ethan's outer layer: the ring keeps its twelve cards and angles;
        // the review pair sits one reach beyond the app card.
        let plainRing=WandRadialLayout.wandMenu(legend:home.legend.filter { $0.cell.wandReviewMode == nil },page:.modes,isHome:true).ring
        XCTAssertEqual(home.wandRadialLayout!.ring,plainRing)
        XCTAssertEqual(home.wandRadialLayout!.outer.map(\.cell),[.wandReviewChanges,.wandReviewFiles])
        XCTAssertEqual(Set(home.wandRadialLayout!.outer.map(\.parent)),[.frontmostAppModeSelector])
        model.apply(home)
        let renderer=ImageRenderer(content:ModeHUDView(model:model));renderer.scale=1
        let image=try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width,WandWheelMetrics.panelWidth,accuracy:1)
        if let path=ProcessInfo.processInfo.environment["WAND_REVIEW_VISUAL_OUTPUT"],let data=image.tiffRepresentation,
           let bitmap=NSBitmapImageRep(data:data),let png=bitmap.representation(using:.png,properties:[:]) {
            try png.write(to:URL(fileURLWithPath:path))
        }
        home.legend.removeAll { $0.cell.wandReviewMode != nil }
        home.wandRadialLayout = .wandMenu(legend:home.legend,page:.modes,isHome:true)
        model.apply(home)
        let normal=ImageRenderer(content:ModeHUDView(model:model));normal.scale=1
        XCTAssertEqual(try XCTUnwrap(normal.nsImage).size, image.size, "review cards never resize the wheel")
    }

    private func snapshot(
        legend: [ModeHUDLegendItem],
        focus: ModeHUDPointerFocus?,
        source: MouseSource = .wand
    ) -> ModeHUDSnapshot {
        ModeHUDSnapshot(
            isActive: true,
            modeTitle: "Chrome mode",
            source: source,
            selection: nil,
            legend: legend,
            accent: RGBColor(red: 0, green: 132, blue: 255),
            footerTitle: "Chrome mode",
            presentationStyle: .boldOpaque,
            showsOnAllDisplays: true,
            pointerFocus: focus
        )
    }
}

private final class NoIconProvider: ModeHUDAppIconProviding {
    func icon(for backdrop: ModeHUDAppBackdrop) -> NSImage? { nil }
}
