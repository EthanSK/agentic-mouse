import AppKit
import ScimitarKit
import SwiftUI
@testable import ScimitarUI
import XCTest

/// Opt-in manual visual harness. It creates only two click-through preview
/// panels on the built-in display and never dispatches an input action.
@MainActor
final class WandLivePreviewTests: XCTestCase {
    func testNativeGlassOverBusyDesktop() async throws {
        guard let folder=ProcessInfo.processInfo.environment["WAND_LIVE_PREVIEW_OUTPUT"] else {
            throw XCTSkip("Opt-in native glass visual harness")
        }
        let screen=try XCTUnwrap(NSScreen.screens.first{$0.localizedName == "Built-in Retina Display"})
        let area=screen.visibleFrame.insetBy(dx:screen.visibleFrame.width*0.1,dy:screen.visibleFrame.height*0.1)
        let size=CGSize(width:min(860,area.width),height:min(820,area.height))
        let frame=CGRect(x:area.midX-size.width/2,y:area.midY-size.height/2,width:size.width,height:size.height)
        let background=HUDPanel(contentRect:frame)
        background.title="Wand visual backdrop"
        background.level = .floating
        background.contentView=NSHostingView(rootView:Canvas {context,size in
            for y in stride(from:0,to:Int(size.height),by:18) {
                for x in stride(from:0,to:Int(size.width),by:18) {
                    context.fill(Path(CGRect(x:x,y:y,width:18,height:18)),with:.color((x/18+y/18)%2 == 0 ? .white : .black))
                }
            }
            for y in stride(from:10,to:Int(size.height),by:35) {
                context.draw(Text("let selected = window.value + 12345 // busy desktop")
                    .font(.system(size:14,design:.monospaced)).foregroundColor(.cyan),at:CGPoint(x:size.width/2,y:CGFloat(y)))
            }
        })
        let recorder=RecordingModeHUDPresenter()
        let target=ModePickerCoordinator(lease:WandModeLease(),hud:recorder,
            scheduler:ManualTickScheduler(),log:Log(category:"test",sink:NullLogSink()))
        target.enterWandHome(source:.wand,pointerFocus:.init(cell:.clipboardWheelControl,isArmed:true))
        let model=ModeHUDViewModel(source:.wand)
        model.apply(try XCTUnwrap(recorder.snapshots.last))
        let hosting=ScaledHUDHostingView(rootView:ModeHUDView(model:model).environment(\.colorScheme,.dark),scale:0.8)
        let hudSize=hosting.fittingSize
        let panel=HUDPanel(contentRect:CGRect(x:frame.midX-hudSize.width/2,y:frame.midY-hudSize.height/2,
            width:hudSize.width,height:hudSize.height))
        panel.title="Wand native glass visual proof"
        panel.level = .floating
        panel.contentView=hosting
        defer {panel.close();background.close()}
        background.orderFrontRegardless();panel.orderFrontRegardless()
        try FileManager.default.createDirectory(atPath:folder,withIntermediateDirectories:true)
        let info:[String:Any]=["hudWindow":panel.windowNumber,"backdropWindow":background.windowNumber,
            "rect":[frame.minX,frame.minY,frame.width,frame.height],
            "captureRect":[frame.minX,(NSScreen.screens.first?.frame.maxY ?? 0)-frame.maxY,frame.width,frame.height]]
        try JSONSerialization.data(withJSONObject:info).write(to:URL(fileURLWithPath:folder).appendingPathComponent("live-window.json"))
        try await Task.sleep(nanoseconds:20_000_000_000)
        model.pointerFocus = .init(cell:PhysicalCell(rawValue:7)!)
        try await Task.sleep(nanoseconds:8_000_000_000)
    }
}
