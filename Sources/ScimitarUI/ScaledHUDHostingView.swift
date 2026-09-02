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
        wantsLayer = true
        hostingView.wantsLayer = true
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
        hostingView.frame = NSRect(origin: .zero, size: unscaledSize)
        hostingView.layer?.anchorPoint = .zero
        hostingView.layer?.position = .zero
        hostingView.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
    }
}
