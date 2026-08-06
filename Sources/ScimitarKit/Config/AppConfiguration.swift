import Foundation

/// Everything Agentic Mouse reads from disk.
///
/// The file lives at `~/.config/agentic-mouse/config.json`, **outside**
/// this repository. `Config/config.example.json` ships placeholders only; the
/// loader recognises those placeholders and treats the corresponding feature as
/// unconfigured rather than trying to use them.
public struct AppConfiguration: Codable, Equatable, Sendable {
    public var hue: HueConfiguration
    public var lighting: LightingConfiguration
    public var multiTap: MultiTapConfigurationFile
    public var input: InputConfiguration
    public var hud: HUDConfiguration

    public init(
        hue: HueConfiguration = .init(),
        lighting: LightingConfiguration = .init(),
        multiTap: MultiTapConfigurationFile = .init(),
        input: InputConfiguration = .init(),
        hud: HUDConfiguration = .init()
    ) {
        self.hue = hue
        self.lighting = lighting
        self.multiTap = multiTap
        self.input = input
        self.hud = hud
    }

    public static let `default` = AppConfiguration()

    // MARK: - Hue

    public struct HueConfiguration: Codable, Equatable, Sendable {
        public var enabled: Bool
        /// Bridge IP or `.local` name. Never committed.
        public var bridgeHost: String
        /// Where the application key comes from. Prefer the Keychain.
        public var applicationKeySource: SecretSource
        public var lights: [HueLightAssignment]
        public var brightnessFloor: Double
        public var brightnessCeiling: Double
        public var brightnessGamma: Double
        public var saturationBoost: Double
        public var offPolicy: LampOffPolicy
        public var coalescingInterval: TimeInterval

        public init(
            enabled: Bool = true,
            bridgeHost: String = "REPLACE_ME_BRIDGE_HOST",
            applicationKeySource: SecretSource = .keychain(
                service: "com.ethan.agentic-mouse",
                account: "hue-application-key"
            ),
            lights: [HueLightAssignment] = [],
            brightnessFloor: Double = 0.12,
            brightnessCeiling: Double = 1.0,
            brightnessGamma: Double = 0.7,
            saturationBoost: Double = 0.15,
            offPolicy: LampOffPolicy = .blackout,
            coalescingInterval: TimeInterval = 0.08
        ) {
            self.enabled = enabled
            self.bridgeHost = bridgeHost
            self.applicationKeySource = applicationKeySource
            self.lights = lights
            self.brightnessFloor = brightnessFloor
            self.brightnessCeiling = brightnessCeiling
            self.brightnessGamma = brightnessGamma
            self.saturationBoost = saturationBoost
            self.offPolicy = offPolicy
            self.coalescingInterval = coalescingInterval
        }

        public var policy: HueMirrorPolicy {
            HueMirrorPolicy(
                brightnessFloor: brightnessFloor,
                brightnessCeiling: brightnessCeiling,
                brightnessGamma: brightnessGamma,
                offPolicy: offPolicy,
                saturationBoost: saturationBoost
            )
        }

        public var isConfigured: Bool {
            enabled
                && !bridgeHost.isEmpty
                && !bridgeHost.hasPrefix("REPLACE_ME")
                && lights.contains { !$0.isPlaceholder }
        }
    }

    // MARK: - Lighting

    public struct LightingConfiguration: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var device: DeviceMatcher
        /// iCUE itself sits at 127 and other shared clients default to 128.
        public var layerPriority: UInt32
        /// Extra search paths for the proprietary SDK, tried before the
        /// built-in list.
        public var sdkSearchPaths: [String]
        public var modeIndicatorColor: String
        public var modeIndicatorSecondaryColor: String
        public var modeIndicatorPulseEnabled: Bool
        public var modeIndicatorPulsePeriod: TimeInterval
        public var modeIndicatorPulseDepth: Double
        /// Upper bound on iCUE writes per second.
        public var maximumWritesPerSecond: Double

        public init(
            enabled: Bool = true,
            device: DeviceMatcher = .scimitar,
            layerPriority: UInt32 = 130,
            sdkSearchPaths: [String] = [],
            modeIndicatorColor: String = "#FF00A8",
            modeIndicatorSecondaryColor: String = "#3000FF",
            modeIndicatorPulseEnabled: Bool = true,
            modeIndicatorPulsePeriod: TimeInterval = 1.6,
            modeIndicatorPulseDepth: Double = 0.35,
            maximumWritesPerSecond: Double = 30
        ) {
            self.enabled = enabled
            self.device = device
            self.layerPriority = layerPriority
            self.sdkSearchPaths = sdkSearchPaths
            self.modeIndicatorColor = modeIndicatorColor
            self.modeIndicatorSecondaryColor = modeIndicatorSecondaryColor
            self.modeIndicatorPulseEnabled = modeIndicatorPulseEnabled
            self.modeIndicatorPulsePeriod = modeIndicatorPulsePeriod
            self.modeIndicatorPulseDepth = modeIndicatorPulseDepth
            self.maximumWritesPerSecond = maximumWritesPerSecond
        }

        public var modeIndicatorStyle: ModeIndicatorStyle {
            ModeIndicatorStyle(
                color: RGBColor(hex: modeIndicatorColor) ?? RGBColor(red: 0xFF, green: 0x00, blue: 0xA8),
                pulse: modeIndicatorPulseEnabled
                    ? PulseStyle(period: modeIndicatorPulsePeriod, depth: modeIndicatorPulseDepth)
                    : nil,
                secondaryColor: RGBColor(hex: modeIndicatorSecondaryColor)
            )
        }
    }

    // MARK: - Multi-tap

    public struct MultiTapConfigurationFile: Codable, Equatable, Sendable {
        public var enabled: Bool
        public var multiTapTimeout: TimeInterval
        public var holdThreshold: TimeInterval
        public var echoPolicy: EchoPolicy
        public var focusChangePolicy: FocusChangePolicy
        public var initialShiftState: ShiftState
        /// Leave the mode automatically after this long with no input. 0 = never.
        public var autoExitAfterIdle: TimeInterval
        /// Ignore a second toggle press that arrives within this window.
        public var toggleDebounce: TimeInterval

        public init(
            enabled: Bool = true,
            multiTapTimeout: TimeInterval = 0.9,
            holdThreshold: TimeInterval = 0.35,
            echoPolicy: EchoPolicy = .commitOnly,
            focusChangePolicy: FocusChangePolicy = .cancelPending,
            initialShiftState: ShiftState = .initialCaps,
            autoExitAfterIdle: TimeInterval = 180,
            toggleDebounce: TimeInterval = 0.25
        ) {
            self.enabled = enabled
            self.multiTapTimeout = multiTapTimeout
            self.holdThreshold = holdThreshold
            self.echoPolicy = echoPolicy
            self.focusChangePolicy = focusChangePolicy
            self.initialShiftState = initialShiftState
            self.autoExitAfterIdle = autoExitAfterIdle
            self.toggleDebounce = toggleDebounce
        }

        public var engineConfiguration: MultiTapConfiguration {
            MultiTapConfiguration(
                multiTapTimeout: multiTapTimeout,
                holdThreshold: holdThreshold,
                echoPolicy: echoPolicy,
                focusChangePolicy: focusChangePolicy,
                initialShiftState: initialShiftState
            )
        }
    }

    // MARK: - Input

    public struct InputConfiguration: Codable, Equatable, Sendable {
        public enum TransportKind: String, Codable, CaseIterable, Sendable {
            /// Raw `CorsairKeyEvent`s from the exact device. The production route.
            case icueMacroKey
            /// Documented fallback. No device attribution; opt-in only.
            case cgEventTap
        }

        public var transport: TransportKind
        /// Which macro keys form the grid. The audited Scimitar reports 1…12.
        public var gridMacroKeys: [Int]
        /// The button that enters and leaves the mode.
        public var toggleKey: Int
        /// Fallback-only: how each grid key appears as a CGEvent.
        public var fallbackBindings: [String: InputBinding]

        public init(
            transport: TransportKind = .icueMacroKey,
            gridMacroKeys: [Int] = Array(1...12),
            toggleKey: Int = 12,
            fallbackBindings: [String: InputBinding] = [:]
        ) {
            self.transport = transport
            self.gridMacroKeys = gridMacroKeys
            self.toggleKey = toggleKey
            self.fallbackBindings = fallbackBindings
        }

        /// Reverses the user-facing `k1`...`k12` dictionary into the exact
        /// physical binding lookup the event tap needs. The map is usable only
        /// when all twelve names are present exactly once and no two keys share
        /// a signal; otherwise the fallback fails closed.
        public var fallbackLogicalBindings: [InputBinding: MultiTapKey]? {
            guard fallbackBindings.count == MultiTapKey.allCases.count else { return nil }
            var reversed: [InputBinding: MultiTapKey] = [:]
            for key in MultiTapKey.allCases {
                guard let binding = fallbackBindings["k\(key.rawValue)"],
                      binding.isCGEventTapObservable,
                      reversed[binding] == nil
                else {
                    return nil
                }
                reversed[binding] = key
            }
            return reversed
        }
    }

    // MARK: - HUD

    public struct HUDConfiguration: Codable, Equatable, Sendable {
        public enum Corner: String, Codable, CaseIterable, Sendable {
            case topLeft, topRight, bottomLeft, bottomRight, center
        }

        public var corner: Corner
        public var margin: Double
        public var opacity: Double
        /// Follow the screen the pointer is on, rather than the main screen.
        public var followsPointerScreen: Bool
        public var showsTapProgressRing: Bool

        public init(
            corner: Corner = .bottomRight,
            margin: Double = 28,
            opacity: Double = 0.96,
            followsPointerScreen: Bool = true,
            showsTapProgressRing: Bool = true
        ) {
            self.corner = corner
            self.margin = margin
            self.opacity = opacity
            self.followsPointerScreen = followsPointerScreen
            self.showsTapProgressRing = showsTapProgressRing
        }
    }
}

// MARK: - Secret sourcing

/// Where a secret comes from. The value itself never appears in the config
/// file unless the user explicitly chooses `.inlineValue`, which the loader
/// warns about.
public enum SecretSource: Codable, Equatable, Sendable {
    case keychain(service: String, account: String)
    case environmentVariable(String)
    /// Discouraged. Present so a machine without Keychain access still works.
    case inlineValue(String)
    case none

    private enum CodingKeys: String, CodingKey { case kind, service, account, name, value }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "keychain":
            self = .keychain(
                service: try container.decode(String.self, forKey: .service),
                account: try container.decode(String.self, forKey: .account)
            )
        case "environment":
            self = .environmentVariable(try container.decode(String.self, forKey: .name))
        case "inline":
            self = .inlineValue(try container.decode(String.self, forKey: .value))
        default:
            self = .none
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keychain(let service, let account):
            try container.encode("keychain", forKey: .kind)
            try container.encode(service, forKey: .service)
            try container.encode(account, forKey: .account)
        case .environmentVariable(let name):
            try container.encode("environment", forKey: .kind)
            try container.encode(name, forKey: .name)
        case .inlineValue(let value):
            try container.encode("inline", forKey: .kind)
            try container.encode(value, forKey: .value)
        case .none:
            try container.encode("none", forKey: .kind)
        }
    }

    public var redactedDescription: String {
        switch self {
        case .keychain(let service, let account): return "keychain(\(service)/\(account))"
        case .environmentVariable(let name): return "environment(\(name))"
        case .inlineValue(let value): return "inline\(Redaction.secret(value))"
        case .none: return "none"
        }
    }
}
