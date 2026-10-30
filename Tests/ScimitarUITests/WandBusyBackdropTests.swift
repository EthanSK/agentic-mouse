import AppKit
import ScimitarKit
import SwiftUI
@testable import ScimitarUI
import XCTest

@MainActor
final class WandBusyBackdropTests: XCTestCase {
    func testWandCardsStayReadableOverBusyHighContrastBackdrop() throws {
        let hud=RecordingModeHUDPresenter()
        let coordinator=ModePickerCoordinator(lease:WandModeLease(),hud:hud,
            scheduler:ManualTickScheduler(),log:Log(category:"test",sink:NullLogSink()))
        coordinator.enterWandHome(source:.wand,pointerFocus:.init(cell:.clipboardWheelControl,isArmed:true))
        let model=ModeHUDViewModel(source:.wand)
        model.apply(try XCTUnwrap(hud.snapshots.last))
        let content=ModeHUDView(model:model,usesNativeGlass:false)
            .environment(\.colorScheme,.dark)
        let base=ImageRenderer(content:content)
        let size=try XCTUnwrap(base.nsImage).size
        let renderer=ImageRenderer(content:content.background {
            Canvas { context,size in
                for y in stride(from:0,to:Int(size.height),by:16) {
                    for x in stride(from:0,to:Int(size.width),by:16) {
                        let light=(x/16+y/16)%2 == 0
                        context.fill(Path(CGRect(x:x,y:y,width:16,height:16)),with:.color(light ? .white : .black))
                    }
                }
                for y in stride(from:8,to:Int(size.height),by:35) {
                    context.draw(Text("let value = window.selected + 12345 // busy desktop")
                        .font(.system(size:13,design:.monospaced)).foregroundColor(.cyan),
                        at:CGPoint(x:size.width/2,y:CGFloat(y)))
                }
            }.frame(width:size.width,height:size.height)
        })
        renderer.scale=1
        let bitmap=try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(renderer.nsImage?.tiffRepresentation)))
        // Offscreen backing is opaque inside each card; the busy backdrop
        // must not alter a neutral interior even at opposing checker colours.
        let transparent=ImageRenderer(content:content)
        let bare=try XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap(transparent.nsImage?.tiffRepresentation)))
        let geometry=WandWheelGeometry(layout:model.wandRadialLayout ?? .inferred(legend:model.legend))
        for index in geometry.layout.ring.indices {
            let wedge=geometry.wedge(at:index)
            let direction=WandWedge.radial(wedge.centerAngle)
            let radius=wedge.inner+10
            let x=Int(WandWheelMetrics.panelPadding+geometry.center.x+direction.x*radius)
            let y=Int(WandWheelMetrics.panelPadding+geometry.center.y+direction.y*radius)
            let sample=try XCTUnwrap(bare.colorAt(x:x,y:y))
            XCTAssertGreaterThan(sample.alphaComponent,0.99,"wedge backing is opaque in renderer")
            let busy=try XCTUnwrap(bitmap.colorAt(x:x,y:y))
            let a=try XCTUnwrap(sample.usingColorSpace(.deviceRGB))
            let b=try XCTUnwrap(busy.usingColorSpace(.deviceRGB))
            XCTAssertEqual(a.redComponent,b.redComponent,accuracy:0.02)
            XCTAssertEqual(a.greenComponent,b.greenComponent,accuracy:0.02)
            XCTAssertEqual(a.blueComponent,b.blueComponent,accuracy:0.02)
        }
        if let folder=ProcessInfo.processInfo.environment["WAND_TRANSPARENCY_OUTPUT"] {
            try FileManager.default.createDirectory(atPath:folder,withIntermediateDirectories:true)
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
                .write(to:URL(fileURLWithPath:folder).appendingPathComponent("wand-busy.png"))
        }
    }
}
