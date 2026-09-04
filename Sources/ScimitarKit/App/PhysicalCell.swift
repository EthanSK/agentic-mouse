import Foundation

/// The two exact-device adapters that can feed one shared thumb-grid mode.
public enum MouseSource: String, Codable, CaseIterable, Hashable, Sendable {
    case corsair
    case razer

    public var displayName: String {
        switch self {
        case .corsair: return "Corsair"
        case .razer: return "Razer"
        }
    }
}

/// Canonical physical position in the mirrored 4×3 thumb grid.
///
/// Corsair's printed number is already the physical-cell number. The
/// left-handed Naga reverses the top/bottom numbering inside each column, so a
/// separate explicit crosswalk is required. Runtime modes exchange this type,
/// never a vendor's printed label.
public struct PhysicalCell: RawRepresentable, Hashable, Codable, Sendable, Comparable {
    public let rawValue: Int

    public init?(rawValue: Int) {
        guard (1...12).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public static let all: [PhysicalCell] = (1...12).compactMap(PhysicalCell.init(rawValue:))

    /// The thumb grid as Ethan sees it, ordered from the top row to the desk.
    /// Corsair's first number in each column is physically at the bottom, so
    /// presenting `1, 4, 7, 10` first would draw the mouse upside down.
    public static let displayRowsTopToBottom: [[PhysicalCell]] = [
        [3, 6, 9, 12],
        [2, 5, 8, 11],
        [1, 4, 7, 10],
    ].map { $0.compactMap(PhysicalCell.init(rawValue:)) }

    /// Draws the same canonical physical cells from the perspective of the
    /// mouse that opened the HUD. The left-handed Razer sits on the opposite
    /// side of the desk, so its four columns are the horizontal mirror of the
    /// right-handed Corsair. This changes presentation only; action ownership
    /// and the cross-device physical-cell contract remain canonical.
    public static func displayRowsTopToBottom(for source: MouseSource) -> [[PhysicalCell]] {
        switch source {
        case .corsair:
            return displayRowsTopToBottom
        case .razer:
            return displayRowsTopToBottom.map { Array($0.reversed()) }
        }
    }

    /// Source-only first-iteration entry candidate. Keep the generated metadata
    /// and visible labels pinned to this value in tests before any live install.
    public static let colorProofEntry = PhysicalCell(rawValue: 3)!

    /// Shared ordinary top-level persistent Default-legend toggle. This is
    /// Corsair printed 10 and the mirrored left-handed Razer printed 12.
    /// The same physical cell remains the universal Exit inside runtime modes.
    public static let defaultMapToggle = PhysicalCell(rawValue: 10)!

    public static func defaultMapToggle(for source: MouseSource) -> PhysicalCell {
        defaultMapToggle
    }

    /// Ordinary top-level selected-area screenshot toggle. This is Corsair
    /// printed 3 and the mirrored left-handed Razer printed 1.
    public static let screenshotToggle = PhysicalCell(rawValue: 3)!

    /// Entry cell for the shared Utility mode.
    /// This is Corsair printed 12 and left-handed Razer printed 10.
    public static let modePickerEntry = PhysicalCell(rawValue: 12)!

    /// Universal exit for every active runtime mode.
    /// This is Corsair printed 10 and the mirrored Razer printed 12. Outside
    /// a runtime mode, the same physical cell toggles the persistent Default
    /// legend.
    public static let modeExit = PhysicalCell(rawValue: 10)!

    /// Historical Colour Proof-only HUD control retained for its isolated
    /// regression harness. Live product modes do not reserve cell 3: Utility
    /// uses it for Spaces + Wheel, Keypad restores DEF, and other pages show
    /// Spare.
    public static let modeHUDToggle = PhysicalCell(rawValue: 3)!

    /// Selects Keypad from Keys mode.
    public static let keypadModeSelector = PhysicalCell(rawValue: 6)!

    /// Two-way media-track wheel chord inside Keys mode. This is Corsair
    /// printed 9 and Razer printed 7 through the canonical crosswalk.
    public static let mediaTracksWheelControl = PhysicalCell(rawValue: 9)!

    /// Two-way Utility controls. Hold the cell and move the ratcheted wheel;
    /// one wheel step produces one action in the corresponding direction.
    public static let brightnessWheelControl = PhysicalCell(rawValue: 1)!
    public static let zoomWheelControl = PhysicalCell(rawValue: 11)!
    public static let spacesWheelControl = PhysicalCell(rawValue: 3)!
    public static let systemOverviewWheelControl = PhysicalCell(rawValue: 4)!
    public static let applicationWindowsWheelControl = PhysicalCell(rawValue: 5)!
    public static let magnetWheelControl = PhysicalCell(rawValue: 6)!

    /// Ordinary top-level Copy / Paste wheel chord. This is Corsair printed 4
    /// and Razer printed 6 through the canonical physical-cell crosswalk.
    public static let clipboardWheelControl = PhysicalCell(rawValue: 4)!

    /// Types the optional device-local Keychain password from Utility.
    public static let storedPassword = PhysicalCell(rawValue: 7)!

    /// Ordinary top-level horizontal-wheel conversion. Hold cell 1 and use the
    /// same mouse's wheel.
    public static let horizontalScrollWheelControl = PhysicalCell(rawValue: 1)!

    /// Ordinary top-level YouTube scrub wheel chord. Hold cell 6 and use the
    /// same mouse's wheel; each reconstructed ratchet seeks exactly five
    /// seconds through the background VoiceInk YouTube Bridge.
    public static let youtubeScrubWheelControl = PhysicalCell(rawValue: 6)!

    /// Rewinds the selected YouTube target through the existing VoiceInk
    /// YouTube Bridge without bringing Chrome to the front. This is a
    /// top-level action on Corsair printed 6 / Razer printed 4.
    public static let youtubeBackFiveSeconds = PhysicalCell(rawValue: 6)!

    /// Opens the configured-app selector from Utility.
    public static let appSpecificModeSelector = PhysicalCell(rawValue: 2)!

    /// Opens the nested Extra Utilities page from Utility. This is Corsair
    /// printed 12 and Razer printed 10 through the canonical crosswalk. The
    /// same canonical cell remains available to app-specific pages because
    /// active-page semantics, not device transports, own the action.
    public static let extraUtilitiesSelector = PhysicalCell(rawValue: 12)!

    /// Restores Stay's saved Agentic Mouse window layout from Extra Utilities.
    /// This is Corsair printed 1 and Razer printed 3.
    public static let organizeWindows = PhysicalCell(rawValue: 1)!

    /// Starts the current Spotify song's radio from Extra Utilities.
    /// Ethan approved Corsair printed 3 / Razer printed 1 for this action.
    public static let spotifySongRadio = PhysicalCell(rawValue: 3)!

    /// Sends a normal Command-Q to the current frontmost application from
    /// Extra Utilities. This is Corsair printed 9 and Razer printed 7.
    public static let quitApp = PhysicalCell(rawValue: 9)!

    /// Sends one Control-C keyboard interrupt from terminal-capable
    /// app-specific modes. Extra Utilities owns this cell only while that
    /// nested page is active.
    public static let interruptTerminal = PhysicalCell(rawValue: 12)!

    /// Opens the current frontmost application's mode from the ordinary layer.
    /// Inside any app-specific child page, the same physical cell exits that
    /// page exactly like `modeExit`. This is Corsair printed 2 and Razer
    /// printed 2.
    public static let frontmostAppModeSelector = PhysicalCell(rawValue: 2)!

    /// The two reserved exits on every app-specific child page. The manual
    /// app selector is a parent page, so it still uses cell 2 to choose
    /// Terminal and reserves only the universal cell-10 exit.
    public var isAppSpecificModeExit: Bool {
        self == Self.frontmostAppModeSelector || self == Self.modeExit
    }

    /// Opens the shared native arrow-key mode from Utility.
    public static let keysModeSelector = PhysicalCell(rawValue: 9)!

    /// Opens the shared native arrow-key mode directly from the ordinary layer.
    /// This is Corsair printed 9 and Razer printed 7.
    public static let keysModeEntry = PhysicalCell(rawValue: 9)!

    /// Opens Codex's global intelligence-on-demand window with Option-Space
    /// from Utility. Cell 8 is printed 8 on both exact mice.
    public static let intelligenceOnDemand = PhysicalCell(rawValue: 8)!

    /// Holds open the native macOS application switcher outside modes.
    public static let switchApp = PhysicalCell(rawValue: 11)!

    public static func < (lhs: PhysicalCell, rhs: PhysicalCell) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Razer printed side number -> canonical physical cell.
    public static let razerPrintedToPhysical: [Int: PhysicalCell] = [
        1: PhysicalCell(rawValue: 3)!,
        2: PhysicalCell(rawValue: 2)!,
        3: PhysicalCell(rawValue: 1)!,
        4: PhysicalCell(rawValue: 6)!,
        5: PhysicalCell(rawValue: 5)!,
        6: PhysicalCell(rawValue: 4)!,
        7: PhysicalCell(rawValue: 9)!,
        8: PhysicalCell(rawValue: 8)!,
        9: PhysicalCell(rawValue: 7)!,
        10: PhysicalCell(rawValue: 12)!,
        11: PhysicalCell(rawValue: 11)!,
        12: PhysicalCell(rawValue: 10)!,
    ]

    public static func fromPrintedSide(_ printedSide: Int, source: MouseSource) -> PhysicalCell? {
        switch source {
        case .corsair: return PhysicalCell(rawValue: printedSide)
        case .razer: return razerPrintedToPhysical[printedSide]
        }
    }

    public func printedSide(on source: MouseSource) -> Int? {
        switch source {
        case .corsair:
            return rawValue
        case .razer:
            return Self.razerPrintedToPhysical.first(where: { $0.value == self })?.key
        }
    }

    /// User-facing button label for the exact mouse that produced a HUD
    /// command. The two mice share physical cells but print different numbers,
    /// so a reference map must never display one device's label for the other.
    public func displayLabel(on source: MouseSource) -> String {
        "\(source.displayName) \(printedSide(on: source)!)"
    }
}
