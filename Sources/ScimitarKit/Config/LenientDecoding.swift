import Foundation

/// Every configuration struct decodes leniently: a missing key falls back to
/// the documented default rather than failing the whole file.
///
/// This matters because the alternative is brittle in exactly the wrong way. A
/// user who writes a three-line config to change one timeout should get that
/// change, not a silent reversion to defaults because they omitted
/// `saturationBoost`. It also means a future version can add a setting without
/// invalidating every existing config file.
private extension KeyedDecodingContainer {
    /// Decodes `key`, falling back to `fallback` when it is absent, null, or
    /// present but malformed. A single bad value never invalidates the file.
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decode(T.self, forKey: key)) ?? fallback
    }
}

extension AppConfiguration {
    private enum Keys: String, CodingKey {
        case lighting, multiTap, colorProof, defaultMapHint, input, hud
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        self.init(
            lighting: container.value(.lighting, default: LightingConfiguration()),
            multiTap: container.value(.multiTap, default: MultiTapConfigurationFile()),
            colorProof: container.value(.colorProof, default: ColorProofConfiguration()),
            defaultMapHint: container.value(.defaultMapHint, default: DefaultMapHintConfiguration()),
            input: container.value(.input, default: InputConfiguration()),
            hud: container.value(.hud, default: HUDConfiguration())
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(lighting, forKey: .lighting)
        try container.encode(multiTap, forKey: .multiTap)
        try container.encode(colorProof, forKey: .colorProof)
        try container.encode(defaultMapHint, forKey: .defaultMapHint)
        try container.encode(input, forKey: .input)
        try container.encode(hud, forKey: .hud)
    }
}

extension AppConfiguration.DefaultMapHintConfiguration {
    private enum Keys: String, CodingKey {
        case enabled, doubleClickInterval, displayDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let defaults = AppConfiguration.DefaultMapHintConfiguration()
        self.init(
            enabled: container.value(.enabled, default: defaults.enabled),
            doubleClickInterval: container.value(
                .doubleClickInterval,
                default: defaults.doubleClickInterval
            ),
            displayDuration: container.value(.displayDuration, default: defaults.displayDuration)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(doubleClickInterval, forKey: .doubleClickInterval)
        try container.encode(displayDuration, forKey: .displayDuration)
    }
}

extension AppConfiguration.ColorProofConfiguration {
    private enum Keys: String, CodingKey {
        case enabled, autoExitAfterIdle, absoluteTimeout, heartbeatInterval, leaseDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let defaults = AppConfiguration.ColorProofConfiguration()
        self.init(
            enabled: container.value(.enabled, default: defaults.enabled),
            autoExitAfterIdle: container.value(.autoExitAfterIdle, default: defaults.autoExitAfterIdle),
            absoluteTimeout: container.value(.absoluteTimeout, default: defaults.absoluteTimeout),
            heartbeatInterval: container.value(.heartbeatInterval, default: defaults.heartbeatInterval),
            leaseDuration: container.value(.leaseDuration, default: defaults.leaseDuration)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(autoExitAfterIdle, forKey: .autoExitAfterIdle)
        try container.encode(absoluteTimeout, forKey: .absoluteTimeout)
        try container.encode(heartbeatInterval, forKey: .heartbeatInterval)
        try container.encode(leaseDuration, forKey: .leaseDuration)
    }
}

extension AppConfiguration.LightingConfiguration {
    private enum Keys: String, CodingKey {
        case enabled, device, layerPriority, sdkSearchPaths
        case modeIndicatorColor, modeIndicatorSecondaryColor
        case modeIndicatorPulseEnabled, modeIndicatorPulsePeriod, modeIndicatorPulseDepth
        case maximumWritesPerSecond
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let defaults = AppConfiguration.LightingConfiguration()
        self.init(
            enabled: container.value(.enabled, default: defaults.enabled),
            device: container.value(.device, default: defaults.device),
            layerPriority: container.value(.layerPriority, default: defaults.layerPriority),
            sdkSearchPaths: container.value(.sdkSearchPaths, default: defaults.sdkSearchPaths),
            modeIndicatorColor: container.value(.modeIndicatorColor, default: defaults.modeIndicatorColor),
            modeIndicatorSecondaryColor: container.value(
                .modeIndicatorSecondaryColor,
                default: defaults.modeIndicatorSecondaryColor
            ),
            modeIndicatorPulseEnabled: container.value(
                .modeIndicatorPulseEnabled,
                default: defaults.modeIndicatorPulseEnabled
            ),
            modeIndicatorPulsePeriod: container.value(
                .modeIndicatorPulsePeriod,
                default: defaults.modeIndicatorPulsePeriod
            ),
            modeIndicatorPulseDepth: container.value(
                .modeIndicatorPulseDepth,
                default: defaults.modeIndicatorPulseDepth
            ),
            maximumWritesPerSecond: container.value(
                .maximumWritesPerSecond,
                default: defaults.maximumWritesPerSecond
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(device, forKey: .device)
        try container.encode(layerPriority, forKey: .layerPriority)
        try container.encode(sdkSearchPaths, forKey: .sdkSearchPaths)
        try container.encode(modeIndicatorColor, forKey: .modeIndicatorColor)
        try container.encode(modeIndicatorSecondaryColor, forKey: .modeIndicatorSecondaryColor)
        try container.encode(modeIndicatorPulseEnabled, forKey: .modeIndicatorPulseEnabled)
        try container.encode(modeIndicatorPulsePeriod, forKey: .modeIndicatorPulsePeriod)
        try container.encode(modeIndicatorPulseDepth, forKey: .modeIndicatorPulseDepth)
        try container.encode(maximumWritesPerSecond, forKey: .maximumWritesPerSecond)
    }
}

extension AppConfiguration.MultiTapConfigurationFile {
    private enum Keys: String, CodingKey {
        case enabled, multiTapTimeout, holdThreshold, echoPolicy
        case focusChangePolicy, initialShiftState, autoExitAfterIdle, toggleDebounce
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let defaults = AppConfiguration.MultiTapConfigurationFile()
        self.init(
            enabled: container.value(.enabled, default: defaults.enabled),
            multiTapTimeout: container.value(.multiTapTimeout, default: defaults.multiTapTimeout),
            holdThreshold: container.value(.holdThreshold, default: defaults.holdThreshold),
            echoPolicy: container.value(.echoPolicy, default: defaults.echoPolicy),
            focusChangePolicy: container.value(.focusChangePolicy, default: defaults.focusChangePolicy),
            initialShiftState: container.value(.initialShiftState, default: defaults.initialShiftState),
            autoExitAfterIdle: container.value(.autoExitAfterIdle, default: defaults.autoExitAfterIdle),
            toggleDebounce: container.value(.toggleDebounce, default: defaults.toggleDebounce)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(multiTapTimeout, forKey: .multiTapTimeout)
        try container.encode(holdThreshold, forKey: .holdThreshold)
        try container.encode(echoPolicy, forKey: .echoPolicy)
        try container.encode(focusChangePolicy, forKey: .focusChangePolicy)
        try container.encode(initialShiftState, forKey: .initialShiftState)
        try container.encode(autoExitAfterIdle, forKey: .autoExitAfterIdle)
        try container.encode(toggleDebounce, forKey: .toggleDebounce)
    }
}

extension AppConfiguration.InputConfiguration {
    private enum Keys: String, CodingKey { case transport, gridMacroKeys, toggleKey, fallbackBindings }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let defaults = AppConfiguration.InputConfiguration()
        self.init(
            transport: container.value(.transport, default: defaults.transport),
            gridMacroKeys: container.value(.gridMacroKeys, default: defaults.gridMacroKeys),
            toggleKey: container.value(.toggleKey, default: defaults.toggleKey),
            fallbackBindings: container.value(.fallbackBindings, default: defaults.fallbackBindings)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(transport, forKey: .transport)
        try container.encode(gridMacroKeys, forKey: .gridMacroKeys)
        try container.encode(toggleKey, forKey: .toggleKey)
        try container.encode(fallbackBindings, forKey: .fallbackBindings)
    }
}

extension AppConfiguration.HUDConfiguration {
    private enum Keys: String, CodingKey {
        case corner, margin, opacity, followsPointerScreen, showsTapProgressRing
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let defaults = AppConfiguration.HUDConfiguration()
        self.init(
            corner: container.value(.corner, default: defaults.corner),
            margin: container.value(.margin, default: defaults.margin),
            opacity: container.value(.opacity, default: defaults.opacity),
            followsPointerScreen: container.value(
                .followsPointerScreen,
                default: defaults.followsPointerScreen
            ),
            showsTapProgressRing: container.value(
                .showsTapProgressRing,
                default: defaults.showsTapProgressRing
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(corner, forKey: .corner)
        try container.encode(margin, forKey: .margin)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(followsPointerScreen, forKey: .followsPointerScreen)
        try container.encode(showsTapProgressRing, forKey: .showsTapProgressRing)
    }
}

extension DeviceMatcher {
    private enum Keys: String, CodingKey { case modelContains, deviceTag, requiresUniqueMatch }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let defaults = DeviceMatcher()
        self.init(
            modelContains: container.value(.modelContains, default: defaults.modelContains),
            deviceTag: (try? container.decodeIfPresent(String.self, forKey: .deviceTag)) ?? nil,
            requiresUniqueMatch: container.value(
                .requiresUniqueMatch,
                default: defaults.requiresUniqueMatch
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(modelContains, forKey: .modelContains)
        try container.encodeIfPresent(deviceTag, forKey: .deviceTag)
        try container.encode(requiresUniqueMatch, forKey: .requiresUniqueMatch)
    }
}
