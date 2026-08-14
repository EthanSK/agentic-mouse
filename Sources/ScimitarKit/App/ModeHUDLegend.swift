import Foundation

/// One cell in the reusable runtime-mode legend shown by Agentic Mouse.
/// Future modes supply their own action labels while reusing the same physical
/// cross-device grid and non-activating panel.
public struct ModeHUDLegendItem: Equatable, Hashable, Sendable {
    public let cell: PhysicalCell
    public let actionTitle: String
    public let accent: RGBColor
    /// Set only when this card opens another mode or submenu. The destination
    /// colour replaces the ordinary current-mode border and receives stronger
    /// perimeter emphasis, while `accent` remains the card's action fill.
    public let destinationModeAccent: RGBColor?

    public init(
        cell: PhysicalCell,
        actionTitle: String,
        accent: RGBColor,
        destinationModeAccent: RGBColor? = nil
    ) {
        self.cell = cell
        self.actionTitle = actionTitle
        self.accent = accent
        self.destinationModeAccent = destinationModeAccent
    }

}

/// Visual treatment for the reusable mode legend.
///
/// This is deliberately presentation-only. Runtime lighting continues to use
/// the mode's saturated identity colour, while the HUD can render that same
/// identity as a neutral reference or a fully opaque control surface.
public enum ModeHUDPresentationStyle: String, Equatable, Sendable {
    case neutral
    case boldOpaque

    public var requiresOpaqueWindow: Bool { self != .neutral }

    public func displayAccent(_ color: RGBColor) -> RGBColor {
        color
    }

    public func cardFill(_ color: RGBColor) -> RGBColor {
        color
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
/// The mode colour forms the ordinary perimeter across the grid, while the
/// action colour remains inside the card. Navigation cards deliberately use
/// the destination mode's colour as a stronger perimeter so the next submenu
/// is legible before it is opened.
public struct ModeHUDCardColors: Equatable, Sendable {
    public let border: RGBColor
    public let fill: RGBColor
    public let foreground: RGBColor

    public init(
        modeAccent: RGBColor,
        actionAccent: RGBColor,
        destinationModeAccent: RGBColor? = nil,
        presentationStyle: ModeHUDPresentationStyle = .neutral
    ) {
        border = presentationStyle.displayAccent(destinationModeAccent ?? modeAccent)
        fill = presentationStyle.cardFill(actionAccent)
        foreground = presentationStyle.cardForeground(for: fill)
    }
}

/// Border strength for an ordinary action, a mode-navigation card, or the
/// currently selected action. Navigation remains visibly stronger than an
/// ordinary card without competing with selection feedback.
public struct ModeHUDCardBorderTreatment: Equatable, Sendable {
    public let opacity: Double
    public let lineWidth: Double

    public init(isSelected: Bool, isModeNavigation: Bool) {
        if isSelected {
            opacity = 1
            lineWidth = 3.75
        } else if isModeNavigation {
            opacity = 1
            lineWidth = 3.0
        } else {
            opacity = 0.9
            lineWidth = 2.25
        }
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
/// A mode's accent remains the ordinary card perimeter. A card that opens a
/// different mode uses that destination mode's accent instead. Inside either
/// perimeter, controls that form one pair or directional group deliberately
/// share one fill colour, while unrelated controls keep distinct fills. New
/// modes should reuse an existing family or add one explicit family rather
/// than choosing per-button colours independently.
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
    public let accent: RGBColor

    public init(cell: PhysicalCell, title: String, accent: RGBColor) {
        self.cell = cell
        self.title = title
        self.accent = accent
    }
}

/// Short-lived, truthful action feedback rendered in the HUD footer.
///
/// `confirmed` means Agentic Mouse observed the destination application's own
/// state change. `informational` only describes a dispatched command, and
/// `notConfirmed` explicitly refuses to present an ambiguous result as success.
public struct ModeHUDFeedback: Equatable, Sendable {
    public enum Tone: Equatable, Sendable {
        case confirmed
        case informational
        case notConfirmed
    }

    public let message: String
    public let tone: Tone

    public init(message: String, tone: Tone) {
        self.message = message
        self.tone = tone
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
    func flashFeedback(_ feedback: ModeHUDFeedback)
    var isVisible: Bool { get }
}

public final class RecordingModeHUDPresenter: ModeHUDPresenting {
    public private(set) var isVisible = false
    public private(set) var showCount = 0
    public private(set) var hideCount = 0
    public private(set) var snapshots: [ModeHUDSnapshot] = []
    public private(set) var problems: [String] = []
    public private(set) var feedback: [ModeHUDFeedback] = []

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
    public func flashFeedback(_ item: ModeHUDFeedback) { feedback.append(item) }
}
