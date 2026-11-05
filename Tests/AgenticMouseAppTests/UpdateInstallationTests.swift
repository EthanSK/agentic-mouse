// Exercise pending updates against changes during supervisor preparation and aborts.
import XCTest
@testable import AgenticMouseApp

@MainActor final class UpdateInstallationTests: XCTestCase {
    func testBusyUpdateWaitsForAnIdleEventAndInstallsOnce() async {
        var idle = false, preparations = 0, installs = 0
        let updater = UpdateInstallation(mayInstall: { idle }, prepare: { preparations += 1; return true }, restore: {})
        updater.offer { installs += 1 }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(preparations, 0)
        idle = true; updater.requestCheck()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(installs, 1)
        updater.requestCheck()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(installs, 1)
    }

    func testNewWorkDuringPreparationRestoresRecoveryAndWaits() async {
        var idle = true, restores = 0, installs = 0
        let updater = UpdateInstallation(mayInstall: { idle }, prepare: { idle = false; return true }, restore: { restores += 1 })
        updater.offer { installs += 1 }
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(installs, 0)
        XCTAssertEqual(restores, 1)
        await updater.abort()
        XCTAssertEqual(restores, 1)
    }

    func testAbortAfterInstallerHandoffRestoresRecovery() async {
        var restores = 0, installs = 0
        let updater = UpdateInstallation(mayInstall: { true }, prepare: { true }, restore: { restores += 1 })
        updater.offer { installs += 1 }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(installs, 1)
        await updater.abort()
        XCTAssertEqual(restores, 1)
        updater.requestCheck()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(installs, 1)
    }
}
