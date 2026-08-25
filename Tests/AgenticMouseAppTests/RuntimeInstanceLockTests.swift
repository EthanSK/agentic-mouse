@testable import AgenticMouseApp
import Foundation
import XCTest

final class RuntimeInstanceLockTests: XCTestCase {
    func testSecondRuntimeCannotAcquireTheSameLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let lockURL = directory.appendingPathComponent("runtime.lock")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try RuntimeInstanceLock.acquire(at: lockURL)
        try withExtendedLifetime(first) {
            XCTAssertThrowsError(try RuntimeInstanceLock.acquire(at: lockURL)) { error in
                guard case RuntimeInstanceLockError.alreadyRunning = error else {
                    return XCTFail("unexpected lock error: \(error)")
                }
            }
        }
    }

    func testLockCanBeReacquiredAfterOwnerReleasesIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let lockURL = directory.appendingPathComponent("runtime.lock")
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let first = try RuntimeInstanceLock.acquire(at: lockURL)
            withExtendedLifetime(first) {}
        }
        XCTAssertNoThrow(try RuntimeInstanceLock.acquire(at: lockURL))
    }

    func testLockFileIsPrivate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let lockURL = directory.appendingPathComponent("runtime.lock")
        defer { try? FileManager.default.removeItem(at: directory) }

        let lock = try RuntimeInstanceLock.acquire(at: lockURL)
        defer { _ = lock }
        let attributes = try FileManager.default.attributesOfItem(atPath: lockURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }
}
