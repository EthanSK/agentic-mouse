import CoreGraphics
import Foundation

/// Pure decisions for "drag a snapped window away and it gets its old size
/// back", the Magnet behaviour Ethan asked for on 2026-10-31: "when I drag
/// the window from its snapped position and start moving it, normally
/// Magnet will [restore] its original position before the magnet snapped it.
/// Ours doesn't."
///
/// Magnet's own setting for this is "Restore windows to original size"
/// ("dragging windows away from target positions restores them to original
/// size"). Only the SIZE comes back; the window stays under the pointer so
/// the drag continues naturally. Coordinates are top-left (Accessibility).
public enum WindowSnapDragRestore {
    /// Which pre-snap frame to remember for a new snap. A window that is
    /// still exactly where Agentic Mouse last snapped it (e.g. a second
    /// Left press hopping monitors) keeps its ORIGINAL pre-snap frame; a
    /// window the user has moved or resized since gets its current frame.
    public static func originalForSnap(preSnap: CGRect, previousOriginal: CGRect?,
                                       previousAccepted: CGRect?) -> CGRect {
        guard let previousOriginal, let previousAccepted,
              WindowSnapGeometry.approximatelyEqual(preSnap, previousAccepted, tolerance: 2) else { return preSnap }
        return previousOriginal
    }

    /// Where the window should go when a move of a snapped window is seen
    /// while the mouse button is down, or nil when nothing should happen:
    ///  - the window's size no longer matches the snap (the user is
    ///    resizing, or the app changed it) → nil, and the caller forgets it;
    ///  - it hasn't actually left its snapped position yet → nil;
    ///  - its original size is the same as the snapped size → nil.
    /// Otherwise: original size, same top edge, with the pointer kept at the
    /// same fraction across the title bar so the window doesn't jump away.
    public static func restoredFrame(current: CGRect, accepted: CGRect, original: CGRect,
                                     pointer: CGPoint) -> CGRect? {
        guard sameSize(current, accepted) else { return nil }
        let moved = abs(current.minX - accepted.minX) > 3 || abs(current.minY - accepted.minY) > 3
        guard moved, !sameSize(original, accepted), current.width > 0 else { return nil }
        let fraction = min(max((pointer.x - current.minX) / current.width, 0), 1)
        let x = (pointer.x - original.width * fraction).rounded()
        return CGRect(x: x, y: current.minY.rounded(), width: original.width, height: original.height)
    }

    /// True when the window was resized away from the snapped size, so the
    /// snap no longer applies and the remembered original should be dropped.
    public static func sizeChanged(current: CGRect, accepted: CGRect) -> Bool {
        !sameSize(current, accepted)
    }

    private static func sameSize(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }
}
