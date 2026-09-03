import AppKit
import ApplicationServices
import IOKit.hidsystem
import ScimitarKit

enum KeysModeActionError: Error, Equatable {
    case inputBlocked
    case accessibilityPermissionMissing
    case eventCreationFailed
    case passwordNotConfigured
}

/// Sends one bounded, non-repeating native key cycle.
///
/// The executor never changes focus and never holds a direction after the mouse
/// button is released. Karabiner owns device attribution; this boundary owns
/// only the shared semantic action.
@MainActor
struct KeysModeActionExecutor {
    typealias EventPoster = @MainActor (
        _ keyCode: CGKeyCode,
        _ flags: CGEventFlags,
        _ isDown: Bool
    ) -> Bool
    typealias SystemEventPoster = @MainActor (_ keyType: Int32, _ isDown: Bool) -> Bool
    typealias TextPoster = @MainActor (_ text: String) -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool
    typealias InputAllowedProvider = @MainActor () -> Bool
    typealias PasswordProvider = @MainActor () -> String?

    private let postEvent: EventPoster
    private let postSystemEvent: SystemEventPoster
    private let postText: TextPoster
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider
    private let passwordProvider: PasswordProvider

    init(
        postEvent: @escaping EventPoster = Self.postKeyboardEvent,
        postSystemEvent: @escaping SystemEventPoster = Self.postSystemAuxiliaryKey,
        postText: @escaping TextPoster = Self.postText,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping InputAllowedProvider = { true },
        passwordProvider: @escaping PasswordProvider = StoredPasswordKeychain.load
    ) {
        self.postEvent = postEvent
        self.postSystemEvent = postSystemEvent
        self.postText = postText
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
        self.passwordProvider = passwordProvider
    }

    func perform(_ action: KeysModeAction) -> Result<Void, KeysModeActionError> {
        guard inputAllowed() else {
            return .failure(.inputBlocked)
        }
        guard accessibilityTrusted() else {
            return .failure(.accessibilityPermissionMissing)
        }
        let keyCode: CGKeyCode
        let flags: CGEventFlags
        switch action {
        case .arrowLeft: keyCode = 123; flags = []
        case .arrowRight: keyCode = 124; flags = []
        case .arrowDown: keyCode = 125; flags = []
        case .arrowUp: keyCode = 126; flags = []
        case .undo: keyCode = 6; flags = .maskCommand
        case .insertSpace: keyCode = 49; flags = []
        case .pressBackspace: keyCode = 51; flags = []
        }

        let down = postEvent(keyCode, flags, true)
        let up = postEvent(keyCode, flags, false)
        return down && up ? .success(()) : .failure(.eventCreationFailed)
    }

    func perform(_ action: MediaTrackAction) -> Result<Void, KeysModeActionError> {
        guard inputAllowed() else { return .failure(.inputBlocked) }
        guard accessibilityTrusted() else { return .failure(.accessibilityPermissionMissing) }
        let keyType = Int32(action == .next ? NX_KEYTYPE_NEXT : NX_KEYTYPE_PREVIOUS)
        let down = postSystemEvent(keyType, true)
        let up = postSystemEvent(keyType, false)
        return down && up ? .success(()) : .failure(.eventCreationFailed)
    }

    /// Utility owns the password card, but the security-sensitive text path
    /// remains here beside the same lock, TCC, and synthetic-input guards.
    func performStoredPassword() -> Result<Void, KeysModeActionError> {
        guard inputAllowed() else { return .failure(.inputBlocked) }
        guard accessibilityTrusted() else { return .failure(.accessibilityPermissionMissing) }
        guard let password = passwordProvider(), !password.isEmpty else {
            return .failure(.passwordNotConfigured)
        }
        return postText(password) ? .success(()) : .failure(.eventCreationFailed)
    }

    private static func postKeyboardEvent(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        isDown: Bool
    ) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: isDown
        ) else { return false }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        return true
    }

    private static func postSystemAuxiliaryKey(keyType: Int32, isDown: Bool) -> Bool {
        let keyState = Int32(isDown ? NX_KEYDOWN : NX_KEYUP)
        let data1 = Int((keyType << 16) | (keyState << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
            data1: data1,
            data2: -1
        )?.cgEvent else {
            return false
        }
        event.post(tap: .cghidEventTap)
        return true
    }

    private static func postText(_ text: String) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: false
              )
        else { return false }

        let utf16 = Array(text.utf16)
        utf16.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: baseAddress
            )
            keyUp.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: baseAddress
            )
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
