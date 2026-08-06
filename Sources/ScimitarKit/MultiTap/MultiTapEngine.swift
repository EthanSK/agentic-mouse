import Foundation

/// A single, layout-independent edit to apply to the anchored text target.
public enum TextCommand: Equatable, Sendable {
    /// Insert literal Unicode text. Must not depend on the active keyboard layout.
    case insert(String)
    /// Send `count` backspaces.
    case deleteBackward(Int)
    /// Send option-delete (delete previous word).
    case deleteWordBackward
    /// Send Return.
    case newline
}

/// How the pending (not-yet-committed) character reaches the user.
public enum EchoPolicy: String, Codable, CaseIterable, Sendable {
    /// **The default.** Nothing is sent to the application until the character
    /// is committed; the HUD shows the pending character and its tap position
    /// immediately, so the feedback loop is just as tight.
    ///
    /// Commit happens on: the multi-tap timeout, a press of a different key,
    /// Space, Return, or a safe exit. Because a character is written exactly
    /// once and never rewritten, there is no backspace-and-replace loop that
    /// could fire into the wrong field.
    case commitOnly

    /// Expert opt-in. Types the pending character straight into the target and
    /// rewrites it on every further tap, the way a feature phone did.
    ///
    /// This is still fully target-anchored — every rewrite is verified against
    /// the same PID *and* AX element that received the original character, and
    /// is abandoned if either changed — but it issues real backspaces into a
    /// live document, so it is not the safe default.
    case livePreview

    public var isBuffered: Bool { self == .commitOnly }
}

/// What happens to a pending character when the target changes.
public enum FocusChangePolicy: String, Codable, CaseIterable, Sendable {
    /// Cancel the pending character. Nothing is typed into the old field and
    /// nothing is typed into the new one.
    case cancelPending
    /// Cancel the pending character *and* leave multi-tap mode.
    case cancelPendingAndExit
}

public struct MultiTapConfiguration: Equatable, Sendable {
    /// Time after the last tap before the pending character is committed.
    public var multiTapTimeout: TimeInterval
    /// Press duration that counts as a long press.
    public var holdThreshold: TimeInterval
    public var echoPolicy: EchoPolicy
    public var focusChangePolicy: FocusChangePolicy
    /// Case/number state entered on every activation.
    public var initialShiftState: ShiftState

    public init(
        multiTapTimeout: TimeInterval = 0.9,
        holdThreshold: TimeInterval = 0.35,
        echoPolicy: EchoPolicy = .commitOnly,
        focusChangePolicy: FocusChangePolicy = .cancelPending,
        initialShiftState: ShiftState = .initialCaps
    ) {
        self.multiTapTimeout = multiTapTimeout
        self.holdThreshold = holdThreshold
        self.echoPolicy = echoPolicy
        self.focusChangePolicy = focusChangePolicy
        self.initialShiftState = initialShiftState
    }

    public static let `default` = MultiTapConfiguration()
}

/// Why a pending character was dropped without being typed.
public enum PendingCancellation: Equatable, Sendable {
    case targetChanged
    case targetRefused(TextTargetRefusal)
    case modeExited
}

/// Snapshot of the engine, consumed by the HUD. Pure data; no AppKit.
public struct MultiTapState: Equatable, Sendable {
    public var shift: ShiftState = .lower
    public var pendingKey: MultiTapKey?
    public var pendingCharacter: Character?
    public var pendingCycleIndex: Int = 0
    public var pendingCycleLength: Int = 0
    /// Absolute clock time at which the pending character commits itself.
    public var pendingDeadline: TimeInterval?
    public var heldKey: MultiTapKey?
    /// Set when the last action dropped a pending character, so the HUD can
    /// say *why* the letter the user was typing vanished.
    public var lastCancellation: PendingCancellation?
    /// Populated when the current target will not accept text.
    public var targetRefusal: TextTargetRefusal?

    public var hasPending: Bool { pendingCharacter != nil }

    /// 1.0 immediately after a tap, falling to 0.0 at the commit deadline.
    public func pendingProgress(now: TimeInterval, timeout: TimeInterval) -> Double? {
        guard let deadline = pendingDeadline, timeout > 0 else { return nil }
        return max(0, min(1, (deadline - now) / timeout))
    }
}

/// Result of feeding one input to the engine.
public struct MultiTapOutcome: Equatable, Sendable {
    public var textCommands: [TextCommand] = []
    /// The target these commands must be delivered to. Always the target the
    /// character was anchored to — never "whatever is focused now".
    public var textTarget: TextTarget?
    public var exitRequested: Bool = false
    /// Distinguishes the configured focus policy from the physical Exit key so
    /// the coordinator reports the correct lifecycle reason.
    public var focusExitRequested: Bool = false
    public var stateChanged: Bool = false

    public static let none = MultiTapOutcome()

    public init(
        textCommands: [TextCommand] = [],
        textTarget: TextTarget? = nil,
        exitRequested: Bool = false,
        focusExitRequested: Bool = false,
        stateChanged: Bool = false
    ) {
        self.textCommands = textCommands
        self.textTarget = textTarget
        self.exitRequested = exitRequested
        self.focusExitRequested = focusExitRequested
        self.stateChanged = stateChanged
    }

    public var hasWork: Bool { !textCommands.isEmpty }

    mutating func merge(_ other: MultiTapOutcome) {
        if !other.textCommands.isEmpty {
            // Commands for two different targets can never be merged into one
            // batch; the engine is structured so this cannot arise, and the
            // assertion documents that invariant.
            assert(
                textCommands.isEmpty || textTarget == other.textTarget,
                "refusing to merge text commands bound for different targets"
            )
            textCommands.append(contentsOf: other.textCommands)
            textTarget = other.textTarget
        }
        exitRequested = exitRequested || other.exitRequested
        focusExitRequested = focusExitRequested || other.focusExitRequested
        stateChanged = stateChanged || other.stateChanged
    }
}

/// The classic multi-tap state machine.
///
/// Completely pure: presses, timestamps and the current text target go in; text
/// edits come out. No hardware, no permissions, no timers, no AppKit — which is
/// what makes cycling, timeout, hold, case and focus loss exhaustively testable.
///
/// This is deliberately **not** T9. There is no dictionary and no prediction:
/// tap 7 four times and you get `s`, every time.
///
/// Safety model
/// ------------
/// A pending character is anchored, at the moment it is created, to the exact
/// `TextTarget` that was focused. Every subsequent step re-checks that anchor.
/// If the PID or the AX element changed, the character is cancelled outright —
/// never redirected, never deleted from the old field, never typed into the new
/// one. A refused target (no permission, secure field, non-editable) prevents a
/// pending character from being created at all.
public final class MultiTapEngine {
    public private(set) var configuration: MultiTapConfiguration
    public private(set) var keymap: MultiTapKeymap
    public private(set) var state: MultiTapState

    private struct Pending {
        var key: MultiTapKey
        var cycleIndex: Int
        var character: Character
        var lastPressAt: TimeInterval
        /// True once a long press forced this slot to the key's digit.
        var resolvedByHold: Bool
        /// The one and only place this character may ever be delivered.
        var anchor: TextTarget
    }

    private struct HoldTracking {
        var key: MultiTapKey
        var pressedAt: TimeInterval
        var consumed: Bool
        /// Monotonic id so a release from a previous activation cannot resolve
        /// a hold started by a later one.
        var generation: UInt64
    }

    private var pending: Pending?
    private var hold: HoldTracking?
    /// Incremented on every reset. Stale timers and stale releases compare
    /// against it and are ignored.
    private var generation: UInt64 = 0

    public init(
        keymap: MultiTapKeymap = .classic,
        configuration: MultiTapConfiguration = .default
    ) {
        self.keymap = keymap
        self.configuration = configuration
        self.state = MultiTapState(shift: configuration.initialShiftState)
    }

    /// Current activation id. Exposed so the coordinator can drop timer
    /// callbacks that were scheduled before the last exit.
    public var currentGeneration: UInt64 { generation }

    // MARK: - Lifecycle

    /// Clears everything and starts a new generation, so a stale pending
    /// character or a late release can never survive across activations.
    @discardableResult
    public func reset() -> MultiTapOutcome {
        let hadPending = pending != nil
        pending = nil
        hold = nil
        generation &+= 1
        state = MultiTapState(shift: configuration.initialShiftState)
        if hadPending { state.lastCancellation = .modeExited }
        return MultiTapOutcome(stateChanged: true)
    }

    public func update(configuration: MultiTapConfiguration) { self.configuration = configuration }
    public func update(keymap: MultiTapKeymap) { self.keymap = keymap }

    // MARK: - Input

    public func press(
        _ key: MultiTapKey,
        at now: TimeInterval,
        target resolution: TextTargetResolution
    ) -> MultiTapOutcome {
        var outcome = reconcileTarget(resolution, at: now)
        guard !outcome.exitRequested else {
            syncState()
            return outcome
        }
        outcome.merge(expireIfNeeded(at: now, resolution: resolution))

        guard let spec = keymap[key] else {
            // An unmapped button inside the mode does nothing. It is still
            // intercepted, so it cannot leak to the application either.
            return outcome
        }

        // Exit is checked first: it must work from any state, including with a
        // half-typed character on screen and a refused target.
        if spec.tapAction == .exitMode {
            outcome.merge(commitPending(at: now))
            hold = nil
            outcome.exitRequested = true
            outcome.stateChanged = true
            syncState()
            return outcome
        }

        guard let target = resolution.target else {
            // Fail closed: no usable destination means no text is produced.
            state.targetRefusal = resolution.refusal
            outcome.stateChanged = true
            return outcome
        }
        state.targetRefusal = nil

        // `123` mode: the digit is emitted immediately, no cycling, no holds.
        if state.shift.isNumeric, let digit = spec.numericCharacter {
            outcome.merge(commitPending(at: now))
            outcome.merge(MultiTapOutcome(
                textCommands: [.insert(String(digit))],
                textTarget: target,
                stateChanged: true
            ))
            hold = nil
            syncState()
            return outcome
        }

        hold = HoldTracking(key: key, pressedAt: now, consumed: false, generation: generation)

        guard spec.isCycling else {
            // Command keys act on release so a long press can mean something
            // different from a short one.
            outcome.stateChanged = true
            syncState()
            return outcome
        }

        if let current = pending,
           current.key == key,
           current.anchor == target,
           !current.resolvedByHold,
           now - current.lastPressAt < configuration.multiTapTimeout {
            // Same key, same field, still inside the window: advance the cycle.
            let nextIndex = current.cycleIndex + 1
            guard let nextCharacter = spec.character(atCycleIndex: nextIndex, shift: state.shift) else {
                return outcome
            }
            outcome.merge(rewritePreview(from: current.character, to: nextCharacter, anchor: current.anchor))
            pending = Pending(
                key: key,
                cycleIndex: nextIndex,
                character: nextCharacter,
                lastPressAt: now,
                resolvedByHold: false,
                anchor: current.anchor
            )
        } else {
            // Different key, lapsed window, or a different field: commit what
            // was there and start a fresh character anchored to the new target.
            outcome.merge(commitPending(at: now))
            guard let firstCharacter = spec.character(atCycleIndex: 0, shift: state.shift) else {
                return outcome
            }
            if configuration.echoPolicy == .livePreview {
                outcome.merge(MultiTapOutcome(
                    textCommands: [.insert(String(firstCharacter))],
                    textTarget: target
                ))
            }
            pending = Pending(
                key: key,
                cycleIndex: 0,
                character: firstCharacter,
                lastPressAt: now,
                resolvedByHold: false,
                anchor: target
            )
        }

        outcome.stateChanged = true
        syncState()
        return outcome
    }

    public func release(
        _ key: MultiTapKey,
        at now: TimeInterval,
        target resolution: TextTargetResolution
    ) -> MultiTapOutcome {
        var outcome = reconcileTarget(resolution, at: now)
        guard !outcome.exitRequested else {
            syncState()
            return outcome
        }
        // Resolve timeout before classifying the release. A cycling character
        // that already committed must stay a letter rather than turning into a
        // digit merely because no 30 Hz tick happened before key-up.
        outcome.merge(expireIfNeeded(at: now, resolution: resolution))

        guard let tracking = hold, tracking.key == key, tracking.generation == generation else {
            // A release with no matching press, or one left over from a
            // previous activation. Harmless; drop it.
            return outcome
        }
        hold = nil

        if tracking.consumed {
            // A long press already did the work. If it resolved a cycling key
            // to its digit, finalise now rather than waiting for the timeout.
            if let current = pending, current.resolvedByHold, current.key == key {
                outcome.merge(commitPending(at: now))
            }
            outcome.stateChanged = true
            syncState()
            return outcome
        }

        let heldFor = now - tracking.pressedAt
        if heldFor >= configuration.holdThreshold {
            // A release can land between scheduler ticks. Classify the gesture
            // from its actual duration here instead of relying on a prior tick
            // to have marked the hold as consumed.
            let isStale = heldFor > configuration.holdThreshold + configuration.multiTapTimeout
            if !isStale, let spec = keymap[key] {
                if spec.isCycling, let digit = spec.numericCharacter {
                    if var current = pending, current.key == key, !current.resolvedByHold {
                        outcome.merge(
                            rewritePreview(from: current.character, to: digit, anchor: current.anchor)
                        )
                        current.character = digit
                        current.resolvedByHold = true
                        current.lastPressAt = now
                        pending = current
                        outcome.merge(commitPending(at: now))
                    }
                } else if let action = spec.holdAction {
                    outcome.merge(perform(action, at: now, resolution: resolution))
                }
            }
            outcome.stateChanged = true
            syncState()
            return outcome
        }

        if let spec = keymap[key], !spec.isCycling, let action = spec.tapAction {
            outcome.merge(perform(action, at: now, resolution: resolution))
        }

        outcome.stateChanged = true
        syncState()
        return outcome
    }

    /// Drives time-based behaviour: long presses and the commit timeout.
    /// Cheap and safe to call as often as you like.
    public func tick(at now: TimeInterval, target resolution: TextTargetResolution) -> MultiTapOutcome {
        var outcome = reconcileTarget(resolution, at: now)
        guard !outcome.exitRequested else {
            syncState()
            return outcome
        }

        // Expiry is resolved *first*. A character that has already timed out
        // must be committed as the letter the user chose, not retro-actively
        // rewritten into a digit by a hold that is only being noticed now.
        outcome.merge(expireIfNeeded(at: now, resolution: resolution))

        if var tracking = hold,
           tracking.generation == generation,
           !tracking.consumed {

            let heldFor = now - tracking.pressedAt
            if heldFor >= configuration.holdThreshold {
                // A press this old means its release was never delivered — a
                // dropped event, or the mode being entered mid-press. Retire
                // the hold silently rather than firing an action (a stray
                // Return, or a case flip) that the user never asked for.
                let isStale = heldFor > configuration.holdThreshold + configuration.multiTapTimeout

                if isStale {
                    // There is no release left to clear this record. Drop it
                    // completely so the HUD and later input cannot treat the
                    // abandoned key as still being held.
                    hold = nil
                } else if let spec = keymap[tracking.key] {
                    if spec.isCycling, let digit = spec.numericCharacter {
                        // Long press on a letter key types its digit. This is
                        // how numbers stay reachable without spending a button.
                        if var current = pending, current.key == tracking.key, !current.resolvedByHold {
                            outcome.merge(
                                rewritePreview(from: current.character, to: digit, anchor: current.anchor)
                            )
                            current.character = digit
                            current.resolvedByHold = true
                            current.lastPressAt = now
                            pending = current
                        }
                    } else if let action = spec.holdAction {
                        outcome.merge(perform(action, at: now, resolution: resolution))
                    }
                }

                if !isStale {
                    tracking.consumed = true
                    hold = tracking
                }
                outcome.stateChanged = true
            }
        }

        syncState()
        return outcome
    }

    /// Explicit notification that focus moved. The coordinator calls this from
    /// its workspace/AX observers; `reconcileTarget` covers the polled path.
    public func focusChanged(at now: TimeInterval, to resolution: TextTargetResolution) -> MultiTapOutcome {
        var outcome = reconcileTarget(resolution, at: now, force: true)
        if configuration.focusChangePolicy == .cancelPendingAndExit {
            outcome.exitRequested = true
            outcome.focusExitRequested = true
            outcome.stateChanged = true
        }
        syncState()
        return outcome
    }

    // MARK: - Anchoring

    /// Cancels the pending character if the target is no longer the one it was
    /// anchored to.
    ///
    /// This is the single choke point for the safety rule, and it emits **no**
    /// text commands in any branch: the old field is left exactly as it was and
    /// the new field is never touched.
    private func reconcileTarget(
        _ resolution: TextTargetResolution,
        at now: TimeInterval,
        force: Bool = false
    ) -> MultiTapOutcome {
        state.targetRefusal = resolution.refusal

        guard let current = pending else {
            return force ? MultiTapOutcome(stateChanged: true) : .none
        }

        switch resolution {
        case .ready(let target) where target == current.anchor && !force:
            return .none
        case .ready(let target) where target == current.anchor && force:
            return MultiTapOutcome(stateChanged: true)
        case .ready:
            pending = nil
            hold = nil
            state.lastCancellation = .targetChanged
            syncState()
            return MultiTapOutcome(
                exitRequested: configuration.focusChangePolicy == .cancelPendingAndExit,
                focusExitRequested: configuration.focusChangePolicy == .cancelPendingAndExit,
                stateChanged: true
            )
        case .refused(let reason):
            pending = nil
            hold = nil
            state.lastCancellation = .targetRefused(reason)
            syncState()
            return MultiTapOutcome(
                exitRequested: configuration.focusChangePolicy == .cancelPendingAndExit,
                focusExitRequested: configuration.focusChangePolicy == .cancelPendingAndExit,
                stateChanged: true
            )
        }
    }

    // MARK: - Actions

    private func perform(
        _ action: KeyAction,
        at now: TimeInterval,
        resolution: TextTargetResolution
    ) -> MultiTapOutcome {
        var outcome = MultiTapOutcome(stateChanged: true)

        // Mode controls work regardless of whether text can be typed.
        switch action {
        case .exitMode:
            outcome.merge(commitPending(at: now))
            outcome.exitRequested = true
            syncState()
            return outcome
        case .shiftCycle:
            let newShift = state.shift.next
            state.shift = newShift
            if let current = pending,
               let spec = keymap[current.key],
               spec.isCycling,
               let recased = spec.character(atCycleIndex: current.cycleIndex, shift: newShift),
               recased != current.character {
                outcome.merge(rewritePreview(from: current.character, to: recased, anchor: current.anchor))
                pending?.character = recased
            }
            syncState()
            return outcome
        default:
            break
        }

        guard let target = resolution.target else {
            state.targetRefusal = resolution.refusal
            return outcome
        }

        switch action {
        case .space:
            outcome.merge(commitPending(at: now))
            outcome.merge(MultiTapOutcome(textCommands: [.insert(" ")], textTarget: target))

        case .newline:
            outcome.merge(commitPending(at: now))
            outcome.merge(MultiTapOutcome(textCommands: [.newline], textTarget: target))

        case .backspace:
            if let current = pending {
                // Backspace while a character is pending removes that pending
                // character, exactly as a phone did.
                if configuration.echoPolicy == .livePreview {
                    outcome.merge(MultiTapOutcome(
                        textCommands: [.deleteBackward(1)],
                        textTarget: current.anchor
                    ))
                }
                pending = nil
            } else {
                outcome.merge(MultiTapOutcome(textCommands: [.deleteBackward(1)], textTarget: target))
            }

        case .deleteWord:
            if let current = pending, configuration.echoPolicy == .livePreview {
                outcome.merge(MultiTapOutcome(
                    textCommands: [.deleteBackward(1)],
                    textTarget: current.anchor
                ))
            }
            pending = nil
            outcome.merge(MultiTapOutcome(textCommands: [.deleteWordBackward], textTarget: target))

        case .shiftCycle, .exitMode:
            break // handled above
        }

        syncState()
        return outcome
    }

    /// Swaps an already-typed preview character. Only ever reachable under the
    /// expert `.livePreview` policy, and always bound to the original anchor.
    private func rewritePreview(
        from previous: Character,
        to next: Character,
        anchor: TextTarget
    ) -> MultiTapOutcome {
        guard configuration.echoPolicy == .livePreview, previous != next else {
            return MultiTapOutcome(stateChanged: true)
        }
        return MultiTapOutcome(
            textCommands: [.deleteBackward(1), .insert(String(next))],
            textTarget: anchor,
            stateChanged: true
        )
    }

    /// Finalises the pending character into its anchored target.
    private func commitPending(at now: TimeInterval) -> MultiTapOutcome {
        guard let current = pending else { return .none }
        pending = nil
        state.lastCancellation = nil

        var outcome = MultiTapOutcome(stateChanged: true)
        if configuration.echoPolicy == .commitOnly {
            outcome.textCommands = [.insert(String(current.character))]
            outcome.textTarget = current.anchor
        }

        // `Abc` is a one-shot: after the capital lands, drop back to `abc`.
        if state.shift == .initialCaps, current.character.isLetter {
            state.shift = .lower
        }
        return outcome
    }

    private func expireIfNeeded(at now: TimeInterval, resolution: TextTargetResolution) -> MultiTapOutcome {
        guard let current = pending,
              now - current.lastPressAt >= configuration.multiTapTimeout
        else { return .none }

        // The anchor has already been reconciled by this point, so a surviving
        // pending character is known to still belong to its original field.
        var outcome = commitPending(at: now)
        outcome.stateChanged = true
        syncState()
        return outcome
    }

    private func syncState() {
        if let current = pending {
            state.pendingKey = current.key
            state.pendingCharacter = current.character
            state.pendingCycleIndex = current.cycleIndex
            state.pendingCycleLength = keymap[current.key]?.cycle.count ?? 0
            // Always exposed, including for a hold-resolved digit: if a release
            // is ever lost, the timeout is what stops a pending character from
            // living forever.
            state.pendingDeadline = current.lastPressAt + configuration.multiTapTimeout
        } else {
            state.pendingKey = nil
            state.pendingCharacter = nil
            state.pendingCycleIndex = 0
            state.pendingCycleLength = 0
            state.pendingDeadline = nil
        }
        state.heldKey = hold.map(\.key)
    }
}
