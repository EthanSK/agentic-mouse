import AppKit
import ScimitarKit
import SwiftUI

/// Reusable presenter for runtime-mode legends and passive map reminders,
/// sharing the non-activating `HUDPanel` contract without changing multi-tap.
public final class AppKitModeHUDPresenter: NSObject, ModeHUDPresenting {
    private struct PanelInstance {
        let panel: HUDPanel
        let hostingView: NSHostingView<ModeHUDView>
    }

    private enum DisplayScope {
        case target
        case all
    }

    private var panels: [ObjectIdentifier: PanelInstance] = [:]
    private let model: ModeHUDViewModel
    private let source: MouseSource
    private let configuration: AppConfiguration.HUDConfiguration
    private var problemDismissWorkItem: DispatchWorkItem?
    private var feedbackDismissWorkItem: DispatchWorkItem?
    private var delayedScreenReconcileWorkItem: DispatchWorkItem?
    private var displayScope: DisplayScope = .target
    private var panelOpacity: CGFloat

    public init(
        source: MouseSource,
        configuration: AppConfiguration.HUDConfiguration = .init()
    ) {
        self.source = source
        self.model = ModeHUDViewModel(source: source)
        self.configuration = configuration
        self.panelOpacity = CGFloat(configuration.opacity)
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        delayedScreenReconcileWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    public var isVisible: Bool { panels.values.contains { $0.panel.isVisible } }

    public func show(_ snapshot: ModeHUDSnapshot) {
        guard snapshot.source == source else { return }
        model.apply(snapshot)
        displayScope = snapshot.showsOnAllDisplays ? .all : .target
        updatePanelOpacity(for: snapshot)
        reconcilePanels(show: true)
        scheduleSettledScreenReconciliation()
    }

    public func update(_ snapshot: ModeHUDSnapshot) {
        guard snapshot.source == source else { return }
        model.apply(snapshot)
        displayScope = snapshot.showsOnAllDisplays ? .all : .target
        updatePanelOpacity(for: snapshot)
        if isVisible { reconcilePanels(show: true) }
    }

    public func hide() {
        problemDismissWorkItem?.cancel()
        feedbackDismissWorkItem?.cancel()
        delayedScreenReconcileWorkItem?.cancel()
        model.isActive = false
        model.feedback = nil
        panels.values.forEach { $0.panel.orderOut(nil) }
        displayScope = .target
    }

    public func flashProblem(_ message: String) {
        model.problem = message
        reconcilePanels(show: true)

        problemDismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.problem = nil
            if !self.model.isActive {
                self.panels.values.forEach { $0.panel.orderOut(nil) }
            }
        }
        problemDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    public func flashFeedback(_ feedback: ModeHUDFeedback) {
        model.feedback = feedback
        reconcilePanels(show: true)

        feedbackDismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.feedback = nil
            if !self.model.isActive {
                self.panels.values.forEach { $0.panel.orderOut(nil) }
            }
        }
        feedbackDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        guard isVisible else { return }
        reconcilePanels(show: true)
        scheduleSettledScreenReconciliation()
    }

    /// AppKit can publish screen-parameter changes before `NSScreen.screens`
    /// contains the final post-reconfiguration set. Reconcile once immediately
    /// and once after AppKit has settled so a late display is not omitted from
    /// a persistent all-display legend.
    private func scheduleSettledScreenReconciliation() {
        delayedScreenReconcileWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isVisible else { return }
            self.reconcilePanels(show: true)
        }
        delayedScreenReconcileWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func reconcilePanels(show: Bool) {
        let screens = targetScreens()
        let targetKeys = Set(screens.map(ObjectIdentifier.init))

        let staleKeys = panels.keys.filter { !targetKeys.contains($0) }
        for key in staleKeys {
            panels.removeValue(forKey: key)?.panel.orderOut(nil)
        }

        for screen in screens {
            let instance = ensurePanel(for: screen)
            position(instance, on: screen)
            if show { instance.panel.orderFrontRegardless() }
        }
    }

    private func ensurePanel(for screen: NSScreen) -> PanelInstance {
        let key = ObjectIdentifier(screen)
        if let existing = panels[key] { return existing }

        let hosting = NSHostingView(rootView: ModeHUDView(model: model))
        let size = hosting.fittingSize
        let panel = HUDPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.contentView = hosting
        panel.alphaValue = panelOpacity
        let instance = PanelInstance(panel: panel, hostingView: hosting)
        panels[key] = instance
        return instance
    }

    private func updatePanelOpacity(for snapshot: ModeHUDSnapshot) {
        panelOpacity = snapshot.presentationStyle.requiresOpaqueWindow
            ? CGFloat(1)
            : CGFloat(configuration.opacity)
        panels.values.forEach { $0.panel.alphaValue = panelOpacity }
    }

    private func position(_ instance: PanelInstance, on screen: NSScreen) {
        instance.hostingView.layoutSubtreeIfNeeded()
        let size = instance.hostingView.fittingSize
        let visible = screen.visibleFrame
        let margin = CGFloat(configuration.margin)

        let origin: NSPoint
        switch AppConfiguration.HUDConfiguration.sourceCorner(for: source) {
        case .topLeft:
            origin = NSPoint(x: visible.minX + margin, y: visible.maxY - size.height - margin)
        case .topRight:
            origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.maxY - size.height - margin)
        case .bottomLeft:
            origin = NSPoint(x: visible.minX + margin, y: visible.minY + margin)
        case .bottomRight:
            origin = NSPoint(x: visible.maxX - size.width - margin, y: visible.minY + margin)
        case .center:
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        }
        instance.panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func targetScreens() -> [NSScreen] {
        switch displayScope {
        case .all:
            return NSScreen.screens
        case .target:
            return targetScreen().map { [$0] } ?? []
        }
    }

    private func targetScreen() -> NSScreen? {
        guard configuration.followsPointerScreen else { return NSScreen.main }
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }
}
