// Exercise migration using disposable directories only; no test loads or moves
// the owner's real configuration, Keychain data, or app preferences.
import Foundation
import XCTest
@testable import ScimitarKit

final class ConfigurationMigrationTests: XCTestCase {
    private var root: URL!
    private var legacy: URL { ConfigurationFileMigration.legacy(in: root) }
    private var destination: URL { ConfigurationFileMigration.destination(in: root) }
    private let log = Log(category: "config-test", sink: NullLogSink())

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mouse-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func data(lines: Int) -> Data {
        Data("{\n  \"input\": {\"horizontalScrollLinesPerRatchet\": \(lines)}, \"futureSetting\": true\n}\n".utf8)
    }

    private func write(_ bytes: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func resolve() -> URL {
        ConfigurationFileMigration.resolve(legacy: legacy, destination: destination, log: log)
    }

    func testDefaultPathUsesApplicationSupport() {
        XCTAssertEqual(ConfigurationLoader.defaultConfigurationURL.path,
                       NSHomeDirectory() + "/Library/Application Support/Agentic Mouse/config.json")
    }

    func testMigrationPreservesExactBytesSettingsAndPrivatePermissions() throws {
        let original = data(lines: 7)
        try write(original, to: legacy)
        XCTAssertEqual(resolve(), destination)
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directory = try FileManager.default.attributesOfItem(atPath: destination.deletingLastPathComponent().path)
        XCTAssertEqual((directory[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let loaded = ConfigurationLoader.loadResult(from: destination, log: log)
        XCTAssertEqual(loaded.sourceURL, destination)
        XCTAssertEqual(loaded.configuration.input.horizontalScrollLinesPerRatchet, 7)
        XCTAssertTrue(loaded.warnings.isEmpty)
    }

    func testExistingDestinationWinsWithoutTimestampGuessing() throws {
        try write(data(lines: 7), to: legacy)
        let current = data(lines: 9)
        try write(current, to: destination)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)],
                                             ofItemAtPath: destination.path)
        XCTAssertEqual(resolve(), destination)
        XCTAssertEqual(try Data(contentsOf: destination), current)
        XCTAssertEqual(try Data(contentsOf: legacy), data(lines: 7))
    }

    func testLaterLegacyChangesAreNeverMergedBack() throws {
        try write(data(lines: 7), to: legacy)
        XCTAssertEqual(resolve(), destination)
        try write(data(lines: 2), to: legacy)
        let selected = ConfigurationFileMigration.resolve(legacy: legacy, destination: destination, log: log) { _, _ in
            XCTFail("An existing destination must not be republished")
        }
        XCTAssertEqual(selected, destination)
        XCTAssertEqual(try Data(contentsOf: destination), data(lines: 7))
    }

    func testWriteFailureKeepsLoadingTheLegacyFile() throws {
        let original = data(lines: 7)
        try write(original, to: legacy)
        let selected = ConfigurationFileMigration.resolve(legacy: legacy, destination: destination, log: log) { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        }
        XCTAssertEqual(selected, legacy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        XCTAssertEqual(ConfigurationLoader.loadResult(from: selected, log: log)
            .configuration.input.horizontalScrollLinesPerRatchet, 7)
    }

    func testRealFilesystemWriteFailureRetainsRecovery() throws {
        try write(data(lines: 7), to: legacy)
        let barrier = destination.deletingLastPathComponent()
        try write(Data("retain this file".utf8), to: barrier)
        XCTAssertEqual(resolve(), legacy)
        XCTAssertEqual(try Data(contentsOf: barrier), Data("retain this file".utf8))
        XCTAssertEqual(try Data(contentsOf: legacy), data(lines: 7))
    }

    func testRacingDestinationWriterWins() throws {
        try write(data(lines: 7), to: legacy)
        let other = data(lines: 9)
        let selected = ConfigurationFileMigration.resolve(legacy: legacy, destination: destination, log: log) { _, url in
            try self.write(other, to: url)
            throw CocoaError(.fileWriteFileExists)
        }
        XCTAssertEqual(selected, destination)
        XCTAssertEqual(try Data(contentsOf: destination), other)
        XCTAssertEqual(try Data(contentsOf: legacy), data(lines: 7))
    }

    func testMalformedLegacyIsRetainedWithoutPublishingIt() throws {
        let original = Data("{broken".utf8)
        try write(original, to: legacy)
        XCTAssertEqual(resolve(), legacy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        XCTAssertFalse(ConfigurationLoader.loadResult(from: legacy, log: log).warnings.isEmpty)
    }

    func testNoConfigDoesNotCreateOrMigrateAnything() {
        XCTAssertEqual(resolve(), destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().path))
    }

    func testAtomicPublisherNeverOverwritesAnExistingFile() throws {
        try write(data(lines: 9), to: destination)
        XCTAssertThrowsError(try ConfigurationFileMigration.publishAtomically(data(lines: 7), to: destination))
        XCTAssertEqual(try Data(contentsOf: destination), data(lines: 9))
        let names = try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
        XCTAssertEqual(names, ["config.json"])
    }
}
