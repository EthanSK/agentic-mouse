import AppKit
import SwiftUI

/// What the wand's bottom-centre reminder shows. Review selections are
/// "changes" or "files"; the create-chat status and the repeat-keys exit hint
/// temporarily take the slot.
enum WandIndicatorContent: Equatable {
    case review(String)
    case creatingChat
    case repeatKeysHint

    /// The pill's one title line.
    var title:String {
        switch self {
        case .review(let mode): return mode == "changes" ? "Review changes" : "Stage files"
        // Progress, not a promise: Agent Flow owns the actual chat.
        case .creatingChat: return "Creating chat…"
        // Ethan: "double click to exit so you don't get stuck".
        case .repeatKeysHint: return "Double-click to exit"
        }
    }
    var systemImage:String {
        switch self {
        case .review(let mode): return mode == "changes" ? "eye" : "doc.on.doc"
        case .creatingChat: return "square.and.pencil"
        case .repeatKeysHint: return "cursorarrow.click.2"
        }
    }
    /// Short hints for the one subtitle line, shown separated by a centred dot.
    /// Ethan (2026-10-30): "Just say hold to stage selection, do the actual
    /// action" (it stages the selection; it is not a Git commit), and
    /// "double click for stage files mode. ... Use the word mode for things
    /// like that toggle". The double click toggles review ⇄ stage files.
    var hints:[String] {
        guard case .review(let mode)=self else { return [] }
        return ["Hold to stage selection","Double-click for \(WandReviewIndicatorView.toggleDestination(for:mode)) mode"]
    }
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
        // Never wider than the visible screen, so placement can keep it on it.
        let maximumWidth=max(1,screen.visibleFrame.width-24)
        let frame=indicatorFrame(on:screen,size:WandReviewIndicatorView.size(for:content,maximumWidth:maximumWidth))
        let rootView=WandReviewIndicatorView(content:content,maximumWidth:maximumWidth)
        if let panel {
            // Same panel and anchor: swapping content keeps the pill's
            // centre; only the review reminder's subtitle line makes it taller.
            if panel.frame.size != frame.size { panel.setFrame(frame,display:true) }
            else { panel.setFrameOrigin(frame.origin) }
            if shown != content || hosting?.rootView.maximumWidth != maximumWidth {shown=content;hosting?.rootView=rootView}
            return
        }
        shown=content
        let p=NSPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.isOpaque=false;p.backgroundColor = .clear;p.hasShadow=true;p.level = NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+2)
        p.hidesOnDeactivate=false;p.ignoresMouseEvents=true;p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
        let view=NSHostingView(rootView:rootView)
        p.contentView=view;hosting=view
        panel=p;present(p)
    }
    private func indicatorFrame(on screen:NSScreen,size:NSSize)->NSRect {
        if placementAnchor == nil { placementAnchor = .init() }
        return placementAnchor!.frame(size:size,on:screen)
    }

}
/// The wand's floating pill: one title line, then (only when there are hints)
/// one smaller subtitle line of short hints separated by a vertically centred
/// dot. Ethan (2026-10-30): "single line for title and then single line for
/// the subtitle text. And they can be separated by a dot ... vertically
/// centered ... do that everywhere". The pill widens to fit both lines at
/// full size instead of wrapping; size, tests and drawing share these metrics.
struct WandReviewIndicatorView:View {
    let content:WandIndicatorContent
    /// The visible screen's limit; nil measures the natural width.
    let maximumWidth:CGFloat?
    init(mode:String) { content = .review(mode);maximumWidth=nil }
    init(content:WandIndicatorContent,maximumWidth:CGFloat?=nil) { self.content=content;self.maximumWidth=maximumWidth }
    var mode:String? {
        if case .review(let mode)=content { return mode }
        return nil
    }
    /// Ethan reads these from a lounging distance (2026-10-30): a large title
    /// and, as he asked, a smaller subtitle (was 17 pt on two extra lines).
    static let titleSize:CGFloat = 22
    static let detailSize:CGFloat = 15
    static let iconSize:CGFloat = 20
    static let iconGap:CGFloat = 8
    static let lineSpacing:CGFloat = 2
    static let verticalPadding:CGFloat = 12
    /// Clear room between each line's ends and the capsule's curve.
    static let sidePadding:CGFloat = 24
    static let singleLineHeight:CGFloat = 60
    static let singleLineMinimumWidth:CGFloat = 280
    /// The separator: a small dot with an equal visible gap on both sides.
    static let dotDiameter:CGFloat = (detailSize*0.3).rounded(.toNearestOrEven)
    static let dotGap:CGFloat = 9

    static func font(size:CGFloat,weight:NSFont.Weight)->NSFont {
        let base=NSFont.systemFont(ofSize:size,weight:weight)
        return base.fontDescriptor.withDesign(.rounded).flatMap{NSFont(descriptor:$0,size:size)} ?? base
    }
    static let titleFont=font(size:titleSize,weight:.semibold)
    static let detailFont=font(size:detailSize,weight:.medium)
    /// AppKit's measurement plus a little slack: SwiftUI's drawing of the
    /// same rounded font can be a point wider, which truncated a fitted line.
    static func textWidth(_ text:String,size:CGFloat,weight:NSFont.Weight)->CGFloat {
        ceil((text as NSString).size(withAttributes:[.font:font(size:size,weight:weight)]).width)+2
    }
    static func lineHeight(_ font:NSFont)->CGFloat { ceil(font.ascender-font.descender+font.leading) }
    /// SwiftUI centres the dot on the subtitle's line box; lift it to the
    /// visual centre of mixed-case text, half way between the x-height and
    /// cap-height centres, so it reads as vertically centred.
    static var dotLift:CGFloat {
        let font=detailFont
        return (font.xHeight+font.capHeight)/4-(font.ascender+font.descender)/2
    }
    static func hintLineWidth(_ hints:[String],scale:CGFloat=1)->CGFloat {
        guard !hints.isEmpty else { return 0 }
        return hints.map{textWidth($0,size:detailSize*scale,weight:.medium)}.reduce(0,+)
            + CGFloat(hints.count-1)*(dotDiameter+2*dotGap)*scale
    }
    static func titleLineWidth(_ title:String,scale:CGFloat=1)->CGFloat {
        (iconSize+iconGap)*scale+textWidth(title,size:titleSize*scale,weight:.semibold)
    }
    private static func contentHeight(lines:Int)->CGFloat {
        lines<2 ? lineHeight(titleFont) : lineHeight(titleFont)+lineSpacing+lineHeight(detailFont)
    }
    /// Horizontal inset for a pill `height` tall: the side padding plus how far
    /// the capsule's round ends cut into the outermost rows.
    static func contentInset(height:CGFloat,lines:Int)->CGFloat {
        let radius=height/2,reach=min(radius,contentHeight(lines:lines)/2)
        return ceil(sidePadding+radius-sqrt(radius*radius-reach*reach))
    }
    static func size(for content:WandIndicatorContent,maximumWidth:CGFloat?=nil)->NSSize {
        let lines=content.hints.isEmpty ? 1 : 2
        let height=lines<2 ? singleLineHeight : ceil(contentHeight(lines:2)+2*verticalPadding)
        var width=ceil(max(titleLineWidth(content.title),hintLineWidth(content.hints))+2*contentInset(height:height,lines:lines))
        if lines<2 { width=max(width,singleLineMinimumWidth) }
        if let maximumWidth { width=min(width,maximumWidth) }
        return NSSize(width:width,height:height)
    }
    /// The mode a double click switches to from `mode`.
    static func toggleDestination(for mode:String)->String {
        mode == "changes" ? "Stage files" : "Review changes"
    }
    /// 1 at the natural width. Only a screen narrower than the pill shrinks a
    /// whole line, its dot and gaps included, so both hints stay complete.
    static func lineScales(for content:WandIndicatorContent,maximumWidth:CGFloat?)->(title:CGFloat,hints:CGFloat) {
        let size=size(for:content,maximumWidth:maximumWidth)
        let room=size.width-2*contentInset(height:size.height,lines:content.hints.isEmpty ? 1 : 2)
        // Measured at each candidate size: small type is relatively wider.
        func scale(_ width:(CGFloat)->CGFloat)->CGFloat {
            var s=max(0.5,min(1,room/max(1,width(1))))
            while s>0.5 && width(s)>room { s-=0.01 }
            return s
        }
        return (scale{titleLineWidth(content.title,scale:$0)},
                content.hints.isEmpty ? 1 : scale{hintLineWidth(content.hints,scale:$0)})
    }
    var body:some View {
        let size=Self.size(for:content,maximumWidth:maximumWidth)
        let scales=Self.lineScales(for:content,maximumWidth:maximumWidth)
        VStack(spacing:Self.lineSpacing) {
            HStack(spacing:Self.iconGap*scales.title) {
                Image(systemName:content.systemImage).font(.system(size:Self.iconSize*scales.title,weight:.semibold))
                Text(content.title).font(.system(size:Self.titleSize*scales.title,weight:.semibold,design:.rounded))
            }
            if !content.hints.isEmpty {
                let s=scales.hints
                HStack(alignment:.center,spacing:Self.dotGap*s) {
                    ForEach(Array(content.hints.enumerated()),id:\.offset) { index,hint in
                        if index>0 {
                            Circle().frame(width:Self.dotDiameter*s,height:Self.dotDiameter*s)
                                .offset(y:-Self.dotLift*s).accessibilityHidden(true)
                        }
                        Text(hint).font(.system(size:Self.detailSize*s,weight:.medium,design:.rounded))
                    }
                }
            }
        }
            .foregroundStyle(Color.black)
            .lineLimit(1)
            .padding(.horizontal,Self.contentInset(height:size.height,lines:content.hints.isEmpty ? 1 : 2))
            .frame(width:size.width,height:size.height)
            .background(fill,in:Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.28),lineWidth:1))
            .accessibilityElement(children:.combine)
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
