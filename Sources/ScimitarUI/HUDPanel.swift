import AppKit
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
        let hostingView: NSHostingView<HUDView>
    }

    private var panels: [ObjectIdentifier: PanelInstance] = [:]
    private let model: HUDViewModel
    private let source: MouseSource
    private let configuration: AppConfiguration.HUDConfiguration
    private var problemDismissWorkItem: DispatchWorkItem?

    public init(
        source: MouseSource,
        configuration: AppConfiguration.HUDConfiguration = .init()
    ) {
        self.source = source
        self.model = HUDViewModel(source: source)
        self.configuration = configuration
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

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
        // The model must be told the mode is over, not just the window.
        // `flashProblem`'s dismissal asks `model.isActive` whether it is safe to
        // order the panel out; leaving a stale `true` here would strand a
        // failure message on screen indefinitely, because `hide()` is followed
        // by `flashProblem()` on every failure exit.
        model.isActive = false
        panels.values.forEach { $0.panel.orderOut(nil) }
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
            if !self.model.isActive { self.panels.values.forEach { $0.panel.orderOut(nil) } }
        }
        problemDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    // MARK: - Panel plumbing

    @objc private func screenParametersDidChange(_ notification: Notification) {
        guard isVisible else { return }
        reconcilePanels(show: true)
    }

    private func ensurePanel(for screen: NSScreen) -> PanelInstance {
        let key = ObjectIdentifier(screen)
        if let existing = panels[key] { return existing }
        let view = HUDView(
            model: model,
            showsTapProgressRing: configuration.showsTapProgressRing
        )
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = HUDPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.contentView = hosting
        panel.alphaValue = CGFloat(configuration.opacity)

        let instance = PanelInstance(panel: panel, hostingView: hosting)
        panels[key] = instance
        return instance
    }

    private func reconcilePanels(show: Bool) {
        let screens = NSScreen.screens
        let targetKeys = Set(screens.map(ObjectIdentifier.init))
        for key in panels.keys.filter({ !targetKeys.contains($0) }) {
            panels.removeValue(forKey: key)?.panel.orderOut(nil)
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
    }
}
