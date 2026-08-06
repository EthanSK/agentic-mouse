import Foundation

/// How to pick *the one* mouse this companion is allowed to paint.
///
/// The project rule is emphatic: never apply SDK lighting to all Corsair
/// devices. So selection is explicit, deterministic and fails closed — if the
/// criteria match nothing, or match ambiguously in a way the policy forbids,
/// no device is chosen and nothing is written.
public struct DeviceMatcher: Equatable, Codable, Sendable {
    /// Case-insensitive substrings that must all appear in the model name.
    public var modelContains: [String]
    /// Optional exact match on the redacted device tag (`Redaction.tag`), so a
    /// specific unit can be pinned without ever writing its real id to disk.
    public var deviceTag: String?
    /// Refuse to guess when several devices match.
    public var requiresUniqueMatch: Bool

    public init(
        modelContains: [String] = ["scimitar"],
        deviceTag: String? = nil,
        requiresUniqueMatch: Bool = true
    ) {
        self.modelContains = modelContains
        self.deviceTag = deviceTag
        self.requiresUniqueMatch = requiresUniqueMatch
    }

    public static let scimitar = DeviceMatcher()

    public func matches(_ device: ICUEDevice) -> Bool {
        if let deviceTag, !deviceTag.isEmpty {
            let supplied = deviceTag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let copyReadyTag = supplied.hasPrefix("id:") ? String(supplied.dropFirst(3)) : supplied
            return Redaction.tag(device.identifier) == copyReadyTag
        }
        guard !modelContains.isEmpty else { return false }
        let haystack = device.model.lowercased()
        return modelContains.allSatisfy { haystack.contains($0.lowercased()) }
    }
}

public enum DeviceSelectionResult: Equatable {
    case selected(ICUEDevice)
    case noMatch(candidateCount: Int)
    case ambiguous(matchCount: Int)

    public var device: ICUEDevice? {
        if case .selected(let device) = self { return device }
        return nil
    }

    public var explanation: String {
        switch self {
        case .selected(let device):
            return "Selected \(device.safeModel) (\(device.ledCount) LEDs, \(device.redactedIdentifier))."
        case .noMatch(let count):
            return count == 0
                ? "iCUE reported no mice at all. Is the Scimitar connected and awake?"
                : "None of the \(count) mice iCUE reported matched the configured model filter."
        case .ambiguous(let count):
            return "\(count) mice matched the filter. Refusing to guess — pin one with `lighting.device.deviceTag`."
        }
    }
}

public enum DeviceSelector {
    /// Applies an authoritative disconnect exclusion before matching. Keeping
    /// this at the pure selection seam prevents a later stack rebuild from
    /// accidentally reintroducing an identifier that iCUE just reported gone
    /// while device enumeration is still stale.
    public static func select(
        from devices: [ICUEDevice],
        excluding excludedIdentifiers: Set<String>,
        using matcher: DeviceMatcher
    ) -> DeviceSelectionResult {
        select(
            from: devices.filter { !excludedIdentifiers.contains($0.identifier) },
            using: matcher
        )
    }

    /// Pure and total: same inputs always give the same answer.
    public static func select(from devices: [ICUEDevice], using matcher: DeviceMatcher) -> DeviceSelectionResult {
        let matches = devices.filter(matcher.matches)
        switch matches.count {
        case 0:
            return .noMatch(candidateCount: devices.count)
        case 1:
            return .selected(matches[0])
        default:
            if matcher.requiresUniqueMatch {
                return .ambiguous(matchCount: matches.count)
            }
            // Deterministic tie-break: most LEDs first, then by tag, so the
            // choice never depends on enumeration order.
            let sorted = matches.sorted { lhs, rhs in
                if lhs.ledCount != rhs.ledCount { return lhs.ledCount > rhs.ledCount }
                return Redaction.tag(lhs.identifier) < Redaction.tag(rhs.identifier)
            }
            return .selected(sorted[0])
        }
    }
}
