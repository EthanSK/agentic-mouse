import Foundation
import ScimitarKit

/// Sends the first rewind immediately; a same-mouse second click restores its saved video time and pauses. — GPT-6.1 Sol
@MainActor
final class YouTubeClickController {
    enum Action: String { case rewind, restoreAndPause }
    static let notification = Notification.Name("com.ethansk.agenticmouse.youtube.click")
    typealias Notifier = @MainActor (Action, String) -> Bool
    private struct Click { let time: TimeInterval; let token: String }
    private var clicks: [MouseSource: Click] = [:]
    private let interval: TimeInterval
    private let notify: Notifier

    init(interval: TimeInterval, notify: @escaping Notifier = YouTubeClickController.post) {
        self.interval = interval
        self.notify = notify
    }

    @discardableResult
    func click(source: MouseSource, time: TimeInterval) -> Action? {
        if let previous = clicks.removeValue(forKey: source),
           time >= previous.time, time - previous.time <= interval {
            return notify(.restoreAndPause, previous.token) ? .restoreAndPause : nil
        }
        let token = UUID().uuidString
        guard notify(.rewind, token) else { return nil }
        clicks[source] = Click(time: time, token: token)
        return .rewind
    }

    func cancel(source: MouseSource) { clicks[source] = nil }
    func cancelAll() { clicks.removeAll() }

    private static func post(_ action: Action, token: String) -> Bool {
        // Older bridges still understand the first rewind; only the new second-click action needs an update.
        let name = action == .rewind
            ? Notification.Name("com.ethansk.agenticmouse.youtube.seekBackwardFiveSeconds") : notification
        DistributedNotificationCenter.default().postNotificationName(name, object: nil,
            userInfo: ["videoAction": action.rawValue, "requestId": token,
                       "issuedAt": Int(Date().timeIntervalSince1970 * 1_000)], deliverImmediately: true)
        return true
    }
}
