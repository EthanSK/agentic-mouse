import AppKit
import ScimitarKit
import SwiftUI
@testable import ScimitarUI
import XCTest

final class HUDGestureRenderingTests: XCTestCase {
    @MainActor
    func testGestureCardsRenderAcrossGridPages() throws {
        var snapshots:[(String,ModeHUDSnapshot)]=[]
        for source in [MouseSource.corsair,.razer] {
            snapshots.append(("default-\(source.rawValue)",DefaultMapLegend.snapshot(source:source)))
            for (name,legend) in [
                ("utility",ModePickerCoordinator.modesLegend(for:source)),
                ("extra",ModePickerCoordinator.extraUtilitiesLegend(for:source)),
                ("keys",ModePickerCoordinator.keysLegend(for:source)),
                ("chrome",ChromeMode.definition.legend),
                ("codex",CodexMode.definition.legend)
            ] {
                var snapshot=DefaultMapLegend.snapshot(source:source)
                snapshot.legend=legend;snapshot.modeTitle=name;snapshot.presentationStyle = .boldOpaque
                snapshots.append(("\(name)-\(source.rawValue)",snapshot))
            }
        }
        for (name,snapshot) in snapshots {
            let model=ModeHUDViewModel(source:snapshot.source)
            model.apply(snapshot)
            let renderer=ImageRenderer(content:ModeHUDView(model:model,usesNativeGlass:false).environment(\.colorScheme,.dark).background(Color(white:0.11)))
            renderer.scale=2
            let image=try XCTUnwrap(renderer.nsImage,name)
            XCTAssertGreaterThan(image.size.width,100,name)
            if let directory=ProcessInfo.processInfo.environment["HUD_GESTURE_VISUAL_OUTPUT"] {
                try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
                let bitmap=try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(image.tiffRepresentation)))
                try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:directory).appendingPathComponent(name+".png"))
            }
        }
    }
}
