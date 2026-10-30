import Foundation

/// Shared native keyboard actions for the exact-device Keys mode.
///
/// Physical cells stay canonical. The left-handed Razer deliberately swaps the
/// horizontal arrow meanings so the gesture follows that mouse's mirrored
/// physical layout without renumbering either transport.
public enum KeysModeAction: CaseIterable, Equatable, Sendable {
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case undo
    case insertSpace
    case pressBackspace
    case save
    case holdShift

    public var cell: PhysicalCell {
        switch self {
        case .arrowUp: return PhysicalCell(rawValue: 5)!
        case .arrowDown: return PhysicalCell(rawValue: 4)!
        case .arrowLeft: return PhysicalCell(rawValue: 1)!
        case .arrowRight: return PhysicalCell(rawValue: 7)!
        case .undo: return PhysicalCell(rawValue: 3)!
        case .insertSpace: return PhysicalCell(rawValue: 8)!
        case .pressBackspace: return PhysicalCell(rawValue: 11)!
        case .save: return PhysicalCell(rawValue: 12)!
        case .holdShift: return PhysicalCell(rawValue: 2)!
        }
    }

    public func cell(for source: MouseSource) -> PhysicalCell {
        guard source == .razer else { return cell }
        switch self {
        case .arrowLeft: return PhysicalCell(rawValue: 7)!
        case .arrowRight: return PhysicalCell(rawValue: 1)!
        default: return cell
        }
    }

    public var actionTitle: String {
        switch self {
        case .arrowUp: return "↑ Up"
        case .arrowDown: return "↓ Down"
        case .arrowLeft: return "← Left"
        case .arrowRight: return "→ Right"
        case .undo: return "⌘Z Undo"
        case .insertSpace: return "␣ Space"
        case .pressBackspace: return "⌫ Backspace"
        case .save: return "⌘S Save"
        case .holdShift: return "⇧ Hold Shift"
        }
    }

    /// Action-card fill. All four arrows are one directional group; editing and
    /// text-entry controls remain individually identifiable.
    public var hudAccent: RGBColor {
        switch self {
        case .arrowUp, .arrowDown, .arrowLeft, .arrowRight:
            return ModeHUDActionFamilyPalette.arrowKeys
        case .undo:
            return ModeHUDActionFamilyPalette.historyNavigation
        case .insertSpace:
            return ModeHUDActionFamilyPalette.space
        case .pressBackspace:
            return ModeHUDActionFamilyPalette.backspace
        case .save:
            return ModeHUDActionFamilyPalette.save
        case .holdShift:
            return ModeHUDActionFamilyPalette.windowManagement
        }
    }

    /// Wand only: ordinary navigation and text keys that Ethan clicks over and
    /// over keep the open Keys HUD on the same card. One-shot or stateful keys
    /// (Undo, Save, Hold Shift) still finish and hide it. Physical mice are
    /// unaffected: they have no HUD selection to keep.
    public var keepsWandHUDOpen: Bool {
        switch self {
        case .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .insertSpace, .pressBackspace:
            return true
        case .undo, .save, .holdShift:
            return false
        }
    }

    public static func action(
        for cell: PhysicalCell,
        source: MouseSource = .corsair
    ) -> KeysModeAction? {
        allCases.first { $0.cell(for: source) == cell }
    }
}
