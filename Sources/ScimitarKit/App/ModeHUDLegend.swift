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
    /// The destination app does not expose an equivalent action on this card.
    case unavailable
}

/// How a card works beyond a plain click: hold its button and move the mouse
/// wheel, or on the wand hold the HUD button and tilt.
///
/// Ethan asked for one design language for "when a button click actually does
/// the button versus when holding it and doing wheel up or wheel down or wand
/// up or wand down changes some value". Every card title follows one grammar:
///
/// * `Click · Hold ↕` — a plain click does the first part; holding and moving
///   does the arrowed part.
/// * `Hold ↕` — only the hold acts; a plain click does nothing.
/// * No arrow — an ordinary click (or a `Hold …` press with no motion).
///
/// The arrow is the motion and always ends the title, so it marks the held
/// part without a second line. Key-symbol prefixes such as `↑ Up` and
/// `⌘S Save` keep meaning keys. This is one title, not a subtitle.
public struct ModeHUDGesture: Equatable, Hashable, Sendable {
    /// The physical direction that acts, never the Quartz delta sign.
    public enum Motion: String, Equatable, Hashable, Sendable {
        /// Up and down both act (opposite steps, or one toggle either way).
        case upDown
        /// Only physical wheel down (or wand tilt down) acts.
        case down
        /// Only physical wheel up (or wand tilt up) acts.
        case up
        /// Left and right; only the wand's armed Switch App moves this way.
        case leftRight

        public var glyph: String {
            switch self {
            case .upDown: return "↕"
            case .down: return "↓"
            case .up: return "↑"
            case .leftRight: return "↔"
            }
        }

        fileprivate func spokenMove(on source: MouseSource) -> String {
            let wand = source == .wand
            switch self {
            case .upDown: return wand ? "tilt up or down" : "turn the wheel up or down"
            case .down: return wand ? "tilt down" : "turn the wheel down"
            case .up: return wand ? "tilt up" : "turn the wheel up"
            case .leftRight: return wand ? "tilt left or right" : "move left or right"
            }
        }
    }

    /// What a plain click does, or nil when only the hold acts.
    public let click: String?
    /// What holding the button and moving does.
    public let hold: String
    public let motion: Motion
    /// The wand can arm this card and adjust it with the next hold. The mice
    /// always can; a wand-only gesture is attached only to wand legends.
    public let isAvailableOnWand: Bool
    /// How the wand moves for this hold, when it differs from the wheel's
    /// `motion`. A mouse wheel only turns up and down, but the wand moves
    /// along each control's own axis (`WheelChordControl.wandAxis`), so
    /// Spaces, scrolling, tabs, history and Tracks read ↔ on the wand
    /// (Ethan, 2026-10-30: "why is space is still up or down arrow instead of
    /// left or right arrow?"). The physical mice keep their wheel arrows.
    public let wandMotion: Motion?

    public init(click: String? = nil, hold: String, motion: Motion = .upDown, isAvailableOnWand: Bool,
                wandMotion: Motion? = nil) {
        self.click = click
        self.hold = hold
        self.motion = motion
        self.isAvailableOnWand = isAvailableOnWand
        self.wandMotion = wandMotion
    }

    /// The arrow drawn for `source`: the wand's own axis, or the wheel's.
    public func motion(on source: MouseSource) -> Motion {
        source == .wand ? wandMotion ?? motion : motion
    }

    /// The card's words without the motion arrow, in click-then-hold order.
    public var words: String {
        click.map { "\($0) · \(hold)" } ?? hold
    }

    public func isAvailable(on source: MouseSource) -> Bool {
        source == .wand ? isAvailableOnWand : true
    }
}

/// One cell in the reusable runtime-mode legend shown by Agentic Mouse.
/// Future modes supply their own action labels while reusing the same physical
/// cross-device grid and non-activating panel.
public struct ModeHUDLegendItem: Equatable, Hashable, Sendable {
    public let cell: PhysicalCell
    /// The card's words. A card with a `gesture` takes them from it, so the
    /// click and held parts can never drift from their typed definition.
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
    /// Present only when holding this button and moving the wheel (or the
    /// wand) does something. Plain click cards leave it nil.
    public let gesture: ModeHUDGesture?
    /// The wand's own title, where the shared one names a physical-mouse
    /// chord the wand does not perform (Codex's source-specific Pin modifier).
    public private(set) var wandTitle: String?
    /// A separate physical button held while clicking this card. Resolve its
    /// printed mouse label at presentation time, never bake "Hold 2" into copy.
    public private(set) var heldModifierCell: PhysicalCell?

    public func withHeldModifier(_ cell: PhysicalCell) -> ModeHUDLegendItem {
        var copy = self
        copy.heldModifierCell = cell
        return copy
    }

    /// This card with its wand-only title.
    public func withWandTitle(_ title: String) -> ModeHUDLegendItem {
        var copy = self
        copy.wandTitle = title
        return copy
    }

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
        self.gesture = nil
    }

    /// A card whose button also works by holding it and moving the wheel or
    /// wand. Its words come from the gesture itself.
    public init(
        cell: PhysicalCell,
        gesture: ModeHUDGesture,
        accent: RGBColor,
        destinationModeAccent: RGBColor? = nil,
        appBackdrop: ModeHUDAppBackdrop? = nil,
        controlStatus: ModeHUDControlStatus = .normal
    ) {
        self.cell = cell
        self.actionTitle = gesture.words
        self.accent = accent
        self.destinationModeAccent = destinationModeAccent
        self.appBackdrop = appBackdrop
        self.controlStatus = controlStatus
        self.gesture = gesture
    }

    /// The title drawn for one source: the words plus the motion arrow when
    /// that source can perform the hold. A wand card whose hold only the mice
    /// can perform shows just its click.
    public func displayTitle(on source: MouseSource) -> String {
        if source == .wand, let wandTitle { return wandTitle }
        if let heldModifierCell {
            return "\(actionTitle) + Hold \(heldModifierCell.displayLabel(on: source))"
        }
        guard let gesture else { return actionTitle }
        guard gesture.isAvailable(on: source) else { return gesture.click ?? gesture.hold }
        return "\(gesture.words) \(gesture.motion(on: source).glyph)"
    }

    /// Spoken equivalent of the drawn title. The arrows are visual shorthand,
    /// so this says what the click and the hold each do.
    public func accessibilityDescription(on source: MouseSource) -> String {
        if source == .wand, let wandTitle { return wandTitle }
        guard let gesture else { return displayTitle(on: source) }
        guard gesture.isAvailable(on: source) else {
            return gesture.click ?? "\(gesture.hold), mouse wheel only"
        }
        let held = "Hold and \(gesture.motion(on: source).spokenMove(on: source)) for \(gesture.hold)"
        return gesture.click.map { "\($0). \(held)" } ?? held
    }

    /// Keep the repair marker immediately after the source-specific printed
    /// identifier so the action title stays concise and stable. A card that
    /// does nothing on this source (a mouse-wheel-only card on the wand)
    /// reuses the unavailable marker.
    public func printedControlLabel(on source: MouseSource) -> String {
        let label = cell.displayLabel(on: source)
        switch controlStatus {
        case .normal:
            if let gesture, gesture.click == nil, !gesture.isAvailable(on: source) {
                return "\(label) ×"
            }
            return label
        case .reportedBroken: return "\(label) ❌"
        case .unavailable: return "\(label) ×"
        }
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
    /// A two-part `Click · Hold ↕` grid title may shrink this far before it
    /// truncates, so neither the click nor the held half is cut off.
    public static let cardTitleMinimumScale: CGFloat = 0.8
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
    public static let save = RGBColor(red: 45, green: 184, blue: 113)
    public static let storedPassword = RGBColor(red: 190, green: 86, blue: 255)
    public static let media = RGBColor(red: 82, green: 214, blue: 132)
    public static let reasoningEffort = RGBColor(red: 174, green: 112, blue: 255)
}

/// Plain user-facing copy shared by every reference-map presentation.
/// Architectural terms such as "passive" describe implementation behavior,
/// not Ethan, and must never appear as HUD labels.
public enum ModeHUDCopy {
    /// Read the click result first, then the arrowed held-motion result.
    public static func gestureHint(for source: MouseSource) -> String {
        source == .wand ? "Click · Hold + tilt" : "Click · Hold + wheel ↕"
    }

    public static let referenceStatus = "BUTTON MAP"
    /// The card only exists inside the legend it controls, so a stable control
    /// name is clearer than state copy that can only ever be seen while open.
    public static let legendToggleTitle = "Legend toggle · Hold ⌘"
    /// The wand home's cell 10: it closes the wand HUD and holds nothing.
    public static let wandCloseTitle = "Close"
    /// Ethan's exact words (2026-10-30), under the wand home's centre Switch
    /// App: clicks no longer hide the HUD, so this says how to close it.
    public static let wandDoubleClickCloseHint = "Double click to close"

    public static func screenshotActionTitle(
        state: ScreenshotActionPresentationState
    ) -> String {
        if let gesture = screenshotGesture(state: state) { return gesture.words }
        switch state {
        case .capturing: return "Cancel screenshot"
        case .copying: return "Copying screenshot…"
        case .idle, .pasteReady: return WheelChordControl.screenshotPaste.hudGesture.words
        }
    }

    /// Click captures and hold + wheel down pastes, except while the native
    /// crosshair or save owns the button: those states show only their status.
    public static func screenshotGesture(
        state: ScreenshotActionPresentationState
    ) -> ModeHUDGesture? {
        switch state {
        case .idle, .pasteReady: return WheelChordControl.screenshotPaste.hudGesture
        case .capturing, .copying: return nil
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

/// Navigation cursor drawn by a pointer-style selection input such as the
/// wand. It is deliberately separate from `ModeHUDSelection`, which records
/// the last performed action and drives the mouse action-lighting accent.
/// `isArmed` marks a held-wheel card that the wand has selected and is now
/// adjusting without a physical wheel. It changes only the outline treatment;
/// card titles, printed labels and wheel hints stay exactly as they are.
public struct ModeHUDPointerFocus: Equatable, Sendable {
    public let cell: PhysicalCell
    public let isArmed: Bool
    /// Progress toward the next card, clamped to -1...1 for the liquid outline.
    public let pullX: Double
    public let pullY: Double
    /// Present only while an armed wheel card is being adjusted by tilt.
    public let adjustment: ModeHUDWheelAdjustment?
    /// The wand's centre only: the ring card a reach would choose, which the
    /// centre outline leans toward. The wheel starts its outward morph from
    /// that card's direction instead of sweeping round from the last one.
    public let aim: PhysicalCell?

    /// An adjusting card never carries navigation pull: its outline shows
    /// detent progress instead, so the two residuals can never mix.
    public init(
        cell: PhysicalCell,
        isArmed: Bool = false,
        pullX: Double = 0,
        pullY: Double = 0,
        adjustment: ModeHUDWheelAdjustment? = nil,
        aim: PhysicalCell? = nil
    ) {
        self.cell = cell
        self.isArmed = isArmed || adjustment != nil
        self.adjustment = adjustment
        self.pullX = adjustment == nil && pullX.isFinite ? min(1, max(-1, pullX)) : 0
        self.pullY = adjustment == nil && pullY.isFinite ? min(1, max(-1, pullY)) : 0
        self.aim = adjustment == nil && aim != cell ? aim : nil
    }
}

/// Live state of one wand wheel-adjustment hold.
///
/// This describes only the wand input: travel toward the next detent and the
/// detents handed to the existing wheel dispatcher. It deliberately carries no
/// destination value, because Agentic Mouse usually cannot observe whether the
/// app actually changed (the footer keeps saying "sent").
public struct ModeHUDWheelAdjustment: Equatable, Sendable {
    /// Travel toward the next detent, -1...1. Same sign as the outline's pull:
    /// negative stretches toward a physical-up detent, positive toward down.
    public let pull: Double
    /// Detents sent during this hold: up minus down.
    public let netSteps: Int
    /// Every detent sent during this hold; each increment is one step pulse.
    public let sentSteps: Int
    /// The control's wand axis: arrows go left/right instead of above/below.
    public let isHorizontal: Bool
    /// The HUD button is held and the card is listening (Ethan: "a special like glow
    /// ... to indicate it's being held, like it's listening"). False while a
    /// selected card waits with the HUD button up.
    public let isHeld: Bool
    /// Direction of the most recently sent detent, if any: "up" is the
    /// negative screen side (up, or left for a horizontal control).
    public let lastStepWasUp: Bool?

    public init(pull: Double = 0, netSteps: Int = 0, sentSteps: Int = 0, lastStepWasUp: Bool? = nil,
                isHorizontal: Bool = false, isHeld: Bool = true) {
        self.isHorizontal = isHorizontal
        self.isHeld = isHeld
        self.pull = pull.isFinite ? min(1, max(-1, pull)) : 0
        self.netSteps = min(999, max(-999, netSteps))
        self.sentSteps = min(9_999, max(0, sentSteps))
        self.lastStepWasUp = self.sentSteps > 0 ? lastStepWasUp : nil
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
    public var outlineWidth: Double?
    public var lightingTargets: ModeLightingTargets
    public var footerTitle: String
    public var footerHint: String?
    public var problem: String?
    public var presentationStyle: ModeHUDPresentationStyle
    /// Show one copy of this reference HUD on every connected display.
    /// Persistent Default and active-mode legends use this as an explicit
    /// reference surface rather than a transient toast.
    public var showsOnAllDisplays: Bool
    /// Present only while a pointer-style selection input owns this HUD.
    public var pointerFocus: ModeHUDPointerFocus?
    public var wandReviewSelection: PhysicalCell? = nil
    /// The wand's weapon-wheel arrangement of `legend`. Set by the wand
    /// coordinator from the same definition its selection uses; mice leave it
    /// nil and keep their physical grid.
    public var wandRadialLayout: WandRadialLayout? = nil

    public var lightingAvailable: Bool { !lightingTargets.isEmpty }

    public init(
        isActive: Bool,
        modeTitle: String,
        source: MouseSource,
        selection: ModeHUDSelection?,
        legend: [ModeHUDLegendItem],
        accent: RGBColor,
        outlineWidth: Double? = nil,
        lightingTargets: ModeLightingTargets = [],
        footerTitle: String,
        footerHint: String? = nil,
        problem: String? = nil,
        presentationStyle: ModeHUDPresentationStyle = .neutral,
        showsOnAllDisplays: Bool = false,
        pointerFocus: ModeHUDPointerFocus? = nil
    ) {
        self.isActive = isActive
        self.modeTitle = modeTitle
        self.source = source
        self.selection = selection
        self.legend = legend
        self.accent = accent
        self.outlineWidth = outlineWidth
        self.lightingTargets = lightingTargets
        self.footerTitle = footerTitle
        self.footerHint = footerHint
        self.problem = problem
        self.presentationStyle = presentationStyle
        self.showsOnAllDisplays = showsOnAllDisplays
        self.pointerFocus = pointerFocus
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
