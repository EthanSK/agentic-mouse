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
    typealias EventPoster = @MainActor (_ keyCode: CGKeyCode, _ isDown: Bool) -> Bool
    typealias ModifiedEventPoster = @MainActor (
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
    private let postModifiedEvent: ModifiedEventPoster
    private let postSystemEvent: SystemEventPoster
    private let postText: TextPoster
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider
    private let passwordProvider: PasswordProvider

    init(
        postEvent: @escaping EventPoster = Self.postKeyboardEvent,
        postModifiedEvent: @escaping ModifiedEventPoster = Self.postModifiedKeyboardEvent,
        postSystemEvent: @escaping SystemEventPoster = Self.postSystemAuxiliaryKey,
        postText: @escaping TextPoster = Self.postText,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping InputAllowedProvider = { true },
        passwordProvider: @escaping PasswordProvider = StoredPasswordKeychain.load
    ) {
        self.postEvent = postEvent
        self.postModifiedEvent = postModifiedEvent
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
        if action == .pasteStoredPassword {
            guard let password = passwordProvider(), !password.isEmpty else {
                return .failure(.passwordNotConfigured)
            }
            return postText(password) ? .success(()) : .failure(.eventCreationFailed)
        }
        if action == .nextTrack {
            let keyType = Int32(NX_KEYTYPE_NEXT)
            let down = postSystemEvent(keyType, true)
            let up = postSystemEvent(keyType, false)
            return down && up ? .success(()) : .failure(.eventCreationFailed)
        }
        if action == .copy || action == .paste {
            let keyCode: CGKeyCode = action == .copy ? 8 : 9
            let down = postModifiedEvent(keyCode, .maskCommand, true)
            let up = postModifiedEvent(keyCode, .maskCommand, false)
            return down && up ? .success(()) : .failure(.eventCreationFailed)
        }
        let keyCode: CGKeyCode
        switch action {
        case .arrowLeft: keyCode = 123
        case .arrowRight: keyCode = 124
        case .arrowDown: keyCode = 125
        case .arrowUp: keyCode = 126
        case .copy, .paste, .nextTrack:
            preconditionFailure("handled before native key-code selection")
        case .insertSpace: keyCode = 49
        case .pressBackspace: keyCode = 51
        case .pasteStoredPassword:
            preconditionFailure("handled before native key-code selection")
        }

        let down = postEvent(keyCode, true)
        let up = postEvent(keyCode, false)
        return down && up ? .success(()) : .failure(.eventCreationFailed)
    }

    private static func postKeyboardEvent(keyCode: CGKeyCode, isDown: Bool) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: isDown
        ) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }

    private static func postModifiedKeyboardEvent(
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
