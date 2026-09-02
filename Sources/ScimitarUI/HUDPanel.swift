import AppKit
import Combine
import ScimitarKit
import SwiftUI

/// A reference panel that can never steal focus.
///
/// Every one of these is load-bearing:
///
///  * `.nonactivatingPanel` — showing it does not activate this process, so the
///    app the user is typing into stays frontmost and keeps its insertion point.
///  * `canBecomeKey`/`canBecomeMain` return `false` — the panel cannot become
///    the key window even if something tries to make it so, so the text caret
///    never moves.
///  * `ignoresMouseEvents = true` — clicks pass straight through to whatever is
///    underneath. The HUD is a reference card, not a control.
///  * `hidesOnDeactivate = false` and `.canJoinAllSpaces` — it stays visible
///    while the user works in another app or another Space, which is the entire
///    point.
///  * `orderFrontRegardless()`, never `makeKeyAndOrderFront(_:)`.
final class HUDPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = true

        // Above normal windows and full-screen apps, below the menu bar's own
        // panels so it never covers a system alert.
        level = .statusBar
        collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications, // The legend can render correctly but remain hidden in another app's macOS window set. Join every app set so this system overlay stays visible without activation. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Belt and braces: even an explicit request is refused.
    override func makeKey() {}
    override func makeKeyAndOrderFront(_ sender: Any?) { orderFrontRegardless() }
}

/// Places and drives the HUD panel.
///
/// Not actor-annotated on purpose: every call arrives on the main queue (the
/// coordinator's tick scheduler and the input callbacks both run there), and
/// keeping it non-isolated lets it satisfy the plain `HUDPresenting` protocol
/// that the hardware-free tests use.
public final class AppKitHUDPresenter: NSObject, HUDPresenting {
    private struct PanelInstance {
        let panel: HUDPanel
        let hostingView: ScaledHUDHostingView<HUDView>
        let scaleControlPanel: HUDScaleControlPanel
    }

    private var panels: [ObjectIdentifier: PanelInstance] = [:]
    private let model: HUDViewModel
    private let source: MouseSource
    private let configuration: AppConfiguration.HUDConfiguration
    private let scaleStore: HUDScaleStore
    private let workspaceNotificationCenter: NotificationCenter
    private var scaleObservation: AnyCancellable?
    private var problemDismissWorkItem: DispatchWorkItem?
    private var delayedSpaceReattachWorkItem: DispatchWorkItem?

    public init(
        source: MouseSource,
        configuration: AppConfiguration.HUDConfiguration = .init(),
        scaleStore: HUDScaleStore = .shared,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.source = source
        self.model = HUDViewModel(source: source)
        self.configuration = configuration
        self.scaleStore = scaleStore
        self.workspaceNotificationCenter = workspaceNotificationCenter
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
        delayedSpaceReattachWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
        workspaceNotificationCenter.removeObserver(self)
    }

    public var isVisible: Bool { panels.values.contains { $0.panel.isVisible } }

    public func show(_ snapshot: HUDSnapshot) {
        guard snapshot.source == source else { return }
        model.apply(snapshot)
        reconcilePanels(show: true)
    }

    public func update(_ snapshot: HUDSnapshot) {
        guard snapshot.source == source else { return }
        model.apply(snapshot)
        if isVisible { reconcilePanels(show: true) }
    }

    public func hide() {
        problemDismissWorkItem?.cancel()
        delayedSpaceReattachWorkItem?.cancel()
        // The model must be told the mode is over, not just the window.
        // `flashProblem`'s dismissal asks `model.isActive` whether it is safe to
        // order the panel out; leaving a stale `true` here would strand a
        // failure message on screen indefinitely, because `hide()` is followed
        // by `flashProblem()` on every failure exit.
        model.isActive = false
        discardPanels()
    }

    /// Shows a short-lived explanation when the mode could not be entered.
    /// Uses the same non-activating panel, so a refusal cannot steal focus
    /// either.
    public func flashProblem(_ message: String) {
        model.problem = message
        reconcilePanels(show: true)

        problemDismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.problem = nil
            if !self.model.isActive { self.discardPanels() }
        }
        problemDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    // MARK: - Panel plumbing

    @objc private func screenParametersDidChange(_ notification: Notification) {
        guard isVisible else { return }
        reconcilePanels(show: true)
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model.isActive else { return }
            self.reattachPanelsToCurrentSpaces()
            self.scheduleSettledSpaceReattachment()
        }
    }

    /// Cached panels can remain attached to a stale Space even while AppKit
    /// reports them visible. Recreate them on a later main-queue turn so each
    /// connected display receives a fresh non-activating panel in its current
    /// Space. Hidden models remain hidden. (Codex task: 01a03a49-d2a9-7d63-85c0-f74ef52aeeab)
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
        let view = HUDView(
            model: model,
            showsTapProgressRing: configuration.showsTapProgressRing
        )
        let hosting = ScaledHUDHostingView(
            rootView: view,
            scale: CGFloat(scaleStore.scale)
        )
        let size = hosting.fittingSize
        let panel = HUDPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.contentView = hosting
        panel.alphaValue = CGFloat(configuration.opacity)
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

    private func reconcilePanels(show: Bool) {
        let screens = NSScreen.screens
        let targetKeys = Set(screens.map(ObjectIdentifier.init))
        for key in panels.keys.filter({ !targetKeys.contains($0) }) {
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

    private func position(_ instance: PanelInstance, on screen: NSScreen) {
        let visible = screen.visibleFrame
        // `problem` conditionally inserts a banner. Force SwiftUI/AppKit to
        // settle that published change before measuring, or the first failure
        // message can be positioned with the smaller pre-banner size.
        instance.hostingView.layoutSubtreeIfNeeded()
        let size = instance.hostingView.fittingSize
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
            origin = NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2
            )
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
}
