import Foundation

public enum WindowResizeAxis: String, Sendable {
    case width
    case height
}

/// Screen coordinates with a top-left origin, matching Quartz and Accessibility.
/// The fractional anchor is fixed at button-down, so reversing a detent restores
/// the original frame without drifting toward an edge or the centre.
public struct WindowResizeGeometry: Sendable {
    public let anchor: CGPoint
    public let fraction: CGPoint
    public let bounds: CGRect

    public init?(frame: CGRect, pointer: CGPoint, bounds: CGRect) {
        guard Self.valid(frame), Self.valid(bounds), pointer.x.isFinite, pointer.y.isFinite,
              frame.contains(pointer), bounds.contains(pointer) else { return nil }
        anchor = pointer
        fraction = CGPoint(x: (pointer.x - frame.minX) / frame.width,
                           y: (pointer.y - frame.minY) / frame.height)
        self.bounds = bounds
    }

    public func frame(from current: CGRect, axis: WindowResizeAxis, delta: CGFloat) -> CGRect? {
        guard Self.valid(current), delta.isFinite else { return nil }
        let ratio = axis == .width ? fraction.x : fraction.y
        let point = axis == .width ? anchor.x : anchor.y
        let lower = axis == .width ? bounds.minX : bounds.minY
        let upper = axis == .width ? bounds.maxX : bounds.maxY
        let leftLimit = ratio > 0 ? (point - lower) / ratio : .infinity
        let rightLimit = ratio < 1 ? (upper - point) / (1 - ratio) : .infinity
        let maximum = min(leftLimit, rightLimit)
        let minimum = min(axis == .width ? 100 : 60, maximum)
        let oldSize = axis == .width ? current.width : current.height
        let size = min(maximum, max(minimum, oldSize + delta))
        var result = current
        if axis == .width { result.size.width = size } else { result.size.height = size }
        return anchored(result, axis: axis)
    }

    /// Re-anchor the size the app actually accepted, including its minimum size.
    public func anchored(_ actual: CGRect, axis: WindowResizeAxis) -> CGRect {
        var result = actual
        if axis == .width { result.origin.x = anchor.x - fraction.x * actual.width }
        else { result.origin.y = anchor.y - fraction.y * actual.height }
        return result
    }

    public static func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 2 && abs(lhs.minY - rhs.minY) <= 2
            && abs(lhs.width - rhs.width) <= 2 && abs(lhs.height - rhs.height) <= 2
    }

    private static func valid(_ frame: CGRect) -> Bool {
        frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite
            && frame.height.isFinite && frame.width > 0 && frame.height > 0
    }
}
