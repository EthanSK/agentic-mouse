// Read Better Git's per-activation receipts, then prove them against the running
// Code host set. Files are capability evidence, never installed-version guesses.
import AppKit
import Darwin
import Foundation
import ScimitarKit

struct VSCodeEyesHostProof: Equatable {
    struct ProcessIdentity: Equatable {
        let pid: Int32
        let startTime: String
        let path: String
    }
    let code: ProcessIdentity
    let hosts: [ProcessIdentity]
}

enum VSCodeEyesHostReceipts {
    struct Target {
        let pid: Int32
        let appURL: URL
    }
    struct Receipt: Decodable {
        let schemaVersion: Int
        let extensionVersion: String
        let capabilities: [String]
        let activationId: String
        let hostPid: Int32
        let hostStartTime: String
        let codePid: Int32
        let codeStartTime: String

        static func decode(_ data: Data, filename: String) -> Self? {
            guard data.count <= 8192, let value = try? JSONDecoder().decode(Self.self, from: data),
                  value.schemaVersion == 1, value.hostPid > 1, value.codePid > 1,
                  value.hostPid != value.codePid, UUID(uuidString: value.activationId) != nil,
                  filename.lowercased() == "\(value.hostPid)-\(value.activationId).json".lowercased(),
                  value.capabilities.count <= 32,
                  value.capabilities.contains("atomic-default-eyes-begin-v1") else { return nil }
            let parts = value.extensionVersion.split(separator: ".", omittingEmptySubsequences: false)
            let version = parts.compactMap { Int($0) }
            guard parts.count == 3, version.count == 3, version.allSatisfy({ $0 >= 0 }),
                  !version.lexicographicallyPrecedes([1, 2, 146]),
                  normalize(value.hostStartTime).count <= 64, !normalize(value.hostStartTime).isEmpty,
                  normalize(value.codeStartTime).count <= 64, !normalize(value.codeStartTime).isEmpty else { return nil }
            return value
        }
    }

    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/BetterGit/active-hosts", isDirectory: true)

    static func normalize(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func hostPIDs(status: String) -> [Int32]? {
        let regex = try! NSRegularExpression(pattern: #"(?m)^.*?\s(\d+)\s+extension-host \[(\d+)\]"#)
        let windowRegex = try! NSRegularExpression(pattern: #"(?m)^.*?\s\d+\s+window \[(\d+)\]"#)
        let range = NSRange(status.startIndex..., in: status)
        let matches = regex.matches(in: status, range: range)
        let pids = matches.compactMap { match -> Int32? in
            guard let range = Range(match.range(at: 1), in: status) else { return nil }
            return Int32(status[range])
        }
        let hostWindows = matches.compactMap { Range($0.range(at: 2), in: status).map { String(status[$0]) } }
        let windows = windowRegex.matches(in: status, range: range).compactMap { Range($0.range(at: 1), in: status).map { String(status[$0]) } }
        // A window whose host is still starting cannot be silently omitted.
        // The Code process is watched throughout this asynchronous snapshot.
        guard !windows.isEmpty, Set(windows).count == windows.count,
              Set(hostWindows).count == hostWindows.count, Set(windows) == Set(hostWindows) else { return nil }
        guard !pids.isEmpty, pids.count <= 64, Set(pids).count == pids.count, pids.allSatisfy({ $0 > 1 }) else { return nil }
        return pids.sorted()
    }

    static func processes(_ text: String) -> [Int32: VSCodeEyesHostProof.ProcessIdentity] {
        var result: [Int32: VSCodeEyesHostProof.ProcessIdentity] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(maxSplits: 6, whereSeparator: { $0.isWhitespace })
            guard fields.count == 7, let pid = Int32(fields[0]), pid > 1 else { continue }
            // ps pads this final column even though splitting has reached its
            // limit. Remove only its leading padding; preserve spaces in paths.
            let path = String(fields[6].drop(while: { $0.isWhitespace }))
            result[pid] = .init(pid: pid, startTime: fields[1...5].joined(separator: " "), path: path)
        }
        return result
    }

    static func qualify(target: Target, hosts: [Int32], processes: [Int32: VSCodeEyesHostProof.ProcessIdentity], receipts: [Receipt]) -> VSCodeEyesHostProof? {
        guard !hosts.isEmpty, hosts.count <= 64, Set(hosts).count == hosts.count,
              let code = processes[target.pid], code.path == target.appURL.appendingPathComponent("Contents/MacOS/Code").path else { return nil }
        var qualified: [VSCodeEyesHostProof.ProcessIdentity] = []
        for pid in hosts.sorted() {
            guard let host = processes[pid], pid != code.pid,
                  host.path.hasPrefix(target.appURL.path + "/Contents/Frameworks/"),
                  receipts.contains(where: {
                      $0.hostPid == pid && $0.codePid == code.pid
                          && normalize($0.hostStartTime) == host.startTime
                          && normalize($0.codeStartTime) == code.startTime
                  }) else { return nil }
            qualified.append(host)
        }
        return .init(code: code, hosts: qualified)
    }

    /// Called only on the consumer's serial worker. Reject incomplete host sets
    /// and stale PID reuse rather than guessing which window currently matters.
    static func read(target: Target, directory: URL, run: (URL, [String]) throws -> String) -> VSCodeEyesHostProof? {
        do {
            let manager = FileManager.default
            let attributes = try manager.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  attributes[.ownerAccountID] as? Int == Int(getuid()),
                  (attributes[.posixPermissions] as? Int ?? 0) & 0o777 == 0o700 else { return nil }
            let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard files.count <= 512 else { return nil }
            let status = try run(target.appURL.appendingPathComponent("Contents/Resources/app/bin/code"), ["--status"])
            guard let hosts = hostPIDs(status: status) else { return nil }
            let identities = processes(try run(URL(fileURLWithPath: "/bin/ps"), ["-p", ([target.pid] + hosts).map(String.init).joined(separator: ","), "-o", "pid=,lstart=,comm="]))
            var receipts: [Receipt] = []
            for file in files where file.pathExtension == "json" {
                // Inspect/read the same descriptor: an atomic replacement or
                // symlink swap must not bypass ownership and bounded reads.
                let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
                guard fd >= 0 else { continue }
                defer { close(fd) }
                var info = stat()
                guard fstat(fd, &info) == 0, info.st_uid == getuid(),
                      info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                      info.st_mode & 0o777 == 0o600, info.st_size <= 8192 else { continue }
                let data = FileHandle(fileDescriptor: fd, closeOnDealloc: false).readData(ofLength: 8193)
                guard let receipt = Receipt.decode(data, filename: file.lastPathComponent) else { continue }
                receipts.append(receipt)
            }
            return qualify(target: target, hosts: hosts, processes: identities, receipts: receipts)
        } catch { return nil }
    }
}

/// Only finite read-only CLI children run here, off AppKit. The deadline is an
/// upper bound on actual work, not padding between input events.
final class VSCodeEyesProcessReader {
    private let lock = NSLock()
    private var current: Process?

    func cancel() {
        lock.lock(); let process = current; lock.unlock()
        if let process, process.isRunning { process.terminate(); kill(process.processIdentifier, SIGKILL) }
    }

    func run(_ executable: URL, _ arguments: [String]) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = executable; process.arguments = arguments
        // Code --status forwards its environment through macOS open. Keep
        // ambient credentials and other apps' launch settings out of that CLI.
        process.environment = ChildProcessEnvironment.minimal.merging(["VSCODE_CLI": "1"]) { _, value in value }
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        lock.lock(); current = process; lock.unlock()
        let deadline = DispatchWorkItem { [weak process] in
            if let process, process.isRunning { process.terminate(); kill(process.processIdentifier, SIGKILL) }
        }
        defer { deadline.cancel(); lock.lock(); current = nil; lock.unlock() }
        try process.run()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 8, execute: deadline)
        var data = Data()
        while true {
            let next = pipe.fileHandleForReading.readData(ofLength: 4096)
            if next.isEmpty { break }
            data.append(next)
            if data.count > 256 * 1024 { cancel(); throw CocoaError(.fileReadTooLarge) }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadUnknown) }
        return text
    }
}
