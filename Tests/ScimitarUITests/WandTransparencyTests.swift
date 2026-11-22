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

    func testWandAndDefaultMouseLegendsKeepTheirBackdropsClear() throws {
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
                XCTAssertLessThan(alpha, 0.01, "\(source) must not add a background fill")
            }
            let midX = bitmap.pixelsWide / 2
            let midY = bitmap.pixelsHigh / 2
            let center = try XCTUnwrap(bitmap.colorAt(x: midX, y: midY))
            if source == .wand {
                XCTAssertGreaterThan(center.alphaComponent, 0.95, "wand centre remains filled")
            } else {
                // Four columns put the centre in a gutter. Sample inside the
                // left card separately so an opaque panel cannot pass for a fill.
                XCTAssertLessThan(center.alphaComponent, 0.01, "gutter shows the underlying glass")
                let card = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 14, y: midY))
                XCTAssertGreaterThan(card.alphaComponent, 0.20, "Default button keeps its fill")
                let rim = try XCTUnwrap(bitmap.colorAt(x: midX, y: 1))
                XCTAssertGreaterThan(rim.alphaComponent, 0.95, "Default keeps its outer perimeter")
            }
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
