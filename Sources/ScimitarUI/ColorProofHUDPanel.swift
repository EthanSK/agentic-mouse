import AppKit
import Combine
import ScimitarKit
import SwiftUI

/// Reusable presenter for runtime-mode legends and passive map reminders,
/// sharing the non-activating `HUDPanel` contract without changing multi-tap.
public final class AppKitModeHUDPresenter: NSObject, ModeHUDPresenting {
    private struct PanelInstance {
        let panel: HUDPanel
        let hostingView: ScaledHUDHostingView<ModeHUDView>
        let scaleControlPanel: HUDScaleControlPanel
    }

    private enum DisplayScope {
        case target
        case all
    }

    private var panels: [ObjectIdentifier: PanelInstance] = [:]
    private let model: ModeHUDViewModel
    private let source: MouseSource
    private let configuration: AppConfiguration.HUDConfiguration
    private let scaleStore: HUDScaleStore
    private let workspaceNotificationCenter: NotificationCenter
    private var scaleObservation: AnyCancellable?
    private var problemDismissWorkItem: DispatchWorkItem?
    private var feedbackDismissWorkItem: DispatchWorkItem?
    private var delayedScreenReconcileWorkItem: DispatchWorkItem?
    private var delayedSpaceReattachWorkItem: DispatchWorkItem?
    private var displayScope: DisplayScope = .target
    private var panelOpacity: CGFloat

    public init(
        source: MouseSource,
        configuration: AppConfiguration.HUDConfiguration = .init(),
        appIconProvider: WorkspaceModeHUDAppIconProvider = .init(),
        scaleStore: HUDScaleStore = .shared,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.source = source
        self.model = ModeHUDViewModel(
            source: source,
            appIconProvider: appIconProvider
        )
        self.configuration = configuration
        self.scaleStore = scaleStore
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.panelOpacity = CGFloat(configuration.opacity)
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        scaleObservation = scaleStore.$scale.dropFirst().sink { [weak self] scale in
            guard let self else { return }
            self.panels.values.forEach { $0.hostingView.setScale(CGFloat(scale)) }
            if self.isVisible { self.reconcilePanels(show: true) }
        }
    }

    deinit {
        delayedScreenReconcileWorkItem?.cancel()
        delayedSpaceReattachWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
        workspaceNotificationCenter.removeObserver(self)
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
        delayedSpaceReattachWorkItem?.cancel()
        model.isActive = false
        model.feedback = nil
        discardPanels()
        displayScope = .target
    }

    public func reattachToCurrentSpaces() {
        guard model.isActive else { return }
        reattachPanelsToCurrentSpaces()
        scheduleSettledSpaceReattachment()
    }

    public func flashProblem(_ message: String) {
        model.problem = message
        reconcilePanels(show: true)

        problemDismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.problem = nil
            if !self.model.isActive {
                self.discardPanels()
            }
        }
        problemDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    public func flashFeedback(_ feedback: ModeHUDFeedback) {
        guard model.isActive else { return } // A screenshot or asynchronous mode result can finish after the user closes the HUD; ignore it so feedback never resurrects an explicitly hidden panel. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
        model.feedback = feedback
        reconcilePanels(show: true)

        feedbackDismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.feedback = nil
            if !self.model.isActive {
                self.discardPanels()
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

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model.isActive else { return }
            self.reattachToCurrentSpaces()
        }
    }

    /// Cached panels can remain fully rendered on a stale Space while AppKit
    /// still reports them visible. Recreate them on a later main-queue turn so
    /// every connected display gets a new click-through panel in its current
    /// Space without changing the model's explicit open state. (Codex task: 01a03a49-d2a9-7d63-85c0-f74ef52aeeab)
    private func reattachPanelsToCurrentSpaces() {
        guard model.isActive else { return }
        discardPanels()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model.isActive else { return }
            self.reconcilePanels(show: true)
        }
    }

    private func scheduleSettledSpaceReattachment() {
        delayedSpaceReattachWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.isActive else { return }
            self.reattachPanelsToCurrentSpaces()
        }
        delayedSpaceReattachWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
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
            guard let instance = panels.removeValue(forKey: key) else { continue }
            HUDScaleHoverCoordinator.shared.unregister(hudPanel: instance.panel)
            instance.scaleControlPanel.orderOut(nil)
            instance.panel.orderOut(nil)
        }

        for screen in screens {
            let instance = ensurePanel(for: screen)
            position(instance, on: screen)
            if show { instance.panel.orderFrontRegardless() }
        }
    }

    private func discardPanels() {
        panels.values.forEach {
            HUDScaleHoverCoordinator.shared.unregister(hudPanel: $0.panel)
            $0.scaleControlPanel.orderOut(nil)
            $0.panel.orderOut(nil)
        }
        panels.removeAll()
    }

    private func ensurePanel(for screen: NSScreen) -> PanelInstance {
        let key = ObjectIdentifier(screen)
        if let existing = panels[key] { return existing }

        let hosting = ScaledHUDHostingView(
            rootView: ModeHUDView(model: model),
            scale: CGFloat(scaleStore.scale)
        )
        let size = hosting.fittingSize
        let panel = HUDPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.contentView = hosting
        panel.alphaValue = panelOpacity
        let scaleControlPanel = HUDScaleControlPanel(scaleStore: scaleStore)
        HUDScaleHoverCoordinator.shared.register(
            hudPanel: panel,
            controlPanel: scaleControlPanel
        )
        let instance = PanelInstance(
            panel: panel,
            hostingView: hosting,
            scaleControlPanel: scaleControlPanel
        )
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
        positionScaleControl(instance)
        HUDScaleHoverCoordinator.shared.refresh()
    }

    private func positionScaleControl(_ instance: PanelInstance) {
        let inset: CGFloat = 8
        let x: CGFloat
        switch AppConfiguration.HUDConfiguration.sourceCorner(for: source) {
        case .topLeft, .bottomLeft:
            x = instance.panel.frame.minX + inset
        case .topRight, .bottomRight, .center:
            x = instance.panel.frame.maxX - HUDScaleControlPanel.size.width - inset
        }
        instance.scaleControlPanel.setFrameOrigin(NSPoint(
            x: x,
            y: instance.panel.frame.minY + inset
        ))
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
