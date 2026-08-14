import Foundation

/// User-facing identity for one packaged Agentic Mouse build.
///
/// The marketing patch and bundle build both advance for every signed local
/// install candidate, so the prominent version never aliases another install.
public enum AgenticMouseVersion {
    public static func displayString(
        marketingVersion: String?,
        buildVersion: String?
    ) -> String {
        let marketing = marketingVersion?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = buildVersion?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let marketing, !marketing.isEmpty, let build, !build.isEmpty {
            return "v\(marketing) (\(build))"
        }
        if let marketing, !marketing.isEmpty {
            return "v\(marketing)"
        }
        if let build, !build.isEmpty {
            return "build \(build)"
        }
        return "development build"
    }

    public static func displayString(bundle: Bundle = .main) -> String {
        displayString(
            marketingVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            buildVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}
