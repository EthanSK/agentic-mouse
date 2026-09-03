import Foundation

/// Owns one mouse's persistent top-level button-map reference. Shared physical
/// Physical cell 10 toggles each source's independent copy. A runtime mode
/// may suspend the panel and later restore it without losing the user's
/// explicit open/closed choice.
public final class DefaultMapHintCoordinator {
    public private(set) var isShowingHint = false
    public private(set) var source: MouseSource?

    private let hud: ModeHUDPresenting
    private let dismissScheduler: TickScheduler
    private let log: Log
    private let isAvailable: () -> Bool
    private let screenshotActionState: () -> ScreenshotActionPresentationState
    private let frontmostAppContext: () -> FrontmostAppModeContext?
    private let youtubeVolumeModifierActive: () -> Bool
    private let displayDuration: TimeInterval
    private let ownedSource: MouseSource

    public init(
        hud: ModeHUDPresenting,
        dismissScheduler: TickScheduler,
        log: Log,
        source: MouseSource,
        isAvailable: @escaping () -> Bool = { true },
        screenshotActionState: @escaping () -> ScreenshotActionPresentationState = { .idle },
        frontmostAppContext: @escaping () -> FrontmostAppModeContext? = { nil },
        youtubeVolumeModifierActive: @escaping () -> Bool = { false },
        displayDuration: TimeInterval = 0
    ) {
        self.hud = hud
        self.dismissScheduler = dismissScheduler
        self.log = log
        self.ownedSource = source
        self.isAvailable = isAvailable
        self.screenshotActionState = screenshotActionState
        self.frontmostAppContext = frontmostAppContext
        self.youtubeVolumeModifierActive = youtubeVolumeModifierActive
        self.displayDuration = max(0, displayDuration)
    }

    public func handleToggle(source: MouseSource) {
        guard source == ownedSource else {
            log.debug("ignored legend command for another mouse")
            return
        }
        guard isAvailable() else {
            log.debug("default-map toggle ignored while a runtime mode owns the grid")
            return
        }
        if isShowingHint {
            hideHint()
            log.info(
                "default mode legend hidden by \(source.displayName) button "
                    + "\(DefaultMapHintCommand.triggerCell(for: source).printedSide(on: source)!)"
            )
        } else {
            showHint(source: source)
        }
    }

    /// Shows a recent wheel trace only in an already-visible Default legend.
    /// Hidden top-level wheel diagnostics remain available in logs and never
    /// create a panel or change the user's explicit legend-toggle state.
    public func flashWheelDiagnostic(
        source: MouseSource,
        message: String
    ) {
        flashWheelFeedback(
            source: source,
            feedback: ModeHUDFeedback(message: message, tone: .informational)
        )
    }

    /// Shows an action result only on the persistent Default legend the user
    /// already opened. A top-level held-wheel action must never create a HUD or
    /// leak its feedback into an active runtime mode.
    public func flashWheelFeedback(
        source: MouseSource,
        feedback: ModeHUDFeedback
    ) {
        flashActionFeedback(source: source, feedback: feedback)
    }

    /// Shows a top-level one-shot result only when the user already has this
    /// source's persistent Default legend open.
    public func flashActionFeedback(
        source: MouseSource,
        feedback: ModeHUDFeedback
    ) {
        guard source == ownedSource else { return }
        guard isAvailable(), isShowingHint else { return }
        hud.flashFeedback(feedback)
    }

    /// Shows a top-level one-shot failure only when the user already has this
    /// source's persistent Default legend open.
    public func flashActionProblem(
        source: MouseSource,
        message: String
    ) {
        guard source == ownedSource else { return }
        guard isAvailable(), isShowingHint else { return }
        hud.flashProblem(message)
    }

    /// Temporarily hides the panel for a mode and returns the exact source to
    /// restore. A nil result means the map was closed before mode entry.
    public func suspendForMode() -> MouseSource? {
        guard isShowingHint else { return nil }
        let saved = source
        dismissScheduler.stop()
        isShowingHint = false
        hud.hide()
        log.info("default mouse map suspended for runtime mode")
        return saved
    }

    public func restoreAfterMode(source: MouseSource) {
        guard source == ownedSource else { return }
        guard !isShowingHint else { return }
        showHint(source: source)
        log.info("default mouse map restored after runtime mode")
    }

    public func cancel() {
        hideHint()
    }

    public func shutdown() {
        hideHint()
    }

    /// Refreshes next-action copy while preserving this mouse's independent
    /// open/closed state and panel ownership.
    public func refresh() {
        guard isShowingHint, let source else { return }
        hud.update(
            DefaultMapLegend.snapshot(
                source: source,
                screenshotActionState: screenshotActionState(),
                frontmostAppContext: frontmostAppContext(),
                youtubeVolumeModifierActive: youtubeVolumeModifierActive()
            )
        )
    }

    private func showHint(source: MouseSource) {
        self.source = source
        isShowingHint = true
        hud.show(
            DefaultMapLegend.snapshot(
                source: source,
                screenshotActionState: screenshotActionState(),
                frontmostAppContext: frontmostAppContext(),
                youtubeVolumeModifierActive: youtubeVolumeModifierActive()
            )
        )
        if displayDuration > 0 {
            dismissScheduler.start(interval: displayDuration) { [weak self] in
                self?.dismissScheduler.stop()
                self?.hideHint()
            }
        }
        log.info(
            "default mode legend shown from \(source.displayName) button "
                + "\(DefaultMapHintCommand.triggerCell(for: source).printedSide(on: source)!)"
        )
    }

    private func hideHint() {
        dismissScheduler.stop()
        guard isShowingHint else {
            source = nil
            return
        }
        isShowingHint = false
        source = nil
        hud.hide()
    }

}

public enum DefaultMapLegend {
    /// Default is the neutral baseline, so its shared card perimeter is white.
    /// Individual action families retain their own internal fill colours.
    public static let accent = RGBColor.white

    public static let legend: [ModeHUDLegendItem] = legend(
        source: .corsair,
        screenshotActionState: .idle
    )

    public static func snapshot(
        source: MouseSource,
        screenshotActionState: ScreenshotActionPresentationState = .idle,
        frontmostAppContext: FrontmostAppModeContext? = nil,
        youtubeVolumeModifierActive: Bool = false
    ) -> ModeHUDSnapshot {
        ModeHUDSnapshot(
            isActive: true,
            modeTitle: "Default mode",
            source: source,
            selection: nil,
            legend: legend(
                source: source,
                screenshotActionState: screenshotActionState,
                frontmostAppContext: frontmostAppContext,
                youtubeVolumeModifierActive: youtubeVolumeModifierActive
            ),
            accent: accent,
            footerTitle: "Default mode",
            footerHint: nil,
            showsOnAllDisplays: true
        )
    }

    private static func legend(
        source: MouseSource,
        screenshotActionState: ScreenshotActionPresentationState,
        frontmostAppContext: FrontmostAppModeContext? = nil,
        youtubeVolumeModifierActive: Bool = false
    ) -> [ModeHUDLegendItem] {
        PhysicalCell.all.map { cell in
            let assignment = DefaultMouseMapping.assignment(for: cell, source: source)
            let title: String
            if cell == DefaultMapHintCommand.triggerCell(for: source) {
                title = ModeHUDCopy.legendToggleTitle
            } else if cell == .screenshotToggle {
                title = ModeHUDCopy.screenshotActionTitle(state: screenshotActionState)
            } else if cell == .frontmostAppModeSelector {
                title = frontmostAppContext?.definition.title ?? "App mode"
            } else if frontmostAppContext?.target == .vsCode,
                      cell == VSCodeModeAction.previousChange.cell {
                title = "Previous Change"
            } else if frontmostAppContext?.target == .vsCode,
                      cell == PhysicalCell(rawValue: 7)! {
                title = "Enter · Stage + Next after 8"
            } else if frontmostAppContext?.target == .vsCode,
                      cell == VSCodeModeAction.nextChange.cell {
                title = "Next Change · Hold + \(PhysicalCell(rawValue: 7)!.printedSide(on: source)!) to Stage"
            } else if youtubeVolumeModifierActive && cell == YouTubeVolumeModifierCommand.triggerCell {
                title = "YouTube Volume held"
            } else if youtubeVolumeModifierActive && cell == .youtubeScrubWheelControl {
                title = "YouTube Volume + Wheel"
            } else if cell == YouTubeVolumeModifierCommand.triggerCell {
                title = "Forward · Hold + \(PhysicalCell.youtubeScrubWheelControl.printedSide(on: source)!) for Volume"
            } else {
                title = assignment?.action ?? "Spare"
            }
            let itemAccent: RGBColor
            let destinationModeAccent: RGBColor?
            if cell == .frontmostAppModeSelector, let frontmostAppContext {
                itemAccent = frontmostAppContext.definition.accent.blended(
                    with: .white,
                    amount: 0.58
                )
                destinationModeAccent = frontmostAppContext.definition.accent
            } else {
                itemAccent = accent(for: title)
                switch cell {
                case .keysModeEntry:
                    destinationModeAccent = ModePickerCoordinator.keysAccent
                case .frontmostAppModeSelector:
                    destinationModeAccent = AppSpecificMode.selectorAccent
                case .modePickerEntry:
                    destinationModeAccent = ModePickerCoordinator.accent
                default:
                    destinationModeAccent = nil
                }
            }
            return ModeHUDLegendItem(
                cell: cell,
                actionTitle: title,
                accent: itemAccent,
                destinationModeAccent: destinationModeAccent,
                appBackdrop: cell == .frontmostAppModeSelector
                    ? frontmostAppContext.flatMap {
                        ModeHUDAppBackdrop(
                            bundleIdentifier: $0.bundleIdentifier,
                            applicationPath: $0.applicationPath
                        )
                    }
                    : nil,
                controlStatus: .normal
            )
        }
    }

    private static func accent(for title: String) -> RGBColor {
        let lowered = title.lowercased()
        if lowered.contains("scroll") { return ModeHUDActionFamilyPalette.horizontalScroll }
        if lowered.contains("spaces") { return ModeHUDActionFamilyPalette.desktopSpaces }
        if lowered.contains("switch") { return RGBColor(red: 168, green: 118, blue: 255) }
        if lowered.contains("track") { return RGBColor(red: 82, green: 214, blue: 132) }
        if lowered.hasPrefix("forward") || lowered == "back" {
            return ModeHUDActionFamilyPalette.historyNavigation
        }
        if lowered.contains("screenshot") { return RGBColor(red: 255, green: 188, blue: 74) }
        if lowered.contains("youtube") { return RGBColor(red: 255, green: 72, blue: 72) }
        if lowered.contains("copy") || lowered.contains("paste") {
            return ModeHUDActionFamilyPalette.clipboard
        }
        if lowered == "enter" { return ModeHUDActionFamilyPalette.enter }
        if lowered.contains("legend") { return ModeHUDActionFamilyPalette.legendToggle }
        if lowered.contains("keys") { return ModePickerCoordinator.keysAccent }
        if lowered.contains("modes") { return ModePickerCoordinator.accent }
        return RGBColor(red: 138, green: 145, blue: 158)
    }
}
