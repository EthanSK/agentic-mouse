import Foundation

public enum ConfigurationLoaderError: Error, Equatable {
    case unreadable(String)
    case malformed(String)
}

/// Loads, validates and reports on the on-disk configuration.
public enum ConfigurationLoader {
    public static var defaultDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/agentic-mouse", isDirectory: true)
    }

    public static var defaultConfigurationURL: URL {
        defaultDirectory.appendingPathComponent("config.json")
    }

    /// Loads from disk, falling back to defaults when the file is absent.
    public static func load(from url: URL? = nil, log: Log) -> (AppConfiguration, [String]) {
        let target = url ?? defaultConfigurationURL
        var warnings: [String] = []

        guard FileManager.default.fileExists(atPath: target.path) else {
            warnings.append(
                "No config file at \(target.path). Running with defaults — "
                + "copy Config/config.example.json there and fill it in."
            )
            return (.default, warnings)
        }

        // A world-readable configuration can expose private device or
        // automation details, so keep this warning.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: target.path),
           let permissions = attributes[.posixPermissions] as? NSNumber,
           permissions.int16Value & 0o077 != 0 {
            warnings.append("\(target.path) is readable by other users; `chmod 600` it.")
        }

        do {
            let data = try Data(contentsOf: target)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(AppConfiguration.self, from: data)
            let sanitized = sanitize(decoded)
            warnings.append(contentsOf: sanitized.warnings)
            warnings.append(contentsOf: semanticWarnings(sanitized.configuration))
            return (sanitized.configuration, warnings)
        } catch let error as DecodingError {
            warnings.append("Config file could not be parsed (\(describe(error))); using defaults.")
            return (.default, warnings)
        } catch {
            warnings.append("Config file could not be read; using defaults.")
            return (.default, warnings)
        }
    }

    /// Non-fatal problems worth surfacing in the menu and the doctor CLI.
    public static func validate(_ configuration: AppConfiguration) -> [String] {
        let sanitized = sanitize(configuration)
        return sanitized.warnings + semanticWarnings(sanitized.configuration)
    }

    /// Replaces dangerous or nonsensical values with the documented defaults.
    /// Every correction is returned as a warning; runtime code therefore never
    /// has to silently invent a different grid, toggle, timer, brightness, or
    /// window geometry than the file describes.
    public static func sanitize(
        _ configuration: AppConfiguration
    ) -> (configuration: AppConfiguration, warnings: [String]) {
        var result = configuration
        var warnings: [String] = []
        let defaults = AppConfiguration.default

        func validUnit(_ value: Double) -> Bool { value.isFinite && (0...1).contains(value) }
        func replace(_ path: String, _ description: String) {
            warnings.append("\(path) \(description); using the documented default.")
        }

        if RGBColor(hex: result.lighting.modeIndicatorColor) == nil {
            replace("lighting.modeIndicatorColor", "must be a six-digit hex colour")
            result.lighting.modeIndicatorColor = defaults.lighting.modeIndicatorColor
        }
        if RGBColor(hex: result.lighting.modeIndicatorSecondaryColor) == nil {
            replace("lighting.modeIndicatorSecondaryColor", "must be a six-digit hex colour")
            result.lighting.modeIndicatorSecondaryColor = defaults.lighting.modeIndicatorSecondaryColor
        }
        if !result.lighting.modeIndicatorPulsePeriod.isFinite
            || result.lighting.modeIndicatorPulsePeriod <= 0 {
            replace("lighting.modeIndicatorPulsePeriod", "must be finite and greater than zero")
            result.lighting.modeIndicatorPulsePeriod = defaults.lighting.modeIndicatorPulsePeriod
        }
        if !validUnit(result.lighting.modeIndicatorPulseDepth) {
            replace("lighting.modeIndicatorPulseDepth", "must be finite and between 0 and 1")
            result.lighting.modeIndicatorPulseDepth = defaults.lighting.modeIndicatorPulseDepth
        }
        if !result.lighting.maximumWritesPerSecond.isFinite
            || result.lighting.maximumWritesPerSecond <= 0 {
            replace("lighting.maximumWritesPerSecond", "must be finite and greater than zero")
            result.lighting.maximumWritesPerSecond = defaults.lighting.maximumWritesPerSecond
        }

        if !result.multiTap.multiTapTimeout.isFinite || result.multiTap.multiTapTimeout <= 0 {
            replace("multiTap.multiTapTimeout", "must be finite and greater than zero")
            result.multiTap.multiTapTimeout = defaults.multiTap.multiTapTimeout
        }
        if !result.multiTap.holdThreshold.isFinite || result.multiTap.holdThreshold <= 0 {
            replace("multiTap.holdThreshold", "must be finite and greater than zero")
            result.multiTap.holdThreshold = defaults.multiTap.holdThreshold
        }
        if !result.multiTap.autoExitAfterIdle.isFinite || result.multiTap.autoExitAfterIdle < 0 {
            replace("multiTap.autoExitAfterIdle", "must be finite and non-negative")
            result.multiTap.autoExitAfterIdle = defaults.multiTap.autoExitAfterIdle
        }
        if !result.multiTap.toggleDebounce.isFinite || result.multiTap.toggleDebounce < 0 {
            replace("multiTap.toggleDebounce", "must be finite and non-negative")
            result.multiTap.toggleDebounce = defaults.multiTap.toggleDebounce
        }

        if !result.colorProof.autoExitAfterIdle.isFinite || result.colorProof.autoExitAfterIdle < 0 {
            replace("colorProof.autoExitAfterIdle", "must be finite and non-negative")
            result.colorProof.autoExitAfterIdle = defaults.colorProof.autoExitAfterIdle
        }
        if !result.colorProof.absoluteTimeout.isFinite || result.colorProof.absoluteTimeout < 0 {
            replace("colorProof.absoluteTimeout", "must be finite and non-negative")
            result.colorProof.absoluteTimeout = defaults.colorProof.absoluteTimeout
        }
        if !result.colorProof.heartbeatInterval.isFinite || result.colorProof.heartbeatInterval <= 0 {
            replace("colorProof.heartbeatInterval", "must be finite and greater than zero")
            result.colorProof.heartbeatInterval = defaults.colorProof.heartbeatInterval
        }
        if !result.colorProof.leaseDuration.isFinite
            || result.colorProof.leaseDuration < result.colorProof.heartbeatInterval * 2
            || result.colorProof.leaseDuration > 10 {
            replace(
                "colorProof.leaseDuration",
                "must be at least twice the heartbeat interval and no more than 10 seconds"
            )
            result.colorProof.leaseDuration = defaults.colorProof.leaseDuration
        }

        if !result.defaultMapHint.doubleClickInterval.isFinite
            || !(0.15...0.8).contains(result.defaultMapHint.doubleClickInterval) {
            replace(
                "defaultMapHint.doubleClickInterval",
                "must be finite and between 0.15 and 0.8 seconds"
            )
            result.defaultMapHint.doubleClickInterval = defaults.defaultMapHint.doubleClickInterval
        }
        if !result.defaultMapHint.displayDuration.isFinite
            || !(0...30).contains(result.defaultMapHint.displayDuration) {
            replace(
                "defaultMapHint.displayDuration",
                "must be finite and between 0 and 30 seconds; 0 keeps it visible until toggled"
            )
            result.defaultMapHint.displayDuration = defaults.defaultMapHint.displayDuration
        }

        if result.input.gridMacroKeys != Array(1...12) {
            warnings.append("input.gridMacroKeys must be exactly [1...12]; using that audited grid.")
            result.input.gridMacroKeys = Array(1...12)
        }
        if result.input.toggleKey != 10 {
            warnings.append(
                "input.toggleKey must be 10, the universal runtime-mode exit; using 10."
            )
            result.input.toggleKey = defaults.input.toggleKey
        }
        if result.input.transport == .cgEventTap, result.input.fallbackLogicalBindings == nil {
            warnings.append(
                "input.fallbackBindings must map each of k1...k12 to a unique CGEvent binding; "
                + "the fallback transport will remain unavailable."
            )
        }

        if !result.hud.margin.isFinite || result.hud.margin < 0 {
            replace("hud.margin", "must be finite and non-negative")
            result.hud.margin = defaults.hud.margin
        }
        if !validUnit(result.hud.opacity) {
            replace("hud.opacity", "must be finite and between 0 and 1")
            result.hud.opacity = defaults.hud.opacity
        }

        return (result, warnings)
    }

    private static func semanticWarnings(_ configuration: AppConfiguration) -> [String] {
        var warnings: [String] = []

        if configuration.input.transport == .cgEventTap {
            warnings.append(
                "Using the cgEventTap fallback transport. It cannot tell the Scimitar from any other mouse; "
                + "prefer icueMacroKey unless iCUE key interception is unavailable."
            )
        }
        if configuration.multiTap.echoPolicy == .livePreview {
            warnings.append(
                "multiTap.echoPolicy is livePreview. It issues real backspaces into the focused document; "
                + "commitOnly is the safe default."
            )
        }
        if configuration.multiTap.enabled && !configuration.lighting.enabled {
            warnings.append(
                "Multi-tap is enabled while mouse lighting is disabled; the HUD still indicates the mode, "
                + "but the Scimitar cannot show the configured mode colour."
            )
        }
        if configuration.lighting.layerPriority <= 128 {
            warnings.append(
                "lighting.layerPriority is \(configuration.lighting.layerPriority); "
                + "iCUE uses 127 and shared clients default to 128, so the mouse may not show these colours."
            )
        }
        return warnings
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): return "missing key '\(key.stringValue)'"
        case .typeMismatch(_, let context): return "type mismatch at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .valueNotFound(_, let context): return "missing value at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        case .dataCorrupted(let context): return context.debugDescription
        @unknown default: return "unknown decoding error"
        }
    }

    /// A human-readable dump. Safe to paste into a bug report.
    public static func describe(_ configuration: AppConfiguration) -> String {
        var lines: [String] = []
        lines.append("Lighting")
        lines.append("  enabled:            \(configuration.lighting.enabled)")
        lines.append("  device filter:      model contains \(configuration.lighting.device.modelContains)")
        lines.append("  layer priority:     \(configuration.lighting.layerPriority) (shared layer)")
        lines.append("  mode colour:        \(configuration.lighting.modeIndicatorColor)")

        lines.append("Multi-tap")
        lines.append("  enabled:            \(configuration.multiTap.enabled)")
        lines.append("  echo policy:        \(configuration.multiTap.echoPolicy.rawValue)")
        lines.append("  focus policy:       \(configuration.multiTap.focusChangePolicy.rawValue)")
        lines.append("  tap timeout:        \(configuration.multiTap.multiTapTimeout)s")
        lines.append("  hold threshold:     \(configuration.multiTap.holdThreshold)s")
        lines.append("  idle auto-exit:     \(configuration.multiTap.autoExitAfterIdle)s")

        lines.append("Colour proof")
        lines.append("  enabled:            \(configuration.colorProof.enabled)")
        lines.append("  idle auto-exit:     \(configuration.colorProof.autoExitAfterIdle)s")
        lines.append("  absolute limit:     \(configuration.colorProof.absoluteTimeout)s")
        lines.append("  routing heartbeat:  \(configuration.colorProof.heartbeatInterval)s")
        lines.append("  routing lease:      \(configuration.colorProof.leaseDuration)s")

        lines.append("Default button map")
        lines.append("  enabled:            \(configuration.defaultMapHint.enabled)")
        lines.append("  toggle:             physical cell \(PhysicalCell.defaultMapToggle.rawValue)")
        let mapDuration = configuration.defaultMapHint.displayDuration == 0
            ? "until toggled"
            : "\(configuration.defaultMapHint.displayDuration)s"
        lines.append("  display duration:   \(mapDuration)")

        lines.append("Input")
        lines.append("  transport:          \(configuration.input.transport.rawValue)")
        lines.append("  grid macro keys:    \(configuration.input.gridMacroKeys)")
        lines.append("  toggle key:         \(configuration.input.toggleKey)")

        return lines.joined(separator: "\n")
    }
}
