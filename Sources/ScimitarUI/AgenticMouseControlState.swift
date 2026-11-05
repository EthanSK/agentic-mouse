import AppKit
import Combine
import ScimitarKit

/// One runtime snapshot feeds the app window. It contains safe status values,
/// never device identifiers, passwords, command payloads or environment data.
public struct AgenticMouseControlSnapshot {
    public var sessionReady = false
    public var accessibilityGranted = false
    public var commandsReady = false
    public var wheelReady = false
    public var corsairConnected = false
    public var razerConnected = false
    public var recovery = "unknown"
    public var icue = "unknown"
    public var passwordConfigured = false
    public var corsairLegend = false
    public var razerLegend = false
    public var corsairMode: String?
    public var razerMode: String?
    public var corsairAccent: ScimitarKit.RGBColor?
    public var razerAccent: ScimitarKit.RGBColor?
    public var warnings: [String] = []
    public var version = AgenticMouseVersion.displayString()

    public init() {}

    public enum Health: Equatable { case paused, working, attention, unavailable }
    public var health: Health {
        if !sessionReady { return .paused }
        if !accessibilityGranted || !commandsReady || !wheelReady { return .unavailable }
        if (!corsairConnected && !razerConnected) || recovery != "enabled" { return .attention }
        return .working
    }

    public var headline: String {
        switch health {
        case .paused: return "Paused"
        case .working: return "Working"
        case .attention: return "Needs attention"
        case .unavailable: return "Not working"
        }
    }

    public var issue: String? {
        if !sessionReady { return "Move the pointer to start" }
        if !accessibilityGranted { return "Accessibility is off" }
        if !commandsReady { return "Mouse commands unavailable" }
        if !wheelReady { return "Wheel actions unavailable" }
        if recovery != "enabled" { return "Keep running: \(recovery)" }
        if !corsairConnected && !razerConnected { return "No mouse connected" }
        return nil
    }

    public var summary: String {
        if let issue { return issue }
        if corsairConnected && razerConnected { return "Corsair and Razer connected" }
        return corsairConnected ? "Corsair connected" : "Razer connected"
    }
}

@MainActor
public final class AgenticMouseControlState: ObservableObject {
    @Published public var snapshot = AgenticMouseControlSnapshot()
    public var onLegend: (MouseSource) -> Void = { _ in }
    public var onExitMode: (MouseSource) -> Void = { _ in }
    public var onSetPassword: () -> Void = {}
    public var onClearPassword: () -> Void = {}
    public var onReload: () -> Void = {}
    public var onRetryRecovery: () -> Void = {}
    public var onLoginItems: () -> Void = {}
    public var onAccessibility: () -> Void = {}
    public var onRevealConfiguration: () -> Void = {}
    public init() {}
}
