import Foundation

protocol AutomaticTerminationControlling: AnyObject {
    var automaticTerminationSupportEnabled: Bool { get set }
    func disableAutomaticTermination(_ reason: String)
}

extension ProcessInfo: AutomaticTerminationControlling {}

/// Keeps the menu-bar runtime alive while it owns mouse input, HUD, and
/// lighting services. Launch-at-login starts the app once; it is not a
/// supervisor and cannot recover a process that AppKit auto-terminates later.
struct ApplicationRuntimeRetention {
    static let reason = "Agentic Mouse provides persistent mouse commands, HUD, and lighting"

    private(set) var isRetained = false

    mutating func retain(using controller: AutomaticTerminationControlling = ProcessInfo.processInfo) {
        guard !isRetained else { return }
        // Call this after AppKit finishes launching the menu-bar app so the
        // documented automatic-termination opt-out counter is held for the
        // complete runtime. LaunchServices' "WouldBeTerminated" diagnostic is
        // not an opt-out-counter readback: Accessibility requests can publish
        // that key even while this supported permanent opt-out is held.
        controller.automaticTerminationSupportEnabled = true
        controller.disableAutomaticTermination(Self.reason)
        isRetained = true
    }
}
