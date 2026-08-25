import AppKit
import ApplicationServices
import IOKit.hidsystem
import ScimitarKit

enum DisplayBrightnessActionError: Error, Equatable {
    case accessibilityPermissionMissing
    case eventCreationFailed
}

/// Posts the same macOS auxiliary key events as the physical brightness keys.
/// This preserves the system brightness HUD and the current display policy
/// without calling private display-setting APIs or scripting System Settings.
@MainActor
struct DisplayBrightnessActionExecutor {
    typealias EventPoster = @MainActor (_ keyType: Int32, _ isDown: Bool) -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool

    private let postEvent: EventPoster
    private let accessibilityTrusted: AccessibilityTrustProvider

    init(
        postEvent: @escaping EventPoster = Self.postSystemAuxiliaryKey,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted
    ) {
        self.postEvent = postEvent
        self.accessibilityTrusted = accessibilityTrusted
    }

    /// Test-only convenience that avoids coupling event-recorder tests to TCC.
    init(_ postEvent: @escaping EventPoster) {
        self.init(postEvent: postEvent, accessibilityTrusted: { true })
    }

    func perform(_ action: ModeUtilityAction) -> Result<Void, DisplayBrightnessActionError> {
        guard accessibilityTrusted() else {
            return .failure(.accessibilityPermissionMissing)
        }
        let keyType: Int32
        switch action {
        case .increaseDisplayBrightness:
            keyType = Int32(NX_KEYTYPE_BRIGHTNESS_UP)
        case .decreaseDisplayBrightness:
            keyType = Int32(NX_KEYTYPE_BRIGHTNESS_DOWN)
        case .rewindYouTubeFiveSeconds, .openIntelligenceOnDemand,
             .zoomIn, .zoomOut, .moveToSpaceLeft, .moveToSpaceRight,
             .copy, .paste, .showDesktop, .missionControl, .pasteStoredPassword,
             .moveWindowLeftWithMagnet, .moveWindowRightWithMagnet,
             .showApplicationWindows, .organizeWindows, .quitApp:
            preconditionFailure("This action is owned by ModeUtilityActionExecutor")
        }

        guard postEvent(keyType, true), postEvent(keyType, false) else {
            return .failure(.eventCreationFailed)
        }
        return .success(())
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
}
