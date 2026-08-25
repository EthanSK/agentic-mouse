import AppKit
import ScimitarKit

/// Delivers Codex's own configured keyboard shortcuts. Renderer-owned commands
/// can target the process without activation. Foreground Electron accelerators
/// use their individually proven system transport: System Events for Side Chat
/// and a hardware-shaped modifier lifecycle for realtime Voice Mode. A separate
/// session-security provider blocks every event while the macOS user session is
/// inactive.
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
    typealias FeedbackHandler = @MainActor (CodexActionFeedback) -> Void
    typealias QueuedMessageEditor = @MainActor () -> Result<Void, ActionError>
    typealias QueuedMessageEditorCanceller = @MainActor () -> Void

    static let hyper: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift,
    ]

    /// Microphone mute and reasoning-effort adjustment use dedicated, additive
    /// custom bindings. Every action with a Codex built-in uses that built-in
    /// directly; Agentic Mouse must never replace Ethan's keyboard map.
    static let microphoneShortcut = Shortcut(keyCode: 90, flags: hyper) // F20
    static let increaseReasoningEffortShortcut = Shortcut(keyCode: 79, flags: hyper) // F18
    static let decreaseReasoningEffortShortcut = Shortcut(keyCode: 80, flags: hyper) // F19
    static let newTaskShortcut = Shortcut(keyCode: 45, flags: .maskCommand)
    static let togglePinShortcut = Shortcut(
        keyCode: 35,
        flags: [.maskCommand, .maskAlternate]
    )
    static let openSideChatShortcut = Shortcut(
        // Ethan uses Dvorak - QWERTY Cmd. With Command+Option held, Codex's
        // semantic "S" accelerator is reached from the physical semicolon
        // position, not the QWERTY S position.
        keyCode: 41, // physical semicolon; logical S in this modifier/layout path
        flags: [.maskCommand, .maskAlternate]
    )
    static let realtimeVoiceShortcut = Shortcut(
        // `realtimeVoice` is an Electron OS-global accelerator. Carbon global
        // shortcuts match the accelerator's ANSI key position, so send the
        // physical V key with a complete Control/Shift modifier lifecycle.
        keyCode: 9,
        flags: [.maskControl, .maskShift]
    )
    static let steerQueuedMessageShortcut = Shortcut(
        keyCode: 36, // Return
        flags: .maskCommand
    )
    static let submitShortcut = Shortcut(keyCode: 36, flags: [])

    private let shortcutDispatcher: ApplicationShortcutDispatcher
    private let editQueuedMessage: QueuedMessageEditor
    private let cancelQueuedMessageEditor: QueuedMessageEditorCanceller
    private let pinChangeVerifier: CodexPinChangeVerifier
    private let voiceSessionVerifier: CodexVoiceSessionVerifier
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider
    private var isCodexAXJourneyInFlight = false

    init(
        targetProcessResolver: @escaping TargetProcessResolver = {
            let applications = NSRunningApplication.runningApplications(
                withBundleIdentifier: CodexMode.bundleIdentifier
            )
            return applications.first(where: { $0.isActive })?.processIdentifier
                ?? applications.first(where: { !$0.isTerminated })?.processIdentifier
        },
        postEvent: EventPoster? = nil,
        targetProcessIsActive: @escaping ApplicationShortcutDispatcher.TargetProcessIsActive = {
            NSRunningApplication(processIdentifier: $0)?.isActive == true
        },
        postSystemShortcut: ApplicationShortcutDispatcher.SystemShortcutPoster? = nil,
        postHardwareSystemShortcut: ApplicationShortcutDispatcher.HardwareSystemShortcutPoster? = nil,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping InputAllowedProvider = { true },
        editQueuedMessage: QueuedMessageEditor? = nil,
        cancelQueuedMessageEditor: QueuedMessageEditorCanceller? = nil,
        pinChangeVerifier: CodexPinChangeVerifier? = nil,
        voiceSessionVerifier: CodexVoiceSessionVerifier? = nil
    ) {
        self.shortcutDispatcher = ApplicationShortcutDispatcher(
            targetProcessResolver: { _ in targetProcessResolver() },
            postEvent: postEvent,
            targetProcessIsActive: targetProcessIsActive,
            postSystemShortcut: postSystemShortcut,
            postHardwareSystemShortcut: postHardwareSystemShortcut,
            accessibilityTrusted: accessibilityTrusted,
            inputAllowed: inputAllowed
        )
        if let editQueuedMessage {
            self.editQueuedMessage = editQueuedMessage
            self.cancelQueuedMessageEditor = cancelQueuedMessageEditor ?? {}
        } else {
            let queuedMessageSteerer = CodexQueuedMessageSteerer(
                targetProcessResolver: targetProcessResolver,
                accessibilityTrusted: accessibilityTrusted,
                inputAllowed: inputAllowed
            )
            self.editQueuedMessage = {
                queuedMessageSteerer.perform(.edit)
            }
            self.cancelQueuedMessageEditor = {
                queuedMessageSteerer.cancelPendingAction()
            }
        }
        self.pinChangeVerifier = pinChangeVerifier ?? CodexPinChangeVerifier()
        let voiceStateReader = CodexVoiceSessionStateReader()
        self.voiceSessionVerifier = voiceSessionVerifier ?? CodexVoiceSessionVerifier(
            readState: { voiceStateReader.read() },
            inputAllowed: inputAllowed,
            accessibilityTrusted: accessibilityTrusted
        )
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
    }

    func perform(
        _ action: CodexModeAction,
        feedback: FeedbackHandler? = nil
    ) -> Result<Void, ActionError> {
        guard inputAllowed() else {
            return .failure(ActionError(
                description: "Mouse commands are disabled while macOS is locked"
            ))
        }
        guard accessibilityTrusted() else {
            return .failure(ActionError(
                description: "Accessibility permission is required for Codex shortcuts"
            ))
        }
        if (action == .toggleVoiceMode || action == .editQueuedMessage),
           isCodexAXJourneyInFlight {
            return .failure(ActionError(
                description: "Another Codex Accessibility action is already in progress"
            ))
        }
        let ownsAXJourney = action == .editQueuedMessage
        if ownsAXJourney { isCodexAXJourneyInFlight = true }
        defer {
            if ownsAXJourney { isCodexAXJourneyInFlight = false }
        }
        let rapidPinRetoggle = action == .togglePin && pinChangeVerifier.isVerificationPending
        if rapidPinRetoggle {
            pinChangeVerifier.cancelPendingVerification()
        }
        let pinStateBeforeDispatch = action == .togglePin
            ? pinChangeVerifier.captureBeforeDispatch()
            : nil
        let voiceStateBeforeDispatch = action == .toggleVoiceMode
            ? voiceSessionVerifier.captureBeforeDispatch()
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
            result = postForegroundHardwareShortcut(Self.realtimeVoiceShortcut)
        case .openSideChat:
            result = postForegroundShortcut(Self.openSideChatShortcut)
        case .steerQueuedMessage:
            result = postShortcut(Self.steerQueuedMessageShortcut)
        case .editQueuedMessage:
            result = editQueuedMessage()
        case .pressEnter:
            result = postShortcut(Self.submitShortcut)
        }

        guard case .success = result, let feedback else { return result }
        if action == .togglePin {
            voiceSessionVerifier.cancelPendingVerification()
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
        } else if action == .toggleVoiceMode {
            pinChangeVerifier.cancelPendingVerification()
            guard let voiceStateBeforeDispatch else {
                feedback(.notConfirmed(
                    "Voice mode shortcut sent — Codex state was not observable"
                ))
                return result
            }
            feedback(.checking("Voice mode shortcut sent — checking Codex state"))
            voiceSessionVerifier.verify(from: voiceStateBeforeDispatch, completion: feedback)
        } else if action == .editQueuedMessage {
            pinChangeVerifier.cancelPendingVerification()
            voiceSessionVerifier.cancelPendingVerification()
            feedback(.sentUnverified("\(action.title) pressed — result not confirmed by Codex"))
        } else {
            pinChangeVerifier.cancelPendingVerification()
            voiceSessionVerifier.cancelPendingVerification()
            feedback(.sentUnverified("\(action.title) sent — result not exposed by Codex"))
        }
        return result
    }

    func cancelPendingActions() {
        cancelPendingVerifications()
        cancelQueuedMessageEdit()
    }

    func cancelPendingVerifications() {
        pinChangeVerifier.cancelPendingVerification()
        voiceSessionVerifier.cancelPendingVerification()
    }

    func cancelQueuedMessageEdit() {
        cancelQueuedMessageEditor()
    }

    func performReasoningEffort(
        _ action: CodexReasoningEffortAction
    ) -> Result<Void, ActionError> {
        postShortcut(
            action == .increase
                ? Self.increaseReasoningEffortShortcut
                : Self.decreaseReasoningEffortShortcut
        )
    }

    func performChatHistory(
        _ action: CodexChatHistoryAction
    ) -> Result<Void, ActionError> {
        let shortcut = Shortcut(
            keyCode: action == .forward ? 124 : 123,
            flags: [.maskCommand, .maskAlternate]
        )
        return postShortcut(shortcut)
    }

    private func postShortcut(_ shortcut: Shortcut) -> Result<Void, ActionError> {
        shortcutDispatcher.perform(
            shortcut,
            targetBundleIdentifier: CodexMode.bundleIdentifier,
            targetDisplayName: "Codex"
        )
    }

    private func postForegroundShortcut(_ shortcut: Shortcut) -> Result<Void, ActionError> {
        shortcutDispatcher.performForegroundSystemShortcut(
            shortcut,
            targetBundleIdentifier: CodexMode.bundleIdentifier,
            targetDisplayName: "Codex"
        )
    }

    private func postForegroundHardwareShortcut(
        _ shortcut: Shortcut
    ) -> Result<Void, ActionError> {
        shortcutDispatcher.performForegroundHardwareShortcut(
            shortcut,
            targetBundleIdentifier: CodexMode.bundleIdentifier,
            targetDisplayName: "Codex"
        )
    }
}
