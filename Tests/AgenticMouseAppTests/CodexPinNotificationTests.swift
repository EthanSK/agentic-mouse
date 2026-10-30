import Foundation
import SQLite3
import UserNotifications
import XCTest
@testable import AgenticMouseApp

final class CodexPinNotificationTests: XCTestCase {
    func testSharedSenderPreservesCopyAsArgumentsAndRoutesToTheExactChat() {
        let id = UUID(uuidString: "01a07dc7-5809-7a02-adc2-efaf01c94206")!
        let group = UUID()
        let name = "My chat: $(touch /tmp/do-not-run) \"quoted\""
        for pinned in [true, false] {
            let args = CodexPinSharedSender.arguments(
                for: CodexPinNotice(threadID: id.uuidString, isPinned: pinned, chatName: name),
                notificationID: group
            )
            XCTAssertEqual(args, ["-title", pinned ? "Pinned" : "Unpinned", "-message", name,
                "-group", "codex-pin-\(group.uuidString)", "-open", "codex://threads/\(id.uuidString.lowercased())"])
            XCTAssertFalse(args.contains("-sound"))
        }
        let invalid = CodexPinSharedSender.arguments(for: CodexPinNotice(threadID: "other://destination", isPinned: true, chatName: "Chat"))
        XCTAssertFalse(invalid.contains("-open"))
    }

    func testSharedSenderRequiresTheConfiguredCodexIdentityAndExecutable() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(CodexPinSharedSender.executable(codexDirectory: directory))
        let contents = directory.appendingPathComponent("apps/Codex Completion.app/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let executable = contents.appendingPathComponent("MacOS/terminal-notifier")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        func writeMetadata(_ identity: String) throws {
            let metadata = ["CFBundleIdentifier": identity, "CFBundleExecutable": "terminal-notifier"]
            try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }
        try writeMetadata("com.ethan.agentic-mouse")
        XCTAssertNil(CodexPinSharedSender.executable(codexDirectory: directory))
        try writeMetadata("com.ethansk.codex-completion-v2")
        XCTAssertEqual(CodexPinSharedSender.executable(codexDirectory: directory), executable)
        try FileManager.default.removeItem(at: executable)
        XCTAssertNil(CodexPinSharedSender.executable(codexDirectory: directory))
    }

    func testStartupAndReorderedPinsAreSilentAndEachChangeIsReportedOnce() {
        var tracker = CodexPinNotificationTracker()
        XCTAssertTrue(tracker.changes(["existing", "other"]).isEmpty)
        XCTAssertTrue(tracker.changes(["other", "existing"]).isEmpty)
        let changes = tracker.changes(["existing", "added"])
        XCTAssertEqual(changes.map(\.id), ["added", "other"])
        XCTAssertEqual(changes.map(\.pinned), [true, false])
        XCTAssertTrue(tracker.changes(["existing", "added"]).isEmpty)
    }

    func testNotificationHasActionTitleAndChatNameBelowWithoutSound() {
        for isPinned in [true, false] {
            let content = CodexPinNotice(threadID: "a", isPinned: isPinned, chatName: "My renamed chat").content
            XCTAssertEqual(content.title, isPinned ? "Pinned" : "Unpinned")
            XCTAssertEqual(content.body, "My renamed chat")
            XCTAssertNil(content.sound)
        }
    }

    func testVisibleDatabaseNameWinsOverPromptAndOldIndexName() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try database(directory, sql: "CREATE TABLE threads(id TEXT, name TEXT, title TEXT); INSERT INTO threads VALUES('a', 'Renamed chat', 'Private initial prompt');")
        try writeIndex(directory, text: "{\"id\":\"a\",\"thread_name\":\"Old name\"}\n")
        let reader = CodexThreadNameReader(codexDirectory: directory)
        XCTAssertEqual(reader.name(for: "a"), "Renamed chat")
        XCTAssertNil(reader.name(for: "a' OR 1=1 --"))
    }

    func testLastIndexRenameWinsAndMalformedLineDoesNotHideIt() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeIndex(directory, text: "{\"id\":\"a\",\"thread_name\":\"Old name\"}\n{\"id\":\"a\",\"thread_name\":\"  New   name  \"}\n{partial")
        XCTAssertEqual(CodexThreadNameReader(codexDirectory: directory).name(for: "a"), "New name")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("state_5.sqlite").path))
    }

    func testMissingVisibleNameNeverFallsBackToPrivateInitialPrompt() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try database(directory, sql: "CREATE TABLE threads(id TEXT, name TEXT, title TEXT); INSERT INTO threads VALUES('a', NULL, 'Private initial prompt');")
        XCTAssertNil(CodexThreadNameReader(codexDirectory: directory).name(for: "a"))
    }

    func testAtomicFileReplacementAndUnreadableSnapshotsDoNotFabricateChanges() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = CodexPinNotificationSource(codexDirectory: directory)
        try writeIndex(directory, text: "{\"id\":\"a\",\"thread_name\":\"Actual chat\"}\n")
        let state = directory.appendingPathComponent(".codex-global-state.json")
        try Data("{\"pinned-thread-ids\":[]}".utf8).write(to: state, options: .atomic)
        let baseline = await source.poll()
        XCTAssertTrue(baseline.isEmpty)
        try Data("{\"pinned-thread-ids\":[\"a\"]}".utf8).write(to: state, options: .atomic)
        let pinned = await source.poll()
        XCTAssertEqual(pinned, [CodexPinNotice(threadID: "a", isPinned: true, chatName: "Actual chat")])
        let unchanged = await source.poll()
        XCTAssertTrue(unchanged.isEmpty)
        try Data("{broken".utf8).write(to: state, options: .atomic)
        let broken = await source.poll()
        XCTAssertTrue(broken.isEmpty)
        try Data("{}".utf8).write(to: state, options: .atomic)
        let missing = await source.poll()
        XCTAssertTrue(missing.isEmpty)
        try Data("{\"pinned-thread-ids\":[]}".utf8).write(to: state, options: .atomic)
        let unpinned = await source.poll()
        XCTAssertEqual(unpinned, [CodexPinNotice(threadID: "a", isPinned: false, chatName: "Actual chat")])
        let restarted = CodexPinNotificationSource(codexDirectory: directory)
        let restartBaseline = await restarted.poll()
        XCTAssertTrue(restartBaseline.isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeIndex(_ directory: URL, text: String) throws {
        try Data(text.utf8).write(to: directory.appendingPathComponent("session_index.jsonl"))
    }

    private func database(_ directory: URL, sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("state_5.sqlite").path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
    }
}
