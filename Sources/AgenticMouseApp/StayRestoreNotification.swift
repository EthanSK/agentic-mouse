import Foundation
import UserNotifications
import os

/// Feedback reports shortcut submission, not unobservable Stay completion.
struct StayRestoreNotification {
    let succeeded: Bool

    var title: String { "Stay" }
    var message: String {
        succeeded ? "Window restore requested" : "Window restore could not be requested"
    }

    func arguments(id: UUID = UUID()) -> [String] {
        ["-title", title, "-message", message, "-group", "stay-restore-\(id.uuidString)"]
    }

    static func sharedSender(codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) -> URL? {
        // The chat-completion sender requires a real chat title. Stay is a
        // system action, so use the existing general-purpose heads-up sender.
        let bundle = codexDirectory.appendingPathComponent("apps/Codex Heads-Up.app")
        guard let data = try? Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
              let metadata = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              metadata["CFBundleIdentifier"] as? String == "com.ethansk.codex-heads-up",
              metadata["CFBundleExecutable"] as? String == "terminal-notifier" else { return nil }
        let executable = bundle.appendingPathComponent("Contents/MacOS/terminal-notifier")
        return FileManager.default.isExecutableFile(atPath: executable.path) ? executable : nil
    }

    func post() {
        let logger = Logger(subsystem: "com.ethan.agentic-mouse", category: "stay-notifications")
        // Reuse the installed, already-authorized general banner sender.
        // Never wait for a banner on the mouse input thread.
        if let executable = Self.sharedSender() {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { child in
                if child.terminationStatus != 0 {
                    logger.error("Stay notification sender failed: \(child.terminationStatus)")
                }
            }
            do { try process.run() }
            catch { logger.error("Stay notification sender could not launch") }
            // No fallback after dispatch: it might already have displayed.
            return
        }

        // Other installations can use Agentic Mouse's own notification grant.
        // No polling, sounds, activation, or window moves are needed for feedback.
        Task {
            let center = UNUserNotificationCenter.current()
            var status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert])
                status = await center.notificationSettings().authorizationStatus
            }
            guard status == .authorized || status == .provisional else {
                logger.notice("Stay notifications are disabled")
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message
            do {
                try await center.add(UNNotificationRequest(
                    identifier: "stay-restore-\(UUID().uuidString)", content: content, trigger: nil
                ))
            } catch { logger.error("Stay notification could not be submitted") }
        }
    }
}
