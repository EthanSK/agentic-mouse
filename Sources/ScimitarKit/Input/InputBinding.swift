import Foundation

/// A physical signal that the companion can recognise.
///
/// `.icueMacroKey` is the production route
/// ---------------------------------------
/// The connected Scimitar reports `CDPI_MacroKeyArray` = `CMKI_1 … CMKI_12`, so
/// each of the twelve side buttons arrives as a raw `CorsairKeyEvent` tagged
/// with the originating device id. That is what the companion uses: it is
/// device-attributed, independent of the iCUE assignment, and suppressible via
/// `CorsairConfigureKeyEvent`.
///
/// The other two cases exist only for the documented event-tap fallback, where
/// the buttons have been given ordinary mouse-button or keystroke assignments:
///
///   - assigned to "Mouse Button N"  → `.mouseButton(N - 1)`
///   - assigned to a keystroke       → `.keyCode(...)`
///
/// Neither fallback form can tell one physical mouse from another. See
/// `docs/ICUE-FALLBACK.md`.
public enum InputBinding: Hashable, Codable, Sendable {
    /// CoreGraphics `mouseButtonNumber`. 0 = left, 1 = right, 2 = middle,
    /// 3 = "button 4"/back, 4 = "button 5"/forward, and so on up to 31.
    case mouseButton(Int)
    /// A virtual key code plus the exact modifier set that must accompany it.
    case keyCode(UInt16, modifiers: ModifierSet)
    /// A Corsair macro key id (CMKI_1 … CMKI_20) delivered over the iCUE SDK.
    case icueMacroKey(Int)

    public var isMouseButton: Bool { if case .mouseButton = self { return true }; return false }
    public var isKeyCode: Bool { if case .keyCode = self { return true }; return false }
    public var isMacroKey: Bool { if case .icueMacroKey = self { return true }; return false }

    /// Whether the fallback event tap can ever decode this binding with its
    /// installed event mask. Left/right buttons use distinct CGEvent types and
    /// raw iCUE macro keys do not exist in CoreGraphics, so both fail closed.
    public var isCGEventTapObservable: Bool {
        switch self {
        case .mouseButton(let number): return (2...31).contains(number)
        case .keyCode(let code, _): return code <= 127
        case .icueMacroKey: return false
        }
    }

    /// Short human description. Contains nothing identifying.
    public var displayName: String {
        switch self {
        case .mouseButton(let number):
            return "mouse button \(number + 1)"
        case .keyCode(let code, let modifiers):
            let mods = modifiers.displayName
            return mods.isEmpty ? "key 0x\(String(code, radix: 16))" : "\(mods)key 0x\(String(code, radix: 16))"
        case .icueMacroKey(let id):
            return "iCUE macro key \(id)"
        }
    }
}

/// The modifier flags that must be present for a `.keyCode` binding to match.
/// Modelled explicitly (rather than as `CGEventFlags`) so bindings round-trip
/// through JSON and can be compared in tests without CoreGraphics.
public struct ModifierSet: OptionSet, Hashable, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = ModifierSet(rawValue: 1 << 0)
    public static let option = ModifierSet(rawValue: 1 << 1)
    public static let control = ModifierSet(rawValue: 1 << 2)
    public static let shift = ModifierSet(rawValue: 1 << 3)
    public static let function = ModifierSet(rawValue: 1 << 4)

    public static let none: ModifierSet = []

    public var displayName: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        if contains(.function) { text += "fn" }
        return text
    }

    /// Parses `"cmd+shift"`, `"⌘⇧"`, `""`, `"none"`.
    public static func parse(_ text: String) -> ModifierSet {
        var result: ModifierSet = []
        let lowered = text.lowercased()
        if lowered.contains("cmd") || lowered.contains("command") || text.contains("⌘") { result.insert(.command) }
        if lowered.contains("opt") || lowered.contains("alt") || text.contains("⌥") { result.insert(.option) }
        if lowered.contains("ctrl") || lowered.contains("control") || text.contains("⌃") { result.insert(.control) }
        if lowered.contains("shift") || text.contains("⇧") { result.insert(.shift) }
        if lowered.contains("fn") || lowered.contains("function") { result.insert(.function) }
        return result
    }
}

extension InputBinding {
    private enum CodingKeys: String, CodingKey {
        case kind, button, keyCode, modifiers, macroKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "mouseButton":
            self = .mouseButton(try container.decode(Int.self, forKey: .button))
        case "keyCode":
            let code = try container.decode(UInt16.self, forKey: .keyCode)
            let modifierText = try container.decodeIfPresent(String.self, forKey: .modifiers) ?? ""
            self = .keyCode(code, modifiers: ModifierSet.parse(modifierText))
        case "icueMacroKey":
            self = .icueMacroKey(try container.decode(Int.self, forKey: .macroKey))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown binding kind '\(kind)'. Expected mouseButton, keyCode or icueMacroKey."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mouseButton(let number):
            try container.encode("mouseButton", forKey: .kind)
            try container.encode(number, forKey: .button)
        case .keyCode(let code, let modifiers):
            try container.encode("keyCode", forKey: .kind)
            try container.encode(code, forKey: .keyCode)
            try container.encode(modifiers.displayName, forKey: .modifiers)
        case .icueMacroKey(let id):
            try container.encode("icueMacroKey", forKey: .kind)
            try container.encode(id, forKey: .macroKey)
        }
    }
}

/// A press or release of a recognised binding.
public struct PhysicalInputEvent: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case press, release }

    public let binding: InputBinding
    public let phase: Phase
    /// Monotonic timestamp from the transport's clock.
    public let timestamp: TimeInterval

    public init(binding: InputBinding, phase: Phase, timestamp: TimeInterval) {
        self.binding = binding
        self.phase = phase
        self.timestamp = timestamp
    }
}
