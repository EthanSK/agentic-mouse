import AppKit
import ApplicationServices
import Carbon
import ScimitarKit

enum ChromeModeShortcutResolver {
    static func shortcut(
        for action: ChromeModeAction
    ) -> ApplicationShortcutDispatcher.Shortcut? {
        switch action {
        case .closeCurrentTab:
            return .init(keyCode: 13, flags: .maskCommand)
        case .openDevTools:
            return .init(keyCode: 34, flags: [.maskCommand, .maskAlternate])
        case .reloadCurrentTab:
            return .init(keyCode: 15, flags: .maskCommand)
        case .newTab:
            return .init(keyCode: 17, flags: .maskCommand)
        case .focusAddress:
            return .init(keyCode: 37, flags: .maskCommand)
        case .reopenClosedTab:
            return .init(keyCode: 17, flags: [.maskCommand, .maskShift])
        case .findPage:
            return .init(keyCode: 3, flags: .maskCommand)
        case .holdYouTubeDoubleSpeed, .cycleTabsWithWheel:
            return nil
        }
    }
}

enum TerminalModeShortcutResolver {
    typealias SemanticKeyCodeResolver = (_ character: Character) -> CGKeyCode?

    static func shortcut(
        for action: TerminalModeAction,
        keyCodeForSemanticCharacter: SemanticKeyCodeResolver =
            CurrentKeyboardLayoutKeyCodeResolver.keyCode
    ) -> ApplicationShortcutDispatcher.Shortcut? {
        switch action {
        case .previousTab: return .init(keyCode: 33, flags: [.maskCommand, .maskShift])
        case .nextTab: return .init(keyCode: 30, flags: [.maskCommand, .maskShift])
        case .find: return .init(keyCode: 3, flags: .maskCommand)
        case .clearScreen: return .init(keyCode: 40, flags: .maskCommand)
        case .newTab: return .init(keyCode: 17, flags: .maskCommand)
        case .zoomOut: return .init(keyCode: 27, flags: .maskCommand)
        case .zoomIn: return .init(keyCode: 24, flags: [.maskCommand, .maskShift])
        case .closeTab: return .init(keyCode: 13, flags: .maskCommand)
        case .settings: return .init(keyCode: 43, flags: .maskCommand)
        case .interruptTerminal:
            // Control does not activate Ethan's QWERTY-Command remap. Resolve
            // semantic C from the live layout so DVORAK-QWERTYCMD does not
            // turn physical QWERTY-C (key code 8) into Control-J / newline.
            guard let keyCode = keyCodeForSemanticCharacter("c") else {
                return nil
            }
            return .init(keyCode: keyCode, flags: .maskControl)
        }
    }
}

enum StandardAppModeShortcutResolver {
    static func shortcut(
        for action: StandardAppModeAction
    ) -> ApplicationShortcutDispatcher.Shortcut {
        var flags: CGEventFlags = []
        if action.modifiers.contains(.command) { flags.insert(.maskCommand) }
        if action.modifiers.contains(.shift) { flags.insert(.maskShift) }
        if action.modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if action.modifiers.contains(.control) { flags.insert(.maskControl) }
        return .init(keyCode: CGKeyCode(action.keyCode), flags: flags)
    }
}

enum IPhoneMirroringModeShortcutResolver {
    typealias SemanticKeyCodeResolver = (_ character: Character) -> CGKeyCode?

    static func shortcut(
        for action: IPhoneMirroringModeAction,
        keyCodeForSemanticCharacter: SemanticKeyCodeResolver = CurrentKeyboardLayoutKeyCodeResolver.keyCode
    ) -> ApplicationShortcutDispatcher.Shortcut? {
        switch action {
        case .notifications:
            // Fn does not activate the QWERTY-Command remap in Ethan's
            // DVORAK-QWERTYCMD input source. Resolve semantic N from the
            // active layout rather than sending the physical QWERTY N key.
            guard let keyCode = keyCodeForSemanticCharacter("n") else {
                return nil
            }
            return .init(keyCode: keyCode, flags: .maskSecondaryFn)
        }
    }
}

enum CurrentKeyboardLayoutKeyCodeResolver {
    typealias KeyTranslator = (_ keyCode: CGKeyCode) -> String?

    static func keyCode(for character: Character) -> CGKeyCode? {
        keyCode(for: character, translating: translatedCharacter)
    }

    static func keyCode(
        for character: Character,
        translating translate: KeyTranslator
    ) -> CGKeyCode? {
        let target = String(character).lowercased()
        return (CGKeyCode(0)...CGKeyCode(127)).first { keyCode in
            translate(keyCode)?.lowercased() == target
        }
    }

    private static func translatedCharacter(for keyCode: CGKeyCode) -> String? {
        guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutDataReference = TISGetInputSourceProperty(
                inputSource,
                kTISPropertyUnicodeKeyLayoutData
              )
        else { return nil }

        let layoutData = unsafeBitCast(layoutDataReference, to: CFData.self)
        guard let layoutBytes = CFDataGetBytePtr(layoutData) else { return nil }

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var characterCount = 0
        let status = layoutBytes.withMemoryRebound(
            to: UCKeyboardLayout.self,
            capacity: 1
        ) { keyboardLayout in
            UCKeyTranslate(
                keyboardLayout,
                keyCode,
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                characters.count,
                &characterCount,
                &characters
            )
        }

        guard status == noErr, characterCount > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: characterCount)
    }
}

/// Delivers one bounded keyboard shortcut directly to a running application's
/// process without activating it. The transport is generic; each app-specific
/// mode supplies only its bundle identifier and shortcut semantics.
@MainActor
final class ApplicationShortcutDispatcher {
    struct DispatchError: Error, CustomStringConvertible {
        let description: String
    }

    struct Shortcut: Equatable {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    typealias TargetProcessResolver = @MainActor (_ bundleIdentifier: String) -> pid_t?
    typealias EventPoster = @MainActor (
        _ pid: pid_t,
        _ keyCode: CGKeyCode,
        _ flags: CGEventFlags,
        _ isDown: Bool
    ) -> Bool
    typealias TargetProcessIsActive = @MainActor (_ pid: pid_t) -> Bool
    typealias SystemShortcutPoster = @MainActor (_ shortcut: Shortcut) -> Bool
    typealias HardwareSystemShortcutPoster = @MainActor (_ shortcut: Shortcut) -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool
    typealias InputAllowedProvider = @MainActor () -> Bool

    private let targetProcessResolver: TargetProcessResolver
    private let postEvent: EventPoster
    private let targetProcessIsActive: TargetProcessIsActive
    private let postSystemShortcut: SystemShortcutPoster
    private let postHardwareSystemShortcut: HardwareSystemShortcutPoster
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider

    init(
        targetProcessResolver: @escaping TargetProcessResolver = { bundleIdentifier in
            let applications = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            )
            return applications.first(where: { $0.isActive })?.processIdentifier
                ?? applications.first(where: { !$0.isTerminated })?.processIdentifier
        },
        postEvent: EventPoster? = nil,
        targetProcessIsActive: @escaping TargetProcessIsActive = { pid in
            NSRunningApplication(processIdentifier: pid)?.isActive == true
        },
        postSystemShortcut: SystemShortcutPoster? = nil,
        postHardwareSystemShortcut: HardwareSystemShortcutPoster? = nil,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping InputAllowedProvider = { true }
    ) {
        self.targetProcessResolver = targetProcessResolver
        self.postEvent = postEvent ?? Self.postKeyboardEvent
        self.targetProcessIsActive = targetProcessIsActive
        self.postSystemShortcut = postSystemShortcut ?? Self.postSystemKeyboardShortcut
        self.postHardwareSystemShortcut = postHardwareSystemShortcut
            ?? Self.postHardwareSystemKeyboardShortcut
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
    }

    func perform(
        _ shortcut: Shortcut,
        targetBundleIdentifier: String,
        targetDisplayName: String
    ) -> Result<Void, DispatchError> {
        guard inputAllowed() else {
            return .failure(DispatchError(
                description: "Mouse commands are disabled while macOS is locked"
            ))
        }
        guard accessibilityTrusted() else {
            return .failure(DispatchError(
                description: "Accessibility permission is required for \(targetDisplayName) shortcuts"
            ))
        }
        guard let pid = targetProcessResolver(targetBundleIdentifier) else {
            return .failure(DispatchError(description: "\(targetDisplayName) is not running"))
        }

        let downSucceeded = postEvent(pid, shortcut.keyCode, shortcut.flags, true)
        let upSucceeded = postEvent(pid, shortcut.keyCode, shortcut.flags, false)
        guard downSucceeded, upSucceeded else {
            return .failure(DispatchError(
                description: "Could not deliver the \(targetDisplayName) shortcut"
            ))
        }
        return .success(())
    }

    /// Delivers an Electron app-level accelerator through the system event
    /// stream. Some Electron commands deliberately ignore PID-targeted
    /// renderer events because those events were not triggered by an app
    /// accelerator. Fail closed unless the intended app is frontmost so the
    /// system event can never reach an unrelated application.
    func performForegroundSystemShortcut(
        _ shortcut: Shortcut,
        targetBundleIdentifier: String,
        targetDisplayName: String
    ) -> Result<Void, DispatchError> {
        guard inputAllowed() else {
            return .failure(DispatchError(
                description: "Mouse commands are disabled while macOS is locked"
            ))
        }
        guard accessibilityTrusted() else {
            return .failure(DispatchError(
                description: "Accessibility permission is required for \(targetDisplayName) shortcuts"
            ))
        }
        guard let pid = targetProcessResolver(targetBundleIdentifier) else {
            return .failure(DispatchError(description: "\(targetDisplayName) is not running"))
        }
        guard targetProcessIsActive(pid) else {
            return .failure(DispatchError(
                description: "\(targetDisplayName) must be frontmost for this shortcut"
            ))
        }
        guard postSystemShortcut(shortcut) else {
            return .failure(DispatchError(
                description: "Could not deliver the \(targetDisplayName) shortcut"
            ))
        }
        return .success(())
    }

    /// Delivers an OS-level shortcut as a hardware-shaped HID cycle. This is
    /// separate from Electron's System Events boundary because macOS's Fn
    /// shortcuts require the SecondaryFn event flag. The intended app must be
    /// frontmost so a global shortcut cannot leak to an unrelated workflow.
    func performForegroundHardwareShortcut(
        _ shortcut: Shortcut,
        targetBundleIdentifier: String,
        targetDisplayName: String
    ) -> Result<Void, DispatchError> {
        guard inputAllowed() else {
            return .failure(DispatchError(
                description: "Mouse commands are disabled while macOS is locked"
            ))
        }
        guard accessibilityTrusted() else {
            return .failure(DispatchError(
                description: "Accessibility permission is required for \(targetDisplayName) shortcuts"
            ))
        }
        guard let pid = targetProcessResolver(targetBundleIdentifier) else {
            return .failure(DispatchError(description: "\(targetDisplayName) is not running"))
        }
        guard targetProcessIsActive(pid) else {
            return .failure(DispatchError(
                description: "\(targetDisplayName) must be frontmost for this shortcut"
            ))
        }
        guard postHardwareSystemShortcut(shortcut) else {
            return .failure(DispatchError(
                description: "Could not deliver the \(targetDisplayName) shortcut"
            ))
        }
        return .success(())
    }

    private static func postKeyboardEvent(
        pid: pid_t,
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        isDown: Bool
    ) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: isDown
              )
        else { return false }
        event.flags = flags
        event.postToPid(pid)
        return true
    }

    private static func postSystemKeyboardShortcut(_ shortcut: Shortcut) -> Bool {
        guard let source = systemEventsAppleScript(for: shortcut) else { return false }
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }

    private static func postHardwareSystemKeyboardShortcut(_ shortcut: Shortcut) -> Bool {
        guard let events = hardwareSystemKeyboardEvents(for: shortcut) else {
            return false
        }
        return SyntheticKeyboardChordPoster.shared.post(events)
    }

    /// Global shortcuts are most reliable when the event stream contains the
    /// modifiers' real `flagsChanged` lifecycle. Merely attaching flags to the
    /// action key can create a valid Quartz event that a Carbon/Electron global
    /// accelerator still ignores.
    static func hardwareSystemKeyboardEvents(
        for shortcut: Shortcut
    ) -> [SyntheticKeyboardChordPoster.Event]? {
        let supportedModifiers: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
            (.maskControl, CGKeyCode(kVK_Control)),
            (.maskShift, CGKeyCode(kVK_Shift)),
            (.maskAlternate, CGKeyCode(kVK_Option)),
            (.maskCommand, CGKeyCode(kVK_Command)),
            (.maskSecondaryFn, CGKeyCode(kVK_Function)),
        ]
        let supportedFlags = supportedModifiers.reduce(into: CGEventFlags()) {
            $0.insert($1.flag)
        }
        guard !shortcut.flags.isEmpty,
              shortcut.flags.subtracting(supportedFlags).isEmpty else { return nil }

        let activeModifiers = supportedModifiers.filter {
            shortcut.flags.contains($0.flag)
        }
        var events: [SyntheticKeyboardChordPoster.Event] = []
        var accumulatedFlags: CGEventFlags = []
        var offset: TimeInterval = 0

        for modifier in activeModifiers {
            accumulatedFlags.insert(modifier.flag)
            events.append(.modifier(
                keyCode: modifier.keyCode,
                flags: accumulatedFlags,
                at: offset
            ))
            offset += 0.006
        }
        events.append(.key(
            keyCode: shortcut.keyCode,
            flags: shortcut.flags,
            isDown: true,
            at: offset
        ))
        offset += 0.020
        events.append(.key(
            keyCode: shortcut.keyCode,
            flags: shortcut.flags,
            isDown: false,
            at: offset
        ))
        offset += 0.006
        for modifier in activeModifiers.reversed() {
            accumulatedFlags.remove(modifier.flag)
            events.append(.modifier(
                keyCode: modifier.keyCode,
                flags: accumulatedFlags,
                at: offset
            ))
            offset += 0.006
        }
        return events
    }

    /// Electron 40 no longer treats Quartz-generated key events as app/global
    /// accelerators, even when they carry the correct flags. System Events is
    /// the supported macOS keyboard-automation boundary and produces the same
    /// command invocation as Ethan pressing the shortcut physically.
    static func systemEventsAppleScript(for shortcut: Shortcut) -> String? {
        let supportedFlags: CGEventFlags = [
            .maskCommand, .maskControl, .maskAlternate, .maskShift,
        ]
        guard shortcut.flags.subtracting(supportedFlags).isEmpty else { return nil }

        var modifiers: [String] = []
        if shortcut.flags.contains(.maskCommand) { modifiers.append("command down") }
        if shortcut.flags.contains(.maskControl) { modifiers.append("control down") }
        if shortcut.flags.contains(.maskAlternate) { modifiers.append("option down") }
        if shortcut.flags.contains(.maskShift) { modifiers.append("shift down") }
        let usingClause = modifiers.isEmpty
            ? ""
            : " using {\(modifiers.joined(separator: ", "))}"
        return "tell application \"System Events\" to key code \(shortcut.keyCode)\(usingClause)"
    }
}

/// Keeps VS Code's semantic commands separate from their macOS key transport.
/// Tests pin this boundary so a panel shortcut cannot silently replace the
/// dedicated integrated-terminal command again.
enum VSCodeModeShortcutResolver {
    static func shortcut(
        for command: VSCodeModeCommand,
        keyCodeForSemanticCharacter: TerminalModeShortcutResolver.SemanticKeyCodeResolver =
            CurrentKeyboardLayoutKeyCodeResolver.keyCode
    ) -> ApplicationShortcutDispatcher.Shortcut? {
        switch command {
        case .closeTab:
            return .init(keyCode: 13, flags: .maskCommand) // Command-W
        case .find:
            return .init(keyCode: 3, flags: .maskCommand) // Command-F
        case .previousChange:
            return .init(keyCode: 64, flags: []) // F17
        case .nextChange:
            return .init(keyCode: 105, flags: []) // F13
        case .stageAndPrevious:
            return .init(keyCode: 80, flags: []) // F19
        case .stageAndNext:
            return .init(keyCode: 79, flags: []) // F18
        case .undoLastStageAndAdvance:
            return .init(keyCode: 106, flags: []) // F16
        case .toggleTerminal:
            return nil // The VS Code bridge owns the Hide-first Terminal alternator.
        case .commandPalette:
            return .init(keyCode: 35, flags: [.maskCommand, .maskShift]) // Command-Shift-P
        case .goToDefinition:
            return .init(keyCode: 111, flags: []) // F12
        case .interruptTerminal:
            return TerminalModeShortcutResolver.shortcut(
                for: .interruptTerminal,
                keyCodeForSemanticCharacter: keyCodeForSemanticCharacter
            )
        case .navigateBack, .navigateForward:
            // Cursor History is executed by the allow-listed VS Code URI
            // bridge. It intentionally has no keyboard-event fallback.
            return nil
        }
    }
}
