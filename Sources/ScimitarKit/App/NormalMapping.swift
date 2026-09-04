import Foundation

/// The intended side-button semantics implemented by the generated Karabiner
/// adapter, recorded here so the helper can describe and check them.
///
/// This type configures nothing. iCUE owns Corsair hardware and neutral source
/// transports; Karabiner owns these semantics. The helper never writes an iCUE
/// profile or edits iCUE's database. What it is for:
///
///  * `agentic-mouse-doctor mapping` prints it, so the generated and installed
///    Karabiner rules can be checked against what the helper believes is true.
///  * Tests assert that the shared Modes entry does not leak a transport.
///  * It is the single place to correct when the mapping changes, instead of a
///    dozen prose descriptions drifting out of date in the docs.
///
/// While a runtime mode is active, exact-device Karabiner routing owns cells
/// 1–12 and none of these actions fire. Exiting clears the expiring lease, and
/// Karabiner resumes this base behavior or the VS Code override for cells 5/8.
public struct ScimitarNormalMapping: Equatable, Sendable {

    /// A single button's documented purpose.
    public struct Assignment: Equatable, Sendable {
        public let button: Int
        /// What it does, in Ethan's words.
        public let action: String
        /// How it is implemented, where that matters for verification.
        public let implementation: String?

        public init(button: Int, action: String, implementation: String? = nil) {
            self.button = button
            self.action = action
            self.implementation = implementation
        }
    }

    public let profileName: String
    public let assignments: [Assignment]
    /// Set when this semantic context is scoped to a specific application.
    public let linkedApplicationPath: String?

    public init(profileName: String, assignments: [Assignment], linkedApplicationPath: String? = nil) {
        self.profileName = profileName
        self.assignments = assignments
        self.linkedApplicationPath = linkedApplicationPath
    }

    public func assignment(for button: Int) -> Assignment? {
        assignments.first { $0.button == button }
    }

    // MARK: - The live configuration

    /// Every visible DPI stage, Sniper included, is set to this one value so the
    /// pointer feels identical to the Logitech regardless of stage.
    public static let unifiedDPI = 2750

    /// The default semantic layer.
    ///
    /// Buttons 5/8 are the ordinary Forward/Back pair. Holding cell 1 turns
    /// that mouse's ratcheted wheel into one-step horizontal scrolling;
    /// holding cell 4 turns it into Copy/Paste.
    /// Speech-to-text remains on the separate DPI control.
    public static let normal = ScimitarNormalMapping(
        profileName: "Normal",
        assignments: [
            Assignment(
                button: 1,
                action: "Horizontal Scroll + Wheel",
                implementation: "Hold the exact-device cell; Agentic Mouse converts each ratchet into one native horizontal step"
            ),
            Assignment(
                button: 2,
                action: "App-specific mode",
                implementation: "Exact-device Karabiner opens the current frontmost app mode; active cell 10 exits"
            ),
            Assignment(
                button: 3,
                action: "Screenshot",
                implementation: "Agentic Mouse toggles the native selected-area screenshot session"
            ),
            Assignment(
                button: 4,
                action: "Copy / Paste + Wheel",
                implementation: "Hold the exact-device cell; Agentic Mouse sends Paste or Copy for each accepted ratchet"
            ),
            Assignment(
                button: 5,
                action: "Forward · Hold + 6 for Volume",
                implementation: "Release without a cell-6 volume ratchet to send ordinary Forward; a same-source 6+5 wheel hold adjusts YouTube volume instead"
            ),
            Assignment(
                button: 6,
                action: "YouTube · Hold 2× / Scrub + Wheel",
                implementation: "Click to rewind five seconds; hold for 350 ms to request temporary 2× speed and restore the prior rate without seeking on release; wheel input cancels speed and scrubs by five seconds per ratchet without focusing Chrome"
            ),
            Assignment(
                button: 7,
                action: "Enter",
                implementation: "Karabiner action: press-enter outside runtime modes"
            ),
            Assignment(button: 8, action: "Back"),
            Assignment(
                button: 9,
                action: "Keys mode",
                implementation: "Exact-device Karabiner opens the shared native-key mode; active cell 10 exits"
            ),
            Assignment(
                button: 10,
                action: "Legend toggle / mode exit",
                implementation: "Toggles the persistent Default legend outside modes; universal Exit while a mode is active"
            ),
            Assignment(
                button: 11,
                action: "Switch App",
                implementation: "Karabiner action: hold-open-app-switcher outside runtime modes"
            ),
            Assignment(
                button: 12,
                action: "Utility modes",
                implementation: "One press opens Utility immediately"
            )
        ]
    )

    /// This readable helper records the default map. Karabiner separately owns
    /// the approved VS Code-only navigation override for physical cells 5/8.
    public static let allProfiles: [ScimitarNormalMapping] = [.normal]

    /// Controls that are **never** part of the multi-tap grid and are never
    /// intercepted, in any mode.
    ///
    /// The DPI Toggle control stays outside the side-grid interception. iCUE
    /// emits one neutral transport; Karabiner triggers VoiceInk++ on release
    /// without changing sensor DPI.
    public static let untouchedControls: [String] = [
        "Left click",
        "Right click",
        "Wheel scroll (vertical; temporarily captured only while a wheel chord is held)",
        "Wheel press — neutral middle click; exact-device Karabiner Play/Pause",
        "Pointer movement",
        "DPI Toggle button — neutral exact-device F19 transport; Karabiner triggers VoiceInk++ speech-to-text on physical release; does not change DPI"
    ]

    /// A human-readable table, used by `agentic-mouse-doctor mapping`.
    public func describe() -> String {
        var lines: [String] = []
        lines.append("Profile: \(profileName)")
        if let linkedApplicationPath {
            lines.append("Linked to: \(linkedApplicationPath)")
        }
        for assignment in assignments.sorted(by: { $0.button < $1.button }) {
            let detail = assignment.implementation.map { "  (\($0))" } ?? ""
            lines.append(String(format: "  %2d  %@%@", assignment.button, assignment.action, detail))
        }
        return lines.joined(separator: "\n")
    }
}

/// Projects the ordinary top-level meaning for the exact mouse that owns the
/// input. Printed labels and transports differ, but semantics are canonical
/// physical cells unless a separately documented hardware exception applies.
public enum DefaultMouseMapping {
    public static func assignment(
        for cell: PhysicalCell,
        source: MouseSource
    ) -> ScimitarNormalMapping.Assignment? {
        guard let assignment = ScimitarNormalMapping.normal.assignment(for: cell.rawValue) else {
            return nil
        }
        return assignment
    }
}
