import AppKit
import CodexNativeControls
import Darwin
import ScimitarKit

/// Delivers Codex's own configured keyboard shortcuts. Renderer-owned commands
/// can target the process without activation. Foreground Electron accelerators
/// use their individually proven system transport, while Voice Mode uses its
/// dedicated app-scoped command binding. A separate session-security provider
/// blocks every event while the macOS user session is inactive.
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
    static let hyper: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift,
    ]

    /// Dedicated, additive bindings leave the ordinary keyboard map intact.
    /// Chat navigation must not share Codex's Next/Previous Tab accelerators:
    /// those route to an open side panel before the main sidebar.
    static let previousChatShortcut = Shortcut(keyCode: 105, flags: hyper) // F13
    static let nextChatShortcut = Shortcut(keyCode: 107, flags: hyper) // F14
    static let microphoneShortcut = Shortcut(keyCode: 90, flags: hyper) // F20
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
    static let closeTabShortcut = Shortcut(keyCode: 13, flags: .maskCommand) // Command-W
    static let voiceModeShortcut = Shortcut(keyCode: 64, flags: hyper) // Codex's configured "Toggle voice chat", delivered privately like Ethan's HeyChat.
    static let submitShortcut = Shortcut(keyCode: 36, flags: [])

    private let shortcutDispatcher: ApplicationShortcutDispatcher
    private let voiceShortcutDispatcher: ApplicationShortcutDispatcher
    private let pinChangeVerifier: CodexPinChangeVerifier
    private let voiceSessionVerifier: CodexVoiceSessionVerifier
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider
    private let requestResponseSpeed: @MainActor (CodexResponseSpeedAction) -> Bool
    private let requestReasoningEffort: @MainActor (CodexReasoningEffortAction) -> Bool
    private let cancelReasoningRequest: @MainActor () -> Bool
    private var responseSpeedPending = false
    private var reasoningEffortPending = false

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
        pinChangeVerifier: CodexPinChangeVerifier? = nil,
        voiceSessionVerifier: CodexVoiceSessionVerifier? = nil,
        requestResponseSpeed: (@MainActor (CodexResponseSpeedAction) -> Bool)? = nil,
        requestReasoningEffort: (@MainActor (CodexReasoningEffortAction) -> Bool)? = nil,
        cancelReasoningRequest: (@MainActor () -> Bool)? = nil,
        requestNativeCommand: (@MainActor (CodexShortcuts.Command) -> Bool)? = nil,
        adjustmentFeedback: @escaping CodexMouseAdjustment.Feedback = { _, _ in },
        recentHardwareTyping: @escaping @MainActor () -> Bool = {
            CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown) < 1.0
        }
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
        let voiceEventSource = CGEventSource(stateID: .privateState)
        self.voiceShortcutDispatcher = ApplicationShortcutDispatcher(
            targetProcessResolver: { _ in targetProcessResolver() },
            postEvent: postEvent ?? { pid, keyCode, flags, isDown in
                guard let voiceEventSource, let event = Self.voiceKeyboardEvent(
                    source: voiceEventSource, keyCode: keyCode, flags: flags, isDown: isDown
                ) else { return false }
                event.postToPid(pid)
                return true
            },
            accessibilityTrusted: accessibilityTrusted,
            inputAllowed: inputAllowed
        )
        self.pinChangeVerifier = pinChangeVerifier ?? CodexPinChangeVerifier()
        let voiceStateReader = CodexVoiceSessionStateReader()
        self.voiceSessionVerifier = voiceSessionVerifier ?? CodexVoiceSessionVerifier(
            readState: { voiceStateReader.read() },
            inputAllowed: inputAllowed,
            accessibilityTrusted: accessibilityTrusted
        )
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
        // Ethan: Mouse "shouldn't have a dependency on the bar". Both apps
        // embed this one shared focus/shortcut engine; no URL handler or other
        // running companion participates. Keep the live lock/trust gates active
        // after admission, including while background focus work is queued.
        let adjustment = CodexMouseAdjustment { family, feedback in
            guard inputAllowed(), accessibilityTrusted() else { return }
            adjustmentFeedback(family, feedback)
        }
        let native = CodexShortcutController(
            inputAllowed: { MainActor.assumeIsolated { inputAllowed() && accessibilityTrusted() } },
            performer: { command, _, codex, started, isCurrent in
                adjustment.perform(command, codex: codex, started: started, isCurrent: isCurrent)
            }
        )
        let postNative: @MainActor (CodexShortcuts.Command) -> Bool = requestNativeCommand ?? { command in
            guard let pid = targetProcessResolver(),
                  let codex = NSRunningApplication(processIdentifier: pid),
                  CodexShortcuts.load(command) != nil else { return false }
            native.change(command, source: .mouse, codex: codex) { result in
                guard inputAllowed(), accessibilityTrusted(), case .failed(let message) = result else { return }
                let family: CodexShortcutController.Family = command == .cycleSpeed ? .speed : .reasoning
                adjustmentFeedback(family, .notConfirmed(message))
            }
            return true // Completion is reported after a Codex-owned setting read.
        }
        let sendNative: @MainActor (CodexShortcuts.Command) -> Bool = { command in
            // Retain the existing reasoning path's one-second recent-typing
            // protection. New hardware input after admission is also checked
            // by the shared controller before any native key is posted.
            guard command == .cycleSpeed || !recentHardwareTyping() else { return false }
            return postNative(command)
        }
        self.requestResponseSpeed = requestResponseSpeed ?? { action in
            if action == .cancel { native.cancelMouse(.speed); return true }
            return sendNative(.cycleSpeed) // One native forward cycle in either wheel direction.
        }
        self.requestReasoningEffort = requestReasoningEffort ?? { action in
            sendNative(action == .increase ? .increaseReasoning : .decreaseReasoning)
        }
        self.cancelReasoningRequest = cancelReasoningRequest ?? {
            native.cancelMouse(.reasoning); return true
        }
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
            result = voiceShortcutDispatcher.perform(
                Self.voiceModeShortcut,
                targetBundleIdentifier: CodexMode.bundleIdentifier,
                targetDisplayName: "Codex"
            )
        case .openSideChat:
            result = postForegroundShortcut(Self.openSideChatShortcut)
        case .closeTab:
            result = postForegroundShortcut(Self.closeTabShortcut)
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
        } else {
            pinChangeVerifier.cancelPendingVerification()
            voiceSessionVerifier.cancelPendingVerification()
            feedback(.sentUnverified("\(action.title) sent — result not exposed by Codex"))
        }
        return result
    }

    func cancelPendingActions() {
        cancelResponseSpeed()
        cancelReasoningEffort()
        cancelPendingVerifications()
    }

    func cancelReasoningEffort() {
        guard reasoningEffortPending else { return }
        reasoningEffortPending = false
        // Release and teardown cancel only queued ratchets, including after lock.
        _ = cancelReasoningRequest()
    }

    func cancelResponseSpeed() {
        guard responseSpeedPending else { return }
        responseSpeedPending = false
        // This is cancellation only, so it remains safe after the lock gate
        // closes. An unused click must never launch the external handler.
        _ = requestResponseSpeed(.cancel)
    }

    func cancelPendingVerifications() {
        pinChangeVerifier.cancelPendingVerification()
        voiceSessionVerifier.cancelPendingVerification()
    }

    /// Ethan: "just click the speed button". Use the existing completed-hold
    /// record: any wheel input suppresses the click, including consumed input.
    /// Teardown never produces a release, and the wand keeps its existing path.
    func performResponseSpeedClick(_ release: WheelChordStateMachine.Release) -> Result<Void, ActionError>? {
        guard release.control == .codexResponseSpeed, release.source != .wand,
              !release.didObserveWheelInput else { return nil }
        return performResponseSpeed(.increase) // Both directions already mean one native forward cycle.
    }

    func performResponseSpeed(_ action: CodexResponseSpeedAction) -> Result<Void, ActionError> {
        guard inputAllowed() else {
            return .failure(ActionError(description: "Mouse commands are disabled while macOS is locked"))
        }
        guard accessibilityTrusted() else {
            return .failure(ActionError(description: "Accessibility permission is required for Codex shortcuts"))
        }
        guard requestResponseSpeed(action) else {
            return .failure(ActionError(description: "Could not deliver the Codex shortcut"))
        }
        responseSpeedPending = true
        return .success(())
    }

    func performReasoningEffort(
        _ action: CodexReasoningEffortAction
    ) -> Result<Void, ActionError> {
        guard inputAllowed() else {
            return .failure(ActionError(description: "Mouse commands are disabled while macOS is locked"))
        }
        guard accessibilityTrusted() else {
            return .failure(ActionError(description: "Accessibility permission is required for Codex shortcuts"))
        }
        guard requestReasoningEffort(action) else {
            return .failure(ActionError(description: "Could not deliver the Codex shortcut"))
        }
        reasoningEffortPending = true
        return .success(())
    }

    func performChatHistory(
        _ action: CodexChatHistoryAction
    ) -> Result<Void, ActionError> {
        postShortcut(
            action == .forward
                ? Self.nextChatShortcut
                : Self.previousChatShortcut
        )
    }

    private func postShortcut(_ shortcut: Shortcut) -> Result<Void, ActionError> {
        shortcutDispatcher.perform(
            shortcut,
            targetBundleIdentifier: CodexMode.bundleIdentifier,
            targetDisplayName: "Codex"
        )
    }

    /// HeyChat's established pattern: private event state, fresh timestamps,
    /// then postToPid. Never broadcast Voice's modifier chord to global
    /// recorders, and never alter the transport of other Codex shortcuts.
    static func voiceKeyboardEvent(
        source: CGEventSource, keyCode: CGKeyCode, flags: CGEventFlags, isDown: Bool
    ) -> CGEvent? {
        guard let event = CGEvent(
                keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown
              ) else { return nil }
        event.flags = flags
        event.timestamp = mach_absolute_time()
        return event
    }

    private func postForegroundShortcut(_ shortcut: Shortcut) -> Result<Void, ActionError> {
        shortcutDispatcher.performForegroundSystemShortcut(
            shortcut,
            targetBundleIdentifier: CodexMode.bundleIdentifier,
            targetDisplayName: "Codex"
        )
    }

}
