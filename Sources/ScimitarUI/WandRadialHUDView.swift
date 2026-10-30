import AppKit
import ScimitarKit
import SwiftUI

/// Ethan's weapon-wheel wand HUD: the centre card with every other card
/// spaced evenly around it. Card colours, borders, artwork, review styling
/// and copy are the same as the grid's; only the arrangement differs. The
/// physical mouse HUDs never use this view.
struct WandRadialWheel: View {
    @ObservedObject var model: ModeHUDViewModel
    let reduceMotion: Bool
    /// Live HUDs show native glass through each card; offscreen renders use
    /// the shared neutral stand-in, like `ModeHUDView`.
    var usesNativeGlass = true

    private var geometry: WandWheelGeometry {
        WandWheelGeometry(layout: model.wandRadialLayout ?? .inferred(legend: model.legend))
    }

    var body: some View {
        let geometry = geometry
        let plan = WandWheelPlan.plan(
            for: geometry,
            cards: Dictionary(model.legend.map {
                // The measured title is exactly the drawn one, motion arrow
                // included, so the cue never crowds an unmeasured wedge.
                // Ethan: "we don't need to show the Corsair label thingies when
                // in Magic Wand HUD mode". The wand has no printed buttons.
                ($0.cell, WandWheelPlan.Entry(title: $0.displayTitle(on: model.source),
                                              label: Self.caption(for: $0.cell, in: geometry.layout) ?? "",
                                              labelStyle: .caption,
                                              reservesArrows: $0.gesture?.isAvailable(on: model.source) == true))
            }, uniquingKeysWith: { first, _ in first }),
            locked: model.wandReviewSelection
        )
        let drawsCenter = plan.center != nil && (geometry.layout.center.map { item(for: $0) != nil } ?? false)
        let drawnRing = geometry.layout.ring.indices.filter { item(for: geometry.layout.ring[$0]) != nil && $0 < plan.ring.count }
        let drawnOuter = geometry.layout.outer.indices.filter { item(for: geometry.layout.outer[$0].cell) != nil }
        let lifted = model.pointerFocus.flatMap { geometry.slot(for: $0.cell) }
        ZStack {
            // Exactly the cards drawn below, so no gutter or corner is backed.
            WandWheelBacking(
                silhouette: WandWheelSilhouette(geometry: geometry, includesCenter: drawsCenter, ringIndices: drawnRing,
                                                outerIndices: drawnOuter, lifted: lifted),
                size: geometry.size,
                usesNativeGlass: usesNativeGlass
            )
            if let center = geometry.layout.center, let item = item(for: center), let card = plan.center {
                WandRadialCard(model: model, item: item,
                               shape: .disc(WandCenterDiscShape(radius: WandWheelMetrics.centerRadius)),
                               text: card.text, wheelCenter: geometry.center, artworkFrame: geometry.centerBounds)
                    .wandCardLift(WandCardLift.pose(for: .center, lifted: lifted == .center, in: geometry),
                                  reduceMotion: reduceMotion)
                    .zIndex(lifted == .center ? 1 : 0)
            }
            ForEach(Array(geometry.layout.ring.enumerated()), id: \.element) { index, cell in
                if let item = item(for: cell), index < plan.ring.count {
                    WandRadialCard(model: model, item: item,
                                   shape: .wedge(WandWedgeShape(wedge: geometry.wedge(at: index))),
                                   text: plan.ring[index].text, wheelCenter: geometry.center,
                                   artworkFrame: geometry.bounds(at: index))
                        .wandCardLift(WandCardLift.pose(for: .ring(index), lifted: lifted == .ring(index), in: geometry),
                                      reduceMotion: reduceMotion)
                        .zIndex(lifted == .ring(index) ? 1 : 0)
                }
            }
            // Ethan's outer layer: thinner cards one reach beyond their parent.
            ForEach(drawnOuter, id: \.self) { index in
                let card = geometry.layout.outer[index]
                if let item = item(for: card.cell) {
                    WandRadialCard(model: model, item: item,
                                   shape: .wedge(WandWedgeShape(wedge: geometry.outerWedge(at: index))),
                                   text: index < plan.outer.count ? plan.outer[index].text : nil,
                                   wheelCenter: geometry.center,
                                   artworkFrame: geometry.outerBounds(at: index))
                        .wandCardLift(WandCardLift.pose(for: .outer(index), lifted: lifted == .outer(index), in: geometry),
                                      reduceMotion: reduceMotion)
                        .zIndex(lifted == .outer(index) ? 1 : 0)
                }
            }
            WandRadialFocusLayer(model: model, geometry: geometry, plan: plan, reduceMotion: reduceMotion)
                .zIndex(2)
        }
        .frame(width: geometry.size, height: geometry.size)
    }

    private func item(for cell: PhysicalCell) -> ModeHUDLegendItem? {
        model.legend.first { $0.cell == cell }
    }

    /// Ethan (2026-10-30): the home centre's Switch App says "in tiny text
    /// underneath it ... double click to close", since clicks keep the HUD
    /// open. Every page's centre carries it, so the open HUD itself owns the
    /// way out (also while Keys repeats keys, which once needed a separate
    /// floating "Double-click to exit" capsule over the HUD footer).
    static func caption(for cell: PhysicalCell, in layout: WandRadialLayout) -> String? {
        layout.center == cell ? ModeHUDCopy.wandDoubleClickCloseHint : nil
    }
}

/// A wheel card's shape: the centre disc or one ring wedge.
enum WandCardShape: InsettableShape {
    case disc(WandCenterDiscShape)
    case wedge(WandWedgeShape)

    func path(in rect: CGRect) -> Path {
        switch self {
        case .disc(let shape): return shape.path(in: rect)
        case .wedge(let shape): return shape.path(in: rect)
        }
    }

    func inset(by amount: CGFloat) -> WandCardShape {
        switch self {
        case .disc(let shape): return .disc(shape.inset(by: amount))
        case .wedge(let shape): return .wedge(shape.inset(by: amount))
        }
    }
}

private struct WandRadialCard: View {
    @ObservedObject var model: ModeHUDViewModel
    let item: ModeHUDLegendItem
    let shape: WandCardShape
    /// Planned whole-word lines, relative to the wheel centre.
    let text: WandCardText?
    let wheelCenter: CGPoint
    /// The card's own bounds, which its app artwork fills edge to edge.
    let artworkFrame: CGRect

    var body: some View {
        let selected = item.cell == model.selection?.cell
        let colors = ModeHUDCardColors(
            modeAccent: model.accent,
            actionAccent: item.accent,
            destinationModeAccent: item.destinationModeAccent,
            presentationStyle: model.presentationStyle
        )
        let border = ModeHUDCardBorderTreatment(isSelected: selected, isModeNavigation: item.destinationModeAccent != nil)
        let isReview = item.cell.wandReviewMode != nil
        let reviewSelected = model.wandReviewSelection == item.cell
        let fill = reviewSelected ? Color(wheel: item.accent)
            : (isReview ? Color(red: 0.055, green: 0.075, blue: 0.10) : Color(wheel: colors.fill))
        let foreground = reviewSelected ? Color.black : (isReview ? Color.white : Color(wheel: colors.foreground))

        ZStack {
            shape.fill(cardFill(fill, selected: selected, strong: isReview || colors.usesStrongDestinationFill))
            if let icon = model.appIcons[item.cell] {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: artworkFrame.width * ModeHUDAppBackdropMetrics.scale,
                           height: artworkFrame.height * ModeHUDAppBackdropMetrics.scale)
                    .position(x: artworkFrame.midX, y: artworkFrame.midY)
                    .saturation(1.35)
                    .contrast(1.08)
                    .blur(radius: ModeHUDAppBackdropMetrics.blurRadius)
                    .clipShape(shape)
                shape.fill(Color.black.opacity(0.28))
                shape.fill(fill.opacity(0.18))
            }
            if isReview {
                shape.fill(Color(wheel: item.accent).opacity(0.12))
                shape.strokeBorder(Color(wheel: item.accent).opacity(0.7), lineWidth: 1.5)
            }
            shape.strokeBorder(Color(wheel: colors.border).opacity(border.opacity), lineWidth: border.lineWidth)
            if reviewSelected {
                shape.strokeBorder(Color(wheel: item.accent), lineWidth: 5)
                    .shadow(color: Color(wheel: item.accent).opacity(0.6), radius: 6)
            }
            label(foreground: foreground, reviewSelected: reviewSelected)
        }
        .allowsHitTesting(false)
    }

    /// Each title line is drawn as planned: whole words, the authored
    /// capitalization (easier to read than capitals at this size), and room
    /// already checked against the card's real shape. The printed label stays
    /// underneath, including any repair marker.
    @ViewBuilder
    private func label(foreground: Color, reviewSelected: Bool) -> some View {
        if let text {
            ZStack {
                if reviewSelected, let lock = text.lock {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(foreground)
                        .modifier(WandCardTextHalo(foregroundIsDark: reviewSelected))
                        .rotationEffect(.radians(text.rotation))
                        .position(drawn(lock, in: text))
                }
                ForEach(Array(text.lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text)
                        .font(.system(size: text.titleSize, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(foreground)
                        .modifier(WandCardTextHalo(foregroundIsDark: reviewSelected))
                        .rotationEffect(.radians(text.rotation))
                        .position(drawn(line.center, in: text))
                }
                Text(text.label.text)
                    .font(text.labelStyle == .caption
                          ? .system(size: WandCardTypography.captionSize, weight: .medium, design: .rounded)
                          : .system(size: WandCardTypography.labelSize, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(text.labelStyle == .caption ? 1 : WandCardTypography.labelMinimumScale)
                    .frame(width: text.label.room)
                    .foregroundStyle(foreground.opacity(text.labelStyle == .caption ? 0.82 : 1))
                    .modifier(WandCardTextHalo(foregroundIsDark: reviewSelected))
                    .rotationEffect(.radians(text.rotation))
                    .position(drawn(text.label.center, in: text))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text([item.accessibilityDescription(on: model.source), text.label.text]
                .filter { !$0.isEmpty }.joined(separator: ". ")))
        }
    }

    /// A planned point as drawn in the wheel frame, including any tilt.
    private func drawn(_ point: CGPoint, in text: WandCardText) -> CGPoint {
        let turned = text.drawn(point)
        return CGPoint(x: wheelCenter.x + turned.x, y: wheelCenter.y + turned.y)
    }

    private func cardFill(_ color: Color, selected: Bool, strong: Bool) -> Color {
        switch model.presentationStyle {
        case .neutral:
            return strong ? color : color.opacity(selected ? 0.58 : 0.24)
        case .boldOpaque:
            return color
        }
    }
}

// MARK: - Focus outline

private struct WandRadialFocusLayer: View {
    @ObservedObject var model: ModeHUDViewModel
    let geometry: WandWheelGeometry
    /// The drawn titles, so adjustment arrows can keep clear of them.
    let plan: WandWheelPlan
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            if model.isActive, let focus = model.pointerFocus, let slot = geometry.slot(for: focus.cell) {
                // One outline view for every card, so a move between the
                // centre and the ring morphs instead of fading. The timeline
                // is always present (arming never swaps the outline's
                // identity) but it ticks only while an armed card marches.
                TimelineView(WandArmedOutlineStyle.schedule(for: focus, reduceMotion: reduceMotion)) { timeline in
                    WandRadialFocusOutline(
                        focus: focus,
                        onCenter: slot == .center,
                        wedge: geometry.focusWedge(for: slot, angle: model.wandFocusAngle),
                        accent: accent(for: focus.cell),
                        reduceMotion: reduceMotion,
                        arrows: focus.adjustment.flatMap {
                            WandAdjustArrowPlacement.points(for: slot, horizontal: $0.isHorizontal, in: geometry,
                                                            avoiding: plan.text(for: slot))
                        },
                        armedDashPhase: WandArmedOutlineStyle.dashPhase(at: timeline.date, reduceMotion: reduceMotion)
                    )
                }
                // Rides with the lifted card it outlines, on its own angle
                // so a slide round the ring carries the lift with it.
                .wandCardLift(WandCardLift.pose(for: slot, lifted: true, in: geometry, angle: model.wandFocusAngle),
                              reduceMotion: reduceMotion)
            }
        }
        .allowsHitTesting(false)
    }

    private func accent(for cell: PhysicalCell) -> Color {
        Color(wheel: model.legend.first { $0.cell == cell }?.accent ?? model.accent)
    }
}

/// Animation choices for the wheel cursor, pure so reduce motion stays testable.
enum WandRadialFocusStyle {
    /// Card-to-card travel, including the centre-to-ring morph.
    static func slideAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .interactiveSpring(response: 0.3, dampingFraction: 0.8)
    }

    static func pullAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .linear(duration: 0.03)
    }

    /// The wheel-adjustment ring leans less than navigation so its stretch
    /// stays inside the panel at the outer edge.
    static let adjustmentPullScale = 0.6
}

/// Solid while moving, marching dashes when a wheel card is armed, and a
/// coloured ratchet while that card is being adjusted, matching the grid
/// outline's meaning in the wheel's own shapes.
private struct WandRadialFocusOutline: View {
    let focus: ModeHUDPointerFocus
    let onCenter: Bool
    let wedge: WandWedge
    let accent: Color
    let reduceMotion: Bool
    /// Where the locked adjustment's two arrows sit, in the wheel frame.
    var arrows: WandAdjustArrowPlacement.Points? = nil
    let armedDashPhase: CGFloat

    var body: some View {
        if let adjustment = focus.adjustment {
            adjustmentRing(adjustment)
        } else {
            morph(pullX: focus.pullX, pullY: focus.pullY)
                .stroke(navigationGradient, style: navigationStyle)
                // Innermost wins: a card change springs the whole morph; pull
                // alone keeps its 30 ms follow.
                .animation(WandRadialFocusStyle.slideAnimation(reduceMotion: reduceMotion), value: focus.cell)
                .animation(WandRadialFocusStyle.pullAnimation(reduceMotion: reduceMotion), value: focus.pullX)
                .animation(WandRadialFocusStyle.pullAnimation(reduceMotion: reduceMotion), value: focus.pullY)
                .shadow(color: Color.white.opacity(0.75), radius: 6)
        }
    }

    private func morph(pullX: Double, pullY: Double) -> WandLiquidMorphOutline {
        WandLiquidMorphOutline(
            progress: onCenter ? 0 : 1,
            angle: wedge.centerAngle,
            pullX: pullX,
            pullY: pullY,
            towardCenter: onCenter,
            wedge: wedge.expanded(by: WandWheelMetrics.focusOutset),
            discRadius: WandWheelMetrics.centerRadius + WandWheelMetrics.focusOutset
        )
    }

    private var navigationStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: ModeHUDPointerFocusMetrics.lineWidth,
            lineJoin: .round,
            dash: focus.isArmed ? WandArmedOutlineStyle.dash : [],
            dashPhase: focus.isArmed ? armedDashPhase : 0
        )
    }

    private var navigationGradient: LinearGradient {
        LinearGradient(colors: [.white, .white.opacity(0.65), .white], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func ratchetStyle(_ adjustment: ModeHUDWheelAdjustment) -> StrokeStyle {
        StrokeStyle(
            lineWidth: WandAdjustRingStyle.lineWidth,
            lineCap: .round,
            dash: WandAdjustRingStyle.dash,
            dashPhase: WandAdjustRingStyle.dashPhase(netSteps: adjustment.netSteps)
        )
    }

    @ViewBuilder
    private var restOutline: some View {
        if onCenter {
            WandCenterDiscShape(radius: WandWheelMetrics.centerRadius + WandWheelMetrics.focusOutset).stroke(accent, lineWidth: 2)
        } else {
            WandWedgeShape(wedge: wedge.expanded(by: WandWheelMetrics.focusOutset)).stroke(accent, lineWidth: 2)
        }
    }

    private var slotCenter: UnitPoint {
        guard !onCenter else { return .center }
        let direction = WandWedge.radial(wedge.centerAngle)
        let radius = (wedge.inner + wedge.outer) / 2
        let size = WandWheelMetrics.wheelSize
        return UnitPoint(x: 0.5 + direction.x * radius / size, y: 0.5 + direction.y * radius / size)
    }

    /// Ethan: "we should have like an arrow above and below that gets filled
    /// ... more bright as you're closer, or every time it registers a tick ...
    /// rather than have the same like liquid outline animation, which is
    /// confusing because it looks like it's going to move but it's actually
    /// latched on." The locked outline stays still at the card; only its
    /// ratchet dashes notch per tick, and the arrows carry direction.
    private func adjustmentRing(_ adjustment: ModeHUDWheelAdjustment) -> some View {
        let gradient = LinearGradient(colors: [accent, .white, accent], startPoint: .top, endPoint: .bottom)
        return ZStack {
            if adjustment.isHeld {
                // Listening: the HUD button is held and wand motion adjusts this card.
                morph(pullX: 0, pullY: 0)
                    .fill(accent.opacity(WandAdjustListeningStyle.fillOpacity))
                    .shadow(color: accent.opacity(0.9), radius: WandAdjustListeningStyle.glowRadius)
                    .transition(.opacity)
            }
            morph(pullX: 0, pullY: 0)
                .stroke(gradient, style: ratchetStyle(adjustment))
                .animation(WandAdjustRingStyle.notchAnimation(reduceMotion: reduceMotion), value: adjustment.netSteps)
                .shadow(color: accent.opacity(adjustment.isHeld ? 0.9 : 0.5), radius: adjustment.isHeld ? 9 : 4)
            if let arrows {
                WandAdjustArrows(adjustment: adjustment, points: arrows, reduceMotion: reduceMotion)
            }
        }
    }
}

/// Ethan: "a special like glow or something of the background or outline to
/// indicate it's being held, like it's listening".
enum WandAdjustListeningStyle {
    static let fillOpacity = 0.22
    static let glowRadius: CGFloat = 16
    /// Arrows on a selected card waiting for a hold stay dim.
    static let waitingArrowOpacity = 0.25
}

/// Where a locked card's arrows go: on the control's own axis, either side
/// of its title, as far apart as fits inside the card and never on top of a
/// title row. Ethan reads the wheel from a lounging distance, so an arrow
/// that overprints a letter ("H^rizontal") costs both. The pair centres on
/// the title first; where the title fills the card along that axis, the pair
/// slides across it (toward the roomier rim on a wedge) to clear the text.
enum WandAdjustArrowPlacement {
    struct Points: Equatable {
        /// The up or left arrow, then the down or right arrow, in the wheel frame.
        let negative: CGPoint
        let positive: CGPoint
        let horizontal: Bool
    }
    static let maximumOffset: CGFloat = 92
    static let minimumOffset: CGFloat = 18
    static let margin: CGFloat = 12
    /// Chevron glyph size.
    static let glyphSize: CGFloat = 20
    /// Distance an arrow's centre keeps from every title row.
    static let textClearance: CGFloat = 14
    /// Farthest the pair slides across its axis to clear a title.
    static let maximumShift: CGFloat = 96

    static func points(for slot: WandWheelGeometry.Slot, horizontal: Bool, in geometry: WandWheelGeometry,
                       avoiding text: WandCardText? = nil) -> Points? {
        let middle: CGPoint
        let inside: (CGPoint) -> Bool
        switch slot {
        case .center:
            middle = .zero
            let radius = WandWheelMetrics.centerRadius - margin
            inside = { hypot($0.x, $0.y) <= radius }
        case .ring(let index):
            let wedge = geometry.wedge(at: index)
            middle = geometry.textCenter(for: wedge)
            inside = { wedge.contains($0, margin: margin) }
        case .outer(let index):
            let wedge = geometry.outerWedge(at: index)
            middle = WandWheelGeometry.bandMiddle(of: wedge)
            inside = { wedge.contains($0, margin: margin / 2) }
        }
        let axis = horizontal ? CGPoint(x: 1, y: 0) : CGPoint(x: 0, y: 1)
        let across = CGPoint(x: axis.y, y: axis.x)
        let rows = text.map(drawnRows) ?? []
        func clear(_ point: CGPoint) -> Bool { rows.allSatisfy { $0.distance(to: point) >= textClearance } }
        func widest(around centre: CGPoint, needsClearance: Bool) -> Points? {
            var offset = maximumOffset
            while offset >= minimumOffset {
                let a = CGPoint(x: centre.x - axis.x * offset, y: centre.y - axis.y * offset)
                let b = CGPoint(x: centre.x + axis.x * offset, y: centre.y + axis.y * offset)
                if inside(a) && inside(b) && (!needsClearance || (clear(a) && clear(b))) {
                    let c = geometry.center
                    return Points(negative: CGPoint(x: c.x + a.x, y: c.y + a.y),
                                  positive: CGPoint(x: c.x + b.x, y: c.y + b.y), horizontal: horizontal)
                }
                offset -= 2
            }
            return nil
        }
        guard !rows.isEmpty else { return widest(around: middle, needsClearance: false) }
        if case .outer(let index) = slot {
            // A thin band has no room above and below its title: the pair
            // sits at the band's two ends, in the room its fit reserved,
            // ordered along the control's axis (the upper end is up).
            let wedge = geometry.outerWedge(at: index)
            let radius = (wedge.inner + wedge.outer) / 2
            // The chevron's centre, a clearance short of the reserved room.
            let inset = (WandCardRoom.outerSideMargin + WandCardRoom.outerArrowRoom - textClearance - 1 + wedge.halfGap) / radius
            let ends = [-1.0, 1.0].map { sign -> CGPoint in
                let angle = wedge.centerAngle + sign * (wedge.halfWidth - Double(inset))
                let direction = WandWedge.radial(angle)
                return CGPoint(x: direction.x * radius, y: direction.y * radius)
            }
            let key = { (p: CGPoint) in horizontal ? p.x : p.y }
            let ordered = ends.sorted { key($0) < key($1) }
            let c = geometry.center
            return Points(negative: CGPoint(x: c.x + ordered[0].x, y: c.y + ordered[0].y),
                          positive: CGPoint(x: c.x + ordered[1].x, y: c.y + ordered[1].y), horizontal: horizontal)
        }
        let key = "\(geometry.layout.cells.map(\.rawValue))#\(slot)#\(horizontal)#"
            + rows.map { String(format: "%.1f,%.1f,%.1f,%.1f", $0.centre.x, $0.centre.y, $0.halfWidth, $0.halfHeight) }.joined(separator: ";")
        if let known = cache[key] { return known }
        // Centred on the title, then sliding across the axis in either
        // direction, nearest first. Where the title fills the card across
        // too (a long single row near the rim), the pair may sit off the
        // title's middle, nearest first. The first clear pair wins.
        let titleCentre = rows.map(\.centre).reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let start = CGPoint(x: titleCentre.x / CGFloat(rows.count), y: titleCentre.y / CGFloat(rows.count))
        var shifts: [CGPoint] = []
        var shift: CGFloat = 0
        while shift <= maximumShift {
            for sign in (shift == 0 ? [CGFloat(1)] : [1, -1]) { shifts.append(CGPoint(x: 0, y: shift * sign)) }
            shift += 4
        }
        var grid: [CGPoint] = []
        for along in stride(from: -maximumShift, through: maximumShift, by: 8) {
            for acrossShift in stride(from: -maximumShift, through: maximumShift, by: 8) where along != 0 {
                grid.append(CGPoint(x: along, y: acrossShift))
            }
        }
        grid.sort { hypot($0.x, $0.y) < hypot($1.x, $1.y) }
        var found: Points?
        for (index, offset) in (shifts + grid).enumerated() {
            let centre = CGPoint(x: start.x + axis.x * offset.x + across.x * offset.y,
                                 y: start.y + axis.y * offset.x + across.y * offset.y)
            // Off-centre pairs must still read as a pair, not two stray chevrons.
            if let points = widest(around: centre, needsClearance: true),
               index < shifts.count || hypot(points.positive.x - points.negative.x, points.positive.y - points.negative.y) >= 2 * pairedOffset {
                found = points
                break
            }
        }
        let result = found ?? widest(around: middle, needsClearance: false)
        if cache.count > 64 { cache.removeAll() }
        cache[key] = result
        return result
    }

    /// Half the spacing an off-centre pair needs.
    static let pairedOffset: CGFloat = 24
    private static var cache: [String: Points?] = [:]

    /// A title row as drawn: its measured box turned by the card's tilt.
    struct Row {
        let centre: CGPoint
        let halfWidth: CGFloat
        let halfHeight: CGFloat
        let rotation: Double

        /// Distance from `point` to the row's box (zero inside it).
        func distance(to point: CGPoint) -> CGFloat {
            let c = CGFloat(cos(-rotation)), s = CGFloat(sin(-rotation))
            let dx = point.x - centre.x, dy = point.y - centre.y
            let x = abs(dx * c - dy * s) - halfWidth, y = abs(dx * s + dy * c) - halfHeight
            return hypot(max(0, x), max(0, y))
        }
    }

    /// Every visible title row, in wheel-centred coordinates.
    static func drawnRows(_ text: WandCardText) -> [Row] {
        // Glyph ink sits inside the line box; the box's leading is enough margin.
        text.lines.filter { $0.measured > 0 }.map { line in
            Row(centre: text.drawn(line.center), halfWidth: line.measured / 2,
                halfHeight: text.titleSize * 0.5, rotation: text.rotation)
        }
    }

    /// Arrow brightness, 0.3 at rest: the side the wand is travelling toward
    /// brightens with progress to the next tick.
    static func opacity(positiveSide: Bool, pull: Double) -> Double {
        let toward = positiveSide ? max(0, pull) : max(0, -pull)
        return 0.3 + 0.7 * min(1, toward)
    }
}

/// Two chevrons on the locked control's own axis. Each accepted tick flashes
/// its arrow; Reduce Motion keeps the last tick's arrow bright instead.
private struct WandAdjustArrows: View {
    let adjustment: ModeHUDWheelAdjustment
    let points: WandAdjustArrowPlacement.Points
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            arrow(positive: false)
            arrow(positive: true)
            if let up = adjustment.lastStepWasUp, !reduceMotion {
                glyph(positive: !up)
                    .id(adjustment.sentSteps)
                    .transition(.asymmetric(insertion: .modifier(active: WandArrowFlash(phase: 0), identity: WandArrowFlash(phase: 1)),
                                            removal: .identity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: adjustment.sentSteps)
        .animation(reduceMotion ? nil : .linear(duration: 0.05), value: adjustment.pull)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func arrow(positive: Bool) -> some View {
        let lit = reduceMotion && adjustment.lastStepWasUp.map { $0 != positive } == true
        let resting = adjustment.isHeld ? WandAdjustArrowPlacement.opacity(positiveSide: positive, pull: adjustment.pull)
            : WandAdjustListeningStyle.waitingArrowOpacity
        return glyph(positive: positive)
            .opacity(lit && adjustment.isHeld ? 1 : resting)
    }

    private func glyph(positive: Bool) -> some View {
        let name = points.horizontal ? (positive ? "chevron.right" : "chevron.left") : (positive ? "chevron.down" : "chevron.up")
        return Image(systemName: name)
            .font(.system(size: WandAdjustArrowPlacement.glyphSize, weight: .heavy))
            .foregroundStyle(Color.white)
            .modifier(WandCardTextHalo(foregroundIsDark: false))
            .position(positive ? points.positive : points.negative)
    }
}

/// One accepted tick: the arrow starts fully bright and slightly larger, then fades.
private struct WandArrowFlash: ViewModifier {
    let phase: CGFloat
    func body(content: Content) -> some View {
        content.opacity(Double(1 - phase)).scaleEffect(1 + 0.25 * (1 - phase))
    }
}

/// A sent detent's pulse, grown about its own card rather than the wheel.
private struct WandRadialRipple: ViewModifier {
    let phase: CGFloat
    let offset: CGFloat
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + WandAdjustRingStyle.rippleGrowth * phase, anchor: anchor)
            .offset(y: offset * phase)
            .opacity(Double(1 - phase))
    }
}

extension Color {
    init(wheel rgb: ScimitarKit.RGBColor) {
        self.init(
            red: Double(rgb.red) / 255.0,
            green: Double(rgb.green) / 255.0,
            blue: Double(rgb.blue) / 255.0,
            opacity: Double(rgb.alpha) / 255.0
        )
    }
}
