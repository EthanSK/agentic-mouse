import Foundation

/// One configured Living-room light and the cluster it belongs to.
///
/// `resourceIdentifier` is a Hue v2 resource UUID. It lives in the user's local
/// config file, never in this repository: the example config ships placeholders
/// and the loader treats them as "unconfigured".
public struct HueLightAssignment: Equatable, Codable, Sendable {
    public var resourceIdentifier: String
    public var cluster: HueCluster
    /// Friendly label for the doctor CLI and the menu. Free text chosen by the
    /// user; defaults to the cluster name so nothing identifying is required.
    public var label: String
    /// Relative influence inside its cluster. 1.0 unless a lamp should count
    /// for more.
    public var weight: Double

    public init(resourceIdentifier: String, cluster: HueCluster, label: String, weight: Double = 1.0) {
        self.resourceIdentifier = resourceIdentifier
        self.cluster = cluster
        self.label = label
        self.weight = weight
    }

    /// Placeholder values in the example config must never be treated as real.
    public var isPlaceholder: Bool {
        resourceIdentifier.isEmpty
            || resourceIdentifier.hasPrefix("REPLACE_ME")
            || resourceIdentifier.hasPrefix("00000000-0000-0000-0000-")
    }
}

/// Aggregates several lamps into one colour per cluster.
///
/// Averaging colour correctly matters here. Mixing `#FF0000` and `#00FF00` in
/// gamma-encoded sRGB gives a muddy dark olive; mixing them in *linear* light
/// gives the yellow a real room would show. So every lamp is decoded to linear
/// RGB, weighted by its own brightness (a lamp at 5% should barely tint the
/// result) and by its configured weight, then re-encoded once at the end.
public enum HueClusterAggregator {

    /// The colour for one cluster, or `nil` when every lamp in it is off.
    public static func color(
        for cluster: HueCluster,
        assignments: [HueLightAssignment],
        states: [String: HueLightState],
        policy: HueMirrorPolicy = .default
    ) -> RGBColor? {
        let members = assignments.filter { $0.cluster == cluster && !$0.isPlaceholder }
        guard !members.isEmpty else { return nil }

        var accumulatedRed = 0.0
        var accumulatedGreen = 0.0
        var accumulatedBlue = 0.0
        var totalWeight = 0.0
        var brightestContribution = 0.0

        for member in members {
            guard let state = states[member.resourceIdentifier], state.isOn else { continue }

            let base = HueColorConverter.baseColor(for: state)
            let brightness = HueColorConverter.effectiveBrightness(for: state, policy: policy)
            let weight = max(0, member.weight) * max(0.0001, brightness)
            guard weight > 0 else { continue }

            let linear = linearComponents(of: base)
            accumulatedRed += linear.red * weight
            accumulatedGreen += linear.green * weight
            accumulatedBlue += linear.blue * weight
            totalWeight += weight
            brightestContribution = max(brightestContribution, brightness)
        }

        // Every lamp in this cluster is off.
        guard totalWeight > 0 else { return nil }

        let mixed = (
            red: accumulatedRed / totalWeight,
            green: accumulatedGreen / totalWeight,
            blue: accumulatedBlue / totalWeight
        )

        // Normalise the mixed hue to full intensity, then re-apply the cluster's
        // overall brightness so a dim room produces a dim mouse.
        let peak = max(mixed.red, max(mixed.green, mixed.blue))
        guard peak > 1e-9 else { return .black }

        let normalised = RGBColor(
            unitRed: HueColorConverter.gammaEncode(mixed.red / peak),
            unitGreen: HueColorConverter.gammaEncode(mixed.green / peak),
            unitBlue: HueColorConverter.gammaEncode(mixed.blue / peak)
        )
        let saturated = HueColorConverter.saturate(normalised, by: policy.saturationBoost)
        return saturated.scaledBrightness(brightestContribution)
    }

    /// The complete two-zone frame.
    ///
    /// Returns `nil` only when *nothing* is configured, which the caller treats
    /// as "release the layer". A configured cluster whose lamps are all off
    /// renders black, so the mouse mirrors the room going dark rather than
    /// reverting to iCUE's rainbow.
    public static func frame(
        assignments: [HueLightAssignment],
        states: [String: HueLightState],
        policy: HueMirrorPolicy = .default,
        lastLitColors: [HueCluster: RGBColor] = [:]
    ) -> LightingFrame? {
        let configured = assignments.filter { !$0.isPlaceholder }
        guard !configured.isEmpty else { return nil }

        var colors: [MouseZone: RGBColor] = [:]
        for cluster in HueCluster.allCases {
            let members = configured.filter { $0.cluster == cluster }
            guard !members.isEmpty else { continue }

            if let color = color(for: cluster, assignments: configured, states: states, policy: policy) {
                colors[cluster.zone] = color
            } else {
                // All lamps in this cluster are off.
                switch policy.offPolicy {
                case .releaseLayer:
                    colors[cluster.zone] = .transparent
                case .blackout:
                    colors[cluster.zone] = .black
                case .dimLastColor:
                    colors[cluster.zone] = (lastLitColors[cluster] ?? .black)
                        .scaledBrightness(policy.dimFactor)
                }
            }
        }

        guard !colors.isEmpty else { return nil }
        return LightingFrame(colors: colors)
    }

    /// sRGB byte → linear light.
    static func linearComponents(of color: RGBColor) -> (red: Double, green: Double, blue: Double) {
        (
            red: gammaDecode(Double(color.red) / 255.0),
            green: gammaDecode(Double(color.green) / 255.0),
            blue: gammaDecode(Double(color.blue) / 255.0)
        )
    }

    static func gammaDecode(_ value: Double) -> Double {
        let v = max(0, min(1, value))
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
}
