import Foundation
import Security

/// Reads a secret from wherever the config says it lives.
public protocol SecretResolving: AnyObject {
    func resolve(_ source: SecretSource) -> String?
}

/// Keychain-backed resolver. Reads only; it never creates or updates items, so
/// running the companion cannot silently store a credential anywhere.
public final class KeychainSecretResolver: SecretResolving {
    private let environment: [String: String]
    private let log: Log

    public init(environment: [String: String] = ProcessInfo.processInfo.environment, log: Log) {
        self.environment = environment
        self.log = log
    }

    public func resolve(_ source: SecretSource) -> String? {
        switch source {
        case .keychain(let service, let account):
            return readKeychain(service: service, account: account)
        case .environmentVariable(let name):
            return environment[name].flatMap { $0.isEmpty ? nil : $0 }
        case .inlineValue(let value):
            guard !value.isEmpty, !value.hasPrefix("REPLACE_ME") else { return nil }
            log.notice("using an inline secret from the config file; the Keychain is safer")
            return value
        case .none:
            return nil
        }
    }

    private func readKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                log.notice("Keychain lookup failed with status \(status)")
            }
            return nil
        }
        return value.isEmpty ? nil : value
    }
}

/// Test/simulation resolver.
public final class StaticSecretResolver: SecretResolving {
    private let values: [String: String]
    public init(values: [String: String] = [:]) { self.values = values }

    public func resolve(_ source: SecretSource) -> String? {
        switch source {
        case .keychain(let service, let account): return values["\(service)/\(account)"]
        case .environmentVariable(let name): return values[name]
        case .inlineValue(let value): return value.hasPrefix("REPLACE_ME") ? nil : value
        case .none: return nil
        }
    }
}

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

        // A world-readable file holding a bridge key is worth complaining about.
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

        if !validUnit(result.hue.brightnessFloor) {
            replace("hue.brightnessFloor", "must be finite and between 0 and 1")
            result.hue.brightnessFloor = defaults.hue.brightnessFloor
        }
        if !validUnit(result.hue.brightnessCeiling) {
            replace("hue.brightnessCeiling", "must be finite and between 0 and 1")
            result.hue.brightnessCeiling = defaults.hue.brightnessCeiling
        }
        if result.hue.brightnessFloor > result.hue.brightnessCeiling {
            replace("hue brightness range", "must have floor no greater than ceiling")
            result.hue.brightnessFloor = defaults.hue.brightnessFloor
            result.hue.brightnessCeiling = defaults.hue.brightnessCeiling
        }
        if !result.hue.brightnessGamma.isFinite || result.hue.brightnessGamma <= 0 {
            replace("hue.brightnessGamma", "must be finite and greater than zero")
            result.hue.brightnessGamma = defaults.hue.brightnessGamma
        }
        if !validUnit(result.hue.saturationBoost) {
            replace("hue.saturationBoost", "must be finite and between 0 and 1")
            result.hue.saturationBoost = defaults.hue.saturationBoost
        }
        if !result.hue.coalescingInterval.isFinite || result.hue.coalescingInterval < 0 {
            replace("hue.coalescingInterval", "must be finite and non-negative")
            result.hue.coalescingInterval = defaults.hue.coalescingInterval
        }
        for index in result.hue.lights.indices {
            let weight = result.hue.lights[index].weight
            if !weight.isFinite || weight <= 0 {
                replace("hue.lights[\(index)].weight", "must be finite and greater than zero")
                result.hue.lights[index].weight = 1
            }
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

        if result.input.gridMacroKeys != Array(1...12) {
            warnings.append("input.gridMacroKeys must be exactly [1...12]; using that audited grid.")
            result.input.gridMacroKeys = Array(1...12)
        }
        if result.input.toggleKey != 12 {
            warnings.append(
                "input.toggleKey must be 12 with the classic phone keymap (where k12 is Exit); using 12."
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

        if configuration.hue.enabled && !configuration.hue.isConfigured {
            warnings.append("Hue mirroring is enabled but the bridge host or the light list is still a placeholder.")
        }

        let configuredLights = configuration.hue.lights.filter { !$0.isPlaceholder }
        for cluster in HueCluster.allCases where configuration.hue.enabled {
            let members = configuredLights.filter { $0.cluster == cluster }
            if members.isEmpty && !configuredLights.isEmpty {
                warnings.append("No lights assigned to the \(cluster.displayName) cluster; \(cluster.zone.displayName) will stay dark.")
            }
        }

        if case .inlineValue = configuration.hue.applicationKeySource {
            warnings.append("The Hue application key is stored inline in the config file. Move it to the Keychain.")
        }

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

    /// A redacted, human-readable dump. Safe to paste into a bug report.
    public static func describe(_ configuration: AppConfiguration, resolver: SecretResolving) -> String {
        var lines: [String] = []
        lines.append("Hue")
        lines.append("  enabled:            \(configuration.hue.enabled)")
        lines.append("  bridge:             \(Redaction.host(configuration.hue.bridgeHost))")
        lines.append("  application key:    \(configuration.hue.applicationKeySource.redactedDescription) "
                     + "-> \(Redaction.secret(resolver.resolve(configuration.hue.applicationKeySource)))")
        lines.append("  off policy:         \(configuration.hue.offPolicy.rawValue)")
        for cluster in HueCluster.allCases {
            let members = configuration.hue.lights.filter { $0.cluster == cluster }
            let described = members.map { member in
                "\(member.label)[\(member.isPlaceholder ? "placeholder" : Redaction.tag(member.resourceIdentifier))]"
            }
            lines.append("  \(cluster.displayName) -> \(cluster.zone.displayName) (0x\(String(cluster.zone.luid, radix: 16))): "
                         + (described.isEmpty ? "none" : described.joined(separator: ", ")))
        }

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

        lines.append("Input")
        lines.append("  transport:          \(configuration.input.transport.rawValue)")
        lines.append("  grid macro keys:    \(configuration.input.gridMacroKeys)")
        lines.append("  toggle key:         \(configuration.input.toggleKey)")

        return lines.joined(separator: "\n")
    }
}
