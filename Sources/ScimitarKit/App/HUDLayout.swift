import Foundation

/// Pure layout + label derivation for the reference HUD.
///
/// Kept out of the AppKit layer so the thing most likely to be wrong — what
/// each cell says, and which cell is highlighted — is unit-testable without a
/// window server.
public enum HUDLayout {

    /// One cell of the on-screen grid.
    public struct Cell: Equatable, Sendable {
        public let key: MultiTapKey
        /// The large positional label. Runtime Keypad uses the exact number
        /// printed on the source mouse; the standalone classic map retains the
        /// historical phone glyphs.
        public let legend: String
        /// `ABC`, `SPACE`, `DEL`, `EXIT`, …
        public let caption: String
        /// `hold 2`, `hold ⏎`, … or nil.
        public let holdCaption: String?
        /// The exact characters this key cycles through, already case-folded to
        /// the current shift state, so the HUD shows `ABC` in caps mode.
        public let cycle: [String]
        /// Index of the pending character within `cycle`, when this key is the
        /// one being tapped.
        public let activeCycleIndex: Int?
        public let isPending: Bool
        public let isHeld: Bool
        /// The dedicated enter/exit control.
        public let isModeToggle: Bool

        public var isCommandKey: Bool { cycle.isEmpty }
    }

    /// The grid as it appears on the mouse: four columns, three rows.
    ///
    /// Rendering it in the mouse's own geometry — rather than as a phone
    /// keypad — is deliberate. The user is looking at their thumb, so the HUD
    /// has to match what their thumb can feel. The phone digit is printed in
    /// each cell so the familiar `2 = ABC` mapping stays obvious.
    public static let columnCount = 4
    public static let rowCount = 3

    /// Row-major cells from the top of the mouse to the desk, i.e.
    /// `[[3, 6, 9, 12], [2, 5, 8, 11], [1, 4, 7, 10]]`.
    public static func grid(for snapshot: HUDSnapshot, toggleKey: MultiTapKey = .k12) -> [[Cell]] {
        PhysicalCell.displayRowsTopToBottom(for: snapshot.source).map { row in
            row.map { physicalCell in
                let key = MultiTapKey(rawValue: physicalCell.rawValue) ?? .k1
                return cell(for: key, snapshot: snapshot, toggleKey: toggleKey)
            }
        }
    }

    public static func cell(
        for key: MultiTapKey,
        snapshot: HUDSnapshot,
        toggleKey: MultiTapKey = .k12
    ) -> Cell {
        let spec = snapshot.keymap[key]
        let shift = snapshot.state.shift
        let isPending = snapshot.state.pendingKey == key

        let cycle: [String] = (spec?.cycle.indices ?? (0..<0)).compactMap { index in
            spec?.character(atCycleIndex: index, shift: shift).map(String.init)
        }

        return Cell(
            key: key,
            legend: legend(for: key, snapshot: snapshot),
            caption: caption(for: spec, shift: shift),
            holdCaption: spec?.holdCaption,
            cycle: cycle,
            activeCycleIndex: isPending ? snapshot.state.pendingCycleIndex : nil,
            isPending: isPending,
            isHeld: snapshot.state.heldKey == key,
            isModeToggle: key == toggleKey
        )
    }

    /// Runtime Keypad is learned against the physical mouse, not a fictional
    /// phone bottom row. Source projection also places Razer printed 1 at its
    /// real top-right position without changing any canonical action cell.
    static func legend(for key: MultiTapKey, snapshot: HUDSnapshot) -> String {
        guard snapshot.keymap == .modesKeypad,
              let physicalCell = PhysicalCell(rawValue: key.rawValue),
              let printedSide = physicalCell.printedSide(on: snapshot.source)
        else { return key.keypadLegend }
        return String(printedSide)
    }

    /// In `123` mode a letter key shows its digit rather than `ABC`, which is
    /// what a phone did and what stops the HUD lying about what a press will do.
    static func caption(for spec: KeySpec?, shift: ShiftState) -> String {
        guard let spec else { return "" }
        if shift.isNumeric, let digit = spec.numericCharacter {
            return String(digit)
        }
        guard spec.isCycling else { return spec.caption }
        switch shift {
        case .lower:
            return spec.caption.lowercased()
        case .initialCaps, .upper, .numeric:
            return spec.caption.uppercased()
        }
    }

    /// The single line describing what is being typed right now.
    public static func pendingDescription(for snapshot: HUDSnapshot) -> String {
        if let refusal = snapshot.state.targetRefusal {
            return refusal.explanation
        }
        if let cancellation = snapshot.state.lastCancellation, snapshot.state.pendingCharacter == nil {
            switch cancellation {
            case .targetChanged:
                return "Focus moved — pending letter discarded."
            case .targetRefused(let reason):
                return reason.explanation
            case .modeExited:
                return ""
            }
        }
        guard let character = snapshot.state.pendingCharacter else {
            return "Ready"
        }
        let position = snapshot.state.pendingCycleIndex + 1
        let total = max(snapshot.state.pendingCycleLength, position)
        return "\(character)  ·  tap \(position) of \(total)"
    }

    /// 1.0 right after a tap, decaying to 0.0 at the commit deadline. `nil`
    /// when nothing is pending.
    public static func pendingProgress(for snapshot: HUDSnapshot) -> Double? {
        snapshot.state.pendingProgress(now: snapshot.now, timeout: snapshot.multiTapTimeout)
    }

    /// Short status line: the case indicator plus anything worth flagging.
    public static func statusLine(for snapshot: HUDSnapshot) -> String {
        var parts = [snapshot.state.shift.indicator]
        if let problem = snapshot.problem, !problem.isEmpty {
            parts.append(problem)
        }
        return parts.joined(separator: "  ·  ")
    }
}
