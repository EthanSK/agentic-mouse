import AppKit
import ScimitarKit

/// Delivers Codex's own configured keyboard shortcuts directly to its process.
/// `CGEvent.postToPid` lets an app-specific Codex submenu target the background
/// process without bringing Codex to the front. A separate session-security
/// provider blocks every event while the macOS user session is inactive.
@MainActor
final class CodexModeActionExecutor {
    typealias ActionError = ApplicationShortcutDispatcher.DispatchError
    typealias Shortcut = ApplicationShortcutDispatcher.Shortcut

    typealias TargetProcessResolver = @MainActor () -> pid_t?
    typealias EventPoster = @MainActor (
        _ pid: pid_t,
        _ keyCode: CGKeyCode,
        _ flags: CGEventFlags,
        _ isDown: Bool
    ) -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool
    typealias InputAllowedProvider = @MainActor () -> Bool
    typealias DelayedActionScheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @Sendable @MainActor () -> Void
    ) -> Void
    typealias FeedbackHandler = @MainActor (CodexActionFeedback) -> Void

    static let hyper: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift,
    ]

    /// Microphone mute and reasoning-effort adjustment use dedicated, additive
    /// custom bindings. Every action with a Codex built-in uses that built-in
    /// directly; Agentic Mouse must never replace Ethan's keyboard map.
    static let microphoneShortcut = Shortcut(keyCode: 90, flags: hyper) // F20
    static let increaseReasoningEffortShortcut = Shortcut(keyCode: 79, flags: hyper) // F18
    static let decreaseReasoningEffortShortcut = Shortcut(keyCode: 80, flags: hyper) // F19
    static let steerShortcut = Shortcut(
        keyCode: 36,
        flags: [.maskCommand, .maskShift]
    )
    static let newTaskShortcut = Shortcut(keyCode: 45, flags: .maskCommand)
    static let togglePinShortcut = Shortcut(
        keyCode: 35,
        flags: [.maskCommand, .maskAlternate]
    )
    static let startVoiceShortcut = Shortcut(keyCode: 64, flags: hyper) // F17
    static let submitShortcut = Shortcut(keyCode: 36, flags: [])

    private let shortcutDispatcher: ApplicationShortcutDispatcher
    private let scheduleDelayedAction: DelayedActionScheduler
    private let pinChangeVerifier: CodexPinChangeVerifier

    init(
        targetProcessResolver: @escaping TargetProcessResolver = {
            let applications = NSRunningApplication.runningApplications(
                withBundleIdentifier: CodexMode.bundleIdentifier
            )
            return applications.first(where: { $0.isActive })?.processIdentifier
                ?? applications.first(where: { !$0.isTerminated })?.processIdentifier
        },
        postEvent: EventPoster? = nil,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping InputAllowedProvider = { true },
        pinChangeVerifier: CodexPinChangeVerifier? = nil,
        scheduleDelayedAction: @escaping DelayedActionScheduler = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    ) {
        self.shortcutDispatcher = ApplicationShortcutDispatcher(
            targetProcessResolver: { _ in targetProcessResolver() },
            postEvent: postEvent,
            accessibilityTrusted: accessibilityTrusted,
            inputAllowed: inputAllowed
        )
        self.pinChangeVerifier = pinChangeVerifier ?? CodexPinChangeVerifier()
        self.scheduleDelayedAction = scheduleDelayedAction
    }

    func perform(
        _ action: CodexModeAction,
        feedback: FeedbackHandler? = nil
    ) -> Result<Void, ActionError> {
        let rapidPinRetoggle = action == .togglePin && pinChangeVerifier.isVerificationPending
        if rapidPinRetoggle {
            pinChangeVerifier.cancelPendingVerification()
        }
        let pinStateBeforeDispatch = action == .togglePin
            ? pinChangeVerifier.captureBeforeDispatch()
            : nil
        let result: Result<Void, ActionError>
        switch action {
        case .newTask:
            result = postShortcut(Self.newTaskShortcut)
        case .togglePin:
            result = postShortcut(Self.togglePinShortcut)
        case .toggleMicrophoneMute:
            result = postShortcut(Self.microphoneShortcut)
        case .toggleVoiceMode:
            result = postShortcut(Self.startVoiceShortcut)
        case .steerQueuedMessage:
            // Ethan's follow-up mode is Queue. Codex documents
            // Command-Shift-Return as the one-message inverse: Steer.
            result = postShortcut(Self.steerShortcut)
        case .pressEnter:
            result = postShortcut(Self.submitShortcut)
        case .startNewVoiceChat:
            guard case .success = postShortcut(Self.newTaskShortcut) else {
                return .failure(ActionError(description: "Could not create a new Codex task"))
            }
            // A new empty Codex task is not mounted synchronously. Wait for its
            // composer before invoking Codex's built-in voice-mode shortcut.
            scheduleDelayedAction(0.75) { [weak self] in
                _ = self?.postShortcut(Self.startVoiceShortcut)
            }
            result = .success(())
        case .increaseReasoningEffort:
            result = postShortcut(Self.increaseReasoningEffortShortcut)
        case .decreaseReasoningEffort:
            result = postShortcut(Self.decreaseReasoningEffortShortcut)
        }

        guard case .success = result, let feedback else { return result }
        if action == .togglePin {
            if rapidPinRetoggle {
                feedback(.sentUnverified("Rapid pin toggle sent — confirmation cancelled"))
                return result
            }
            guard let pinStateBeforeDispatch else {
                feedback(.sentUnverified("Pin shortcut sent — confirmation unavailable"))
                return result
            }
            feedback(.checking("Pin change sent — checking Codex state"))
            pinChangeVerifier.verify(from: pinStateBeforeDispatch, completion: feedback)
        } else {
            pinChangeVerifier.cancelPendingVerification()
            feedback(.sentUnverified("\(action.title) sent — result not exposed by Codex"))
        }
        return result
    }

    private func postShortcut(_ shortcut: Shortcut) -> Result<Void, ActionError> {
        shortcutDispatcher.perform(
            shortcut,
            targetBundleIdentifier: CodexMode.bundleIdentifier,
            targetDisplayName: "Codex"
        )
    }
}
