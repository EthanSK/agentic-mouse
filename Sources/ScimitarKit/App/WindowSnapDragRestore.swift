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
/// size"). Only the SIZE comes back in place; macOS retains the title-bar
/// drag's original grab offset. A grab near the far edge of a wide snap can
/// lie beyond the restored narrow window. Coordinates are top-left (AX).
public enum WindowSnapDragRestore {
    /// Ethan's "pre-magnet, pre-our custom magnet size" is the size before
    /// the FIRST snap, not the frame before the latest command. Keep it until
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
    /// resize in place. Do not move the window: macOS owns the drag and keeps
    /// its own grab offset, so a position write mid-drag is undone on the next
    /// mouse event and the window jumps away from the pointer. That jump was
    /// the symptom in Ethan's "doesn't quite work" report. Mac mini drag tests
    /// (upstream synthetic title-bar drags with movement deltas) reported:
    /// size+position → window jumped back ~130 pt from the pointer; size only →
    /// window kept following smoothly with the pointer on its title bar.
    /// The 2026-11-01 binary investigation found that Magnet also corrects
    /// some far-edge grabs; size-only restoration does not implement that
    /// separate correction. `pointer` remains unused by this size decision.
    public static func restoredFrame(current: CGRect, accepted: CGRect, original: CGRect,
                                     pointer: CGPoint) -> CGRect? {
        guard sameSize(current, accepted) else { return nil }
        let moved = abs(current.minX - accepted.minX) > 3 || abs(current.minY - accepted.minY) > 3
        guard moved, !sameSize(original, accepted), current.width > 0 else { return nil }
        return CGRect(origin: current.origin, size: original.size)
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
