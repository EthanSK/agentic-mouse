import Foundation

/// One cell in the reusable runtime-mode legend shown by Agentic Mouse.
/// Future modes supply their own action labels while reusing the same physical
/// cross-device grid and non-activating panel.
public struct ModeHUDLegendItem: Equatable, Hashable, Sendable {
    public let cell: PhysicalCell
    public let actionTitle: String
    public let detail: String?
    public let accent: RGBColor

    public init(cell: PhysicalCell, actionTitle: String, detail: String? = nil, accent: RGBColor) {
        self.cell = cell
        self.actionTitle = actionTitle
        self.detail = detail
        self.accent = accent
    }

}

/// Visual treatment for the reusable mode legend.
///
/// This is deliberately presentation-only. Runtime lighting continues to use
/// the mode's saturated identity colour, while the HUD can render that same
/// identity as a neutral reference, a fully opaque control surface, or a
/// softer app-specific pastel.
public enum ModeHUDPresentationStyle: String, Equatable, Sendable {
    case neutral
    case boldOpaque
    case pastel

    public var requiresOpaqueWindow: Bool { self != .neutral }

    public func displayAccent(_ color: RGBColor) -> RGBColor {
        switch self {
        case .neutral, .boldOpaque:
            return color
        case .pastel:
            return color.blended(with: .white, amount: 0.58)
        }
    }

    public func cardFill(_ color: RGBColor) -> RGBColor {
        switch self {
        case .neutral, .boldOpaque:
            return color
        case .pastel:
            return color.blended(with: .white, amount: 0.68)
        }
    }

    public func cardForeground(for fill: RGBColor) -> RGBColor {
        guard self != .neutral else { return .white }
        return fill.relativeLuminance > 0.62
            ? RGBColor(red: 18, green: 22, blue: 30)
            : .white
    }
}

/// The two independent colour roles of one HUD card.
///
/// The mode colour forms a consistent perimeter across the whole grid, while
/// the action colour remains inside the card. This makes the active mode
/// legible at a glance without discarding per-action distinctions.
public struct ModeHUDCardColors: Equatable, Sendable {
    public let border: RGBColor
    public let fill: RGBColor
    public let foreground: RGBColor

    public init(
        modeAccent: RGBColor,
        actionAccent: RGBColor,
        presentationStyle: ModeHUDPresentationStyle = .neutral
    ) {
        border = presentationStyle.displayAccent(modeAccent)
        fill = presentationStyle.cardFill(actionAccent)
        foreground = presentationStyle.cardForeground(for: fill)
    }
}

/// Shared spacing tokens for the reusable mode and Keypad cards.
public enum ModeHUDLayoutMetrics {
    /// Keeps two-line labels and compact keypad previews clear of the card
    /// perimeter without changing the accepted outer grid geometry.
    public static let cardHorizontalContentInset: CGFloat = 12
}

/// Shared fill colours for semantically related HUD actions.
///
/// A mode's accent remains the perimeter of every card. Inside that perimeter,
/// controls that form one pair or directional group deliberately share one
/// fill colour, while unrelated controls keep distinct fills. New modes should
/// reuse an existing family or add one explicit family rather than choosing
/// per-button colours independently.
public enum ModeHUDActionFamilyPalette {
    public static let horizontalScroll = RGBColor(red: 42, green: 201, blue: 224)
    public static let historyNavigation = RGBColor(red: 78, green: 151, blue: 255)
    public static let brightness = RGBColor(red: 255, green: 196, blue: 45)
    public static let applicationZoom = RGBColor(red: 35, green: 218, blue: 177)
    public static let desktopSpaces = RGBColor(red: 66, green: 132, blue: 255)
    public static let arrowKeys = RGBColor(red: 255, green: 170, blue: 28)
    public static let clipboard = RGBColor(red: 52, green: 210, blue: 184)
    public static let enter = RGBColor(red: 48, green: 218, blue: 126)
    public static let space = RGBColor(red: 55, green: 150, blue: 255)
    public static let backspace = RGBColor(red: 255, green: 70, blue: 92)
    public static let storedPassword = RGBColor(red: 190, green: 86, blue: 255)
    public static let media = RGBColor(red: 82, green: 214, blue: 132)
    public static let reasoningEffort = RGBColor(red: 174, green: 112, blue: 255)
}

/// Plain user-facing copy shared by every reference-map presentation.
/// Architectural terms such as "passive" describe implementation behavior,
/// not Ethan, and must never appear as HUD labels.
public enum ModeHUDCopy {
    public static let referenceStatus = "BUTTON MAP"
    /// The card only exists inside the legend it controls, so a stable control
    /// name is clearer than state copy that can only ever be seen while open.
    public static let legendToggleTitle = "Legend toggle"

    public static func screenshotActionTitle(isCapturing: Bool) -> String {
        isCapturing ? "Cancel screenshot" : "Screenshot"
    }

    public static func referenceHeader(for source: MouseSource) -> String {
        "\(source.displayName.uppercased()) BUTTON MAP"
    }
}

/// The reusable presentation contract for a mouse mode or a short mapping
/// reminder. Runtime modes can highlight one physical cell; passive reminders
/// deliberately leave `selection` nil so they never look like a latched mode.
public struct ModeHUDSelection: Equatable, Sendable {
    public let cell: PhysicalCell
    public let title: String
    public let detail: String?
    public let accent: RGBColor

    public init(cell: PhysicalCell, title: String, detail: String? = nil, accent: RGBColor) {
        self.cell = cell
        self.title = title
        self.detail = detail
        self.accent = accent
    }
}

public struct ModeHUDSnapshot: Equatable, Sendable {
    public var isActive: Bool
    public var modeTitle: String
    public var source: MouseSource
    public var selection: ModeHUDSelection?
    public var legend: [ModeHUDLegendItem]
    public var accent: RGBColor
    public var lightingTargets: ModeLightingTargets
    public var footerTitle: String
    public var footerHint: String?
    public var problem: String?
    public var presentationStyle: ModeHUDPresentationStyle
    /// Show one copy of this reference HUD on every connected display.
    /// Persistent Default and active-mode legends use this as an explicit
    /// reference surface rather than a transient toast.
    public var showsOnAllDisplays: Bool

    public var lightingAvailable: Bool { !lightingTargets.isEmpty }

    public init(
        isActive: Bool,
        modeTitle: String,
        source: MouseSource,
        selection: ModeHUDSelection?,
        legend: [ModeHUDLegendItem],
        accent: RGBColor,
        lightingTargets: ModeLightingTargets = [],
        footerTitle: String,
        footerHint: String? = nil,
        problem: String? = nil,
        presentationStyle: ModeHUDPresentationStyle = .neutral,
        showsOnAllDisplays: Bool = false
    ) {
        self.isActive = isActive
        self.modeTitle = modeTitle
        self.source = source
        self.selection = selection
        self.legend = legend
        self.accent = accent
        self.lightingTargets = lightingTargets
        self.footerTitle = footerTitle
        self.footerHint = footerHint
        self.problem = problem
        self.presentationStyle = presentationStyle
        self.showsOnAllDisplays = showsOnAllDisplays
    }
}

public protocol ModeHUDPresenting: AnyObject {
    func show(_ snapshot: ModeHUDSnapshot)
    func update(_ snapshot: ModeHUDSnapshot)
    func hide()
    func flashProblem(_ message: String)
    var isVisible: Bool { get }
}

public final class RecordingModeHUDPresenter: ModeHUDPresenting {
    public private(set) var isVisible = false
    public private(set) var showCount = 0
    public private(set) var hideCount = 0
    public private(set) var snapshots: [ModeHUDSnapshot] = []
    public private(set) var problems: [String] = []

    public init() {}

    public func show(_ snapshot: ModeHUDSnapshot) {
        isVisible = true
        showCount += 1
        snapshots.append(snapshot)
    }

    public func update(_ snapshot: ModeHUDSnapshot) { snapshots.append(snapshot) }

    public func hide() {
        guard isVisible else { return }
        isVisible = false
        hideCount += 1
    }

    public func flashProblem(_ message: String) { problems.append(message) }
}
