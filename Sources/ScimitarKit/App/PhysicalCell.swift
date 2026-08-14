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

    /// Shared ordinary top-level Utility / legend control. One press opens
    /// Utility; a rapid second press toggles the persistent Default legend.
    public static let defaultMapToggle = PhysicalCell(rawValue: 12)!

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
    /// a runtime mode, the same physical cell is deliberately blank.
    public static let modeExit = PhysicalCell(rawValue: 10)!

    /// Historical Colour Proof-only HUD control retained for its isolated
    /// regression harness. Live product modes do not reserve cell 3: Utility
    /// uses it for Space Left, Keypad restores DEF, and other pages show Spare.
    public static let modeHUDToggle = PhysicalCell(rawValue: 3)!

    /// Selects Keypad from the Modes menu.
    public static let keypadModeSelector = PhysicalCell(rawValue: 7)!

    /// Adjusts the current macOS display brightness from Utility. The controls
    /// form the left vertical pair: cell 1 increases and cell 4 decreases.
    public static let brightnessIncrease = PhysicalCell(rawValue: 1)!
    public static let brightnessDecrease = PhysicalCell(rawValue: 4)!

    /// Rewinds the selected YouTube target through the existing VoiceInk
    /// YouTube Bridge without bringing Chrome to the front.
    public static let youtubeBackFiveSeconds = PhysicalCell(rawValue: 8)!

    /// Applies the standard macOS application zoom shortcuts to whichever app
    /// is frontmost when the Modes utility is pressed.
    public static let applicationZoomIn = PhysicalCell(rawValue: 2)!
    public static let applicationZoomOut = PhysicalCell(rawValue: 5)!

    /// Moves between adjacent macOS Spaces using the standard system
    /// Control-Left / Control-Right shortcuts.
    public static let desktopSpaceLeft = PhysicalCell(rawValue: 3)!
    public static let desktopSpaceRight = PhysicalCell(rawValue: 6)!

    /// Opens the configured-app selector from Utility.
    public static let appSpecificModeSelector = PhysicalCell(rawValue: 11)!

    /// Opens the current frontmost application's mode from the ordinary layer.
    public static let frontmostAppModeSelector = PhysicalCell(rawValue: 2)!

    /// Opens the shared native arrow-key mode from Utility.
    public static let keysModeSelector = PhysicalCell(rawValue: 9)!

    /// Opens the shared native arrow-key mode directly from the ordinary layer.
    public static let keysModeEntry = PhysicalCell(rawValue: 6)!

    /// Ordinary app-specific wildcard. It is silent unless the current app has
    /// an explicit override.
    public static let appShortcut = PhysicalCell(rawValue: 9)!

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
