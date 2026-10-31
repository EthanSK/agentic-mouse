import AppKit
import ApplicationServices
import ScimitarKit

enum MagnetWindowActionError: Error, Equatable {
    case inputBlocked
    case accessibilityPermissionMissing
    case eventCreationFailed
}

/// Runs the wand/mouse "Magnet" Left/Right window commands.
///
/// Ethan's terminology: the Magic Wand's "Magnet wedge" (and the mice's
/// Magnet + Wheel card) means these two actions. Since 2026-10-30 they are
/// served by LODESTONE (`com.ethansk.lodestone`, ~/Projects/lodestone), Ethan's
/// own Magnet-style window manager:
///
///  1. Lodestone running → post its `com.ethansk.lodestone.perform`
///     distributed notification with object "left"/"right". No keyboard
///     events are synthesized, so nothing can leak into the focused app and
///     nothing collides with Magnet's ⌃⌥←/→. Lodestone owns placement,
///     including walking a window across displays on repeated presses.
///  2. Lodestone not running → the original behaviour: Magnet's configured
///     global Control-Option-Arrow accelerator, sent as the same complete
///     modifier/arrow lifecycle a physical keyboard produces. Magnet stays the
///     working fallback, so uninstalling or quitting Lodestone never breaks
///     the wedge.
@MainActor
struct MagnetWindowActionExecutor {
    typealias KeyEvent = SyntheticKeyboardChordPoster.Event

    typealias ChordPoster = @MainActor (_ events: [KeyEvent]) -> Bool
    typealias AccessibilityTrustProvider = @MainActor () -> Bool
    typealias InputAllowedProvider = @MainActor () -> Bool
    /// True when Lodestone should serve the command (it is running).
    typealias LodestoneAvailability = @MainActor () -> Bool
    /// Delivers one Lodestone command id; returns false when it could not be sent.
    typealias LodestonePoster = @MainActor (_ commandID: String) -> Bool

    /// Lodestone's public command contract (see Lodestone's
    /// `CommandInterface.swift`). Kept as literals so Agentic Mouse does not
    /// link Lodestone code; Lodestone treats these names as stable API.
    static let lodestoneBundleIdentifier = "com.ethansk.lodestone"
    static let lodestonePerformNotification = "com.ethansk.lodestone.perform"

    static let leftControlKeyCode: CGKeyCode = 59
    static let leftOptionKeyCode: CGKeyCode = 58
    static let leftArrowKeyCode: CGKeyCode = 123
    static let rightArrowKeyCode: CGKeyCode = 124

    private let postChord: ChordPoster
    private let accessibilityTrusted: AccessibilityTrustProvider
    private let inputAllowed: InputAllowedProvider
    private let lodestoneAvailable: LodestoneAvailability
    private let postLodestone: LodestonePoster

    init(
        postChord: @escaping ChordPoster = SyntheticKeyboardChordPoster.shared.post,
        accessibilityTrusted: @escaping AccessibilityTrustProvider = AXIsProcessTrusted,
        inputAllowed: @escaping InputAllowedProvider = { true },
        lodestoneAvailable: @escaping LodestoneAvailability = Self.isLodestoneRunning,
        postLodestone: @escaping LodestonePoster = Self.postLodestoneCommand
    ) {
        self.postChord = postChord
        self.accessibilityTrusted = accessibilityTrusted
        self.inputAllowed = inputAllowed
        self.lodestoneAvailable = lodestoneAvailable
        self.postLodestone = postLodestone
    }

    /// Test-only convenience that avoids coupling command-routing tests to TCC.
    /// Pins the Magnet keyboard route so the tests don't depend on whether
    /// Lodestone happens to be running on the machine executing them.
    init(_ postChord: @escaping ChordPoster) {
        self.init(
            postChord: postChord,
            accessibilityTrusted: { true },
            inputAllowed: { true },
            lodestoneAvailable: { false }
        )
    }

    func perform(_ action: ModeUtilityAction) -> Result<Void, MagnetWindowActionError> {
        guard inputAllowed() else { return .failure(.inputBlocked) }
        guard accessibilityTrusted() else {
            return .failure(.accessibilityPermissionMissing)
        }

        // The Accessibility gate above deliberately also covers the
        // Lodestone route: the wedge keeps one permission contract whichever
        // app serves it, and an untrusted Agentic Mouse fails closed.
        if let commandID = Self.lodestoneCommandID(for: action), lodestoneAvailable() {
            return postLodestone(commandID) ? .success(()) : .failure(.eventCreationFailed)
        }

        guard let events = Self.keyEvents(for: action) else {
            preconditionFailure("MagnetWindowActionExecutor only owns Magnet Left and Right")
        }
        return postChord(events)
            ? .success(())
            : .failure(.eventCreationFailed)
    }

    /// Lodestone's stable command ids for the two wedge directions.
    static func lodestoneCommandID(for action: ModeUtilityAction) -> String? {
        switch action {
        case .moveWindowLeftWithMagnet: return "left"
        case .moveWindowRightWithMagnet: return "right"
        default: return nil
        }
    }

    /// Lodestone is a single-instance menu-bar app; "running" is the whole
    /// availability test. Checked per command (the wheel sequencer paces
    /// these to one every 400 ms), so quitting Lodestone mid-session falls
    /// straight back to Magnet on the next step.
    static func isLodestoneRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: lodestoneBundleIdentifier).isEmpty
    }

    /// Fire-and-forget: `deliverImmediately` because Lodestone is a
    /// background menu-bar app whose delivery would otherwise be deferred.
    /// Lodestone replies on `com.ethansk.lodestone.result` for diagnostics;
    /// the wedge does not wait for it.
    static func postLodestoneCommand(_ commandID: String) -> Bool {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(lodestonePerformNotification),
            object: commandID,
            userInfo: ["source": "agentic-mouse"],
            deliverImmediately: true
        )
        return true
    }

    static func keyEvents(for action: ModeUtilityAction) -> [KeyEvent]? {
        let arrowKeyCode: CGKeyCode
        switch action {
        case .moveWindowLeftWithMagnet:
            arrowKeyCode = leftArrowKeyCode
        case .moveWindowRightWithMagnet:
            arrowKeyCode = rightArrowKeyCode
        case .increaseDisplayBrightness, .decreaseDisplayBrightness,
             .rewindYouTubeFiveSeconds, .openIntelligenceOnDemand, .zoomIn, .zoomOut,
             .moveToSpaceLeft, .moveToSpaceRight,
             .selectAll, .tab, .save, .copy, .paste, .showDesktop, .missionControl,
             .pasteStoredPassword, .showApplicationWindows, .organizeWindows, .spotifySongRadio, .quitApp:
            return nil
        }

        let control: CGEventFlags = .maskControl
        let controlOption: CGEventFlags = [.maskControl, .maskAlternate]
        // Physical arrow keys carry both of these flags. Omitting them turns
        // the chord into an application-level escape sequence that Magnet's
        // global accelerator does not treat as its configured shortcut.
        let arrowFlags: CGEventFlags = [
            .maskControl,
            .maskAlternate,
            .maskSecondaryFn,
            .maskNumericPad,
        ]
        return [
            KeyEvent.modifier(keyCode: leftControlKeyCode, flags: control, at: 0),
            KeyEvent.modifier(keyCode: leftOptionKeyCode, flags: controlOption, at: 0.006),
            KeyEvent.key(keyCode: arrowKeyCode, flags: arrowFlags, isDown: true, at: 0.012),
            KeyEvent.key(keyCode: arrowKeyCode, flags: arrowFlags, isDown: false, at: 0.032),
            KeyEvent.modifier(keyCode: leftOptionKeyCode, flags: control, at: 0.038),
            KeyEvent.modifier(keyCode: leftControlKeyCode, flags: [], at: 0.044),
        ]
    }
}
