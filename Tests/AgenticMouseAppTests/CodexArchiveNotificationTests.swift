import Foundation
import SQLite3
import XCTest
@testable import AgenticMouseApp

final class CodexArchiveNotificationTests: XCTestCase {
    private let id = "01a07dc7-5809-7a02-adc2-efaf01c94206"

    func testOnlyKnownLiveToArchivedTransitionsNotifyOnce() {
        var tracker = CodexArchiveNotificationTracker()
        XCTAssertEqual(tracker.changes(["live": false, "old": true]), [])
        XCTAssertEqual(tracker.changes(["live": true, "old": true, "imported": true]), ["live"])
        XCTAssertEqual(tracker.changes(["live": true, "old": true, "imported": true]), [])
        XCTAssertEqual(tracker.changes(["live": false]), [])
        XCTAssertEqual(tracker.changes(["live": true]), ["live"])
        XCTAssertEqual(tracker.changes([:]), [])
        XCTAssertEqual(tracker.changes(["live": true]), [])
    }

    func testArchiveNoticeUsesSameSilentSenderAndExactTaskLink() {
        let group = UUID()
        let name = "A quoted \"task\" $(not a command)"
        let notice = CodexPinNotice(threadID: id, action: .archived, chatName: name)
        XCTAssertEqual(notice.content.title, "Archived")
        XCTAssertEqual(notice.content.body, name)
        XCTAssertNil(notice.content.sound)
        XCTAssertEqual(notice.content.userInfo["codexTaskURL"] as? String, "codex://threads/\(id)")
        XCTAssertEqual(CodexPinSharedSender.arguments(for: notice, notificationID: group), [
            "-title", "Archived", "-message", name, "-group", "codex-archive-\(group.uuidString)",
            "-open", "codex://threads/\(id)"
        ])
        XCTAssertNil(CodexPinNotice(threadID: "invalid", action: .archived, chatName: name).taskURL)
    }

    func testWALCommitNotPinFileDrivesNoticeAndRestartIsSilent() async throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        try exec(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE threads(id TEXT, name TEXT, title TEXT, archived INTEGER); INSERT INTO threads VALUES('\(id)', 'Exact task name', 'Private prompt', 0);")
        let source = CodexPinNotificationSource(codexDirectory: directory)
        let baseline = await source.poll()
        XCTAssertEqual(baseline, []) // No pin file exists: archive observer still runs.
        let path = directory.appendingPathComponent("state_5.sqlite").path
        let before = try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
        try exec(db, "BEGIN; UPDATE threads SET archived=1;")
        let uncommitted = await source.poll()
        XCTAssertEqual(uncommitted, [])
        try exec(db, "COMMIT;")
        XCTAssertEqual(before, try FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
        let notices = await source.poll()
        XCTAssertEqual(notices, [CodexPinNotice(threadID: id, action: .archived, chatName: "Exact task name")])
        let duplicate = await source.poll()
        XCTAssertEqual(duplicate, [])
        let restarted = CodexPinNotificationSource(codexDirectory: directory)
        let afterRestart = await restarted.poll()
        XCTAssertEqual(afterRestart, [])
        try exec(db, "UPDATE threads SET archived=0;")
        let restored = await source.poll()
        XCTAssertEqual(restored, [])
        try exec(db, "UPDATE threads SET archived=1;")
        let rearchived = await source.poll()
        XCTAssertEqual(rearchived, notices)
    }

    func testReadFailureRetainsBaselineAndPrivatePromptIsNeverShown() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        try exec(db, "CREATE TABLE threads(id TEXT, name TEXT, title TEXT, archived INTEGER); INSERT INTO threads VALUES('\(id)', 'Exact task', 'Private prompt', 0);")
        var source = CodexArchiveNotificationSource(codexDirectory: directory)
        XCTAssertEqual(source.poll(), [])
        try exec(db, "BEGIN EXCLUSIVE; UPDATE threads SET archived=1;")
        XCTAssertEqual(source.poll(), [])
        try exec(db, "COMMIT;")
        XCTAssertEqual(source.poll().map(\.chatName), ["Exact task"])
        try exec(db, "UPDATE threads SET archived=0;")
        XCTAssertEqual(source.poll(), [])
        try exec(db, "UPDATE threads SET archived=2;")
        XCTAssertEqual(source.poll(), [])
        try exec(db, "UPDATE threads SET archived=1;")
        XCTAssertEqual(source.poll().map(\.chatName), ["Exact task"])
        try exec(db, "UPDATE threads SET archived=0;")
        XCTAssertEqual(source.poll(), [])
        try exec(db, "UPDATE threads SET archived=1, name=NULL;")
        XCTAssertEqual(source.poll(), [])
    }

    func testMissingOrReplacedDatabaseIsNotAnArchiveEvent() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("state_5.sqlite")
        var source = CodexArchiveNotificationSource(codexDirectory: directory)
        XCTAssertEqual(source.poll(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        func create(_ archived: Int) throws {
            var db: OpaquePointer?
            XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
            defer { sqlite3_close(db) }
            try exec(db, "CREATE TABLE threads(id TEXT, name TEXT, archived INTEGER); INSERT INTO threads VALUES('\(id)', 'Task', \(archived));")
        }
        try create(0)
        XCTAssertEqual(source.poll(), [])
        try FileManager.default.moveItem(at: path, to: directory.appendingPathComponent("old.sqlite"))
        XCTAssertEqual(source.poll(), [])
        try create(1)
        XCTAssertEqual(source.poll(), [])
    }

    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func exec(_ database: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLiteFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
        }
    }
}
