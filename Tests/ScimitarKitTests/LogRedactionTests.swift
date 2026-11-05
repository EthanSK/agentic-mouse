import XCTest
@testable import ScimitarKit

/// Synthetic credentials exercise the real logging boundary without touching
/// Ethan's login credentials or writing them to a test artifact.
final class CredentialLoggingBoundaryTests: XCTestCase {
    func testRedactsProviderTokensWithoutAmbientEnvironment() {
        for prefix in ["ghp_", "gho_", "github_pat_", "sk-"] {
            let credential = prefix + String(repeating: "a", count: 36)
            let result = LogRedaction.redact("command \(credential) failed", knownSecrets: [])
            XCTAssertFalse(result.contains(credential))
            XCTAssertTrue(result.contains("failed"))
        }
    }

    func testRedactsArbitraryKnownSecretAndAuthorizationForms() {
        let value = "synthetic-opaque-value"
        for text in ["error \(value)", "TOKEN=\(value)", "Bearer \(value)", "https://\(value)@example.test"] {
            XCTAssertFalse(LogRedaction.redact(text, knownSecrets: [value]).contains(value))
        }
    }

    func testDirectSinkAndFacadeNeverStoreToken() {
        let credential = "gho_" + String(repeating: "b", count: 36)
        let sink = RecordingLogSink()
        sink.write(level: .error, category: "test", message: credential)
        Log(category: "test", sink: sink).info("failed: \(credential)")
        XCTAssertEqual(sink.entries.count, 2)
        XCTAssertTrue(sink.entries.allSatisfy { !$0.message.contains(credential) })
    }

    func testKeepsUsefulNonSecretDiagnostics() {
        let text = "Code host 123 exited; Accessibility trusted: true"
        XCTAssertEqual(LogRedaction.redact(text, knownSecrets: []), text)
    }

    func testChildEnvironmentIsAnExplicitAllowList() {
        XCTAssertEqual(Set(ChildProcessEnvironment.minimal.keys),
                       Set(["PATH", "HOME", "USER", "LOGNAME", "TMPDIR", "LC_ALL", "LANG", "TZ"]))
        XCTAssertNil(ChildProcessEnvironment.minimal["GITHUB_PERSONAL_ACCESS_TOKEN"])
        XCTAssertNil(ChildProcessEnvironment.minimal["DYLD_INSERT_LIBRARIES"])
        XCTAssertNil(ChildProcessEnvironment.minimal["NODE_OPTIONS"])
    }
}
