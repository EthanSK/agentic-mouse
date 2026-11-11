import AppKit
import ApplicationServices
import CodexModelBarCore
import CodexNativeControls

/// The mouse borrows focus once per burst. The shared shortcut controller owns
/// request admission and cancellation. All mutable state below lives on its AX queue.
final class CodexMouseAdjustment {
    struct Burst {
        private var lastStep: TimeInterval?

        mutating func begins(at time: TimeInterval) -> Bool {
            let begins = lastStep.map { time - $0 >= 5 } ?? true
            lastStep = time
            return begins
        }
    }

    private struct Target {
        let pid: pid_t
        let window: AXUIElement
        let windowTitle: String
        let composer: AXUIElement
        let modelButton: AXUIElement?
        let models: [CodexModel]

        var windowIsCurrent: Bool {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let current: AXUIElement = CodexAX.attribute(
                    AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute
                  )
            else { return false }
            return CFEqual(current, window) && CodexAX.title(current) == windowTitle
        }

        var hasFocus: Bool {
            windowIsCurrent && CodexComposerFocus.hasFocus(composer, pid: pid)
        }
    }

    private struct Observation: Equatable {
        let model: String?
        let value: String
    }

    typealias Feedback = @MainActor (CodexShortcutController.Family, CodexActionFeedback) -> Void
    private let feedback: Feedback
    private var burst = Burst()
    private var target: Target?
    private var verificationGeneration: [CodexShortcutController.Family: Int] = [:]

    init(feedback: @escaping Feedback) {
        self.feedback = feedback
    }

    func perform(
        _ command: CodexShortcuts.Command, codex: NSRunningApplication,
        started: TimeInterval, isCurrent: () -> Bool
    ) -> CodexShortcutController.Result {
        let startsBurst = burst.begins(at: started)
        if startsBurst { target = nil }
        guard isCurrent(), !Self.userInteracted(since: started) else { return .cancelledForTyping }
        guard let shortcut = CodexShortcuts.load(command) else {
            return .failed("Codex shortcut is unassigned")
        }
        if startsBurst {
            guard let intended = Self.resolveTarget(pid: codex.processIdentifier, isCurrent: isCurrent),
                  Self.focus(intended, codex: codex, canFocus: {
                      isCurrent() && !Self.userInteracted(since: started)
                  })
            else { return .failed("Could not focus the Codex chat") }
            target = intended
        }
        guard let target, target.pid == codex.processIdentifier, target.hasFocus else {
            return .failed("Codex chat focus changed")
        }

        let family: CodexShortcutController.Family = command == .cycleSpeed ? .speed : .reasoning
        let before = Self.read(family, in: target)
        guard CodexNativeKey.post(shortcut, pid: target.pid, canPost: {
            isCurrent() && !Self.userInteracted(since: started) && target.hasFocus
        }) else {
            return isCurrent() ? .failed("Codex chat focus changed") : .cancelled
        }
        // Read back on the AX queue without occupying it between polls. Further
        // ratchets can proceed while Codex is updating its setting.
        verificationGeneration[family, default: 0] += 1
        let generation = verificationGeneration[family, default: 0]
        verify(family, target: target, before: before, generation: generation,
               started: started, deadline: ProcessInfo.processInfo.systemUptime + 1)
        return .requested
    }

    private func verify(
        _ family: CodexShortcutController.Family, target: Target,
        before: Observation?, generation: Int, started: TimeInterval, deadline: TimeInterval
    ) {
        CodexAX.queue.asyncAfter(deadline: .now() + .milliseconds(75)) { [weak self] in
            guard let self, self.verificationGeneration[family] == generation else { return }
            let name = family == .speed ? "speed" : "reasoning effort"
            guard !Self.userInteracted(since: started), target.hasFocus else { return }
            if let before, let after = Self.read(family, in: target),
               before.model == after.model, before.value != after.value {
                let message = family == .speed ? "Codex saved \(after.value) speed" : "Reasoning effort set to \(after.value)"
                self.report(family, .confirmed(message))
            } else if before == nil || ProcessInfo.processInfo.systemUptime >= deadline {
                self.report(family, .notConfirmed("Could not confirm Codex \(name)"))
            } else {
                self.verify(family, target: target, before: before, generation: generation,
                            started: started, deadline: deadline)
            }
        }
    }

    private func report(_ family: CodexShortcutController.Family, _ result: CodexActionFeedback) {
        DispatchQueue.main.async { self.feedback(family, result) }
    }

    private static func focus(
        _ target: Target, codex: NSRunningApplication, canFocus: () -> Bool
    ) -> Bool {
        if target.hasFocus { return canFocus() }
        let selection: AXValue? = CodexAX.attribute(target.composer, kAXSelectedTextRangeAttribute)
        guard CodexInputFocus.activate(codex, canFocus: canFocus) else { return false }
        if !target.windowIsCurrent {
            guard canFocus(), codex.isActive,
                  AXUIElementPerformAction(target.window, kAXRaiseAction as CFString) == .success,
                  CodexControlWait.until(timeout: 0.25, { canFocus() && target.windowIsCurrent })
            else { return false }
        }
        guard CodexInputFocus.focus(target.composer, pid: target.pid, placeCaret: false,
                                   canFocus: { canFocus() && target.windowIsCurrent }),
              canFocus(), target.hasFocus
        else { return false }
        if let selection {
            guard let current: AXValue = CodexAX.attribute(target.composer, kAXSelectedTextRangeAttribute)
            else { return false }
            if !CFEqual(selection, current) {
                guard canFocus(), target.hasFocus,
                      AXUIElementSetAttributeValue(target.composer, kAXSelectedTextRangeAttribute as CFString,
                                                   selection) == .success,
                      let restored: AXValue = CodexAX.attribute(target.composer, kAXSelectedTextRangeAttribute),
                      CFEqual(selection, restored)
                else { return false }
            }
        }
        return target.hasFocus
    }

    private static func resolveTarget(pid: pid_t, isCurrent: () -> Bool) -> Target? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        CodexAX.enableWebAccessibility(pid: pid)
        guard let window = CodexAX.focusedWindow(pid: pid), isCurrent() else { return nil }

        let models = (try? Data(contentsOf: codexDirectory.appendingPathComponent("models_cache.json")))
            .map(CodexModelParsing.parseModelsCache) ?? []
        let focused: AXUIElement? = CodexAX.attribute(app, kAXFocusedUIElementAttribute)
        let sharedInput = CodexComposerFocus.focusedInput(in: window)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.6
        let locator = ComposerLocator<AXUIElement>(
            children: CodexAX.children, parent: CodexAX.parent,
            isTextArea: { CodexAX.role($0) == kAXTextAreaRole },
            isModelButton: {
                CodexAX.role($0) == kAXPopUpButtonRole
                    && CurrentModelMatcher.isModelButtonTitle(CodexAX.title($0), among: models)
            }, equals: { CFEqual($0, $1) }, hasKeyboardFocus: CodexAX.isFocused,
            isWebArea: { CodexAX.role($0) == "AXWebArea" },
            isConversationRegion: {
                CodexAX.string($0, kAXSubroleAttribute) == "AXLandmarkRegion"
                    && CodexAX.string($0, kAXDescriptionAttribute) == "Conversation"
            },
            isInterrupted: { ProcessInfo.processInfo.systemUptime >= deadline }
        )
        let located = locator.locate(in: window, focused: focused, previousComposer: nil)
        guard let composer = sharedInput ?? located?.composer, isCurrent() else { return nil }
        let modelButton = located.flatMap { CFEqual($0.composer, composer) ? $0.modelButton : nil }
        return Target(pid: pid, window: window, windowTitle: CodexAX.title(window),
                      composer: composer, modelButton: modelButton, models: models)
    }

    private static let codexDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")

    private static func read(_ family: CodexShortcutController.Family, in target: Target) -> Observation? {
        switch family {
        case .speed:
            // Codex's local composer saves the default after updating the chat.
            // This only confirms the saved speed. The hidden Fast icon cannot
            // distinguish all tiers, and a per-chat-only change may not write it.
            guard let config = try? String(contentsOf: codexDirectory.appendingPathComponent("config.toml"),
                                           encoding: .utf8),
                  let speed = ResponseSpeed(codexConfig: config) else { return nil }
            return Observation(model: nil, value: speed.rawValue)
        case .reasoning:
            guard let button = target.modelButton else { return nil }
            let selection = CurrentModelMatcher.selection(forButtonTitle: CodexAX.title(button), among: target.models)
            guard let model = selection.modelID, let effort = selection.effort else { return nil }
            return Observation(model: model, value: CurrentModelMatcher.label(forEffort: effort))
        }
    }

    private static func userInteracted(since started: TimeInterval) -> Bool {
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        return [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown].contains {
            CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) < elapsed
        }
    }
}
