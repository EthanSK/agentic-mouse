import Foundation

/// The twelve side buttons of the Scimitar, named by the number printed on the
/// mouse itself.
///
/// Physical layout (thumb side, viewed from the left of the mouse). Corsair
/// numbers the pad in four columns of three, front to back:
///
///     ┌────┬────┬────┬────┐
///     │  1 │  4 │  7 │ 10 │   ← top row
///     ├────┼────┼────┼────┤
///     │  2 │  5 │  8 │ 11 │
///     ├────┼────┼────┼────┤
///     │  3 │  6 │  9 │ 12 │   ← bottom row
///     └────┴────┴────┴────┘
///        front ────────► back
///
/// Rotate that ninety degrees and it *is* a phone keypad: each physical column
/// is one keypad row, and the numbers already line up.
///
///     1 2 3      column 1 → 1 2 3
///     4 5 6      column 2 → 4 5 6
///     7 8 9      column 3 → 7 8 9
///     * 0 #      column 4 → * 0 #   (buttons 10, 11, 12)
///
/// That coincidence is the whole reason this mapping is learnable: button *n*
/// is keypad key *n*, with no translation table to memorise.
public enum MultiTapKey: Int, CaseIterable, Codable, Hashable, Sendable {
    case k1 = 1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12

    /// Zero-based column in the physical 4×3 pad (0 = frontmost).
    public var physicalColumn: Int { (rawValue - 1) / 3 }
    /// Zero-based row in the physical 4×3 pad (0 = top).
    public var physicalRow: Int { (rawValue - 1) % 3 }

    /// Zero-based row on the equivalent phone keypad (0 = the "1 2 3" row).
    public var keypadRow: Int { physicalColumn }
    /// Zero-based column on the equivalent phone keypad.
    public var keypadColumn: Int { physicalRow }

    /// The glyph a phone would print on this key.
    public var keypadLegend: String {
        switch self {
        case .k10: return "*"
        case .k11: return "0"
        case .k12: return "#"
        default: return String(rawValue)
        }
    }
}

/// What a key does when it is not simply cycling through letters.
public enum KeyAction: Equatable, Hashable, Codable, Sendable {
    case space
    case newline
    case backspace
    /// Deletes back to the start of the previous word.
    case deleteWord
    /// Advances abc → Abc → ABC → 123 → abc.
    case shiftCycle
    /// Leaves multi-tap mode, restoring the ordinary mouse immediately.
    case exitMode
}

/// Text-entry case/number state, exactly as a feature phone showed it in the
/// corner of the screen.
public enum ShiftState: String, CaseIterable, Codable, Sendable {
    /// `abc` — everything lower case.
    case lower
    /// `Abc` — the next letter committed is capitalised, then it falls back to `abc`.
    case initialCaps
    /// `ABC` — locked upper case.
    case upper
    /// `123` — every key emits its digit on the first press, no cycling.
    case numeric

    public var indicator: String {
        switch self {
        case .lower: return "abc"
        case .initialCaps: return "Abc"
        case .upper: return "ABC"
        case .numeric: return "123"
        }
    }

    public var next: ShiftState {
        switch self {
        case .lower: return .initialCaps
        case .initialCaps: return .upper
        case .upper: return .numeric
        case .numeric: return .lower
        }
    }

    public var isNumeric: Bool { self == .numeric }
}

/// Everything one physical button does inside multi-tap mode.
public struct KeySpec: Equatable, Sendable {
    /// Characters cycled by repeated taps. Empty for pure command keys.
    public var cycle: [Character]
    /// Character produced in `123` mode and by a long press in the letter modes.
    /// This is how digits stay reachable without stealing a button.
    public var numericCharacter: Character?
    /// Action performed by a short press when `cycle` is empty.
    public var tapAction: KeyAction?
    /// Action performed by a long press when `cycle` is empty.
    public var holdAction: KeyAction?
    /// Short caption shown on the HUD, e.g. `ABC` or `SPACE`.
    public var caption: String
    /// Secondary caption describing the long press, e.g. `hold: 2`.
    public var holdCaption: String?

    public init(
        cycle: [Character] = [],
        numericCharacter: Character? = nil,
        tapAction: KeyAction? = nil,
        holdAction: KeyAction? = nil,
        caption: String,
        holdCaption: String? = nil
    ) {
        self.cycle = cycle
        self.numericCharacter = numericCharacter
        self.tapAction = tapAction
        self.holdAction = holdAction
        self.caption = caption
        self.holdCaption = holdCaption
    }

    public var isCycling: Bool { !cycle.isEmpty }

    /// Applies the current case state to a cycled character.
    public func character(atCycleIndex index: Int, shift: ShiftState) -> Character? {
        guard !cycle.isEmpty else { return nil }
        let base = cycle[((index % cycle.count) + cycle.count) % cycle.count]
        switch shift {
        case .lower:
            return base
        case .initialCaps, .upper:
            let upper = String(base).uppercased()
            return upper.count == 1 ? Character(upper) : base
        case .numeric:
            return numericCharacter ?? base
        }
    }
}

/// The complete button → behaviour table.
public struct MultiTapKeymap: Equatable, Sendable {
    public private(set) var specs: [MultiTapKey: KeySpec]

    public init(specs: [MultiTapKey: KeySpec]) {
        self.specs = specs
    }

    public subscript(key: MultiTapKey) -> KeySpec? { specs[key] }

    public func withSpec(_ spec: KeySpec, for key: MultiTapKey) -> MultiTapKeymap {
        var copy = specs
        copy[key] = spec
        return MultiTapKeymap(specs: copy)
    }

    /// The button that both enters and leaves multi-tap mode.
    public var exitKey: MultiTapKey? {
        MultiTapKey.allCases.first { specs[$0]?.tapAction == .exitMode }
    }

    /// The classic layout.
    ///
    /// Letters are the universal ITU-T E.161 assignment — the one printed on
    /// every phone ever made — so no relearning is required:
    ///
    ///   2 ABC · 3 DEF · 4 GHI · 5 JKL · 6 MNO · 7 PQRS · 8 TUV · 9 WXYZ
    ///
    /// Key 1 keeps its traditional role as the punctuation key. The final
    /// column carries the three controls that a phone put on `*`, `0` and `#`:
    ///
    ///   10 (`*`) tap = Backspace, hold = case/number cycle
    ///   11 (`0`) tap = Space,     hold = Return
    ///   12 (`#`) tap = Exit multi-tap mode
    ///
    /// One rule covers the whole pad: **tap gives the common thing, hold gives
    /// the secondary thing.** On keys 1–9 the secondary thing is the digit.
    public static let classic: MultiTapKeymap = {
        func letters(_ key: MultiTapKey, _ text: String) -> (MultiTapKey, KeySpec) {
            let chars = Array(text.lowercased())
            let digit = Character(String(key.rawValue))
            return (key, KeySpec(
                cycle: chars,
                numericCharacter: digit,
                caption: text.uppercased(),
                holdCaption: "hold \(digit)"
            ))
        }

        var specs: [MultiTapKey: KeySpec] = [:]

        // Key 1: the punctuation key. Ordered by how often each mark is
        // actually typed, so the common ones need the fewest taps.
        specs[.k1] = KeySpec(
            cycle: [".", ",", "?", "!", "'", "\"", "-", ":", ";", "/", "(", ")", "@"],
            numericCharacter: "1",
            caption: ".,?!",
            holdCaption: "hold 1"
        )

        for (key, spec) in [
            letters(.k2, "abc"),
            letters(.k3, "def"),
            letters(.k4, "ghi"),
            letters(.k5, "jkl"),
            letters(.k6, "mno"),
            letters(.k7, "pqrs"),
            letters(.k8, "tuv"),
            letters(.k9, "wxyz")
        ] {
            specs[key] = spec
        }

        specs[.k10] = KeySpec(
            tapAction: .backspace,
            holdAction: .shiftCycle,
            caption: "DEL",
            holdCaption: "hold aA1"
        )
        specs[.k11] = KeySpec(
            numericCharacter: "0",
            tapAction: .space,
            holdAction: .newline,
            caption: "SPACE",
            holdCaption: "hold ⏎"
        )
        specs[.k12] = KeySpec(
            tapAction: .exitMode,
            caption: "EXIT",
            holdCaption: nil
        )

        return MultiTapKeymap(specs: specs)
    }()

    /// The shared Modes-menu keypad. Cells 1...9 keep the familiar phone
    /// punctuation/letter layout and digit holds. Universal runtime exit cell
    /// 10 leaves the text engine, cell 11 inserts Space, and cell 12 taps
    /// Backspace or holds Return.
    public static let modesKeypad: MultiTapKeymap = {
        var map = classic
        map = map.withSpec(KeySpec(tapAction: .exitMode, caption: "EXIT"), for: .k10)
        map = map.withSpec(
            KeySpec(tapAction: .space, caption: "SPACE"),
            for: .k11
        )
        map = map.withSpec(
            KeySpec(
                tapAction: .backspace,
                holdAction: .newline,
                caption: "BACKSPACE",
                holdCaption: "hold ⏎"
            ),
            for: .k12
        )
        return map
    }()
}
