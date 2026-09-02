import AppKit
import SwiftUI

/// The only pointer-interactive part of the HUD. It remains non-activating so
/// resizing never takes focus from the app Ethan is using.
final class HUDScaleControlPanel: NSPanel {
    static let size = NSSize(width: 30, height: 78)

    init(scaleStore: HUDScaleStore) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        level = .statusBar
        collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        contentView = FirstMouseHostingView(rootView: HUDScaleControlView(store: scaleStore))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func makeKey() {}
    override func makeKeyAndOrderFront(_ sender: Any?) { orderFrontRegardless() }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct HUDScaleControlView: View {
    @ObservedObject var store: HUDScaleStore

    var body: some View {
        GeometryReader { geometry in
            let trackHeight = max(1, geometry.size.height - 22)
            let progress = (store.scale - HUDScaleStore.minimumScale)
                / (HUDScaleStore.maximumScale - HUDScaleStore.minimumScale)

            ZStack {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))

                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(width: 3, height: trackHeight)

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                    .position(
                        x: geometry.size.width / 2,
                        y: 11 + trackHeight * (1 - progress)
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let normalized = 1 - min(1, max(0, (value.location.y - 11) / trackHeight))
                        store.setScale(
                            HUDScaleStore.minimumScale
                                + normalized * (HUDScaleStore.maximumScale - HUDScaleStore.minimumScale)
                        )
                    }
            )
        }
        .frame(width: HUDScaleControlPanel.size.width, height: HUDScaleControlPanel.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("HUD size")
        .accessibilityValue("\(Int((store.scale * 100).rounded())) percent")
    }
}

/// Watches pointer movement once for the whole app. The reference panels stay
/// click-through; only the small control belonging to the hovered HUD is shown.
final class HUDScaleHoverCoordinator {
    static let shared = HUDScaleHoverCoordinator()

    private struct Registration {
        weak var hudPanel: HUDPanel?
        weak var controlPanel: HUDScaleControlPanel?
    }

    private var registrations: [ObjectIdentifier: Registration] = [:]
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] _ in
            self?.refresh()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.refresh()
            return event
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    func register(hudPanel: HUDPanel, controlPanel: HUDScaleControlPanel) {
        registrations[ObjectIdentifier(hudPanel)] = Registration(
            hudPanel: hudPanel,
            controlPanel: controlPanel
        )
        refresh()
    }

    func unregister(hudPanel: HUDPanel) {
        let registration = registrations.removeValue(forKey: ObjectIdentifier(hudPanel))
        registration?.controlPanel?.orderOut(nil)
    }

    func refresh() {
        let pointer = NSEvent.mouseLocation
        registrations = registrations.filter { _, registration in
            guard let hudPanel = registration.hudPanel,
                  let controlPanel = registration.controlPanel
            else { return false }
            let isHovered = hudPanel.isVisible
                && (hudPanel.frame.contains(pointer) || controlPanel.frame.contains(pointer))
            if isHovered {
                controlPanel.orderFrontRegardless()
            } else {
                controlPanel.orderOut(nil)
            }
            return true
        }
    }
}
