import Foundation

/// An 8-bit-per-channel colour with an alpha channel used as *layer opacity*.
///
/// Alpha matters: the iCUE SDK treats alpha as the opacity of this client's
/// shared lighting layer. `alpha == 0` means "completely translucent", which is
/// how this project releases the mouse back to ordinary iCUE lighting without
/// ever requesting exclusive control.
public struct RGBColor: Equatable, Hashable, Codable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Builds a colour from unit-interval components, clamping out-of-range input.
    public init(unitRed: Double, unitGreen: Double, unitBlue: Double, unitAlpha: Double = 1.0) {
        self.red = RGBColor.quantise(unitRed)
        self.green = RGBColor.quantise(unitGreen)
        self.blue = RGBColor.quantise(unitBlue)
        self.alpha = RGBColor.quantise(unitAlpha)
    }

    /// Parses `#RRGGBB`, `RRGGBB`, `#RGB` or `#RRGGBBAA`.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard !text.isEmpty, text.allSatisfy({ $0.isHexDigit }) else { return nil }

        // Expand the shorthand form so the rest of the parser sees pairs.
        if text.count == 3 {
            text = text.map { String(repeating: $0, count: 2) }.joined()
        }
        guard text.count == 6 || text.count == 8 else { return nil }

        let bytes = stride(from: 0, to: text.count, by: 2).compactMap { offset -> UInt8? in
            let start = text.index(text.startIndex, offsetBy: offset)
            let end = text.index(start, offsetBy: 2)
            return UInt8(text[start..<end], radix: 16)
        }
        guard bytes.count == text.count / 2 else { return nil }

        self.init(red: bytes[0], green: bytes[1], blue: bytes[2], alpha: bytes.count == 4 ? bytes[3] : 255)
    }

    public var hexString: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    public static let black = RGBColor(red: 0, green: 0, blue: 0)
    public static let white = RGBColor(red: 255, green: 255, blue: 255)

    /// A fully translucent colour: our lighting layer contributes nothing and
    /// whatever iCUE is doing shows through unchanged.
    public static let transparent = RGBColor(red: 0, green: 0, blue: 0, alpha: 0)

    /// Multiplies the RGB channels by `factor` (alpha untouched).
    public func scaledBrightness(_ factor: Double) -> RGBColor {
        let clamped = max(0, min(1, factor))
        return RGBColor(
            red: RGBColor.quantise(Double(red) / 255.0 * clamped),
            green: RGBColor.quantise(Double(green) / 255.0 * clamped),
            blue: RGBColor.quantise(Double(blue) / 255.0 * clamped),
            alpha: alpha
        )
    }

    public func withAlpha(_ newAlpha: UInt8) -> RGBColor {
        RGBColor(red: red, green: green, blue: blue, alpha: newAlpha)
    }

    /// Linear interpolation in 8-bit space. `t == 0` returns `self`.
    public func blended(with other: RGBColor, amount t: Double) -> RGBColor {
        let clamped = max(0, min(1, t))
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            RGBColor.quantise((Double(a) * (1 - clamped) + Double(b) * clamped) / 255.0)
        }
        return RGBColor(
            red: mix(red, other.red),
            green: mix(green, other.green),
            blue: mix(blue, other.blue),
            alpha: mix(alpha, other.alpha)
        )
    }

    /// Rec. 709 relative luminance in the unit interval.
    public var relativeLuminance: Double {
        (0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)) / 255.0
    }

    static func quantise(_ value: Double) -> UInt8 {
        guard value.isFinite else { return 0 }
        let scaled = (value * 255.0).rounded()
        return UInt8(max(0, min(255, scaled)))
    }
}

extension RGBColor: CustomStringConvertible {
    public var description: String {
        alpha == 255 ? hexString : "\(hexString)@\(alpha)"
    }
}
