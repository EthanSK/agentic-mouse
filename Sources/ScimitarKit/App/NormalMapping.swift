import Foundation

/// The side-button assignments that live in **iCUE**, recorded here so the
/// helper can describe and check them.
///
/// This type configures nothing. iCUE owns these assignments; the helper never
/// writes an iCUE profile and never edits iCUE's database. What it is for:
///
///  * `agentic-mouse-doctor mapping` prints it, so the profile in iCUE can be
///    checked against what the helper believes is true.
///  * Tests assert that the multi-tap toggle does not displace an assignment.
///  * It is the single place to correct when the mapping changes, instead of a
///    dozen prose descriptions drifting out of date in the docs.
///
/// While multi-tap mode is active, buttons 1–12 are intercepted through
/// `CAL_ExclusiveKeyEventsListening` and none of these actions fire. Exiting
/// releases the interception, and iCUE resumes whichever profile is applicable
/// — the normal one, or the VS Code one if VS Code is frontmost.
public struct ScimitarNormalMapping: Equatable, Sendable {

    /// A single button's documented purpose.
    public struct Assignment: Equatable, Sendable {
        public let button: Int
        /// What it does, in Ethan's words.
        public let action: String
        /// How it is implemented in iCUE, where that matters for verification.
        public let implementation: String?

        public init(button: Int, action: String, implementation: String? = nil) {
            self.button = button
            self.action = action
            self.implementation = implementation
        }
    }

    public let profileName: String
    public let assignments: [Assignment]
    /// Set when this profile is linked to a specific application in iCUE.
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

    /// The default profile.
    ///
    /// Buttons 5/8 are the ordinary Forward/Back pair and 7/10 are the
    /// horizontal-scroll pair. Speech-to-text sits on button 4 because that is
    /// where the thumb naturally rests — the DPI Toggle button is explicitly
    /// **disabled** and must never trigger it.
    public static let normal = ScimitarNormalMapping(
        profileName: "Normal",
        assignments: [
            Assignment(
                button: 4,
                action: "VoiceInk++ speech-to-text toggle",
                implementation: "direct iCUE macro: LeftShift+LeftCtrl+LeftAlt press, then the reverse release sequence"
            ),
            Assignment(button: 5, action: "Forward"),
            Assignment(button: 6, action: "Next Track"),
            Assignment(button: 7, action: "Horizontal scroll left", implementation: "repeating while held"),
            Assignment(button: 8, action: "Back"),
            Assignment(button: 9, action: "Previous Track"),
            Assignment(button: 10, action: "Horizontal scroll right", implementation: "repeating while held"),
            Assignment(
                button: 12,
                action: "Multi-tap mode toggle",
                implementation: "no iCUE assignment; the helper listens for the raw CMKI_12 macro-key event"
            )
        ]
    )

    /// The application-linked profile for VS Code.
    ///
    /// It overrides **only** 7, 8 and 10, sending function keys that VS Code
    /// binds to Better Git commands. Buttons 4, 5, 6 and 9 deliberately keep
    /// their normal behaviour, so speech-to-text, Forward/Back and track
    /// skipping work identically inside and outside the editor.
    ///
    /// Think of 7/8 as moving through the diff in 3D: 8 goes "up" to the
    /// previous change, 7 goes "down" to the next one, and 10 — right beside
    /// them — stages what you are looking at.
    public static let vsCode = ScimitarNormalMapping(
        profileName: "VS Code",
        assignments: [
            Assignment(button: 4, action: "VoiceInk++ speech-to-text toggle", implementation: "inherited from Normal"),
            Assignment(button: 5, action: "Forward", implementation: "inherited from Normal"),
            Assignment(button: 6, action: "Next Track", implementation: "inherited from Normal"),
            Assignment(
                button: 7,
                action: "Better Git: next change",
                implementation: "F13 → better-git-vscode.next-scm-change"
            ),
            Assignment(
                button: 8,
                action: "Better Git: previous change",
                implementation: "F17 → better-git-vscode.previous-scm-change"
            ),
            Assignment(button: 9, action: "Previous Track", implementation: "inherited from Normal"),
            Assignment(
                button: 10,
                action: "Better Git: stage current file",
                implementation: "F18 → better-git-vscode.stage-current-file"
            ),
            Assignment(
                button: 12,
                action: "Multi-tap mode toggle",
                implementation: "no iCUE assignment; the helper listens for the raw CMKI_12 macro-key event"
            )
        ],
        linkedApplicationPath: "/Applications/Visual Studio Code.app"
    )

    public static let allProfiles: [ScimitarNormalMapping] = [.normal, .vsCode]

    /// Controls that are **never** part of the multi-tap grid and are never
    /// intercepted, in any mode.
    ///
    /// The DPI Toggle button matters most here: it is disabled in iCUE, and it
    /// must not acquire a speech-to-text role by accident. Speech-to-text is on
    /// side button 4 and nowhere else.
    public static let untouchedControls: [String] = [
        "Left click",
        "Right click",
        "Wheel scroll (vertical)",
        "Wheel press — Play/Pause",
        "Pointer movement",
        "DPI Toggle button — disabled in iCUE; must never trigger speech-to-text"
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
