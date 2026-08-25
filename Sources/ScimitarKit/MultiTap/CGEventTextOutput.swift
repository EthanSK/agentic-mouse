#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

/// Types into one specific process, using CoreGraphics events.
///
/// Layout independence
/// -------------------
/// Characters are **not** produced by looking up a virtual key code. That would
/// break immediately on Ethan's Dvorak layout, where the key that produces `s`
/// on QWERTY produces `o`. Instead each character is delivered by attaching a
/// UTF-16 string to a synthetic key event with `keyboardSetUnicodeString`. The
/// system passes the string straight through to the focused text view, so the
/// result is identical on QWERTY, Dvorak, Colemak or any other layout, and it
/// covers characters that have no key at all (`@`, `—`, `£`).
///
/// Only the two edits that genuinely *are* keys — Delete and Return — use
/// virtual key codes, and those two codes are positional and layout-invariant
/// on every Mac keyboard.
///
/// Targeting
/// ---------
/// Events are posted with `CGEvent.postToPid(_:)`, not `post(tap:)`. A global
/// HID post goes wherever focus happens to be at the instant it lands, which
/// makes a late commit racy. Posting to the captured PID means a character can
/// only ever arrive at the application it was anchored to; if the user has
/// switched away, the event is delivered to the original (now background) app
/// or dropped, but it can never be typed into somebody else's window.
public final class CGEventTextOutput: TextOutput {
    typealias EventPoster = (CGEvent, pid_t) -> Void

    /// `kVK_Delete`. Positional, identical on every layout.
    private static let deleteKeyCode: CGKeyCode = 0x33
    /// `kVK_Return`.
    private static let returnKeyCode: CGKeyCode = 0x24

    private let permission: AccessibilityPermissionChecking
    private let targetResolver: TextTargetResolving?
    private let log: Log
    private let postEvent: EventPoster
    /// Gap between synthetic events. Zero works in most apps, but a small pause
    /// keeps Electron and Java text views from dropping characters.
    private let interEventDelay: TimeInterval
    /// Chunk size for a single unicode payload.
    private let maximumChunkLength = 20

    public init(
        permission: AccessibilityPermissionChecking = AccessibilityPermission(),
        targetResolver: TextTargetResolving? = nil,
        log: Log,
        interEventDelay: TimeInterval = 0.0015
    ) {
        self.permission = permission
        self.targetResolver = targetResolver
        self.log = log
        self.postEvent = { event, pid in event.postToPid(pid) }
        self.interEventDelay = interEventDelay
    }

    init(
        permission: AccessibilityPermissionChecking,
        targetResolver: TextTargetResolving? = nil,
        log: Log,
        interEventDelay: TimeInterval = 0,
        postEvent: @escaping EventPoster
    ) {
        self.permission = permission
        self.targetResolver = targetResolver
        self.log = log
        self.postEvent = postEvent
        self.interEventDelay = interEventDelay
    }

    public func apply(_ commands: [TextCommand], to target: TextTarget) throws {
        guard !commands.isEmpty else { return }
        guard permission.isTrusted else { throw TextOutputError.accessibilityPermissionMissing }
        try verify(target)

        // A private state source keeps our synthetic keystrokes from inheriting
        // modifier flags the user happens to be holding (a stray ⌘ would turn
        // `q` into "quit").
        guard let source = CGEventSource(stateID: .privateState) else {
            throw TextOutputError.eventSourceUnavailable
        }
        source.localEventsSuppressionInterval = 0

        for command in commands {
            // Re-resolve between commands as well as before the batch. A focus
            // move must cancel the rest of a multi-command edit rather than
            // redirecting it to another field in the same application.
            try verify(target)
            switch command {
            case .insert(let text):
                try insert(text, source: source, target: target)
            case .deleteBackward(let count):
                for _ in 0..<max(0, count) {
                    try verify(target)
                    try tapKey(Self.deleteKeyCode, flags: [], source: source, pid: target.processIdentifier)
                }
            case .deleteWordBackward:
                try tapKey(Self.deleteKeyCode, flags: .maskAlternate, source: source, pid: target.processIdentifier)
            case .newline:
                try tapKey(Self.returnKeyCode, flags: [], source: source, pid: target.processIdentifier)
            }
        }
    }

    private func verify(_ target: TextTarget) throws {
        guard let targetResolver else { return }
        guard let current = targetResolver.resolveCurrentTarget().target else {
            throw TextOutputError.targetChanged
        }
        switch target.anchor {
        case .focusedElement:
            guard current == target else { throw TextOutputError.targetChanged }
        case .frontmostApplication:
            // Chromium-backed editors can expose no AX-focused element when
            // Keypad starts, then expose one before the pending character is
            // committed. The same PID remains the safe application anchor;
            // switching to another application still cancels delivery.
            guard current.processIdentifier == target.processIdentifier else {
                throw TextOutputError.targetChanged
            }
        }
    }

    private func insert(_ text: String, source: CGEventSource, target: TextTarget) throws {
        guard !text.isEmpty else { return }
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let end = min(index + maximumChunkLength, units.count)
            var chunk = Array(units[index..<end])
            index = end

            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw TextOutputError.eventSourceUnavailable
            }
            down.flags = []
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
            up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)

            // Keep long Unicode payloads from crossing a detected same-app
            // field change between chunks. CoreGraphics still cannot make the
            // final check and delivery atomic; that narrow boundary is
            // documented in LIMITATIONS.md.
            try verify(target)
            post(down, to: target.processIdentifier)
            post(up, to: target.processIdentifier)
        }
    }

    private func tapKey(_ code: CGKeyCode, flags: CGEventFlags, source: CGEventSource, pid: pid_t) throws {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else {
            throw TextOutputError.eventSourceUnavailable
        }
        down.flags = flags
        up.flags = flags
        post(down, to: pid)
        post(up, to: pid)
    }

    private func post(_ event: CGEvent, to pid: pid_t) {
        postEvent(event, pid)
        if interEventDelay > 0 {
            Thread.sleep(forTimeInterval: interEventDelay)
        }
    }
}
#endif
