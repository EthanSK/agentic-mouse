import CoreGraphics
import SwiftUI

/// Ethan: "when each HUD item is selected, it should sort of do like a nice
/// animation where it like zooms in a bit gradually for that wedge", and "can
/// we have a wedge animate to be higher". The outlined card grows a little and
/// rises outward from the wheel centre; the centre card only grows.
///
/// One pose drives the card, its text, its outline and its glass mask, so they
/// never separate. The lift is modest: a lifted ring card still stays inside
/// the wheel frame and clear of the centre card, and it changes no selection
/// geometry (navigation keeps using the resting layout).
enum WandCardLift {
    static let scale: CGFloat = 1.05
    /// Outward travel of a lifted ring card, in points.
    static let rise: CGFloat = 7

    struct Pose: Equatable {
        var scale: CGFloat
        /// Scale origin, in the wheel frame's unit coordinates.
        var anchor: UnitPoint
        var offset: CGSize
    }

    /// The pose for the card in `slot`. Ring cards anchor on their own middle
    /// so they grow in place; `angle` lets the moving outline follow its own
    /// centre angle instead of a card's.
    static func pose(for slot: WandWheelGeometry.Slot, lifted: Bool, in geometry: WandWheelGeometry,
                     angle: Double? = nil) -> Pose {
        let size = max(geometry.size, 1)
        switch slot {
        case .center:
            return Pose(scale: lifted ? scale : 1, anchor: .center, offset: .zero)
        case .ring(let index):
            let direction = WandWedge.radial(angle ?? geometry.layout.angle(at: index))
            let middle = (WandWheelMetrics.innerRadius + WandWheelMetrics.outerRadius) / 2
            let anchor = UnitPoint(x: (geometry.center.x + direction.x * middle) / size,
                                   y: (geometry.center.y + direction.y * middle) / size)
            let offset = lifted ? CGSize(width: direction.x * rise, height: direction.y * rise) : .zero
            return Pose(scale: lifted ? scale : 1, anchor: anchor, offset: offset)
        case .outer(let index):
            // Outer cards grow about their own band and rise a little less,
            // so a lifted large card stays inside the fixed wheel frame.
            let direction = WandWedge.radial(angle ?? geometry.layout.outerAngle(at: index))
            let wedge = geometry.outerWedge(at: index)
            let middle = (wedge.inner + wedge.outer) / 2
            let anchor = UnitPoint(x: (geometry.center.x + direction.x * middle) / size,
                                   y: (geometry.center.y + direction.y * middle) / size)
            let travel = rise * 0.6
            let offset = lifted ? CGSize(width: direction.x * travel, height: direction.y * travel) : .zero
            return Pose(scale: lifted ? scale : 1, anchor: anchor, offset: offset)
        }
    }

    /// The same pose as an affine transform in wheel-frame points, matching
    /// `scaleEffect(_:anchor:)` followed by `offset(_:)`.
    static func transform(_ pose: Pose, size: CGFloat) -> CGAffineTransform {
        let anchor = CGPoint(x: pose.anchor.x * size, y: pose.anchor.y * size)
        return CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(scaleX: pose.scale, y: pose.scale))
            .concatenating(CGAffineTransform(translationX: anchor.x + pose.offset.width,
                                             y: anchor.y + pose.offset.height))
    }

    /// A gentle one-shot settle; nothing repeats. Reduce Motion lifts the card
    /// at once without travel.
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78)
    }
}

extension View {
    /// Applies a lift pose: scale about its anchor, then rise. Animates only
    /// when the pose changes, so a resting wheel does no work.
    func wandCardLift(_ pose: WandCardLift.Pose, reduceMotion: Bool) -> some View {
        scaleEffect(pose.scale, anchor: pose.anchor)
            .offset(pose.offset)
            .animation(WandCardLift.animation(reduceMotion: reduceMotion), value: pose)
    }
}

/// Ethan: "the text is still a bit hard to read. Maybe you can give it like a
/// thin black outline or an outline that works well for its color". A tight
/// halo in the colour opposite the text traces each glyph, and a softer one
/// separates it from busy artwork or desktop behind the glass. It is applied
/// per text run, never to a whole-wheel layer.
struct WandCardTextHalo: ViewModifier {
    /// True for the black text on a selected review card.
    let foregroundIsDark: Bool

    static func haloColor(foregroundIsDark: Bool) -> Color {
        foregroundIsDark ? .white : .black
    }

    func body(content: Content) -> some View {
        let halo = Self.haloColor(foregroundIsDark: foregroundIsDark)
        content
            .shadow(color: halo.opacity(foregroundIsDark ? 0.5 : 0.7), radius: 0.8)
            .shadow(color: halo.opacity(foregroundIsDark ? 0.25 : 0.4), radius: 2.5)
    }
}
