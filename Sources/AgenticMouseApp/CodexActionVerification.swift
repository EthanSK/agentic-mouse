import AppKit
import ApplicationServices
import Foundation
import os
import ScimitarKit

/// Truthful feedback for a Codex action dispatched by Agentic Mouse.
///
/// `confirmed` is reserved for an observed Codex-owned state transition or a
/// successful Codex-owned Accessibility action. A successful
/// `CGEvent.postToPid` is only `sent`: it proves delivery to the Codex process,
/// not that Codex accepted or completed the command.
enum CodexActionFeedback: Equatable, Sendable {
    case checking(String)
    case confirmed(String)
    case sentUnverified(String)
    case notConfirmed(String)
}

/// Reads the sidebar pin set persisted by the Codex desktop app itself.
///
/// The currently installed Codex app-server schema does not expose `isPinned`,
/// even though newer public protocol documentation does. This read-only state
/// is therefore the narrowest observable boundary available today. It is never
/// mutated by Agentic Mouse.
struct CodexPinnedThreadStateReader {
    enum ReadError: Error {
        case invalidState
    }

    let stateURL: URL

    init(
        stateURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/.codex-global-state.json")
    ) {
        self.stateURL = stateURL
    }

    func read() throws -> Set<String> {
        let data = try Data(contentsOf: stateURL, options: .mappedIfSafe)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              let identifiers = root["pinned-thread-ids"] as? [String],
              identifiers.allSatisfy({ !$0.isEmpty }) else {
            throw ReadError.invalidState
        }
        return Set(identifiers)
    }
}

/// Confirms a pin/unpin only after Codex's own persisted pin set changes.
///
/// The verifier deliberately refuses to infer intent from the shortcut alone.
/// One added ID is a confirmed pin; one removed ID is a confirmed unpin. More
/// than one changed ID is ambiguous, and no observed change is unconfirmed.
@MainActor
final class CodexPinChangeVerifier {
    typealias StateProvider = @MainActor () throws -> Set<String>
    typealias Scheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @Sendable @MainActor () -> Void
    ) -> Void
    typealias Completion = @MainActor (CodexActionFeedback) -> Void

    private let readPinnedThreadIDs: StateProvider
    private let schedule: Scheduler
    private let retryDelays: [TimeInterval]
    private var generation = 0
    private(set) var isVerificationPending = false

    init(
        readPinnedThreadIDs: @escaping StateProvider = {
            try CodexPinnedThreadStateReader().read()
        },
        schedule: @escaping Scheduler = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        },
        retryDelays: [TimeInterval] = [0.08, 0.18, 0.34, 0.62, 1.0]
    ) {
        self.readPinnedThreadIDs = readPinnedThreadIDs
        self.schedule = schedule
        self.retryDelays = retryDelays
    }

    func captureBeforeDispatch() -> Set<String>? {
        try? readPinnedThreadIDs()
    }

    func verify(
        from before: Set<String>,
        completion: @escaping Completion
    ) {
        generation += 1
        isVerificationPending = true
        let currentGeneration = generation
        poll(
            from: before,
            delays: ArraySlice(retryDelays),
            generation: currentGeneration,
            completion: completion
        )
    }

    func cancelPendingVerification() {
        generation += 1
        isVerificationPending = false
    }

    static func feedback(
        before: Set<String>,
        after: Set<String>
    ) -> CodexActionFeedback? {
        let added = after.subtracting(before)
        let removed = before.subtracting(after)
        let changedCount = added.count + removed.count

        if added.count == 1, removed.isEmpty {
            return .confirmed("Pinned — confirmed by Codex")
        }
        if removed.count == 1, added.isEmpty {
            return .confirmed("Unpinned — confirmed by Codex")
        }
        if changedCount > 1 {
            return .notConfirmed("Pin change was ambiguous — not confirmed")
        }
        return nil
    }

    private func poll(
        from before: Set<String>,
        delays: ArraySlice<TimeInterval>,
        generation currentGeneration: Int,
        completion: @escaping Completion
    ) {
        guard currentGeneration == generation else { return }
        guard let delay = delays.first else {
            isVerificationPending = false
            completion(.notConfirmed("Pin change was not confirmed"))
            return
        }

        schedule(delay) { [weak self] in
            guard let self, currentGeneration == self.generation else { return }
            if let after = try? self.readPinnedThreadIDs(),
               let feedback = Self.feedback(before: before, after: after) {
                self.generation += 1
                self.isVerificationPending = false
                completion(feedback)
                return
            }
            self.poll(
                from: before,
                delays: delays.dropFirst(),
                generation: currentGeneration,
                completion: completion
            )
        }
    }
}

/// Reads only the exact public voice controls exposed by the frontmost Codex
/// window. Dispatch is never treated as success: a start/stop is confirmed
/// only when Codex changes between an inactive and active voice control.
@MainActor
struct CodexVoiceSessionStateReader {
    enum State: Equatable, Sendable {
        case inactive
        case active
    }

    private struct RootSearchResult {
        let state: State?
        let completed: Bool
    }

    private struct ElementIdentity: Hashable {
        let element: AXUIElement

        static func == (lhs: ElementIdentity, rhs: ElementIdentity) -> Bool {
            CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(CFHash(element))
        }
    }

    private static let inactiveLabels: Set<String> = [
        "start voice chat",
        "start new voice chat",
        "resume voice chat",
        "open voice chat",
    ]
    private static let activeLabels: Set<String> = ["stop voice chat"]
    private static let logger = Logger(
        subsystem: "com.ethan.agentic-mouse",
        category: "codex-voice-state"
    )

    func read() -> State? {
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: CodexMode.bundleIdentifier
        )
        guard let application = applications.first(where: { $0.isActive }) else { return nil }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.28
        AXUIElementSetMessagingTimeout(applicationElement, 0.04)
        var roots = windows(of: applicationElement).filter { !isMinimized($0) }
        guard !roots.isEmpty,
              ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        roots.sort(by: smallerWindowFirst)

        var sawInactive = false
        for root in roots {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            let search = state(in: root, limit: 1_500, deadline: deadline)
            if search.state == .active {
                Self.logger.debug("Codex voice AX state=active")
                return .active
            }
            guard search.completed else {
                Self.logger.debug("Codex voice AX state=unavailable partial=true")
                return nil
            }
            if search.state == .inactive { sawInactive = true }
        }
        let result: State? = sawInactive ? .inactive : nil
        Self.logger.debug("Codex voice AX state=\(result == .inactive ? "inactive" : "unavailable", privacy: .public)")
        return result
    }

    private func state(
        in root: AXUIElement,
        limit: Int,
        deadline: TimeInterval
    ) -> RootSearchResult {
        let traversal = CodexQueuedMessageSteerer.boundedBreadthFirstTraversalResult(
            roots: [root],
            limit: limit,
            identity: { ElementIdentity(element: $0) },
            children: children,
            shouldContinue: { ProcessInfo.processInfo.systemUptime < deadline }
        )
        var sawInactive = false
        var processedAllElements = true
        for element in traversal.nodes {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                processedAllElements = false
                break
            }
            if stringAttribute(kAXRoleAttribute as CFString, of: element)
                == kAXButtonRole as String,
               isEnabled(element),
               supportsPress(element) {
                let labels = [
                    stringAttribute(kAXTitleAttribute as CFString, of: element),
                    stringAttribute(kAXDescriptionAttribute as CFString, of: element),
                    stringAttribute(kAXHelpAttribute as CFString, of: element),
                ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                if labels.contains(where: Self.activeLabels.contains) {
                    return RootSearchResult(state: .active, completed: traversal.completed)
                }
                if labels.contains(where: Self.inactiveLabels.contains) { sawInactive = true }
            }
        }
        let completed = traversal.completed
            && processedAllElements
            && ProcessInfo.processInfo.systemUptime < deadline
        return RootSearchResult(
            state: completed && sawInactive ? .inactive : nil,
            completed: completed
        )
    }

    private func windows(of application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func smallerWindowFirst(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        let lhsArea = frame(of: lhs).map { $0.width * $0.height } ?? .greatestFiniteMagnitude
        let rhsArea = frame(of: rhs).map { $0.width * $0.height } ?? .greatestFiniteMagnitude
        return lhsArea < rhsArea
    }

    private func isMinimized(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXMinimizedAttribute as CFString,
            &value
        ) == .success else { return false }
        return value as? Bool == true
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let rawPosition = positionValue,
        let rawSize = sizeValue,
        CFGetTypeID(rawPosition) == AXValueGetTypeID(),
        CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        let positionAX = unsafeBitCast(rawPosition, to: AXValue.self)
        let sizeAX = unsafeBitCast(rawSize, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAX, .cgPoint, &position),
              AXValueGetValue(sizeAX, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func stringAttribute(_ name: CFString, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value as? String
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func isEnabled(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXEnabledAttribute as CFString,
            &value
        ) == .success else { return false }
        return value as? Bool == true
    }

    private func supportsPress(_ element: AXUIElement) -> Bool {
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success,
              let names = actions as? [String] else { return false }
        return names.contains(kAXPressAction as String)
    }
}

/// Confirms Voice Mode against Codex's own current Accessibility state.
@MainActor
final class CodexVoiceSessionVerifier {
    typealias State = CodexVoiceSessionStateReader.State
    typealias StateProvider = @MainActor () -> State?
    typealias Scheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @Sendable @MainActor () -> Void
    ) -> Void
    typealias Completion = @MainActor (CodexActionFeedback) -> Void

    private let readState: StateProvider
    private let captureState: StateProvider
    private let schedule: Scheduler
    private let retryDelays: [TimeInterval]
    private let inputAllowed: @MainActor () -> Bool
    private let accessibilityTrusted: @MainActor () -> Bool
    private var generation = 0

    init(
        readState: @escaping StateProvider = { CodexVoiceSessionStateReader().read() },
        captureState: StateProvider? = nil,
        schedule: @escaping Scheduler = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        },
        retryDelays: [TimeInterval] = [0.08, 0.18, 0.34, 0.62, 1.0],
        inputAllowed: @escaping @MainActor () -> Bool = { true },
        accessibilityTrusted: @escaping @MainActor () -> Bool = { true }
    ) {
        self.readState = readState
        self.captureState = captureState ?? readState
        self.schedule = schedule
        self.retryDelays = retryDelays
        self.inputAllowed = inputAllowed
        self.accessibilityTrusted = accessibilityTrusted
    }

    func captureBeforeDispatch() -> State? {
        guard inputAllowed(), accessibilityTrusted() else { return nil }
        return captureState()
    }

    func verify(from before: State, completion: @escaping Completion) {
        generation += 1
        poll(
            from: before,
            delays: ArraySlice(retryDelays),
            generation: generation,
            completion: completion
        )
    }

    func cancelPendingVerification() {
        generation += 1
    }

    static func feedback(before: State, after: State) -> CodexActionFeedback? {
        guard before != after else { return nil }
        switch after {
        case .active:
            return .confirmed("Voice mode started — confirmed by Codex")
        case .inactive:
            return .confirmed("Voice mode stopped — confirmed by Codex")
        }
    }

    private func poll(
        from before: State,
        delays: ArraySlice<TimeInterval>,
        generation currentGeneration: Int,
        completion: @escaping Completion
    ) {
        guard currentGeneration == generation else { return }
        guard let delay = delays.first else {
            completion(.notConfirmed("Voice mode change was not confirmed by Codex"))
            return
        }
        schedule(delay) { [weak self] in
            guard let self, currentGeneration == self.generation else { return }
            guard self.inputAllowed(), self.accessibilityTrusted() else {
                self.generation += 1
                completion(.notConfirmed("Voice mode change was not confirmed by Codex"))
                return
            }
            if let after = self.readState(),
               let feedback = Self.feedback(before: before, after: after) {
                self.generation += 1
                completion(feedback)
                return
            }
            self.poll(
                from: before,
                delays: delays.dropFirst(),
                generation: currentGeneration,
                completion: completion
            )
        }
    }
}
