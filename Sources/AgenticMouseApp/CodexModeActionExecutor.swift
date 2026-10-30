import AppKit
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
    static let closeTabShortcut = Shortcut(keyCode: 13, flags: .maskCommand) // Command-W
    static let voiceModeShortcut = Shortcut(keyCode: 64, flags: hyper) // Hello Chat parity: composer.startVoiceMode toggles native Voice; physical mice use the same chord through Karabiner.
    static let submitShortcut = Shortcut(keyCode: 36, flags: [])

    private let shortcutDispatcher: ApplicationShortcutDispatcher
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
        requestResponseSpeed: @escaping @MainActor (CodexResponseSpeedAction) -> Bool = { action in
            CodexModeActionExecutor.sendResponseSpeedRequest(action)
        },
        requestReasoningEffort: @escaping @MainActor (CodexReasoningEffortAction) -> Bool = { action in
            CodexModeActionExecutor.sendModelBarRequest(action.modelBarURL)
        },
        cancelReasoningRequest: @escaping @MainActor () -> Bool = {
            CodexModeActionExecutor.sendModelBarRequest(URL(string: "codex-model-bar://reasoning-cancel")!)
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
        self.pinChangeVerifier = pinChangeVerifier ?? CodexPinChangeVerifier()
        let voiceStateReader = CodexVoiceSessionStateReader()
        self.voiceSessionVerifier = voiceSessionVerifier ?? CodexVoiceSessionVerifier(
            readState: { voiceStateReader.read() },
            inputAllowed: inputAllowed,
            accessibilityTrusted: accessibilityTrusted
        )
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
        self.requestResponseSpeed = requestResponseSpeed
        self.requestReasoningEffort = requestReasoningEffort
        self.cancelReasoningRequest = cancelReasoningRequest
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
            result = postShortcut(Self.voiceModeShortcut)
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

    func performResponseSpeed(_ action: CodexResponseSpeedAction) -> Result<Void, ActionError> {
        guard inputAllowed() else {
            return .failure(ActionError(description: "Mouse commands are disabled while macOS is locked"))
        }
        guard accessibilityTrusted() else {
            return .failure(ActionError(description: "Accessibility permission is required for Codex shortcuts"))
        }
        guard requestResponseSpeed(action) else {
            return .failure(ActionError(description: "Could not open Codex Model Bar"))
        }
        responseSpeedPending = true
        return .success(())
    }

    /// Opening a custom URL with `open(URL)` activates its handler and steals
    /// the composer's focus. Keep this relay in the background; Model Bar owns
    /// the one whole-command insertion and the guarded Enter, without retries.
    static func sendResponseSpeedRequest(
        _ action: CodexResponseSpeedAction,
        resolveHandler: (URL) -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: $0) },
        open: ([URL], URL, NSWorkspace.OpenConfiguration) -> Void = { urls, application, configuration in
            NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: configuration)
        }
    ) -> Bool {
        sendModelBarRequest(action.modelBarURL, resolveHandler: resolveHandler, open: open)
    }

    /// Extraction of the existing sendResponseSpeedRequest background relay.
    /// Ethan's speed and reasoning controls now both use Model Bar's own focus
    /// code; Agentic Mouse never copies its composer lookup or sends reasoning keys.
    static func sendModelBarRequest(
        _ url: URL,
        resolveHandler: (URL) -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: $0) },
        open: ([URL], URL, NSWorkspace.OpenConfiguration) -> Void = { urls, application, configuration in
            NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: configuration)
        }
    ) -> Bool {
        guard let application = resolveHandler(url) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.promptsUserIfNeeded = false
        configuration.addsToRecentItems = false
        open([url], application, configuration)
        return true
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
            return .failure(ActionError(description: "Could not open Codex Model Bar"))
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

    private func postForegroundShortcut(_ shortcut: Shortcut) -> Result<Void, ActionError> {
        shortcutDispatcher.performForegroundSystemShortcut(
            shortcut,
            targetBundleIdentifier: CodexMode.bundleIdentifier,
            targetDisplayName: "Codex"
        )
    }

}
