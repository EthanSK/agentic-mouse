// The configuration loader uses this once-on-first-load migration. Publish a
// complete private file without replacing an existing destination, and retain
// the legacy file for recovery and older app rollbacks.
import Darwin
import Foundation

enum ConfigurationFileMigration {
    static func destination(in home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Agentic Mouse/config.json")
    }

    static func legacy(in home: URL) -> URL {
        home.appendingPathComponent(".config/agentic-mouse/config.json")
    }

    static func resolve(
        legacy: URL, destination: URL, log: Log,
        publish: (Data, URL) throws -> Void = publishAtomically
    ) -> URL {
        let files = FileManager.default
        // The destination is authoritative even if both files exist. Do not
        // guess from timestamps or merge a retained rollback copy on each load.
        guard !files.fileExists(atPath: destination.path) else { return destination }
        guard files.fileExists(atPath: legacy.path) else { return destination }
        do {
            let data = try Data(contentsOf: legacy)
            _ = try JSONDecoder().decode(AppConfiguration.self, from: data)
            try publish(data, destination)
            log.notice("Configuration migrated to \(destination.path); legacy copy retained for recovery.")
            return destination
        } catch {
            // Another app/CLI process may have published its configuration
            // first. Its complete file wins; never replace it with our snapshot.
            if files.fileExists(atPath: destination.path) { return destination }
            log.error("Configuration migration failed; continuing with \(legacy.path).")
            return legacy
        }
    }

    static func publishAtomically(_ data: Data, to destination: URL) throws {
        let files = FileManager.default
        let directory = destination.deletingLastPathComponent()
        try files.createDirectory(at: directory, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".config-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); try? files.removeItem(at: temporary) }
        guard fchmod(descriptor, 0o600) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        try handle.write(contentsOf: data)
        guard fsync(descriptor) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        // A same-directory hard link publishes the fully written inode
        // atomically and refuses an existing file, including a racing writer.
        guard link(temporary.path, destination.path) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }
}
