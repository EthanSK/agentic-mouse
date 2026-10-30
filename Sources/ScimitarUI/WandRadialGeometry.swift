import AppKit
import CoreGraphics
import Foundation
import ScimitarKit
import SwiftUI

/// Fixed geometry of the wand's weapon-wheel HUD, at 100 % HUD scale. The
/// wheel never resizes with its card count or outline state, so the panel
/// frame stays still while the wand moves.
enum WandWheelMetrics {
    /// Room for the outer layer is always reserved, so the panel never jumps
    /// when VS Code's review cards appear. The ring itself is unchanged.
    static let wheelSize: CGFloat = 820
    static let outerRadius: CGFloat = 324
    static let innerRadius: CGFloat = 134
    static let centerRadius: CGFloat = 115
    /// Outer layer: one gutter beyond the ring, then a thin or large band.
    static var outerLayerInner: CGFloat { outerRadius + gap }
    /// Ethan (2026-10-29): "The small outer edge thing text is too small.
    /// Make it taller and the text bigger so I can read it."
    static let thinOuterHeight: CGFloat = 50
    static let largeOuterHeight: CGFloat = 66
    static func outerHeight(_ height: WandOuterCard.Height) -> CGFloat {
        height == .thin ? thinOuterHeight : largeOuterHeight
    }
    /// Constant-width gutter between neighbouring ring cards.
    static let gap: CGFloat = 9
    static let cornerRadius: CGFloat = 16
    static let panelPadding: CGFloat = 22
    static var panelWidth: CGFloat { wheelSize + panelPadding * 2 }
    /// Same outset as the grid outline: drawn in the gutter, outside the card.
    static let focusOutset: CGFloat = 4
}

/// One rounded annular sector: a ring card, or its outline when expanded.
///
/// `halfWidth` measures the sector's boundary rays from its centre angle.
/// The visible edges run parallel to those rays, `halfGap` inside them, so
/// neighbouring cards keep a constant-width gutter at every radius.
/// Angles are radians clockwise from 12 o'clock; points are screen-space
/// offsets from the wheel centre.
struct WandWedge: Equatable {
    var centerAngle: Double
    var halfWidth: Double
    var inner: CGFloat
    var outer: CGFloat
    var halfGap: CGFloat
    var cornerRadius: CGFloat

    /// Grows (or, negative, shrinks) every edge by the same distance.
    func expanded(by amount: CGFloat) -> WandWedge {
        var value = self
        value.inner = max(1, inner - amount)
        value.outer = outer + amount
        value.halfGap = halfGap - amount
        value.cornerRadius = max(0.5, cornerRadius + amount)
        return value
    }

    static func radial(_ angle: Double) -> CGPoint { CGPoint(x: sin(angle), y: -cos(angle)) }
    static func tangent(_ angle: Double) -> CGPoint { CGPoint(x: cos(angle), y: sin(angle)) }

    /// Largest usable corner radius at each corner, so arcs never overlap.
    func clampedRadius(_ radius: CGFloat, inner isInner: Bool) -> CGFloat {
        let thicknessLimit = max(0.5, (outer - inner) / 2 - 0.5)
        var limit = min(radius, thicknessLimit)
        let s = CGFloat(sin(min(halfWidth, .pi / 2)))
        if isInner, s < 0.999 {
            // The inner arc is the shortest edge: its two corner arcs must not cross.
            limit = min(limit, max(0.5, (inner * s - halfGap) / (1 - s) - 0.5))
        } else if !isInner, s < 0.999 {
            limit = min(limit, max(0.5, (outer * s - halfGap) / (1 + s) - 0.5))
        }
        return max(0.5, limit)
    }

    /// Exact rounded outline, clockwise on screen, sampled about every
    /// `step` points. Radii are outer-start, outer-end, inner-end and
    /// inner-start, where "start" is the counter-clockwise edge.
    func outline(radii requested: [CGFloat]? = nil, step: CGFloat = 2.5) -> [CGPoint] {
        let base = requested ?? Array(repeating: cornerRadius, count: 4)
        let r = [
            clampedRadius(base[0], inner: false), clampedRadius(base[1], inner: false),
            clampedRadius(base[2], inner: true), clampedRadius(base[3], inner: true),
        ]
        let a0 = centerAngle - halfWidth
        let a1 = centerAngle + halfWidth
        let g = halfGap

        struct Corner { let center: CGPoint; let onLine: CGPoint; let onArc: CGPoint; let radius: CGFloat; let arcAngle: Double }
        // side +1: start edge (interior lies clockwise); -1: end edge.
        func corner(edge a: Double, side: CGFloat, arcRadius: CGFloat, outerArc: Bool, radius: CGFloat) -> Corner {
            let distance = outerArc ? arcRadius - radius : arcRadius + radius
            let off = g + radius
            let along = sqrt(max(0, distance * distance - off * off))
            let er = Self.radial(a), et = Self.tangent(a)
            let center = CGPoint(x: er.x * along + et.x * side * off, y: er.y * along + et.y * side * off)
            let onLine = CGPoint(x: er.x * along + et.x * side * g, y: er.y * along + et.y * side * g)
            let scale = distance > 0 ? arcRadius / distance : 0
            let onArc = CGPoint(x: center.x * scale, y: center.y * scale)
            let arcAngle = a + Double(side) * asin(Double(min(1, off / max(distance, 0.001))))
            return Corner(center: center, onLine: onLine, onArc: onArc, radius: radius, arcAngle: arcAngle)
        }
        let outerStart = corner(edge: a0, side: 1, arcRadius: outer, outerArc: true, radius: r[0])
        let outerEnd = corner(edge: a1, side: -1, arcRadius: outer, outerArc: true, radius: r[1])
        let innerEnd = corner(edge: a1, side: -1, arcRadius: inner, outerArc: false, radius: r[2])
        let innerStart = corner(edge: a0, side: 1, arcRadius: inner, outerArc: false, radius: r[3])

        var points: [CGPoint] = []
        func arc(radius: CGFloat, from start: Double, to end: Double) {
            let count = max(2, Int((abs(end - start) * Double(radius) / Double(step)).rounded(.up)))
            for index in 0..<count {
                let angle = start + (end - start) * Double(index) / Double(count)
                points.append(CGPoint(x: radius * CGFloat(sin(angle)), y: -radius * CGFloat(cos(angle))))
            }
        }
        func cornerArc(_ c: Corner, from p: CGPoint, to q: CGPoint) {
            let start = atan2(Double(p.y - c.center.y), Double(p.x - c.center.x))
            var delta = atan2(Double(q.y - c.center.y), Double(q.x - c.center.x)) - start
            while delta > .pi { delta -= 2 * .pi }
            while delta <= -.pi { delta += 2 * .pi }
            let count = max(2, Int((abs(delta) * Double(c.radius) / Double(step)).rounded(.up)))
            for index in 0..<count {
                let angle = start + delta * Double(index) / Double(count)
                points.append(CGPoint(x: c.center.x + c.radius * CGFloat(cos(angle)),
                                      y: c.center.y + c.radius * CGFloat(sin(angle))))
            }
        }
        func line(from p: CGPoint, to q: CGPoint) {
            let count = max(1, Int((hypot(q.x - p.x, q.y - p.y) / step).rounded(.up)))
            for index in 0..<count {
                let f = CGFloat(index) / CGFloat(count)
                points.append(CGPoint(x: p.x + (q.x - p.x) * f, y: p.y + (q.y - p.y) * f))
            }
        }
        arc(radius: outer, from: outerStart.arcAngle, to: outerEnd.arcAngle)
        cornerArc(outerEnd, from: outerEnd.onArc, to: outerEnd.onLine)
        line(from: outerEnd.onLine, to: innerEnd.onLine)
        cornerArc(innerEnd, from: innerEnd.onLine, to: innerEnd.onArc)
        arc(radius: inner, from: innerEnd.arcAngle, to: innerStart.arcAngle)
        cornerArc(innerStart, from: innerStart.onArc, to: innerStart.onLine)
        line(from: innerStart.onLine, to: outerStart.onLine)
        cornerArc(outerStart, from: outerStart.onLine, to: outerStart.onArc)
        return points
    }

    /// Whether `point` lies inside the card with `margin` to spare.
    func contains(_ point: CGPoint, margin: CGFloat) -> Bool {
        contains(point, horizontalMargin: margin, verticalMargin: margin)
    }

    /// Margin to a border depends on its direction: text keeps the full
    /// horizontal inset from a border beside it and a smaller one from a
    /// border above or below it. A border's margin interpolates by how
    /// sideways its normal points.
    func contains(_ point: CGPoint, horizontalMargin: CGFloat, verticalMargin: CGFloat) -> Bool {
        func margin(normalX: CGFloat) -> CGFloat {
            verticalMargin + (horizontalMargin - verticalMargin) * abs(normalX)
        }
        let radius = hypot(point.x, point.y)
        let arcMargin = margin(normalX: point.x / max(radius, 0.001))
        guard radius >= inner + arcMargin, radius <= outer - arcMargin else { return false }
        let theta = WandRadialLayout.angle(x: Double(point.x), y: Double(point.y))
        let offset = WandRadialLayout.angularDifference(theta, centerAngle)
        guard abs(offset) <= halfWidth else { return false }
        guard halfWidth < .pi / 2 else { return true }
        let start = Self.tangent(centerAngle - halfWidth), end = Self.tangent(centerAngle + halfWidth)
        let fromStart = point.x * start.x + point.y * start.y
        let fromEnd = -(point.x * end.x + point.y * end.y)
        return fromStart >= halfGap + margin(normalX: start.x) && fromEnd >= halfGap + margin(normalX: end.x)
    }
}

/// Everything the wheel needs to place and outline its cards, derived only
/// from the shared `WandRadialLayout`.
struct WandWheelGeometry {
    enum Slot: Equatable {
        case center
        case ring(Int)
        /// Index into `layout.outer`.
        case outer(Int)
    }

    let layout: WandRadialLayout
    let size: CGFloat

    init(layout: WandRadialLayout, size: CGFloat = WandWheelMetrics.wheelSize) {
        self.layout = layout
        self.size = size
    }

    var center: CGPoint { CGPoint(x: size / 2, y: size / 2) }

    func slot(for cell: PhysicalCell) -> Slot? {
        if layout.center == cell { return .center }
        if let index = layout.outerIndex(of: cell) { return .outer(index) }
        return layout.ringIndex(of: cell).map(Slot.ring)
    }

    /// An outer-layer card: its parent's sector (shared evenly between
    /// siblings), one gutter beyond the ring, as thick as its height.
    func outerWedge(at index: Int, angle: Double? = nil) -> WandWedge {
        let card = layout.outer[index]
        var inner = WandWheelMetrics.outerLayerInner
        if card.layer > 1, let parent = layout.parentRingIndex(ofOuter: index) {
            // One gutter beyond the deepest first-layer card on this wedge.
            let first = layout.outerIndices(ofRing: parent, layer: 1)
                .map { WandWheelMetrics.outerHeight(layout.outer[$0].height) }.max() ?? 0
            inner += first + WandWheelMetrics.gap
        }
        let height = WandWheelMetrics.outerHeight(card.height)
        return WandWedge(
            centerAngle: angle ?? layout.outerAngle(at: index),
            halfWidth: layout.outerHalfWidth(at: index),
            inner: inner,
            outer: inner + height,
            halfGap: WandWheelMetrics.gap / 2,
            cornerRadius: min(WandWheelMetrics.cornerRadius, height / 2 - 2)
        )
    }

    /// The resting card shape the focus outline follows for `slot`.
    func focusWedge(for slot: Slot, angle: Double) -> WandWedge {
        if case .outer(let index) = slot { return outerWedge(at: index, angle: angle) }
        return wedge(at: 0, angle: angle)
    }

    func outerBounds(at index: Int) -> CGRect {
        let points = outerWedge(at: index).outline(step: 6)
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
        return CGRect(x: minX + center.x, y: minY + center.y, width: maxX - minX, height: maxY - minY)
    }

    func wedge(at index: Int, angle: Double? = nil) -> WandWedge {
        WandWedge(
            centerAngle: angle ?? layout.angle(at: index),
            halfWidth: layout.sectorWidth / 2,
            inner: WandWheelMetrics.innerRadius,
            outer: WandWheelMetrics.outerRadius,
            halfGap: WandWheelMetrics.gap / 2,
            cornerRadius: WandWheelMetrics.cornerRadius
        )
    }

    /// Bounding box of a ring card in wheel coordinates.
    func bounds(at index: Int) -> CGRect {
        let points = wedge(at: index).outline(step: 6)
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .zero }
        return CGRect(x: minX + center.x, y: minY + center.y, width: maxX - minX, height: maxY - minY)
    }

    var centerBounds: CGRect {
        let radius = WandWheelMetrics.centerRadius
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

}

// MARK: - Liquid deformation

/// Ethan's "liquidy" wand outline, rebuilt for the wheel.
///
/// Every outline point moves through one smooth field, so the whole
/// silhouette travels and the rounded corners go with their edges rather
/// than staying pinned. At rest the outline is exactly the card's rounded
/// shape. Pull is the shared navigator's screen-space vector.
enum WandLiquidMetrics {
    // Ring card, in fractions of its half-width or thickness.
    static let leadStretch = 0.4
    static let trailFollow = 0.12
    static let neck = 0.16
    static let leadBulge = 0.06
    static let inwardLead = 0.2
    static let inwardFollow = 0.06
    static let inwardNarrowing = 0.22
    static let leadRounding: CGFloat = 0.55
    static let trailTightening: CGFloat = 0.15
    // Centre disc, in fractions of its radius.
    static let discReach = 0.2
    static let discStretch = 0.16
    static let discNeck = 0.2
}

extension WandWedge {
    /// Splits a screen-space pull into travel along the ring (clockwise
    /// positive) and toward the centre (positive inward).
    func components(ofPull pull: CGPoint) -> (along: Double, inward: Double) {
        let radial = Self.radial(centerAngle), tangent = Self.tangent(centerAngle)
        let along = Double(pull.x * tangent.x + pull.y * tangent.y)
        let inward = -Double(pull.x * radial.x + pull.y * radial.y)
        return (max(-1, min(1, along)), max(-1, min(1, inward)))
    }

    /// The liquid outline for travel `along` the ring and `inward`.
    func liquidOutline(along: Double, inward: Double, step: CGFloat = 2.5) -> [CGPoint] {
        let t = along.isFinite ? max(-1, min(1, along)) : 0
        let r = inward.isFinite ? max(-1, min(1, inward)) : 0
        let a = CGFloat(abs(t)), inwardAmount = CGFloat(max(0, r))
        // Leading corners soften into a tip while trailing ones tighten.
        let lead = cornerRadius * (1 + WandLiquidMetrics.leadRounding * a)
        let trail = cornerRadius * max(0.5, 1 - WandLiquidMetrics.trailTightening * a)
        var radii: [CGFloat] = t >= 0 ? [trail, lead, lead, trail] : [lead, trail, trail, lead]
        radii[2] *= 1 + 0.6 * inwardAmount
        radii[3] *= 1 + 0.6 * inwardAmount
        let rest = outline(radii: radii, step: step)
        guard t != 0 || r != 0 else { return rest }

        let sign: Double = t >= 0 ? 1 : -1
        let span = Double(outer - inner)
        let mid = Double(inner + outer) / 2
        return rest.map { point in
            let rho = Double(hypot(point.x, point.y))
            let theta = WandRadialLayout.angle(x: Double(point.x), y: Double(point.y))
            var u = WandRadialLayout.angularDifference(theta, centerAngle) / halfWidth
            let normalized = max(0, min(1, (rho - Double(inner)) / span))
            let leading = max(0, min(1, (u * sign + 1) / 2))
            let eased = leading * leading * (3 - 2 * leading)
            // Leading edge reaches far, trailing edge follows a little, and
            // the leading edge bows outward in the middle like a meniscus.
            u += sign * Double(a) * (WandLiquidMetrics.trailFollow
                + (WandLiquidMetrics.leadStretch - WandLiquidMetrics.trailFollow) * leading)
            u += sign * Double(a) * WandLiquidMetrics.leadBulge
                * pow(max(0, u * sign), 8) * sin(.pi * normalized)
            // Volume is conserved: the stretched end narrows.
            var radius = mid + (rho - mid) * (1 - WandLiquidMetrics.neck * Double(a) * eased)
            if r != 0 {
                let toward = r > 0
                    ? WandLiquidMetrics.inwardLead * (1 - normalized) + WandLiquidMetrics.inwardFollow * normalized
                    : WandLiquidMetrics.inwardFollow * (1 - normalized) + WandLiquidMetrics.inwardLead * normalized
                radius -= r * span * toward
                let narrowEnd = r > 0 ? 1 - normalized : normalized
                u *= 1 - abs(r) * WandLiquidMetrics.inwardNarrowing * narrowEnd
            }
            let angle = centerAngle + u * halfWidth
            return CGPoint(x: CGFloat(radius * sin(angle)), y: CGFloat(-radius * cos(angle)))
        }
    }
}

enum WandLiquidDisc {
    /// Circle of `radius` drawn toward `pull` like one drop: the leading side
    /// reaches out and narrows, the trailing side follows a little.
    static func outline(radius: CGFloat, pull: CGPoint, step: CGFloat = 2.5) -> [CGPoint] {
        let count = max(48, Int((2 * .pi * radius / step).rounded(.up)))
        let length = min(1, hypot(pull.x, pull.y))
        let direction = length > 0.0001 ? CGPoint(x: pull.x / length, y: pull.y / length) : CGPoint(x: 0, y: -1)
        let normal = CGPoint(x: -direction.y, y: direction.x)
        let v = Double(length)
        return (0..<count).map { index in
            let alpha = 2 * Double.pi * Double(index) / Double(count)
            var along = Double(radius) * cos(alpha)
            var across = Double(radius) * sin(alpha)
            if v > 0 {
                along = along * (1 + WandLiquidMetrics.discStretch * v) + WandLiquidMetrics.discReach * v * Double(radius)
                across *= 1 - WandLiquidMetrics.discNeck * v * (1 + cos(alpha)) / 2
            }
            return CGPoint(x: direction.x * CGFloat(along) + normal.x * CGFloat(across),
                           y: direction.y * CGFloat(along) + normal.y * CGFloat(across))
        }
    }
}

// MARK: - Shapes

private func closedPath(_ points: [CGPoint], around center: CGPoint) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: CGPoint(x: first.x + center.x, y: first.y + center.y))
    for point in points.dropFirst() {
        path.addLine(to: CGPoint(x: point.x + center.x, y: point.y + center.y))
    }
    path.closeSubpath()
    return path
}

/// A ring card's fill and border. Drawn across the whole wheel frame.
struct WandWedgeShape: InsettableShape {
    var wedge: WandWedge

    func path(in rect: CGRect) -> Path {
        closedPath(wedge.outline(), around: CGPoint(x: rect.midX, y: rect.midY))
    }

    func inset(by amount: CGFloat) -> WandWedgeShape {
        WandWedgeShape(wedge: wedge.expanded(by: -amount))
    }
}

/// The centre card, a circle about the wheel centre.
struct WandCenterDiscShape: InsettableShape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
    }

    func inset(by amount: CGFloat) -> WandCenterDiscShape {
        WandCenterDiscShape(radius: max(0.5, radius - amount))
    }
}

/// Liquid wand outline around a ring card. The centre angle animates too, so
/// a neighbour change slides the outline round the wheel.
struct WandLiquidWedgeOutline: Shape {
    var wedge: WandWedge
    var along: Double
    var inward: Double

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(wedge.centerAngle, AnimatablePair(along, inward)) }
        set {
            wedge.centerAngle = newValue.first
            along = newValue.second.first
            inward = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        closedPath(wedge.liquidOutline(along: along, inward: inward), around: CGPoint(x: rect.midX, y: rect.midY))
    }
}

/// Liquid wand outline around the centre card.
struct WandLiquidDiscOutline: Shape {
    var radius: CGFloat
    var pullX: Double
    var pullY: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(pullX, pullY) }
        set { pullX = newValue.first; pullY = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        closedPath(
            WandLiquidDisc.outline(radius: radius, pull: CGPoint(x: pullX, y: pullY)),
            around: CGPoint(x: rect.midX, y: rect.midY)
        )
    }
}
