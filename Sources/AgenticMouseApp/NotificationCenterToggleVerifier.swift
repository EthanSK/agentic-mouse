import AppKit
import CoreGraphics

/// Verifies the public WindowServer state change produced by macOS's Fn-N
/// shortcut. Posting an event is not proof that Notification Centre handled it.
@MainActor
final class NotificationCenterToggleVerifier {
    private struct ScheduledAction: @unchecked Sendable {
        let run: @MainActor () -> Void
    }

    enum Outcome: Equatable {
        case opened
        case closed
        case unchanged
        case unavailable
    }

    typealias VisibilityProvider = @MainActor () -> Bool?
    typealias Scheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> Void

    private let visibility: VisibilityProvider
    private let scheduler: Scheduler
    private var generation: UInt64 = 0

    init(
        visibility: @escaping VisibilityProvider = NotificationCenterWindowDetector.isVisible,
        scheduler: @escaping Scheduler = { delay, action in
            let scheduled = ScheduledAction(run: action)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { scheduled.run() }
            }
        }
    ) {
        self.visibility = visibility
        self.scheduler = scheduler
    }

    func captureBeforeToggle() -> Bool? {
        visibility()
    }

    func verifyToggle(
        from previousVisibility: Bool?,
        completion: @escaping @MainActor (Outcome) -> Void
    ) {
        generation &+= 1
        let requestedGeneration = generation
        guard let previousVisibility else {
            completion(.unavailable)
            return
        }

        verify(
            previousVisibility: previousVisibility,
            requestedGeneration: requestedGeneration,
            delays: [0.28, 0.72],
            completion: completion
        )
    }

    func cancel() {
        generation &+= 1
    }

    private func verify(
        previousVisibility: Bool,
        requestedGeneration: UInt64,
        delays: ArraySlice<TimeInterval>,
        completion: @escaping @MainActor (Outcome) -> Void
    ) {
        guard let delay = delays.first else {
            completion(.unchanged)
            return
        }
        scheduler(delay) { [weak self] in
            guard let self, self.generation == requestedGeneration else { return }
            guard let currentVisibility = self.visibility() else {
                completion(.unavailable)
                return
            }
            if currentVisibility != previousVisibility {
                completion(currentVisibility ? .opened : .closed)
                return
            }
            self.verify(
                previousVisibility: previousVisibility,
                requestedGeneration: requestedGeneration,
                delays: delays.dropFirst(),
                completion: completion
            )
        }
    }
}

enum NotificationCenterWindowDetector {
    typealias WindowInfo = [String: Any]

    static func isVisible() -> Bool? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [WindowInfo] else {
            return nil
        }
        return isVisible(in: windows)
    }

    static func isVisible(in windows: [WindowInfo]) -> Bool {
        windows.contains { info in
            guard isNotificationCenterOwner(info),
                  number(info[kCGWindowLayer as String]).map({ $0 >= 0 }) == true,
                  number(info[kCGWindowAlpha as String]).map({ $0 > 0.01 }) != false,
                  let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(
                      dictionaryRepresentation: boundsDictionary as CFDictionary
                  ),
                  bounds.width >= 250,
                  bounds.height >= 250
            else { return false }
            return true
        }
    }

    private static func isNotificationCenterOwner(_ info: WindowInfo) -> Bool {
        if let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
           let application = NSRunningApplication(
               processIdentifier: pid_t(pidNumber.int32Value)
           ),
           application.bundleIdentifier == "com.apple.notificationcenterui" {
            return true
        }

        let owner = (info[kCGWindowOwnerName as String] as? String)?
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return owner == "notification center" || owner == "notification centre"
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
