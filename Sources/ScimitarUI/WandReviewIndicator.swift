import AppKit
import SwiftUI

/// What the wand's bottom-centre reminder shows. Review selections are
/// "changes" or "files"; the create-chat status and the repeat-keys exit hint
/// temporarily take the slot.
enum WandIndicatorContent: Equatable {
    case review(String)
    case creatingChat
    case repeatKeysHint
}

/// A non-activating reminder of the wand's selected VS Code review mode, and
/// the same slot for the brief Creating chat… status and the Keys repeat
/// hint. Precedence: Creating chat…, then the hint, then the review mode. The
/// controller owns its lifetime; hiding the main HUD does not clear it. Since
/// 2026-10-30 the app no longer sends the repeat hint: it only applied while
/// the Keys HUD was open, whose centre now says "Double click to close", and
/// this capsule sat over that HUD's footer.
public final class WandReviewIndicator {
    private var panel:NSPanel?
    private var hosting:NSHostingView<WandReviewIndicatorView>?
    private var shown:WandIndicatorContent?
    /// The selected review mode is kept while an overlay covers it.
    private var reviewMode:String?
    private var creatingChat=false
    private var repeatKeysHint=false
    private var placementAnchor: WandHUDPlacement.Anchor?
    private var screenProvider:()->NSScreen? = {NSScreen.main}
    private var present:(NSPanel)->Void = {$0.orderFrontRegardless()}
    public init() {}
    init(screenProvider:@escaping ()->NSScreen?,present:@escaping (NSPanel)->Void) {
        self.screenProvider=screenProvider;self.present=present
    }
    public func update(mode:String?) {
        reviewMode = mode.flatMap { ["changes","files"].contains($0) ? $0 : nil }
        render()
    }
    /// Shows Creating chat… in the review slot. False restores the current
    /// review selection, or hides the reminder when there is none.
    public func setCreatingChat(_ active:Bool) {
        creatingChat=active
        render()
    }
    /// Shows Double-click to exit while the wand's Keys HUD is repeating keys.
    /// False restores whatever lower-priority content remains, or hides.
    public func setRepeatKeysHint(_ active:Bool) {
        guard repeatKeysHint != active else { return }
        repeatKeysHint=active
        render()
    }
    var isVisible:Bool { panel != nil }
    var currentContent:WandIndicatorContent? { shown }
    private var desired:WandIndicatorContent? {
        if creatingChat { return .creatingChat }
        if repeatKeysHint { return .repeatKeysHint }
        return reviewMode.map(WandIndicatorContent.review)
    }
    private func render() {
        guard let content=desired, let screen=screenProvider() else {
            shown=nil;hosting=nil;panel?.orderOut(nil);panel=nil;placementAnchor=nil;return
        }
        let frame=indicatorFrame(on:screen,size:WandReviewIndicatorView.size(for:content))
        if let panel {
            // Same panel and anchor: swapping content keeps the capsule's
            // centre; only the three-line review reminder is a little taller.
            if panel.frame.size != frame.size { panel.setFrame(frame,display:true) }
            else { panel.setFrameOrigin(frame.origin) }
            if shown != content {shown=content;hosting?.rootView=WandReviewIndicatorView(content:content)}
            return
        }
        shown=content
        let p=NSPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=true;p.level = NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+2)
        p.hidesOnDeactivate=false;p.ignoresMouseEvents=true;p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let view=NSHostingView(rootView:WandReviewIndicatorView(content:content))
        p.contentView=view;hosting=view
        panel=p;present(p)
    }
    private func indicatorFrame(on screen:NSScreen,size:NSSize)->NSRect {
        if placementAnchor == nil { placementAnchor = .init() }
        return placementAnchor!.frame(size:size,on:screen)
    }

}
struct WandReviewIndicatorView:View {
    let content:WandIndicatorContent
    init(mode:String) { content = .review(mode) }
    init(content:WandIndicatorContent) { self.content = content }
    var mode:String? {
        if case .review(let mode)=content { return mode }
        return nil
    }
    /// Ethan reads these from a lounging distance (2026-10-30), so the wand's
    /// reminder uses large type: the main line at `titleSize` and the review
    /// reminder's two hint lines at `detailSize` (were 12 and 10 pt in a
    /// 210-point capsule). Each capsule fits its longest line with room to
    /// spare; only the three-line review reminder is taller.
    static let titleSize:CGFloat = 22
    static let detailSize:CGFloat = 17
    static let iconSize:CGFloat = 20
    static func size(for content:WandIndicatorContent)->NSSize {
        if case .review = content { return NSSize(width:340,height:104) }
        return NSSize(width:280,height:60)
    }
    /// The mode a double click switches to from `mode`.
    static func toggleDestination(for mode:String)->String {
        mode == "changes" ? "Stage files" : "Review changes"
    }
    var body:some View {
        let size=Self.size(for:content)
        Group {
            switch content {
            case .review(let mode):
                VStack(spacing:4) {
                    title(mode == "changes" ? "Review changes" : "Stage files",systemImage:mode == "changes" ? "eye" : "doc.on.doc")
                    // Ethan calls this "commit selection" (formerly "commit set"): stage the selection, not a Git commit.
                    Text("(Hold to commit selection)")
                        .font(.system(size:Self.detailSize,weight:.medium,design:.rounded))
                    // Ethan: double click toggles review ⇄ stage files, "back and forth".
                    Text("Double-click for \(Self.toggleDestination(for:mode))")
                        .font(.system(size:Self.detailSize,weight:.medium,design:.rounded))
                }
            case .creatingChat:
                // Progress, not a promise: Agent Flow owns the actual chat.
                title("Creating chat…",systemImage:"square.and.pencil")
            case .repeatKeysHint:
                // Ethan: "double click to exit so you don't get stuck".
                title("Double-click to exit",systemImage:"cursorarrow.click.2")
            }
        }
            .foregroundStyle(Color.black)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal,20).frame(width:size.width,height:size.height)
            .background(fill,in:Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.28),lineWidth:1))
            .accessibilityElement(children:.combine)
    }
    /// The capsule's main line: its symbol and words at the large title size.
    private func title(_ text:String,systemImage:String)->some View {
        HStack(spacing:8) {
            Image(systemName:systemImage).font(.system(size:Self.iconSize,weight:.semibold))
            Text(text).font(.system(size:Self.titleSize,weight:.semibold,design:.rounded))
        }
    }
    private var fill:Color {
        switch content {
        case .review(let mode): return mode == "changes" ? Color.green : Color(red:0.78,green:0.6,blue:1)
        // The HUD's existing legend-toggle cyan: calm, distinct, legible in black.
        case .creatingChat: return Color(red:0,green:205.0/255,blue:1)
        // The arrow-key family's orange, matching the cards being repeated.
        case .repeatKeysHint: return Color(red:1,green:170.0/255,blue:28.0/255)
        }
    }
}
