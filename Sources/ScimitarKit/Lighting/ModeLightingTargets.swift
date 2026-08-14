import Foundation

/// Runtime lighting destinations that accepted the current mode colour.
///
/// Each device remains independent: one unavailable or failed adapter must not
/// suppress the other, and the HUD remains authoritative when this set is empty.
public struct ModeLightingTargets: OptionSet, Equatable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let corsair = ModeLightingTargets(rawValue: 1 << 0)
    public static let razer = ModeLightingTargets(rawValue: 1 << 1)
}
