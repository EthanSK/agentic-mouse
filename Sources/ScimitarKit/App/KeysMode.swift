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

    public var cell: PhysicalCell {
        switch self {
        case .arrowUp: return PhysicalCell(rawValue: 5)!
        case .arrowDown: return PhysicalCell(rawValue: 4)!
        case .arrowLeft: return PhysicalCell(rawValue: 1)!
        case .arrowRight: return PhysicalCell(rawValue: 7)!
        case .undo: return PhysicalCell(rawValue: 3)!
        case .insertSpace: return PhysicalCell(rawValue: 8)!
        case .pressBackspace: return PhysicalCell(rawValue: 11)!
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
        case .arrowUp: return "Up Arrow"
        case .arrowDown: return "Down Arrow"
        case .arrowLeft: return "Left Arrow"
        case .arrowRight: return "Right Arrow"
        case .undo: return "Undo"
        case .insertSpace: return "Space"
        case .pressBackspace: return "Backspace"
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
        }
    }

    public static func action(
        for cell: PhysicalCell,
        source: MouseSource = .corsair
    ) -> KeysModeAction? {
        allCases.first { $0.cell(for: source) == cell }
    }
}
