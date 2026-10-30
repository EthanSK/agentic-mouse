import AppKit
import ScimitarKit
import SwiftUI
@testable import ScimitarUI
import XCTest

@MainActor
final class WandTransparencyTests: XCTestCase {
    private func snapshot(_ source: MouseSource) -> ModeHUDSnapshot {
        if source != .wand { return DefaultMapLegend.snapshot(source: source) }
        let hud = RecordingModeHUDPresenter()
        let coordinator = ModePickerCoordinator(lease: WandModeLease(), hud: hud,
            scheduler: ManualTickScheduler(), log: Log(category: "test", sink: NullLogSink()))
        coordinator.enterWandHome(source: .wand, pointerFocus: .init(cell: .switchApp))
        return hud.snapshots.last!
    }

    func testOnlyCircularWandRootHasTransparentOuterPixels() throws {
        for source in [MouseSource.wand, .corsair, .razer] {
            let model = ModeHUDViewModel(source: source)
            model.apply(snapshot(source))
            let renderer = ImageRenderer(content: ModeHUDView(model: model, usesNativeGlass: false)
                .environment(\.colorScheme, .dark))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            // The panel's outermost corners, outside the wand footer's text
            // (whose lounging-distance type reaches the old 35-point samples).
            for (x,y) in [(12,12),(bitmap.pixelsWide-13,12),
                          (12,bitmap.pixelsHigh-13),(bitmap.pixelsWide-13,bitmap.pixelsHigh-13)] {
                let alpha = try XCTUnwrap(bitmap.colorAt(x:x,y:y)).alphaComponent
                if source == .wand { XCTAssertLessThan(alpha,0.01,"wand corner must be transparent") }
                else { XCTAssertGreaterThan(alpha,0.95,"mouse grid keeps its panel") }
            }
            let center = try XCTUnwrap(bitmap.colorAt(x:bitmap.pixelsWide/2,y:bitmap.pixelsHigh/2))
            XCTAssertGreaterThan(center.alphaComponent,0.95,"cards remain filled")
            if let folder = ProcessInfo.processInfo.environment["WAND_TRANSPARENCY_OUTPUT"] {
                try FileManager.default.createDirectory(atPath:folder,withIntermediateDirectories:true)
                try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
                    .write(to:URL(fileURLWithPath:folder).appendingPathComponent(source.rawValue+".png"))
            }
        }
    }

    func testNativePanelAndHostingWrapperDoNotFillTransparentRoot() {
        let model = ModeHUDViewModel(source:.wand)
        model.apply(snapshot(.wand))
        let hosting = ScaledHUDHostingView(rootView:ModeHUDView(model:model),scale:1)
        let panel = HUDPanel(contentRect:NSRect(x:0,y:0,width:100,height:100))
        panel.contentView=hosting
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor?.alphaComponent,0)
        XCTAssertFalse(hosting.isOpaque)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        panel.close()
    }
}
