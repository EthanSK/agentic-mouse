@testable import AgenticMouseSupervisor
import Foundation
import XCTest

final class RuntimeSupervisorRecoveryPolicyTests: XCTestCase {
    func testRunningApplicationDoesNotLaunch() {
        var policy = RuntimeSupervisorRecoveryPolicy()

        XCTAssertEqual(policy.observe(isRunning: true, now: 0), .none)
        XCTAssertEqual(policy.observe(isRunning: true, now: 61), .none)
        XCTAssertTrue(policy.attemptTimes.isEmpty)
    }

    func testAbsentApplicationLaunchesWithBoundedBackoff() {
        var policy = RuntimeSupervisorRecoveryPolicy()

        XCTAssertEqual(policy.observe(isRunning: false, now: 0), .launch)
        XCTAssertEqual(policy.observe(isRunning: false, now: 1), .none)
        XCTAssertEqual(policy.observe(isRunning: false, now: 2), .launch)
        XCTAssertEqual(policy.observe(isRunning: false, now: 6), .none)
        XCTAssertEqual(policy.observe(isRunning: false, now: 7), .launch)
    }

    func testCrashLoopPausesAfterFiveAttempts() {
        var policy = RuntimeSupervisorRecoveryPolicy()
        let attempts: [TimeInterval] = [0, 2, 7, 17, 47]
        for time in attempts {
            XCTAssertEqual(policy.observe(isRunning: false, now: time), .launch)
        }

        XCTAssertEqual(
            policy.observe(isRunning: false, now: 107),
            .paused(RuntimeSupervisorRecoveryPolicy.crashLoopPause)
        )
        XCTAssertEqual(policy.observe(isRunning: false, now: 108), .none)
    }

    func testStableRuntimeClearsEarlierCrashAttempts() {
        var policy = RuntimeSupervisorRecoveryPolicy()
        XCTAssertEqual(policy.observe(isRunning: false, now: 0), .launch)
        XCTAssertEqual(policy.observe(isRunning: true, now: 1), .none)
        XCTAssertEqual(policy.observe(isRunning: true, now: 62), .none)
        XCTAssertTrue(policy.attemptTimes.isEmpty)

        XCTAssertEqual(policy.observe(isRunning: false, now: 63), .launch)
        XCTAssertEqual(policy.attemptTimes, [63])
    }
}

final class OuterApplicationLocatorTests: XCTestCase {
    func testFindsOuterBundleWithExpectedIdentifier() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outer = root.appendingPathComponent("AgenticMouse.app", isDirectory: true)
        let helper = outer
            .appendingPathComponent("Contents/Library/LoginItems/AgenticMouseSupervisor.app")
        let executable = helper
            .appendingPathComponent("Contents/MacOS/AgenticMouseSupervisor")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeInfoPlist(
            identifier: AgenticMouseRuntimeSupervisor.applicationBundleIdentifier,
            at: outer
        )
        try makeInfoPlist(identifier: "com.example.Helper", at: helper)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(
            OuterApplicationLocator.locate(
                from: executable,
                expectedBundleIdentifier: AgenticMouseRuntimeSupervisor.applicationBundleIdentifier
            )?.standardizedFileURL,
            outer.standardizedFileURL
        )
    }

    func testRejectsUnrelatedOuterBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outer = root.appendingPathComponent("Other.app", isDirectory: true)
        let executable = outer
            .appendingPathComponent("Contents/Library/LoginItems/Helper.app/Contents/MacOS/Helper")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeInfoPlist(identifier: "com.example.Other", at: outer)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertNil(
            OuterApplicationLocator.locate(
                from: executable,
                expectedBundleIdentifier: AgenticMouseRuntimeSupervisor.applicationBundleIdentifier
            )
        )
    }

    private func makeInfoPlist(identifier: String, at bundleURL: URL) throws {
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": identifier,
                "CFBundlePackageType": "APPL",
            ],
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }
}

final class AgenticMouseRuntimeSupervisorTests: XCTestCase {
    func testRequestsOneBackgroundLaunchWhileApplicationIsAbsent() {
        let manager = RecordingApplicationManager()
        manager.isRunning = false
        var now: TimeInterval = 0
        let supervisor = AgenticMouseRuntimeSupervisor(
            applicationURL: URL(fileURLWithPath: "/Applications/AgenticMouse.app"),
            manager: manager,
            now: { now }
        )

        supervisor.checkNow()
        supervisor.checkNow()
        XCTAssertEqual(manager.launchCount, 1)

        manager.completeLaunch(error: nil)
        now = 1
        supervisor.checkNow()
        XCTAssertEqual(manager.launchCount, 1)

        now = 2
        supervisor.checkNow()
        XCTAssertEqual(manager.launchCount, 2)
    }

    func testNeverLaunchesWhileApplicationIsRunning() {
        let manager = RecordingApplicationManager()
        manager.isRunning = true
        let supervisor = AgenticMouseRuntimeSupervisor(
            applicationURL: URL(fileURLWithPath: "/Applications/AgenticMouse.app"),
            manager: manager,
            now: { 10 }
        )

        supervisor.checkNow()
        XCTAssertEqual(manager.launchCount, 0)
    }

    func testDefersRelaunchWhileLoginWindowOwnsTheSessionWithoutBurningAnAttempt() {
        let manager = RecordingApplicationManager()
        manager.isRunning = false
        manager.sessionAllowsRelaunch = false
        var now: TimeInterval = 0
        let supervisor = AgenticMouseRuntimeSupervisor(
            applicationURL: URL(fileURLWithPath: "/Applications/AgenticMouse.app"),
            manager: manager,
            now: { now }
        )

        supervisor.checkNow()
        now = 30
        supervisor.checkNow()
        XCTAssertEqual(manager.launchCount, 0)

        manager.sessionAllowsRelaunch = true
        supervisor.checkNow()
        XCTAssertEqual(manager.launchCount, 1)
    }
}

private final class RecordingApplicationManager: SupervisedApplicationManaging {
    var isRunning = false
    var sessionAllowsRelaunch = true
    private(set) var launchCount = 0
    private var completions: [(Error?) -> Void] = []

    func isRunning(bundleIdentifier: String) -> Bool {
        XCTAssertEqual(bundleIdentifier, AgenticMouseRuntimeSupervisor.applicationBundleIdentifier)
        return isRunning
    }

    func userSessionAllowsRelaunch() -> Bool { sessionAllowsRelaunch }

    func launch(applicationURL: URL, completion: @escaping (Error?) -> Void) {
        launchCount += 1
        completions.append(completion)
    }

    func completeLaunch(error: Error?) {
        completions.removeFirst()(error)
    }
}
