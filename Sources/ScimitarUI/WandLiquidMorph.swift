import CoreGraphics
import Foundation
import SwiftUI

/// Ethan's liquid wand outline travelling between the centre card and a ring
/// card, instead of fading out on one and reappearing on the other.
///
/// `progress` 0 is the centre disc and 1 is the ring card at `angle`.
/// Between them the centre drop first reaches toward the card, then the
/// outline flows into the card's shape as one blob: its centre travels and its
/// edge morphs, so it never disappears. Moving back runs the same path in
/// reverse. At either end the outline is exactly the existing disc or wedge
/// outline with its live pull, so the morph adds nothing at rest.
enum WandLiquidMorph {
    /// Outline samples used while morphing; the ends use their own outlines.
    static let samples = 144

    static func smoothstep(_ value: Double) -> Double {
        let t = max(0, min(1, value))
        return t * t * (3 - 2 * t)
    }

    /// - Parameters:
    ///   - pull: the live screen-space pull of the focused card.
    ///   - towardCenter: the focus is on the centre, so `pull` is the disc's
    ///     and the morph is the departure from a ring card.
    static func outline(
        progress: Double,
        angle: Double,
        pull: CGPoint,
        towardCenter: Bool,
        wedge template: WandWedge,
        discRadius: CGFloat
    ) -> [CGPoint] {
        var wedge = template
        wedge.centerAngle = angle
        let p = progress.isFinite ? max(0, min(1, progress)) : (towardCenter ? 0 : 1)
        if p <= 0.0001 {
            return WandLiquidDisc.outline(radius: discRadius, pull: towardCenter ? pull : .zero)
        }
        if p >= 0.9999 {
            let parts = towardCenter ? (along: 0.0, inward: 0.0) : wedge.components(ofPull: pull)
            return wedge.liquidOutline(along: parts.along, inward: parts.inward)
        }
        let direction = WandWedge.radial(angle)
        // The centre drop reaches toward the card first...
        let reach = smoothstep(p / 0.55)
        var discPull = CGPoint(x: direction.x * reach, y: direction.y * reach)
        if towardCenter {
            // ...and settles back into the live centre pull as it arrives.
            discPull = CGPoint(x: pull.x + (discPull.x - pull.x) * reach, y: pull.y + (discPull.y - pull.y) * reach)
        }
        // ...then the card's outline flows in from the centre side.
        let settle = smoothstep((p - 0.45) / 0.55)
        let wedgePoints: [CGPoint]
        if towardCenter {
            // Ease out of the resting wedge too. A full inward pull here
            // snapped the outline by 14 points on the first animation frame.
            wedgePoints = wedge.liquidOutline(along: 0, inward: 1 - settle)
        } else {
            let live = wedge.components(ofPull: pull)
            wedgePoints = wedge.liquidOutline(along: live.along * settle,
                                              inward: 1 + (live.inward - 1) * settle)
        }
        let discPoints = WandLiquidDisc.outline(radius: discRadius, pull: discPull)
        return blend(discPoints, wedgePoints, weight: smoothstep((p - 0.25) / 0.5))
    }

    /// One continuous blob between two star-shaped outlines: its centre moves
    /// from one centroid to the other while each ray's radius blends.
    static func blend(_ from: [CGPoint], _ to: [CGPoint], weight: Double) -> [CGPoint] {
        let w = CGFloat(max(0, min(1, weight)))
        if w <= 0 { return from }
        if w >= 1 { return to }
        let a = centroid(from), b = centroid(to)
        let center = CGPoint(x: a.x + (b.x - a.x) * w, y: a.y + (b.y - a.y) * w)
        return (0..<samples).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(samples)
            let ray = CGPoint(x: CGFloat(sin(angle)), y: CGFloat(-cos(angle)))
            let ra = reach(from, center: a, ray: ray), rb = reach(to, center: b, ray: ray)
            let radius = ra + (rb - ra) * w
            return CGPoint(x: center.x + ray.x * radius, y: center.y + ray.y * radius)
        }
    }

    /// Area centroid of a closed polygon.
    static func centroid(_ points: [CGPoint]) -> CGPoint {
        var area: CGFloat = 0, x: CGFloat = 0, y: CGFloat = 0
        for index in points.indices {
            let p = points[index], q = points[(index + 1) % points.count]
            let cross = p.x * q.y - q.x * p.y
            area += cross
            x += (p.x + q.x) * cross
            y += (p.y + q.y) * cross
        }
        guard abs(area) > 0.0001 else {
            let count = CGFloat(max(1, points.count))
            return CGPoint(x: points.reduce(0) { $0 + $1.x } / count, y: points.reduce(0) { $0 + $1.y } / count)
        }
        return CGPoint(x: x / (3 * area), y: y / (3 * area))
    }

    /// Distance from `center` along `ray` to the outline (the farthest hit).
    static func reach(_ points: [CGPoint], center: CGPoint, ray: CGPoint) -> CGFloat {
        var best: CGFloat = 0
        for index in points.indices {
            let p = points[index], q = points[(index + 1) % points.count]
            let edge = CGPoint(x: q.x - p.x, y: q.y - p.y)
            let denominator = ray.x * edge.y - ray.y * edge.x
            guard abs(denominator) > 1e-9 else { continue }
            let offset = CGPoint(x: p.x - center.x, y: p.y - center.y)
            let t = (offset.x * edge.y - offset.y * edge.x) / denominator
            let s = (offset.x * ray.y - offset.y * ray.x) / denominator
            if t >= 0, s >= 0, s <= 1 { best = max(best, t) }
        }
        return best
    }
}

/// The wand's navigation outline on whichever card it is on, morphing
/// between the centre and the ring. Concrete shape (never type-erased) so
/// SwiftUI interpolates progress, angle and pull together.
struct WandLiquidMorphOutline: Shape {
    var progress: Double
    var angle: Double
    var pullX: Double
    var pullY: Double
    let towardCenter: Bool
    /// Its radii and width animate too, so moving between a ring card and an
    /// outer-layer card flows outward instead of cutting.
    var wedge: WandWedge
    let discRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>>,
                                       AnimatablePair<Double, AnimatablePair<Double, Double>>> {
        get {
            AnimatablePair(AnimatablePair(AnimatablePair(progress, angle), AnimatablePair(pullX, pullY)),
                           AnimatablePair(wedge.halfWidth, AnimatablePair(Double(wedge.inner), Double(wedge.outer))))
        }
        set {
            progress = newValue.first.first.first
            angle = newValue.first.first.second
            pullX = newValue.first.second.first
            pullY = newValue.first.second.second
            wedge.halfWidth = newValue.second.first
            wedge.inner = CGFloat(newValue.second.second.first)
            wedge.outer = CGFloat(newValue.second.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        let points = WandLiquidMorph.outline(
            progress: progress, angle: angle, pull: CGPoint(x: pullX, y: pullY),
            towardCenter: towardCenter, wedge: wedge, discRadius: discRadius
        )
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x + rect.midX, y: first.y + rect.midY))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x + rect.midX, y: point.y + rect.midY))
        }
        path.closeSubpath()
        return path
    }
}
