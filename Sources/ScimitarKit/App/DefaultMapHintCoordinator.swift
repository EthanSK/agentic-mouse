import Foundation

/// Owns the persistent top-level button-map reference. Cell 10 toggles it. A
/// runtime mode may suspend the panel and later restore it without losing the
/// user's explicit open/closed choice.
public final class DefaultMapHintCoordinator {
    public private(set) var isShowingHint = false
    public private(set) var source: MouseSource?

    private let hud: ModeHUDPresenting
    private let dismissScheduler: TickScheduler
    private let log: Log
    private let isAvailable: () -> Bool
    private let isScreenshotCapturing: () -> Bool
    private let frontmostAppContext: () -> FrontmostAppModeContext?
    private let displayDuration: TimeInterval
    private let ownedSource: MouseSource

    public init(
        hud: ModeHUDPresenting,
        dismissScheduler: TickScheduler,
        log: Log,
        source: MouseSource,
        isAvailable: @escaping () -> Bool = { true },
        isScreenshotCapturing: @escaping () -> Bool = { false },
        frontmostAppContext: @escaping () -> FrontmostAppModeContext? = { nil },
        displayDuration: TimeInterval = 0
    ) {
        self.hud = hud
        self.dismissScheduler = dismissScheduler
        self.log = log
        self.ownedSource = source
        self.isAvailable = isAvailable
        self.isScreenshotCapturing = isScreenshotCapturing
        self.frontmostAppContext = frontmostAppContext
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
                    + "\(PhysicalCell.defaultMapToggle.printedSide(on: source)!)"
            )
        } else {
            showHint(source: source)
        }
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

    public func cancel() { hideHint() }
    public func shutdown() { hideHint() }

    /// Refreshes next-action copy while preserving this mouse's independent
    /// open/closed state and panel ownership.
    public func refresh() {
        guard isShowingHint, let source else { return }
        hud.update(
            DefaultMapLegend.snapshot(
                source: source,
                screenshotIsCapturing: isScreenshotCapturing(),
                frontmostAppContext: frontmostAppContext()
            )
        )
    }

    private func showHint(source: MouseSource) {
        self.source = source
        isShowingHint = true
        hud.show(
            DefaultMapLegend.snapshot(
                source: source,
                screenshotIsCapturing: isScreenshotCapturing(),
                frontmostAppContext: frontmostAppContext()
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
                + "\(PhysicalCell.defaultMapToggle.printedSide(on: source)!)"
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
        screenshotIsCapturing: false
    )

    public static func snapshot(
        source: MouseSource,
        screenshotIsCapturing: Bool = false,
        frontmostAppContext: FrontmostAppModeContext? = nil
    ) -> ModeHUDSnapshot {
        ModeHUDSnapshot(
            isActive: true,
            modeTitle: "Default mode",
            source: source,
            selection: nil,
            legend: legend(
                screenshotIsCapturing: screenshotIsCapturing,
                frontmostAppContext: frontmostAppContext
            ),
            accent: accent,
            footerTitle: "Default mode",
            footerHint: nil,
            showsOnAllDisplays: true
        )
    }

    private static func legend(
        screenshotIsCapturing: Bool,
        frontmostAppContext: FrontmostAppModeContext? = nil
    ) -> [ModeHUDLegendItem] {
        PhysicalCell.all.map { cell in
            let assignment = ScimitarNormalMapping.normal.assignment(for: cell.rawValue)
            let title: String
            switch cell {
            case .defaultMapToggle:
                title = ModeHUDCopy.legendToggleTitle
            case .screenshotToggle:
                title = ModeHUDCopy.screenshotActionTitle(isCapturing: screenshotIsCapturing)
            case .appSpecificModeSelector:
                title = frontmostAppContext?.definition.title ?? "App mode"
            default:
                title = assignment?.action ?? "Spare"
            }
            let itemAccent: RGBColor
            if cell == .appSpecificModeSelector, let frontmostAppContext {
                itemAccent = ModeHUDPresentationStyle.pastel.displayAccent(
                    frontmostAppContext.definition.accent
                )
            } else {
                itemAccent = accent(for: title)
            }
            return ModeHUDLegendItem(cell: cell, actionTitle: title, accent: itemAccent)
        }
    }

    private static func accent(for title: String) -> RGBColor {
        let lowered = title.lowercased()
        if lowered.contains("scroll") { return ModeHUDActionFamilyPalette.horizontalScroll }
        if lowered.contains("switch") { return RGBColor(red: 168, green: 118, blue: 255) }
        if lowered.contains("track") { return RGBColor(red: 82, green: 214, blue: 132) }
        if lowered == "forward" || lowered == "back" {
            return ModeHUDActionFamilyPalette.historyNavigation
        }
        if lowered.contains("screenshot") { return RGBColor(red: 255, green: 188, blue: 74) }
        if lowered.contains("keys") { return ModePickerCoordinator.keysAccent }
        if lowered.contains("modes") { return ModePickerCoordinator.accent }
        return RGBColor(red: 138, green: 145, blue: 158)
    }
}
