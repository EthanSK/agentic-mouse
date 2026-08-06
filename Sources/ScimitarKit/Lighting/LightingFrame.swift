import Foundation

/// The two controllable LEDs on the audited `SCIMITAR ELITE WIRELESS SE`.
///
/// The live read-only audit found exactly two SDK-controllable LEDs, whose
/// LUIDs follow the documented `(group << 16) | index` encoding with
/// `CLG_Mouse == 4`:
///
///   `0x40001` — `MouseLogoLed`, the palm/logo zone
///   `0x40002` — `MouseSideLed`, the thumb-pad zone beside the twelve buttons
///
/// These are hard-coded because they are a property of the device, but every
/// write still goes through `resolve(availableLuids:)`, which emits only the
/// two audited LUIDs when the device actually reports them. A firmware change
/// that renumbers or adds zones fails closed: unknown LEDs remain owned by
/// iCUE instead of inheriting an unrelated colour.
public enum MouseZone: UInt32, CaseIterable, Codable, Sendable {
    case logo = 0x40001
    case side = 0x40002

    public var luid: UInt32 { rawValue }

    public var displayName: String {
        switch self {
        case .logo: return "MouseLogoLed"
        case .side: return "MouseSideLed"
        }
    }

    /// Where each Hue cluster lands.
    ///
    /// The thumb pad sits under the twelve buttons, so it carries the cosy
    /// candle/sofa cluster; the logo faces up from the desk, so it carries the
    /// two lusters above the desk.
    public var hueCluster: HueCluster {
        switch self {
        case .side: return .candleAndSofa
        case .logo: return .deskLusters
        }
    }
}

/// The two independent groups the four Living room lights are aggregated into.
public enum HueCluster: String, CaseIterable, Codable, Sendable {
    /// Candle + sofa lamp → `MouseSideLed`.
    case candleAndSofa
    /// The two lusters above the desk → `MouseLogoLed`.
    case deskLusters

    public var zone: MouseZone {
        switch self {
        case .candleAndSofa: return .side
        case .deskLusters: return .logo
        }
    }

    public var displayName: String {
        switch self {
        case .candleAndSofa: return "Candle + sofa"
        case .deskLusters: return "Desk lusters"
        }
    }
}

/// A complete description of what the mouse should look like right now: one
/// colour per zone.
public struct LightingFrame: Equatable, Sendable {
    public var colors: [MouseZone: RGBColor]

    public init(colors: [MouseZone: RGBColor]) {
        self.colors = colors
    }

    /// Same colour on every zone.
    public init(uniform color: RGBColor) {
        self.colors = Dictionary(uniqueKeysWithValues: MouseZone.allCases.map { ($0, color) })
    }

    public init(logo: RGBColor, side: RGBColor) {
        self.colors = [.logo: logo, .side: side]
    }

    public subscript(zone: MouseZone) -> RGBColor? {
        get { colors[zone] }
        set { colors[zone] = newValue }
    }

    /// A frame that contributes nothing: every zone becomes fully translucent
    /// and ordinary iCUE lighting shows through untouched.
    public static let released = LightingFrame(uniform: .transparent)

    /// Both zones dark. Used when the room's lights are genuinely all off.
    public static let blackout = LightingFrame(uniform: .black)

    public var isReleased: Bool {
        MouseZone.allCases.allSatisfy { (colors[$0] ?? .transparent).alpha == 0 }
    }

    /// Expands to the concrete `(luid, colour)` payload for the LEDs this
    /// device actually reports.
    ///
    /// Unknown LUIDs (a future device with more zones) and zones the device
    /// does not have are omitted. A known zone missing from a partial frame is
    /// explicitly transparent so it cannot inherit the other zone's colour.
    public func resolve(availableLuids: [UInt32]) -> [(luid: UInt32, color: RGBColor)] {
        availableLuids.compactMap { luid in
            guard let zone = MouseZone(rawValue: luid) else { return nil }
            return (luid: luid, color: colors[zone] ?? .transparent)
        }
    }
}

/// The named contributors to the mouse's colour, in a fixed precedence order.
///
/// The ordering is total, so "what colour should the mouse be?" always has
/// exactly one answer:
///
///   1. `alert`         — a problem the user must notice.
///   2. `modeIndicator` — multi-tap mode is active.
///   3. `hueMirror`     — ordinary living-room mirroring.
///   4. nothing         — the layer is released and iCUE takes the mouse back.
///
/// Disconnects are not a separate level. A Hue bridge that goes away simply
/// stops publishing a `hueMirror` frame, so the mouse falls through to the
/// released state — the same safe outcome as the feature being switched off.
public enum LightingSource: String, CaseIterable, Sendable {
    case hueMirror
    case modeIndicator
    case alert

    public var priority: Int {
        switch self {
        case .hueMirror: return 10
        case .modeIndicator: return 50
        case .alert: return 90
        }
    }
}

/// Resolves competing lighting sources into a single frame. Pure and
/// synchronous; no timing at all.
public struct LightingArbiter: Equatable, Sendable {
    private var frames: [LightingSource: LightingFrame] = [:]

    public init() {}

    public mutating func set(_ source: LightingSource, frame: LightingFrame?) {
        if let frame { frames[source] = frame } else { frames.removeValue(forKey: source) }
    }

    public mutating func clear(_ source: LightingSource) { frames.removeValue(forKey: source) }
    public mutating func clearAll() { frames.removeAll() }

    public func frame(for source: LightingSource) -> LightingFrame? { frames[source] }

    public var activeSources: [LightingSource] {
        frames.keys.sorted { $0.priority > $1.priority }
    }

    public var winningSource: LightingSource? {
        frames.keys.max { $0.priority < $1.priority }
    }

    /// The frame to send. `nil` means "release the layer".
    public var resolved: LightingFrame? {
        guard let winner = winningSource else { return nil }
        return frames[winner]
    }
}

/// Slow brightness modulation that makes multi-tap mode unmistakable.
public struct PulseStyle: Equatable, Sendable {
    /// Seconds for one complete bright → dim → bright cycle.
    public var period: TimeInterval
    /// How far the brightness dips. 0 = no pulse, 1 = all the way to black.
    public var depth: Double

    public init(period: TimeInterval = 1.6, depth: Double = 0.35) {
        self.period = period
        self.depth = depth
    }

    /// Brightness multiplier at a given moment. Deterministic in `now`, so it
    /// is exactly testable.
    public func factor(at now: TimeInterval) -> Double {
        guard period > 0, depth > 0 else { return 1 }
        let phase = now.truncatingRemainder(dividingBy: period) / period
        let wave = (cos(2 * Double.pi * phase) + 1) / 2
        let clampedDepth = max(0, min(1, depth))
        return (1 - clampedDepth) + clampedDepth * wave
    }
}

/// How multi-tap mode paints the mouse.
///
/// While the mode is active it overrides **both** zones with a fixed, obviously
/// artificial colour — the point is that a glance at the mouse tells you the
/// side buttons are not doing their normal jobs. Hue keeps streaming underneath
/// and the newest frame is restored the instant the mode exits.
public struct ModeIndicatorStyle: Equatable, Sendable {
    /// The unmistakable "you are in multi-tap mode" colour.
    public var color: RGBColor
    /// Optional slow pulse layered on top of `color`.
    public var pulse: PulseStyle?
    /// Slight offset between the two zones, so the mouse reads as deliberately
    /// "in a mode" rather than as a lamp that happens to be magenta.
    public var secondaryColor: RGBColor?

    public init(
        color: RGBColor = RGBColor(red: 0xFF, green: 0x00, blue: 0xA8),
        pulse: PulseStyle? = PulseStyle(),
        secondaryColor: RGBColor? = RGBColor(red: 0x30, green: 0x00, blue: 0xFF)
    ) {
        self.color = color
        self.pulse = pulse
        self.secondaryColor = secondaryColor
    }

    public func frame(at now: TimeInterval) -> LightingFrame {
        let factor = pulse?.factor(at: now) ?? 1
        let primary = color.scaledBrightness(factor)
        // The zones pulse in antiphase so the mouse visibly "breathes" between
        // them even in bright daylight.
        let counterFactor = pulse.map { 1 + (1 - $0.depth) - $0.factor(at: now) } ?? 1
        let secondary = (secondaryColor ?? color).scaledBrightness(max(0.25, min(1, counterFactor)))
        return LightingFrame(logo: secondary, side: primary)
    }
}
