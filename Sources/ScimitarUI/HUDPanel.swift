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
public final class AppKitHUDPresenter: HUDPresenting {
    private var panel: HUDPanel?
    private var hostingView: NSHostingView<HUDView>?
    private let model = HUDViewModel()
    private let configuration: AppConfiguration.HUDConfiguration
    private var problemDismissWorkItem: DispatchWorkItem?

    public init(configuration: AppConfiguration.HUDConfiguration = .init()) {
        self.configuration = configuration
    }

    public var isVisible: Bool { panel?.isVisible ?? false }

    public func show(_ snapshot: HUDSnapshot) {
        model.apply(snapshot)
        let panel = ensurePanel()
        position(panel)
        // Regardless — this is what keeps the previously focused app frontmost.
        panel.orderFrontRegardless()
    }

    public func update(_ snapshot: HUDSnapshot) {
        model.apply(snapshot)
    }

    public func hide() {
        problemDismissWorkItem?.cancel()
        // The model must be told the mode is over, not just the window.
        // `flashProblem`'s dismissal asks `model.isActive` whether it is safe to
        // order the panel out; leaving a stale `true` here would strand a
        // failure message on screen indefinitely, because `hide()` is followed
        // by `flashProblem()` on every failure exit.
        model.isActive = false
        panel?.orderOut(nil)
    }

    /// Shows a short-lived explanation when the mode could not be entered.
    /// Uses the same non-activating panel, so a refusal cannot steal focus
    /// either.
    public func flashProblem(_ message: String) {
        model.problem = message
        let panel = ensurePanel()
        position(panel)
        panel.orderFrontRegardless()

        problemDismissWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.problem = nil
            if !self.model.isActive { self.panel?.orderOut(nil) }
        }
        problemDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    // MARK: - Panel plumbing

    private func ensurePanel() -> HUDPanel {
        if let panel { return panel }

        let view = HUDView(
            model: model,
            showsTapProgressRing: configuration.showsTapProgressRing
        )
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = HUDPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.contentView = hosting
        panel.alphaValue = CGFloat(configuration.opacity)

        self.panel = panel
        self.hostingView = hosting
        return panel
    }

    private func position(_ panel: HUDPanel) {
        guard let screen = targetScreen() else { return }
        let visible = screen.visibleFrame
        // `problem` conditionally inserts a banner. Force SwiftUI/AppKit to
        // settle that published change before measuring, or the first failure
        // message can be positioned with the smaller pre-banner size.
        hostingView?.layoutSubtreeIfNeeded()
        let size = hostingView?.fittingSize ?? panel.frame.size
        let margin = CGFloat(configuration.margin)

        let origin: NSPoint
        switch configuration.corner {
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
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func targetScreen() -> NSScreen? {
        guard configuration.followsPointerScreen else { return NSScreen.main }
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }
}
