import CryptoKit
import Foundation

/// Everything that could identify Ethan's hardware or his network goes through
/// here before it is logged, printed by the doctor CLI, or written anywhere.
///
/// The project rule is blunt: no bridge addresses, device IDs, serials, tokens
/// or application keys may leave the process in readable form. `Redaction`
/// produces a short, stable, non-reversible tag instead so that logs are still
/// useful for correlation ("is this the same mouse as before?") without
/// disclosing the value.
public enum Redaction {
    /// A stable 8-hex-character tag derived from the value.
    public static func tag(_ value: String) -> String {
        guard !value.isEmpty else { return "<empty>" }
        let digest = SHA256.hash(data: Data(value.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(8))
    }

    /// `"CORSAIR SCIMITAR…" -> "id:3f2a9c11"`. Safe for logs.
    public static func identifier(_ value: String) -> String {
        "id:\(tag(value))"
    }

    /// Hostnames and IP addresses become `host:xxxxxxxx`.
    public static func host(_ value: String) -> String {
        "host:\(tag(value))"
    }

    /// Secrets never reveal even their length beyond a coarse bucket.
    public static func secret(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "<unset>" }
        return "<set:\(tag(value))>"
    }

    /// Model names are marketing strings and are safe to log verbatim, but we
    /// still normalise them so a device's *serial* can never sneak in via the
    /// model field on a misbehaving device.
    public static func model(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let filtered = value.unicodeScalars.filter { allowed.contains($0) }
        let cleaned = String(String.UnicodeScalarView(filtered)).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "<unknown model>" : String(cleaned.prefix(48))
    }
}
