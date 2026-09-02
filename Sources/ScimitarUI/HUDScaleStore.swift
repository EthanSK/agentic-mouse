import Combine
import Foundation

/// Owns the one persisted size shared by every Agentic Mouse HUD.
public final class HUDScaleStore: ObservableObject {
    public static let defaultScale = 0.5
    public static let minimumScale = 0.35
    public static let maximumScale = 1.0
    public static let shared = HUDScaleStore()

    @Published public private(set) var scale: Double

    private let defaults: UserDefaults
    private let defaultsKey: String

    public init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = "hudScale"
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        let storedScale = defaults.object(forKey: defaultsKey) as? Double
        scale = Self.sanitized(storedScale ?? Self.defaultScale)
    }

    /// Saves a bounded scale so every visible HUD can resize from one source of truth.
    public func setScale(_ requestedScale: Double) {
        let updatedScale = Self.sanitized(requestedScale)
        guard updatedScale != scale else { return }
        scale = updatedScale
        defaults.set(updatedScale, forKey: defaultsKey)
    }

    private static func sanitized(_ scale: Double) -> Double {
        guard scale.isFinite else { return defaultScale }
        return min(maximumScale, max(minimumScale, scale))
    }
}
