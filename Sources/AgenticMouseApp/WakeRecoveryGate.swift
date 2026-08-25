import Foundation

struct WakeRecoveryGate {
    let duplicateWindow: TimeInterval
    private(set) var lastRecoveryAt: TimeInterval?

    init(duplicateWindow: TimeInterval = 1) {
        self.duplicateWindow = duplicateWindow
    }

    mutating func shouldRecover(at now: TimeInterval) -> Bool {
        if let lastRecoveryAt, now - lastRecoveryAt < duplicateWindow {
            return false
        }
        lastRecoveryAt = now
        return true
    }
}
