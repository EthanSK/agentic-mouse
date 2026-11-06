import CoreGraphics
import Foundation

/// Pure geometry for Agentic Mouse's built-in Left/Right window snapping, the
/// action behind the Magic Wand's "Magnet wedge" and the mice's
/// Magnet + Wheel card (Ethan's terminology: "Magnet" here means these
/// Left/Right half placements, not the third-party Magnet app).
///
/// Ported from Ethan's Lodestone prototype (~/Projects/lodestone,
/// LodestoneCore Placement/Display), trimmed to Left/Right halves. Ethan,
/// 2026-10-31: "maybe it should be part of the Agentic Mouse app instead of
/// its own standalone app ... It's just left and right snapping for now".
///
/// COORDINATES: top-left origin at the primary display, y down — the
/// Quartz/Accessibility space `kAXPositionAttribute` uses, same as
/// `WindowResizeGeometry`. Convert NSScreen frames with `fromCocoa`.
public struct WindowSnapDisplay: Equatable, Sendable {
    public let id: String
    /// Whole display, used for neighbour detection.
    public let frame: CGRect
    /// Area excluding menu bar and Dock, where windows are placed.
    public let visibleFrame: CGRect

    public init(id: String, frame: CGRect, visibleFrame: CGRect) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    /// NSScreen frames are bottom-left based; `primaryHeight` is the height
    /// of the screen whose Cocoa origin is (0, 0).
    public static func fromCocoa(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

public enum WindowSnapDirection: String, Sendable {
    case left
    case right
}

/// What Agentic Mouse remembers about the last snap it made to a window, so
/// a repeated press still counts as "already there" when the app refused the
/// exact half size (minimum widths, Terminal's character grid). Without this
/// memory a narrow display's half could be smaller than the app's minimum
/// width, the frame would never match the half, and the window would get
/// stuck instead of hopping to the next monitor — one cause of the "dodgy"
/// cross-monitor behaviour Ethan reported with Magnet.
public struct WindowSnapMemory: Equatable, Sendable {
    public let direction: WindowSnapDirection
    public let displayID: String
    public let acceptedFrame: CGRect

    public init(direction: WindowSnapDirection, displayID: String, acceptedFrame: CGRect) {
        self.direction = direction
        self.displayID = displayID
        self.acceptedFrame = acceptedFrame
    }
}

public struct WindowSnapPlan: Equatable, Sendable {
    public let frame: CGRect
    public let display: WindowSnapDisplay
    /// The side of the display the window belongs on. If the app refuses
    /// the requested size, the window is re-aligned to this edge.
    public let side: WindowSnapDirection
    /// True when the press moved the window onto a neighbouring display.
    public let traversedDisplay: Bool
}

public enum WindowSnapGeometry {
    /// Slack for "the window is already on this half". Apps round sizes to
    /// their own increments; exact equality would block display hopping.
    public static let matchTolerance: CGFloat = 12

    /// The left or right half of a display's usable area. Each edge is
    /// rounded separately so two halves share an exact boundary.
    public static func half(_ side: WindowSnapDirection, of display: WindowSnapDisplay) -> CGRect {
        let v = display.visibleFrame
        let mid = (v.minX + v.width / 2).rounded()
        let minX = side == .left ? v.minX.rounded() : mid
        let maxX = side == .left ? mid : v.maxX.rounded()
        return CGRect(x: minX, y: v.minY.rounded(), width: maxX - minX, height: v.maxY.rounded() - v.minY.rounded())
    }

    /// The display covering most of the window (nearest one if off-screen).
    public static func display(for window: CGRect, in displays: [WindowSnapDisplay]) -> WindowSnapDisplay? {
        var best: (WindowSnapDisplay, CGFloat)?
        for display in displays {
            let overlap = display.frame.intersection(window)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > (best?.1 ?? 0) { best = (display, area) }
        }
        if let best { return best.0 }
        let centre = CGPoint(x: window.midX, y: window.midY)
        return displays.min { distance(centre, $0.frame) < distance(centre, $1.frame) }
    }

    /// The display wholly to the left/right of `current` (1 pt slop). Prefer
    /// the one most level with it (largest vertical overlap), then the
    /// nearest. Ethan's MacBook sits lower-left of the ultrawide and still
    /// counts as its western neighbour.
    public static func neighbor(of current: WindowSnapDisplay, toward side: WindowSnapDirection,
                                in displays: [WindowSnapDisplay]) -> WindowSnapDisplay? {
        let candidates = displays.filter { candidate in
            guard candidate != current else { return false }
            return side == .left
                ? candidate.frame.maxX <= current.frame.minX + 1
                : candidate.frame.minX >= current.frame.maxX - 1
        }
        func overlap(_ d: WindowSnapDisplay) -> CGFloat {
            max(0, min(d.frame.maxY, current.frame.maxY) - max(d.frame.minY, current.frame.minY))
        }
        func gap(_ d: WindowSnapDisplay) -> CGFloat {
            side == .left ? current.frame.minX - d.frame.maxX : d.frame.minX - current.frame.maxX
        }
        return candidates.min { a, b in
            overlap(a) != overlap(b) ? overlap(a) > overlap(b) : gap(a) < gap(b)
        }
    }

    /// Where a Left/Right press sends the window, or nil to leave it alone
    /// (already on that half of the outermost display).
    ///
    /// Behaviour (matches the Magnet behaviour the wedge was built around):
    ///  - not yet on the half → snap to that half of its current display;
    ///  - already on the half → hop to the OPPOSITE half of the neighbouring
    ///    display in that direction (Left lands on the west display's right
    ///    half), so repeated presses walk across every monitor;
    ///  - already there with no neighbour → nil.
    public static func plan(_ side: WindowSnapDirection, window: CGRect, displays: [WindowSnapDisplay],
                            memory: WindowSnapMemory?) -> WindowSnapPlan? {
        guard let current = display(for: window, in: displays) else { return nil }
        let target = half(side, of: current)
        let rememberedHere = memory.map {
            $0.direction == side && $0.displayID == current.id
                && approximatelyEqual($0.acceptedFrame, window, tolerance: 2)
        } ?? false
        let alreadyThere = approximatelyEqual(window, target, tolerance: matchTolerance) || rememberedHere
        guard alreadyThere else {
            return WindowSnapPlan(frame: target, display: current, side: side, traversedDisplay: false)
        }
        guard let next = neighbor(of: current, toward: side, in: displays) else { return nil }
        let landing: WindowSnapDirection = side == .left ? .right : .left
        return WindowSnapPlan(frame: half(landing, of: next), display: next, side: landing, traversedDisplay: true)
    }

    /// After the app answers, keep the window fully on the target display
    /// and flush with its side, even when the app refused the half size
    /// (e.g. a 1,000 pt minimum width on an 864 pt MacBook half). Returns
    /// nil when no correction is needed. This stops a hopped window ending
    /// up straddling two monitors.
    public static func correction(accepted: CGRect, plan: WindowSnapPlan) -> CGRect? {
        let v = plan.display.visibleFrame
        var frame = accepted
        frame.origin.x = plan.side == .left ? plan.frame.minX : plan.frame.maxX - accepted.width
        // Never push the window past either edge of the usable area.
        frame.origin.x = min(max(frame.minX, v.minX), max(v.minX, v.maxX - frame.width))
        frame.origin.y = min(max(accepted.minY, v.minY), max(v.minY, v.maxY - frame.height))
        return approximatelyEqual(frame, accepted, tolerance: 1) ? nil : frame
    }

    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
