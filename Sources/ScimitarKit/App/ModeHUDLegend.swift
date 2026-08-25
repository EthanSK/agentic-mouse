import Foundation

/// Latest physically reported state of one visible mouse control.
///
/// A red cross is deliberately narrower than "not yet tested": it means Ethan
/// explicitly reported the control broken or unreliable and has not since
/// physically accepted it. Source changes, automated tests, and a fresh install
/// do not clear that report by themselves.
public enum ModeHUDControlStatus: Equatable, Hashable, Sendable {
    case normal
    case reportedBroken
}

/// One cell in the reusable runtime-mode legend shown by Agentic Mouse.
/// Future modes supply their own action labels while reusing the same physical
/// cross-device grid and non-activating panel.
public struct ModeHUDLegendItem: Equatable, Hashable, Sendable {
    public let cell: PhysicalCell
    public let actionTitle: String
    public let accent: RGBColor
    /// Set only when this card opens another mode or submenu. The destination
    /// colour replaces the ordinary current-mode border and receives stronger
    /// perimeter emphasis. On the neutral Default page it also becomes the
    /// card's full-strength fill; active mode pages keep their action-family
    /// fill inside the destination-coloured border.
    public let destinationModeAccent: RGBColor?
    /// Optional presentation identity for the one card representing a concrete
    /// application. The UI resolves its real installed icon at render time;
    /// ordinary cards and whole-panel backgrounds never receive this artwork.
    public let appBackdrop: ModeHUDAppBackdrop?
    public let controlStatus: ModeHUDControlStatus

    public init(
        cell: PhysicalCell,
        actionTitle: String,
        accent: RGBColor,
        destinationModeAccent: RGBColor? = nil,
        appBackdrop: ModeHUDAppBackdrop? = nil
    ) {
        self.init(
            cell: cell,
            actionTitle: actionTitle,
            accent: accent,
            destinationModeAccent: destinationModeAccent,
            appBackdrop: appBackdrop,
            controlStatus: .normal
        )
    }

    public init(
        cell: PhysicalCell,
        actionTitle: String,
        accent: RGBColor,
        destinationModeAccent: RGBColor? = nil,
        appBackdrop: ModeHUDAppBackdrop? = nil,
        controlStatus: ModeHUDControlStatus
    ) {
        self.cell = cell
        self.actionTitle = actionTitle
        self.accent = accent
        self.destinationModeAccent = destinationModeAccent
        self.appBackdrop = appBackdrop
        self.controlStatus = controlStatus
    }

    /// Keep the repair marker immediately after the source-specific printed
    /// identifier so the action title stays concise and stable.
    public func printedControlLabel(on source: MouseSource) -> String {
        let label = cell.displayLabel(on: source)
        return controlStatus == .reportedBroken ? "\(label) ❌" : label
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

    /// Accent strength applied over the outer native glass surface. Active
    /// modes need a clear identity without diluting their opaque action cards.
    public var panelAccentOpacity: Double {
        switch self {
        case .neutral: return 0
        case .boldOpaque: return 0.48
        }
    }

    public func displayAccent(_ color: RGBColor) -> RGBColor {
        color
    }

    public func cardFill(_ color: RGBColor) -> RGBColor {
        switch self {
        case .neutral:
            return color
        case .boldOpaque:
            // Keep action-family identity without letting twelve saturated
            // controls compete with the active mode itself. This remains an
            // opaque RGB surface; only its brightness is reduced.
            return color.scaledBrightness(0.52)
        }
    }

    public func cardForeground(for _: RGBColor) -> RGBColor {
        // Agentic Mouse uses bold colour as identity, not as a conventional
        // light surface. Keep the card hierarchy consistent across every mode
        // instead of switching bright fills to black text.
        .white
    }
}

/// The two independent colour roles of one HUD card.
///
/// The mode colour forms the ordinary perimeter across the grid, while the
/// action colour remains as a calmer opaque fill inside ordinary mode cards.
/// Navigation cards deliberately use the destination mode's colour as both a
/// stronger perimeter and a full-strength fill, so the modes themselves remain
/// the most saturated controls in the hierarchy.
public struct ModeHUDCardColors: Equatable, Sendable {
    public let border: RGBColor
    public let fill: RGBColor
    public let foreground: RGBColor
    public let usesStrongDestinationFill: Bool

    public init(
        modeAccent: RGBColor,
        actionAccent: RGBColor,
        destinationModeAccent: RGBColor? = nil,
        presentationStyle: ModeHUDPresentationStyle = .neutral
    ) {
        if let destination = destinationModeAccent {
            usesStrongDestinationFill = true
            border = presentationStyle.displayAccent(destination)
            fill = presentationStyle.displayAccent(destination)
        } else {
            usesStrongDestinationFill = false
            border = presentationStyle.displayAccent(modeAccent)
            fill = presentationStyle.cardFill(actionAccent)
        }
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
    public static let browserTabs = RGBColor(red: 66, green: 133, blue: 244)
    public static let systemOverview = RGBColor(red: 72, green: 118, blue: 255)
    public static let arrowKeys = RGBColor(red: 255, green: 170, blue: 28)
    public static let clipboard = RGBColor(red: 52, green: 210, blue: 184)
    public static let windowManagement = RGBColor(red: 255, green: 116, blue: 74)
    public static let enter = RGBColor(red: 48, green: 218, blue: 126)
    public static let legendToggle = RGBColor(red: 0, green: 205, blue: 255)
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

    public static func screenshotActionTitle(
        state: ScreenshotActionPresentationState
    ) -> String {
        switch state {
        case .idle: return "Screenshot"
        case .capturing: return "Cancel screenshot"
        case .copying: return "Copying screenshot…"
        case .pasteReady: return "Screenshot · 2× Paste"
        }
    }

    public static func referenceHeader(for source: MouseSource) -> String {
        "\(source.displayName.uppercased()) BUTTON MAP"
    }
}

public enum ScreenshotActionPresentationState: Equatable, Sendable {
    case idle
    case capturing
    case copying
    case pasteReady
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

/// Stable app identity used only to resolve presentation artwork in the UI
/// layer. The exact running `.app` path wins for an automatic frontmost-app
/// journey; manually selected configured apps fall back to their canonical
/// bundle identifier. No icon bytes enter the mode domain or persisted config.
public struct ModeHUDAppBackdrop: Equatable, Hashable, Sendable {
    public let bundleIdentifier: String?
    public let applicationPath: String?

    public init?(bundleIdentifier: String?, applicationPath: String? = nil) {
        let normalizedBundleIdentifier = bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedApplicationPath = applicationPath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedBundleIdentifier?.isEmpty == false
                || normalizedApplicationPath?.isEmpty == false
        else { return nil }
        self.bundleIdentifier = normalizedBundleIdentifier?.isEmpty == false
            ? normalizedBundleIdentifier
            : nil
        self.applicationPath = normalizedApplicationPath?.isEmpty == false
            ? normalizedApplicationPath
            : nil
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
