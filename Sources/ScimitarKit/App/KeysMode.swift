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
    case copy
    case paste
    case nextTrack
    case insertSpace
    case pressBackspace
    case pasteStoredPassword

    public var cell: PhysicalCell {
        switch self {
        case .arrowUp: return PhysicalCell(rawValue: 5)!
        case .arrowDown: return PhysicalCell(rawValue: 4)!
        case .arrowLeft: return PhysicalCell(rawValue: 1)!
        case .arrowRight: return PhysicalCell(rawValue: 7)!
        case .copy: return PhysicalCell(rawValue: 6)!
        case .paste: return PhysicalCell(rawValue: 3)!
        case .nextTrack: return PhysicalCell(rawValue: 9)!
        case .insertSpace: return PhysicalCell(rawValue: 8)!
        case .pressBackspace: return PhysicalCell(rawValue: 11)!
        case .pasteStoredPassword: return PhysicalCell(rawValue: 2)!
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
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .nextTrack: return "Next Track"
        case .insertSpace: return "Space"
        case .pressBackspace: return "Backspace"
        case .pasteStoredPassword: return "Paste password"
        }
    }

    /// Action-card fill. All four arrows are one directional group; editing and
    /// text-entry controls remain individually identifiable.
    public var hudAccent: RGBColor {
        switch self {
        case .arrowUp, .arrowDown, .arrowLeft, .arrowRight:
            return ModeHUDActionFamilyPalette.arrowKeys
        case .copy, .paste:
            return ModeHUDActionFamilyPalette.clipboard
        case .nextTrack:
            return ModeHUDActionFamilyPalette.media
        case .insertSpace:
            return ModeHUDActionFamilyPalette.space
        case .pressBackspace:
            return ModeHUDActionFamilyPalette.backspace
        case .pasteStoredPassword:
            return ModeHUDActionFamilyPalette.storedPassword
        }
    }

    public static func action(
        for cell: PhysicalCell,
        source: MouseSource = .corsair
    ) -> KeysModeAction? {
        allCases.first { $0.cell(for: source) == cell }
    }
}
