import Foundation

/// Last-line protection for every log destination, including in-memory
/// diagnostics. Never rely on a caller remembering to hide a credential.
public enum LogRedaction {
    private static let ambientSecrets: [String] = ProcessInfo.processInfo.environment
        .filter { key, value in
            value.count >= 8 && key.range(
                of: "TOKEN|SECRET|PASSWORD|CREDENTIAL|API_?KEY|AUTHORIZATION|COOKIE",
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }.map(\.value).sorted { $0.count > $1.count }

    private static let patterns: [NSRegularExpression] = [
        #"\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,})\b"#,
        #"(?i)\bBearer\s+[^\s\"'<>]+"#,
        #"(?i)\b[A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|CREDENTIAL|API_?KEY|AUTHORIZATION|COOKIE)[A-Z0-9_]*\s*[=:]\s*(?:\"[^\"]*\"|'[^']*'|[^\s,;]+)"#,
        #"(?i)https?://[^\s/@]+(?::[^\s/@]*)?@"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    public static func redact(_ message: String) -> String {
        redact(message, knownSecrets: ambientSecrets)
    }

    /// Explicit secret inputs make regression tests independent of real login
    /// credentials. Neither production nor tests print the original values.
    public static func redact(_ message: String, knownSecrets: [String]) -> String {
        var result = message
        for secret in knownSecrets where secret.count >= 8 {
            result = result.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        for pattern in patterns {
            result = pattern.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result),
                withTemplate: "[REDACTED]"
            )
        }
        return result
    }
}
