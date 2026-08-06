import Foundation

/// What the mouse should do when the living-room lamp is switched off.
public enum LampOffPolicy: String, Codable, CaseIterable, Sendable {
    /// Stop contributing entirely: the shared layer is released and ordinary
    /// iCUE lighting comes back. Lamp off ⇒ mouse looks normal.
    case releaseLayer
    /// Force the mouse dark, mirroring the room going dark.
    case blackout
    /// Keep the last colour, heavily dimmed, as an "it is off but I am still
    /// watching" hint.
    case dimLastColor
}

public struct HueMirrorPolicy: Equatable, Sendable {
    /// Lowest brightness the mouse will show while the lamp is on, so a lamp at
    /// 1% does not make the mouse look broken.
    public var brightnessFloor: Double
    public var brightnessCeiling: Double
    /// Perceptual lift. Hue reports brightness roughly perceptually, while the
    /// LEDs respond roughly linearly; < 1 brightens the low end.
    public var brightnessGamma: Double
    public var offPolicy: LampOffPolicy
    /// Brightness used by `.dimLastColor`.
    public var dimFactor: Double
    /// Extra saturation boost. Small mouse LEDs read as washed-out compared to
    /// a lamp filling a room.
    public var saturationBoost: Double

    public init(
        brightnessFloor: Double = 0.12,
        brightnessCeiling: Double = 1.0,
        brightnessGamma: Double = 0.7,
        // A cluster whose lamps are all off renders black: the mouse mirrors
        // the room going dark, rather than reverting to iCUE's own lighting
        // and looking like the feature broke.
        offPolicy: LampOffPolicy = .blackout,
        dimFactor: Double = 0.08,
        saturationBoost: Double = 0.15
    ) {
        self.brightnessFloor = brightnessFloor
        self.brightnessCeiling = brightnessCeiling
        self.brightnessGamma = brightnessGamma
        self.offPolicy = offPolicy
        self.dimFactor = dimFactor
        self.saturationBoost = saturationBoost
    }

    public static let `default` = HueMirrorPolicy()
}

/// Converts a Hue lamp reading into a colour for the mouse.
///
/// Pure maths, no I/O, fully unit-tested. Three inputs can describe a lamp and
/// all three are handled:
///
///   * `color.xy`             — CIE 1931 chromaticity (a colour bulb)
///   * `color_temperature`    — mirek / reciprocal megakelvin (white ambience)
///   * neither                — a plain dimmable bulb, treated as warm white
public enum HueColorConverter {

    /// The colour a single lamp should contribute, or `nil` when it is off.
    ///
    /// Cluster aggregation lives in `HueClusterAggregator`; this is the
    /// single-lamp primitive it is built from.
    public static func contribution(
        for state: HueLightState,
        policy: HueMirrorPolicy = .default
    ) -> RGBColor? {
        guard state.isOn else {
            switch policy.offPolicy {
            case .releaseLayer, .blackout:
                return nil
            case .dimLastColor:
                return baseColor(for: state).scaledBrightness(policy.dimFactor)
            }
        }
        return color(for: state, policy: policy)
    }

    /// Full conversion including brightness, floor, gamma and saturation.
    public static func color(for state: HueLightState, policy: HueMirrorPolicy = .default) -> RGBColor {
        let base = baseColor(for: state)
        let boosted = saturate(base, by: policy.saturationBoost)
        let brightness = effectiveBrightness(for: state, policy: policy)
        return boosted.scaledBrightness(brightness)
    }

    /// Brightness in 0…1 after the floor, ceiling and gamma are applied.
    public static func effectiveBrightness(for state: HueLightState, policy: HueMirrorPolicy) -> Double {
        // A light that reports no dimming value is at full output.
        let reported = (state.brightnessPercent ?? 100) / 100.0
        let clamped = max(0, min(1, reported))
        let gamma = policy.brightnessGamma > 0 ? policy.brightnessGamma : 1
        let shaped = pow(clamped, gamma)
        let floor = max(0, min(1, policy.brightnessFloor))
        let ceiling = max(floor, min(1, policy.brightnessCeiling))
        return floor + shaped * (ceiling - floor)
    }

    /// The full-brightness hue of the lamp, ignoring dimming.
    public static func baseColor(for state: HueLightState) -> RGBColor {
        if let chromaticity = state.chromaticity, !state.mirekValid {
            return fromChromaticity(x: chromaticity.x, y: chromaticity.y)
        }
        if state.mirekValid, let mirek = state.mirek, mirek > 0 {
            return fromMirek(mirek)
        }
        if let chromaticity = state.chromaticity {
            return fromChromaticity(x: chromaticity.x, y: chromaticity.y)
        }
        if let mirek = state.mirek, mirek > 0 {
            return fromMirek(mirek)
        }
        // Plain dimmable bulb: 2700 K, the standard warm-white Hue tone.
        return fromKelvin(2700)
    }

    // MARK: - CIE xy → sRGB

    /// CIE 1931 xy chromaticity to gamma-encoded sRGB at full luminance.
    public static func fromChromaticity(x: Double, y: Double) -> RGBColor {
        // Degenerate readings (y == 0) have no defined colour; fall back to
        // white rather than dividing by zero.
        guard x.isFinite, y.isFinite, y > 1e-6, x >= 0, x <= 1, y <= 1 else {
            return .white
        }

        let luminance = 1.0
        let bigX = (luminance / y) * x
        let bigY = luminance
        let bigZ = (luminance / y) * (1 - x - y)

        return fromXYZ(x: bigX, y: bigY, z: bigZ)
    }

    /// CIE XYZ (D65) to gamma-encoded sRGB, normalised to full brightness.
    public static func fromXYZ(x: Double, y: Double, z: Double) -> RGBColor {
        // sRGB D65 matrix.
        var r = x * 3.2404542 + y * -1.5371385 + z * -0.4985314
        var g = x * -0.9692660 + y * 1.8760108 + z * 0.0415560
        var b = x * 0.0556434 + y * -0.2040259 + z * 1.0572252

        // Out-of-gamut colours produce negative channels. Desaturating towards
        // white (rather than clipping to zero) keeps the hue recognisable,
        // which is what matters when mirroring a lamp onto four small LEDs.
        let minimum = min(r, min(g, b))
        if minimum < 0 {
            r -= minimum
            g -= minimum
            b -= minimum
        }

        // Normalise so the brightest channel is 1.0; overall brightness is
        // applied separately from the lamp's dimming value.
        let maximum = max(r, max(g, b))
        if maximum > 1e-9 {
            r /= maximum
            g /= maximum
            b /= maximum
        } else {
            return .black
        }

        return RGBColor(
            unitRed: gammaEncode(r),
            unitGreen: gammaEncode(g),
            unitBlue: gammaEncode(b)
        )
    }

    // MARK: - Colour temperature

    /// Hue's mirek (reciprocal megakelvin) to sRGB. 153 mirek = 6500 K,
    /// 500 mirek = 2000 K.
    public static func fromMirek(_ mirek: Int) -> RGBColor {
        guard mirek > 0 else { return .white }
        return fromKelvin(1_000_000.0 / Double(mirek))
    }

    /// Correlated colour temperature to sRGB, via the Kim et al. cubic-spline
    /// approximation of the Planckian locus in CIE xy.
    public static func fromKelvin(_ kelvin: Double) -> RGBColor {
        let t = max(1667, min(25000, kelvin))
        let t2 = t * t
        let t3 = t2 * t

        let x: Double
        if t <= 4000 {
            x = -0.2661239e9 / t3 - 0.2343589e6 / t2 + 0.8776956e3 / t + 0.179910
        } else {
            x = -3.0258469e9 / t3 + 2.1070379e6 / t2 + 0.2226347e3 / t + 0.240390
        }

        let x2 = x * x
        let x3 = x2 * x

        let y: Double
        if t <= 2222 {
            y = -1.1063814 * x3 - 1.34811020 * x2 + 2.18555832 * x - 0.20219683
        } else if t <= 4000 {
            y = -0.9549476 * x3 - 1.37418593 * x2 + 2.09137015 * x - 0.16748867
        } else {
            y = 3.0817580 * x3 - 5.87338670 * x2 + 3.75112997 * x - 0.37001483
        }

        return fromChromaticity(x: x, y: y)
    }

    // MARK: - Helpers

    /// Pushes a colour away from grey by `amount` (0 = unchanged).
    static func saturate(_ color: RGBColor, by amount: Double) -> RGBColor {
        guard amount > 0 else { return color }
        let clamped = min(1, amount)
        let luma = color.relativeLuminance * 255.0
        func adjust(_ channel: UInt8) -> UInt8 {
            let value = Double(channel)
            return RGBColor.quantise((value + (value - luma) * clamped) / 255.0)
        }
        return RGBColor(
            red: adjust(color.red),
            green: adjust(color.green),
            blue: adjust(color.blue),
            alpha: color.alpha
        )
    }

    static func gammaEncode(_ value: Double) -> Double {
        let v = max(0, min(1, value))
        return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1.0 / 2.4) - 0.055
    }
}
