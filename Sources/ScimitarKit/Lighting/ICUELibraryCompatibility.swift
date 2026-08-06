import Foundation

/// Fail-closed gate in front of the dynamically loaded vendor ABI.
///
/// The C shim intentionally builds without Corsair's proprietary headers, so
/// its local static assertions cannot detect a future vendor layout change.
/// Only framework releases whose headers were audited against the shim are
/// allowed to reach `dlopen`. Raw dylibs have no trustworthy version metadata
/// and are rejected.
enum ICUELibraryCompatibility {
    static let supportedFrameworkVersions: Set<String> = ["4.0.84"]

    struct Result: Equatable {
        var accepted: [String] = []
        var rejectedVersions: Set<String> = []
        var rejectedUnversionedCount = 0
    }

    static func validateExistingCandidates(_ paths: [String]) -> Result {
        var result = Result()
        for path in paths where FileManager.default.fileExists(atPath: path) {
            guard let version = frameworkVersion(forExecutablePath: path) else {
                result.rejectedUnversionedCount += 1
                continue
            }
            guard supportedFrameworkVersions.contains(version) else {
                result.rejectedVersions.insert(version)
                continue
            }
            result.accepted.append(path)
        }
        return result
    }

    static func frameworkVersion(forExecutablePath path: String) -> String? {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard let frameworkIndex = components.lastIndex(where: { $0.hasSuffix(".framework") }) else {
            return nil
        }
        let root = NSString.path(withComponents: Array(components.prefix(through: frameworkIndex)))
        let candidates = [
            "\(root)/Versions/A/Resources/Info.plist",
            "\(root)/Resources/Info.plist"
        ]
        for plistPath in candidates {
            guard let data = FileManager.default.contents(atPath: plistPath),
                  let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dictionary = object as? [String: Any],
                  dictionary["CFBundleIdentifier"] as? String == "com.corsair.icuesdk",
                  let version = dictionary["CFBundleShortVersionString"] as? String,
                  !version.isEmpty
            else { continue }
            return version
        }
        return nil
    }

    static var failureExplanation: String {
        let versions = supportedFrameworkVersions.sorted().joined(separator: ", ")
        return "no audited iCUE SDK framework found (supported: \(versions)); unknown versions and raw dylibs are refused before loading"
    }
}
