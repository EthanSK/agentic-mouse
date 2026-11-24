import Foundation
import ScimitarKit

/// Ethan's “long press followed by a short press” toggles playback; ordinary clicks rewind immediately. — GPT-6.1 Sol
@MainActor
final class YouTubeClickController {
    enum Action: String { case rewind, togglePlayback }
    static let notification = Notification.Name("com.ethansk.agenticmouse.youtube.click")
    typealias Notifier = @MainActor (Action) -> Bool
    private struct Press {
        let started: TimeInterval
        var followsLongPress: Bool
        var canArmLongPress: Bool
    }
    private var presses: [MouseSource: Press] = [:]
    private var longReleases: [MouseSource: TimeInterval] = [:]
    private let interval: TimeInterval
    private let longPressThreshold: TimeInterval
    private let notify: Notifier

    init(interval: TimeInterval, longPressThreshold: TimeInterval = YouTubeScrubHoldController.holdThreshold,
         notify: @escaping Notifier = YouTubeClickController.post) {
        self.interval = interval
        self.longPressThreshold = longPressThreshold
        self.notify = notify
    }

    func press(source: MouseSource, time: TimeInterval, canArmLongPress: Bool = true) {
        guard presses[source] == nil else { return }
        let previous = longReleases.removeValue(forKey: source)
        let followsLongPress = canArmLongPress && (previous.map { time >= $0 && time - $0 <= interval } ?? false)
        presses[source] = Press(started: time, followsLongPress: followsLongPress, canArmLongPress: canArmLongPress)
    }

    @discardableResult
    func release(source: MouseSource, time: TimeInterval, isShortClick: Bool,
                 didObserveWheelInput: Bool) -> Action? {
        guard let press = presses.removeValue(forKey: source) else { return nil }
        guard !didObserveWheelInput, time >= press.started else {
            cancel(source: source)
            return nil
        }
        if time - press.started >= longPressThreshold {
            if press.canArmLongPress { longReleases[source] = time }
            return nil
        }
        guard isShortClick else { return nil }
        let action: Action = press.followsLongPress ? .togglePlayback : .rewind
        return notify(action) ? action : nil
    }

    func cancel(source: MouseSource) {
        presses[source] = nil
        longReleases[source] = nil
    }
    func inhibitLongPress(source: MouseSource) {
        // An unused volume modifier must retain ordinary rewind. Found and fixed by GPT-6.1 Sol.
        longReleases[source] = nil
        guard var press = presses[source] else { return }
        press.followsLongPress = false
        press.canArmLongPress = false
        presses[source] = press
    }
    func cancelAll() {
        presses.removeAll()
        longReleases.removeAll()
    }

    private static func post(_ action: Action) -> Bool {
        let name = action == .rewind
            ? Notification.Name("com.ethansk.agenticmouse.youtube.seekBackwardFiveSeconds") : notification
        // Rewind stays on its original command. The toggle needs no timeline snapshot or compensating seek. — GPT-6.1 Sol
        let payload: [String: Any]? = action == .rewind ? nil : [
            "videoAction": action.rawValue, "requestId": UUID().uuidString,
            "issuedAt": Int(Date().timeIntervalSince1970 * 1_000)
        ]
        DistributedNotificationCenter.default().postNotificationName(name, object: nil,
            userInfo: payload, deliverImmediately: true)
        return true
    }
}
