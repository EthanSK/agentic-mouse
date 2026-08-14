import Foundation

/// Everything Agentic Mouse reads from disk.
///
/// The file lives at `~/.config/agentic-mouse/config.json`, **outside**
/// this repository. `Config/config.example.json` ships placeholders only; the
/// loader recognises those placeholders and treats the corresponding feature as
/// unconfigured rather than trying to use them.
public struct AppConfiguration: Codable, Equatable, Sendable {
    public var lighting: LightingConfiguration
    public var multiTap: MultiTapConfigurationFile
    public var colorProof: ColorProofConfiguration
    public var defaultMapHint: DefaultMapHintConfiguration
    public var input: InputConfiguration
    public var hud: HUDConfiguration

    public init(
        lighting: LightingConfiguration = .init(),
        multiTap: MultiTapConfigurationFile = .init(),
        colorProof: ColorProofConfiguration = .init(),
        defaultMapHint: DefaultMapHintConfiguration = .init(),
        input: InputConfiguration = .init(),
        hud: HUDConfiguration = .init()
    ) {
        self.lighting = lighting
        self.multiTap = multiTap
        self.colorProof = colorProof
        self.defaultMapHint = defaultMapHint
        self.input = input
        self.hud = hud
    }

    public static let `default` = AppConfiguration()

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

    // MARK: - Colour proof

    public struct ColorProofConfiguration: Codable, Equatable, Sendable {
        public var enabled: Bool
        /// Leave the mode automatically after this long with no input. 0 = never.
        public var autoExitAfterIdle: TimeInterval
        /// End the mode after this total duration. 0 = no duration limit.
        public var absoluteTimeout: TimeInterval
        public var heartbeatInterval: TimeInterval
        public var leaseDuration: TimeInterval

        public init(
            enabled: Bool = false,
            autoExitAfterIdle: TimeInterval = 0,
            absoluteTimeout: TimeInterval = 0,
            heartbeatInterval: TimeInterval = 2,
            leaseDuration: TimeInterval = 6
        ) {
            self.enabled = enabled
            self.autoExitAfterIdle = autoExitAfterIdle
            self.absoluteTimeout = absoluteTimeout
            self.heartbeatInterval = heartbeatInterval
            self.leaseDuration = leaseDuration
        }
    }

    // MARK: - Default-map reference

    public struct DefaultMapHintConfiguration: Codable, Equatable, Sendable {
        /// Shared physical cell 2 toggles each source's persistent reference.
        public var enabled: Bool
        public var doubleClickInterval: TimeInterval
        /// Optional legacy auto-hide timeout. Zero keeps the map visible until
        /// the same-source toggle closes it.
        public var displayDuration: TimeInterval

        public init(
            enabled: Bool = true,
            doubleClickInterval: TimeInterval = 0.34,
            displayDuration: TimeInterval = 0
        ) {
            self.enabled = enabled
            self.doubleClickInterval = doubleClickInterval
            self.displayDuration = displayDuration
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
        /// Legacy fallback binding for the universal runtime-mode exit.
        public var toggleKey: Int
        /// Fallback-only: how each grid key appears as a CGEvent.
        public var fallbackBindings: [String: InputBinding]

        public init(
            transport: TransportKind = .icueMacroKey,
            gridMacroKeys: [Int] = Array(1...12),
            toggleKey: Int = 10,
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
            corner: Corner = .bottomLeft,
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

        /// Authoritative handed placement for every source-owned mouse HUD.
        ///
        /// The persisted `corner` remains available for legacy generic HUDs,
        /// but a HUD that belongs to an exact mouse must never use one shared
        /// corner: the right-handed Corsair lives at bottom-right and the
        /// left-handed Razer at bottom-left.
        public static func sourceCorner(for source: MouseSource) -> Corner {
            switch source {
            case .corsair: return .bottomRight
            case .razer: return .bottomLeft
            }
        }
    }
}
