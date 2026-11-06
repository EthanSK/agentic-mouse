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
/// size"). Restore size in place first, then correct a far-edge grab only
/// when it falls outside the accepted restored bounds. Coordinates are
/// top-left (AX).
public enum WindowSnapDragRestore {
    /// Ethan's "pre-magnet, pre-our custom magnet size" is the size before
    /// the FIRST size-changing snap, not the frame before the latest command.
    /// Position-only snaps start no size memory. Keep the first size until
    /// a real drag successfully restores it, or the window closes. Settling
    /// frame changes and subsequent app-owned resizes must not replace it.
    public static func originalForSnap(preSnap: CGRect, previousOriginal: CGRect?,
                                       previousAccepted: CGRect?) -> CGRect {
        previousOriginal ?? preSnap
    }

    /// Where the window should go when a move of a snapped window is seen
    /// during an observed mouse drag, or nil when nothing should happen:
    ///  - the window's size no longer matches the snap (the user is
    ///    resizing, or the app changed it) → nil, without losing the original;
    ///  - it hasn't actually left its snapped position yet → nil;
    ///  - its original size is the same as the snapped size → nil.
    /// Otherwise: the original SIZE at the window's CURRENT origin — a
    /// resize in place. Ordinary restores preserve macOS's grab offset;
    /// unconditionally moving the window after every resize caused jumps in
    /// earlier Mini tests. A far-edge grab needs the separate correction below.
    /// Pointer correction is a separate decision after the size write has
    /// been read back; it must use the size the app actually accepted.
    public static func restoredFrame(current: CGRect, accepted: CGRect, original: CGRect,
                                     pointer: CGPoint) -> CGRect? {
        guard sameSize(current, accepted) else { return nil }
        let moved = abs(current.minX - accepted.minX) > 3 || abs(current.minY - accepted.minY) > 3
        guard moved, !sameSize(original, accepted), current.width > 0 else { return nil }
        return CGRect(origin: current.origin, size: original.size)
    }

    /// Keep a far-edge title-bar grab on a narrow restored window. The
    /// original down-point ratio is stable even when the worker reads geometry
    /// after newer pointer events; ordinary in-place restores need no move.
    public static func correctedOrigin(after: CGRect, grabFrame: CGRect,
                                       grabPoint: CGPoint, pointer: CGPoint) -> CGPoint? {
        guard !after.contains(pointer), grabFrame.width > 0, grabFrame.height > 0,
              after.width > 0, after.height > 0 else { return nil }
        let x = min(1, max(0, (grabPoint.x - grabFrame.minX) / grabFrame.width))
        let y = min(1, max(0, (grabPoint.y - grabFrame.minY) / grabFrame.height))
        return CGPoint(x: pointer.x - x * after.width, y: pointer.y - y * after.height)
    }

    /// True when the current size differs from the accepted snap. This does
    /// not invalidate the remembered first size; later snaps still retain it.
    public static func sizeChanged(current: CGRect, accepted: CGRect) -> Bool {
        !sameSize(current, accepted)
    }

    private static func sameSize(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2
    }
}
