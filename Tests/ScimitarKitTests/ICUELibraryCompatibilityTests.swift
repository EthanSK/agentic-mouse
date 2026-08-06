import Foundation
import XCTest
@testable import ScimitarKit

final class ICUELibraryCompatibilityTests: XCTestCase {
    func testOnlyAuditedFrameworkVersionIsAccepted() throws {
        let root = try makeFramework(version: "4.0.84")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let executable = root.appendingPathComponent("Versions/A/iCUESDK").path
        let result = ICUELibraryCompatibility.validateExistingCandidates([executable])
        XCTAssertEqual(result.accepted, [executable])
        XCTAssertTrue(result.rejectedVersions.isEmpty)
        XCTAssertEqual(result.rejectedUnversionedCount, 0)
    }

    func testUnknownFrameworkVersionFailsClosed() throws {
        let root = try makeFramework(version: "99.1.0")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let executable = root.appendingPathComponent("Versions/A/iCUESDK").path
        let result = ICUELibraryCompatibility.validateExistingCandidates([executable])
        XCTAssertTrue(result.accepted.isEmpty)
        XCTAssertEqual(result.rejectedVersions, ["99.1.0"])
    }

    func testRawDylibIsRejectedAsUnversioned() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dylib = directory.appendingPathComponent("libiCUESDK.dylib")
        XCTAssertTrue(FileManager.default.createFile(atPath: dylib.path, contents: Data()))

        let result = ICUELibraryCompatibility.validateExistingCandidates([dylib.path])
        XCTAssertTrue(result.accepted.isEmpty)
        XCTAssertEqual(result.rejectedUnversionedCount, 1)
    }

    private func makeFramework(version: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let framework = directory.appendingPathComponent("iCUESDK.framework", isDirectory: true)
        let versionRoot = framework.appendingPathComponent("Versions/A", isDirectory: true)
        let resources = versionRoot.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(
            atPath: versionRoot.appendingPathComponent("iCUESDK").path,
            contents: Data()
        ))
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.corsair.icuesdk",
            "CFBundleShortVersionString": version
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: resources.appendingPathComponent("Info.plist"))
        return framework
    }
}
