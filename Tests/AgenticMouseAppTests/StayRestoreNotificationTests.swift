import XCTest
@testable import AgenticMouseApp

final class StayRestoreNotificationTests: XCTestCase {
    func testRequestFeedbackDoesNotClaimTheLayoutFinished() {
        let notice = StayRestoreNotification(succeeded: true)
        XCTAssertEqual(notice.title, "Stay")
        XCTAssertEqual(notice.message, "Window restore requested")
    }

    func testFailureFeedbackDoesNotClaimStayWasTriggered() {
        let notice = StayRestoreNotification(succeeded: false)
        XCTAssertEqual(notice.title, "Stay")
        XCTAssertEqual(notice.message, "Window restore could not be requested")
    }

    func testEachAttemptHasItsOwnSilentBannerWithoutNavigation() {
        for success in [false, true] {
            let notice = StayRestoreNotification(succeeded: success)
            let id = UUID()
            XCTAssertEqual(notice.arguments(id: id), [
                "-title", "Stay", "-message", notice.message,
                "-group", "stay-restore-\(id.uuidString)"
            ])
            XCTAssertNotEqual(notice.arguments(), notice.arguments())
        }
    }

    func testSharedSenderRequiresTheGeneralNotificationIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("apps/Codex Heads-Up.app/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let executable = contents.appendingPathComponent("MacOS/terminal-notifier")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        func identity(_ value: String) throws {
            try PropertyListSerialization.data(fromPropertyList: [
                "CFBundleIdentifier": value, "CFBundleExecutable": "terminal-notifier"
            ], format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        }
        try identity("com.ethansk.codex-completion-v2")
        XCTAssertNil(StayRestoreNotification.sharedSender(codexDirectory: root))
        try identity("com.ethansk.codex-heads-up")
        XCTAssertEqual(StayRestoreNotification.sharedSender(codexDirectory: root), executable)
        try FileManager.default.removeItem(at: executable)
        XCTAssertNil(StayRestoreNotification.sharedSender(codexDirectory: root))
    }
}
