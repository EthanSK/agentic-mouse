import AppKit
import SwiftUI

/// Scales the complete rendered HUD, including type, spacing, borders, and material.
final class ScaledHUDHostingView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private(set) var scale: CGFloat

    init(rootView: Content, scale: CGFloat) {
        hostingView = NSHostingView(rootView: rootView)
        self.scale = scale
        super.init(frame: .zero)
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var fittingSize: NSSize {
        let unscaledSize = hostingView.fittingSize
        return NSSize(
            width: unscaledSize.width * scale,
            height: unscaledSize.height * scale
        )
    }

    func setScale(_ scale: CGFloat) {
        guard scale != self.scale else { return }
        self.scale = scale
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let unscaledSize = hostingView.fittingSize
        bounds = NSRect(origin: .zero, size: unscaledSize) // A layer transform clipped SwiftUI to the already-small window frame. Map the full source bounds into that frame so the complete HUD shrinks instead. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
        hostingView.frame = bounds
    }
}
