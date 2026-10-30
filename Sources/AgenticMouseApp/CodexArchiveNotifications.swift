import Foundation
import SQLite3

/// Observe only known live tasks becoming archived. Startup, imported history,
/// deleted rows and unarchiving are silent; restoring never happens here.
struct CodexArchiveNotificationTracker {
    private var previous: [String: Bool]?

    mutating func changes(_ current: [String: Bool]) -> [String] {
        defer { previous = current }
        guard let previous else { return [] }
        return current.keys.filter { current[$0] == true && previous[$0] == false }.sorted()
    }
}

struct CodexArchiveNotificationSource {
    private let codexDirectory: URL
    private var tracker = CodexArchiveNotificationTracker()
    private var databaseInode: UInt64?

    init(codexDirectory: URL) { self.codexDirectory = codexDirectory }

    mutating func poll() -> [CodexPinNotice] {
        let path = codexDirectory.appendingPathComponent("state_5.sqlite").path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let inode = attributes[.systemFileNumber] as? UInt64,
              let snapshot = Self.read(path) else { return [] }
        // Replacing/restoring the database establishes a new silent baseline.
        if databaseInode != inode { tracker = CodexArchiveNotificationTracker() }
        databaseInode = inode
        let names = CodexThreadNameReader(codexDirectory: codexDirectory)
        return tracker.changes(snapshot).compactMap { id in
            guard let name = names.name(for: id) else { return nil }
            return CodexPinNotice(threadID: id, action: .archived, chatName: name)
        }
    }

    /// Open read-only on each poll to see committed WAL changes. Do not use the
    /// main file mtime as a change detector: it stays unchanged until checkpoint.
    /// Any open/prepare/step/type failure is unknown, never an empty snapshot.
    private static func read(_ path: String) -> [String: Bool]? {
        var database: OpaquePointer?
        let status = sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil)
        defer { if let database { sqlite3_close(database) } }
        guard status == SQLITE_OK, let database else { return nil }
        sqlite3_busy_timeout(database, 100)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT id, archived FROM threads", -1, &statement, nil) == SQLITE_OK else { return nil }
        var snapshot: [String: Bool] = [:]
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_DONE: return snapshot
            case SQLITE_ROW:
                guard sqlite3_column_type(statement, 0) == SQLITE_TEXT,
                      sqlite3_column_type(statement, 1) == SQLITE_INTEGER,
                      let rawID = sqlite3_column_text(statement, 0) else { return nil }
                let id = String(cString: rawID)
                let archived = sqlite3_column_int(statement, 1)
                guard !id.isEmpty, snapshot[id] == nil, archived == 0 || archived == 1 else { return nil }
                snapshot[id] = archived == 1
            default: return nil
            }
        }
    }
}
