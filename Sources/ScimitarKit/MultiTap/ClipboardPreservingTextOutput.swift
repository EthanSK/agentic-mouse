#if canImport(AppKit) && canImport(CoreGraphics)
import AppKit
import CoreGraphics
import Foundation

/// Delivers Keypad characters through the ordinary foreground paste route.
///
/// Many Chromium and custom text controls accept Command-V more reliably than
/// Unicode-stamped CGEvents and do not expose their focused editor through AX.
/// Every paste is therefore a short, ownership-marked lease: the existing
/// pasteboard is snapshotted, the character plus a private marker is installed,
/// Command-V is posted only while the original target still owns focus, and the
/// snapshot is restored only if no person or application changed the clipboard
/// in the meantime. Consecutive Keypad commits share the original snapshot.
public final class ClipboardPreservingTextOutput: TextOutput {
    typealias PasteboardItemSnapshot = [(NSPasteboard.PasteboardType, Data)]
    typealias PasteboardSnapshot = [PasteboardItemSnapshot]
    typealias EventPoster = (CGEvent, pid_t?) -> Void
    typealias RestoreScheduler = (TimeInterval, @escaping () -> Void) -> Void

    struct Lease: Equatable {
        let identifier: String
        let expectedText: String
        let changeCount: Int

        func isOwned(on pasteboard: NSPasteboard, markerType: NSPasteboard.PasteboardType) -> Bool {
            pasteboard.changeCount == changeCount
                && pasteboard.string(forType: .string) == expectedText
                && pasteboard.string(forType: markerType) == identifier
        }
    }

    private static let commandKeyCode: CGKeyCode = 0x37
    private static let pasteKeyCode: CGKeyCode = 0x09
    private static let deleteKeyCode: CGKeyCode = 0x33
    private static let returnKeyCode: CGKeyCode = 0x24
    private static let markerType = NSPasteboard.PasteboardType(
        "com.ethansk.agentic-mouse.keypad-paste-session"
    )

    private let permission: AccessibilityPermissionChecking
    private let targetResolver: TextTargetResolving
    private let pasteboard: NSPasteboard
    private let postEvent: EventPoster
    private let scheduleRestore: RestoreScheduler
    private let interEventDelay: TimeInterval
    private let restoreDelay: TimeInterval
    private let log: Log

    private var originalSnapshot: PasteboardSnapshot?
    private var activeLease: Lease?

    public init(
        permission: AccessibilityPermissionChecking = AccessibilityPermission(),
        targetResolver: TextTargetResolving,
        log: Log,
        interEventDelay: TimeInterval = 0.01,
        restoreDelay: TimeInterval = 0.25
    ) {
        self.permission = permission
        self.targetResolver = targetResolver
        self.pasteboard = .general
        self.postEvent = { event, pid in
            if let pid { event.postToPid(pid) } else { event.post(tap: .cghidEventTap) }
        }
        self.scheduleRestore = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
        self.interEventDelay = interEventDelay
        self.restoreDelay = restoreDelay
        self.log = log
    }

    init(
        permission: AccessibilityPermissionChecking,
        targetResolver: TextTargetResolving,
        pasteboard: NSPasteboard,
        postEvent: @escaping EventPoster,
        scheduleRestore: @escaping RestoreScheduler,
        interEventDelay: TimeInterval = 0,
        restoreDelay: TimeInterval = 0.25,
        log: Log
    ) {
        self.permission = permission
        self.targetResolver = targetResolver
        self.pasteboard = pasteboard
        self.postEvent = postEvent
        self.scheduleRestore = scheduleRestore
        self.interEventDelay = interEventDelay
        self.restoreDelay = restoreDelay
        self.log = log
    }

    public func apply(_ commands: [TextCommand], to target: TextTarget) throws {
        guard !commands.isEmpty else { return }
        guard permission.isTrusted else { throw TextOutputError.accessibilityPermissionMissing }
        try verify(target)

        guard let source = CGEventSource(stateID: .privateState) else {
            throw TextOutputError.eventSourceUnavailable
        }
        source.localEventsSuppressionInterval = 0

        for command in commands {
            try verify(target)
            switch command {
            case .insert(let text):
                try paste(text, source: source, target: target)
            case .deleteBackward(let count):
                for _ in 0..<max(0, count) {
                    try verify(target)
                    try tapKey(Self.deleteKeyCode, flags: [], source: source, target: target)
                }
            case .deleteWordBackward:
                try tapKey(Self.deleteKeyCode, flags: .maskAlternate, source: source, target: target)
            case .newline:
                try tapKey(Self.returnKeyCode, flags: [], source: source, target: target)
            }
        }
    }

    private func paste(_ text: String, source: CGEventSource, target: TextTarget) throws {
        guard !text.isEmpty else { return }

        let snapshot: PasteboardSnapshot
        if let lease = activeLease,
           lease.isOwned(on: pasteboard, markerType: Self.markerType),
           let originalSnapshot {
            snapshot = originalSnapshot
        } else {
            snapshot = Self.snapshotClipboard(from: pasteboard)
        }

        let identifier = UUID().uuidString
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString(identifier, forType: Self.markerType)
        guard pasteboard.writeObjects([item]) else {
            throw TextOutputError.eventSourceUnavailable
        }

        let lease = Lease(
            identifier: identifier,
            expectedText: text,
            changeCount: pasteboard.changeCount
        )
        guard lease.isOwned(on: pasteboard, markerType: Self.markerType) else {
            throw TextOutputError.eventSourceUnavailable
        }
        originalSnapshot = snapshot
        activeLease = lease

        guard let commandDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: Self.commandKeyCode,
            keyDown: true
        ), let pasteDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: Self.pasteKeyCode,
            keyDown: true
        ), let pasteUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: Self.pasteKeyCode,
            keyDown: false
        ), let commandUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: Self.commandKeyCode,
            keyDown: false
        ) else {
            restoreIfOwned(lease, snapshot: snapshot)
            throw TextOutputError.eventSourceUnavailable
        }

        commandDown.flags = .maskCommand
        pasteDown.flags = .maskCommand
        pasteUp.flags = .maskCommand
        commandUp.flags = []

        try verify(target)
        postEvent(commandDown, nil)
        wait()
        do {
            try verify(target)
            guard lease.isOwned(on: pasteboard, markerType: Self.markerType) else {
                throw TextOutputError.targetChanged
            }
        } catch {
            postEvent(commandUp, nil)
            restoreIfOwned(lease, snapshot: snapshot)
            throw error
        }

        postEvent(pasteDown, nil)
        wait()
        postEvent(pasteUp, nil)
        wait()
        postEvent(commandUp, nil)
        scheduleRestoration(for: lease, snapshot: snapshot)
        log.debug("Keypad paste posted with clipboard restoration armed")
    }

    private func tapKey(
        _ keyCode: CGKeyCode,
        flags: CGEventFlags,
        source: CGEventSource,
        target: TextTarget
    ) throws {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { throw TextOutputError.eventSourceUnavailable }
        down.flags = flags
        up.flags = flags
        try verify(target)
        postEvent(down, target.processIdentifier)
        wait()
        postEvent(up, target.processIdentifier)
    }

    private func verify(_ target: TextTarget) throws {
        guard let current = targetResolver.resolveCurrentTarget().target else {
            throw TextOutputError.targetChanged
        }
        switch target.anchor {
        case .focusedElement:
            guard current == target else { throw TextOutputError.targetChanged }
        case .frontmostApplication:
            // A Chromium editor can alternate between hiding and exposing its
            // exact AX element while keyboard focus stays put. The fallback's
            // contract is deliberately application-scoped: the same PID may
            // gain a stronger exact-element anchor without invalidating the
            // pending Keypad commit, but any app switch still fails closed.
            guard current.processIdentifier == target.processIdentifier else {
                throw TextOutputError.targetChanged
            }
        }
    }

    private func scheduleRestoration(for lease: Lease, snapshot: PasteboardSnapshot) {
        scheduleRestore(restoreDelay) { [weak self] in
            self?.restoreIfOwned(lease, snapshot: snapshot)
        }
    }

    private func restoreIfOwned(_ lease: Lease, snapshot: PasteboardSnapshot) {
        guard lease.isOwned(on: pasteboard, markerType: Self.markerType) else { return }
        pasteboard.clearContents()
        if !snapshot.isEmpty {
            pasteboard.writeObjects(Self.pasteboardItems(from: snapshot))
        }
        if activeLease == lease {
            activeLease = nil
            originalSnapshot = nil
        }
    }

    private func wait() {
        guard interEventDelay > 0 else { return }
        Thread.sleep(forTimeInterval: interEventDelay)
    }

    static func snapshotClipboard(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        }
    }

    static func pasteboardItems(from snapshot: PasteboardSnapshot) -> [NSPasteboardItem] {
        snapshot.map { itemSnapshot in
            let item = NSPasteboardItem()
            for (type, data) in itemSnapshot {
                item.setData(data, forType: type)
            }
            return item
        }
    }
}
#endif
