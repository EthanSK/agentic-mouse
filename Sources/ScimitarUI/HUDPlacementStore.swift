import AppKit
import Combine
import ScimitarKit

/// Owns Ethan's configurable “top corners” for both mouse legends. The Wand
/// keeps its separate recorder-aware placement. — GPT-6.1 Sol
public final class HUDPlacementStore: ObservableObject {
    public static let shared = HUDPlacementStore()
    public static let defaultTopSpacing = 88.0
    public static let maximumTopSpacing = 240.0
    public static let sideInset = 12.0

    @Published public private(set) var edge: AppConfiguration.HUDConfiguration.VerticalEdge
    @Published public private(set) var topSpacing: Double
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        edge = defaults.string(forKey: "hudVerticalEdge")
            .flatMap(AppConfiguration.HUDConfiguration.VerticalEdge.init(rawValue:)) ?? .top
        topSpacing = Self.sanitized(defaults.object(forKey: "hudTopSpacing") as? Double ?? Self.defaultTopSpacing)
    }

    public func setEdge(_ edge: AppConfiguration.HUDConfiguration.VerticalEdge) {
        guard edge != self.edge else { return }
        self.edge = edge
        defaults.set(edge.rawValue, forKey: "hudVerticalEdge")
    }

    public func setTopSpacing(_ spacing: Double) {
        let spacing = Self.sanitized(spacing)
        guard spacing != topSpacing else { return }
        topSpacing = spacing
        defaults.set(spacing, forKey: "hudTopSpacing")
    }

    /// Spacing uses screen points, independent of HUD zoom. Give up the gap
    /// before letting a tall legend leave the usable screen. — GPT-6.1 Sol
    public func frame(source: MouseSource, size: NSSize, visibleFrame: NSRect, margin: CGFloat) -> NSRect {
        precondition(source != .wand, "Wand placement has its own owner")
        let corner = AppConfiguration.HUDConfiguration.sourceCorner(for: source, edge: edge)
        let inset = edge == .top ? max(margin, CGFloat(Self.sideInset)) : margin
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        let x = corner == .topLeft || corner == .bottomLeft
            ? visibleFrame.minX + inset : maximumX - inset
        let y = edge == .top ? maximumY - max(margin, CGFloat(topSpacing)) : visibleFrame.minY + margin
        return NSRect(x: min(maximumX, max(visibleFrame.minX, x)),
                      y: min(maximumY, max(visibleFrame.minY, y)),
                      width: size.width, height: size.height)
    }

    private static func sanitized(_ spacing: Double) -> Double {
        spacing.isFinite ? min(maximumTopSpacing, max(0, spacing)) : defaultTopSpacing
    }
}
