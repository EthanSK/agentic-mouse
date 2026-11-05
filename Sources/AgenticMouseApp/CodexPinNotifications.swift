import AppKit
import Foundation
import ScimitarKit
import SQLite3
import UserNotifications
import os

struct CodexPinNotice: Equatable, Sendable {
    let threadID: String
    enum Action: String, Sendable { case pinned = "Pinned", unpinned = "Unpinned", archived = "Archived" }
    let action: Action
    let chatName: String

    init(threadID: String, isPinned: Bool, chatName: String) {
        self.init(threadID: threadID, action: isPinned ? .pinned : .unpinned, chatName: chatName)
    }

    init(threadID: String, action: Action, chatName: String) {
        self.threadID = threadID
        self.action = action
        self.chatName = chatName
    }

    var taskURL: URL? {
        guard let id = UUID(uuidString: threadID) else { return nil }
        return URL(string: "codex://threads/\(id.uuidString.lowercased())")
    }

    var content: UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = action.rawValue
        content.body = chatName
        if let taskURL { content.userInfo = ["codexTaskURL": taskURL.absoluteString] }
        // No sound: pin feedback must not interrupt current media or recording.
        return content
    }
}

/// Use the existing Codex-branded notification app when this Mac has it.
/// Notification Centre takes the small app icon from the sender's bundle,
/// so attaching an image to an Agentic Mouse notification cannot fix it.
struct CodexPinSharedSender {
    static func executable(codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) -> URL? {
        let bundle = codexDirectory.appendingPathComponent("apps/Codex Completion.app")
        let metadataURL = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              metadata["CFBundleIdentifier"] as? String == "com.ethansk.codex-completion-v2",
              metadata["CFBundleExecutable"] as? String == "terminal-notifier" else { return nil }
        let executable = bundle.appendingPathComponent("Contents/MacOS/terminal-notifier")
        return FileManager.default.isExecutableFile(atPath: executable.path) ? executable : nil
    }

    static func arguments(for notice: CodexPinNotice, notificationID: UUID = UUID()) -> [String] {
        var arguments = [
            "-title", notice.content.title, "-message", notice.chatName,
            "-group", "codex-\(notice.action == .archived ? "archive" : "pin")-\(notificationID.uuidString)"
        ]
        if let taskURL = notice.taskURL {
            arguments += ["-open", taskURL.absoluteString]
        }
        return arguments
    }

    static func send(_ notice: CodexPinNotice, using executable: URL) throws {
        let process = Process()
        process.environment = ChildProcessEnvironment.minimal
        process.executableURL = executable
        // Pass chat names as data, never through a shell. The shared sender is
        // silent and keeps its Codex icon, click target and retained history.
        process.arguments = arguments(for: notice)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { child in
            if child.terminationStatus != 0 {
                Logger(subsystem: "com.ethansk.AgenticMouse", category: "codex-pin-notifications")
                    .error("Shared pin notification sender failed: \(child.terminationStatus)")
            }
        }
        try process.run()
        // Never wait on the main input thread while the banner is displayed.
    }
}

struct CodexPinNotificationTracker {
    private var previous: Set<String>?

    mutating func changes(_ current: Set<String>) -> [(id: String, pinned: Bool)] {
        defer { previous = current }
        guard let previous else { return [] } // Startup is a baseline, not a pin event.
        return current.subtracting(previous).sorted().map { ($0, true) }
            + previous.subtracting(current).sorted().map { ($0, false) }
    }
}

/// Only visible names are read. `threads.title` contains the initial prompt in
/// current Codex versions and must never become notification text.
struct CodexThreadNameReader: Sendable {
    var codexDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex")

    func name(for threadID: String) -> String? {
        var database: OpaquePointer?
        let databaseURL = codexDirectory.appendingPathComponent("state_5.sqlite")
        let opened = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        defer { if let database { sqlite3_close(database) } }
        if opened == SQLITE_OK, let database {
            sqlite3_busy_timeout(database, 100)
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            if sqlite3_prepare_v2(database, "SELECT name FROM threads WHERE id = ?", -1, &statement, nil) == SQLITE_OK {
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                sqlite3_bind_text(statement, 1, threadID, -1, transient)
                if sqlite3_step(statement) == SQLITE_ROW,
                   let value = sqlite3_column_text(statement, 0),
                   let name = Self.cleaned(String(cString: value)) {
                    return name
                }
            }
        }
        // Older chats can retain their visible rename only in the session
        // index. The last matching rename wins; malformed partial lines skip.
        let indexURL = codexDirectory.appendingPathComponent("session_index.jsonl")
        guard let data = try? Data(contentsOf: indexURL, options: .mappedIfSafe) else { return nil }
        var name: String?
        for line in data.split(separator: 0x0A) {
            guard let row = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  row["id"] as? String == threadID,
                  let value = row["thread_name"] as? String,
                  let cleaned = Self.cleaned(value) else { continue }
            name = cleaned
        }
        return name
    }

    private static func cleaned(_ value: String) -> String? {
        let name = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return name.isEmpty ? nil : name
    }
}

/// Background metadata polling handles Codex's atomic state-file replacement.
/// An unreadable snapshot never means every chat was unpinned.
actor CodexPinNotificationSource {
    private let reader: CodexPinnedThreadStateReader
    private let names: CodexThreadNameReader
    private var tracker = CodexPinNotificationTracker()
    private var stamp: FileStamp?
    private var archives: CodexArchiveNotificationSource

    private struct FileStamp: Equatable {
        let modified: Date?
        let size: UInt64?
        let inode: UInt64?
    }

    init(codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        reader = CodexPinnedThreadStateReader(stateURL: codexDirectory.appendingPathComponent(".codex-global-state.json"))
        names = CodexThreadNameReader(codexDirectory: codexDirectory)
        archives = CodexArchiveNotificationSource(codexDirectory: codexDirectory)
    }

    func poll() -> [CodexPinNotice] {
        // Archive commits live in SQLite/WAL, independently of pin-file writes.
        pinChanges() + archives.poll()
    }

    private func pinChanges() -> [CodexPinNotice] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: reader.stateURL.path) else { return [] }
        let nextStamp = FileStamp(
            modified: attributes[.modificationDate] as? Date,
            size: attributes[.size] as? UInt64,
            inode: attributes[.systemFileNumber] as? UInt64
        )
        guard nextStamp != stamp, let pinned = try? reader.read() else { return [] }
        stamp = nextStamp
        return tracker.changes(pinned).compactMap { change in
            guard let name = names.name(for: change.id) else { return nil }
            return CodexPinNotice(threadID: change.id, isPinned: change.pinned, chatName: name)
        }
    }
}

/// Observes confirmed changes from either Codex UI or Agentic Mouse. It never
/// posts a banner merely because a synthetic shortcut was sent.
@MainActor
final class CodexPinNotificationController: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let inputAllowed: () -> Bool
    private let logger = Logger(subsystem: "com.ethansk.AgenticMouse", category: "codex-pin-notifications")
    private var source = CodexPinNotificationSource()
    private var timer: Timer?
    private var pollTask: Task<Void, Never>?
    private var generation = 0
    private var wasEnabled = false
    private var requestedAuthorization = false

    init(inputAllowed: @escaping () -> Bool) {
        self.inputAllowed = inputAllowed
        super.init()
    }

    func start() {
        stop()
        center.delegate = self
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 0.1
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        reset()
    }

    func reset() {
        generation += 1
        pollTask?.cancel()
        pollTask = nil
        source = CodexPinNotificationSource()
        wasEnabled = false
    }

    private func poll() {
        guard inputAllowed() else {
            if wasEnabled { reset() }
            return
        }
        wasEnabled = true
        if CodexPinSharedSender.executable() == nil && !requestedAuthorization {
            requestedAuthorization = true
            center.requestAuthorization(options: [.alert]) { [weak self] allowed, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.logger.info("Notification permission granted: \(allowed); error: \(error != nil)")
                }
            }
        }
        guard pollTask == nil else { return }
        let expectedGeneration = generation
        let source = source
        pollTask = Task { [weak self] in
            let notices = await source.poll()
            guard let self, expectedGeneration == self.generation else { return }
            self.pollTask = nil
            guard self.inputAllowed(), !notices.isEmpty else { return }
            if let executable = CodexPinSharedSender.executable() {
                for notice in notices {
                    do {
                        try CodexPinSharedSender.send(notice, using: executable)
                        self.logger.info("Codex-branded pin notification sender started")
                    } catch {
                        self.logger.error("Shared pin notification sender could not launch")
                    }
                }
                // Once attempted, never send the same event through a second
                // identity. That can duplicate an already-visible banner.
                return
            }
            // Read current settings so allowing notifications in System Settings
            // takes effect without restarting the mouse helper.
            let settings = await self.center.notificationSettings()
            guard expectedGeneration == self.generation, self.inputAllowed(),
                  settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            for notice in notices {
                let request = UNNotificationRequest(
                    identifier: "codex-pin-\(UUID().uuidString)", content: notice.content, trigger: nil
                )
                self.center.add(request) { [logger = self.logger] error in
                    if let error {
                        logger.error("Pin notification submission failed: \(error.localizedDescription, privacy: .public)")
                    } else {
                        logger.info("Pin notification submitted")
                    }
                }
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let value = response.notification.request.content.userInfo["codexTaskURL"] as? String,
           let url = URL(string: value), url.scheme == "codex", url.host == "threads",
           url.query == nil, url.fragment == nil,
           UUID(uuidString: String(url.path.dropFirst())) != nil {
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
