import Foundation

/// Truthful feedback for a Codex action dispatched by Agentic Mouse.
///
/// `confirmed` is reserved for an observed Codex-owned state transition. A
/// successful `CGEvent.postToPid` is only `sent`: it proves delivery to the
/// Codex process, not that Codex accepted or completed the command.
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
