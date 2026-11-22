import AppKit
import CoreImage.CIFilterBuiltins
import QuartzCore

/// Ethan's “maximum bendy waviness”: distort the live native Clear material
/// around the four edges. The mask leaves the desktop untouched in the centre.
@available(macOS 26.0, *)
final class DefaultLegendGlassView: NSView {
    private let surface = NSView()
    private let carrier = NSView()
    private let glass = ModeHUDNativeGlass.makeEffectView(cornerRadius: 0)
    private let rim = CAShapeLayer()
    // The measured scale keeps a moving line recognisable through the glass.
    private let materialScale: CGFloat = 0.19
    private var previousSize = NSSize.zero
    var hudScale: CGFloat = 1 {
        didSet { if oldValue != hudScale { previousSize = .zero; needsLayout = true } }
    }

    private var lensOffset: CGFloat { 22 * hudScale }
    var samplingMargin: CGFloat { ceil(2 * lensOffset) }

    init() {
        super.init(frame: .zero)
        // The lens reads beyond this view before the rim mask composites it.
        // AppKit's default clip leaves the outer eight points undistorted.
        clipsToBounds = false
        wantsLayer = true
        surface.wantsLayer = true
        rim.fillColor = nil
        rim.strokeColor = NSColor.white.cgColor
        layer?.mask = rim
        carrier.addSubview(glass)
        surface.addSubview(carrier)
        addSubview(surface)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        guard !bounds.isEmpty, bounds.size != previousSize else { return }
        previousSize = bounds.size
        let offset = lensOffset
        let pad = 5 * offset
        let radius = 27 * hudScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        surface.frame = bounds.insetBy(dx: -pad, dy: -pad)
        carrier.frame = surface.bounds
        carrier.bounds.size = NSSize(width: surface.bounds.width / materialScale,
                                     height: surface.bounds.height / materialScale)
        glass.frame = carrier.bounds
        ModeHUDNativeGlass.update(glass, cornerRadius: radius / materialScale)

        let b = surface.bounds
        // Core Image measures these centres in view points, including on Retina.
        let centers: [(CGPoint, Float)] = [
            (CGPoint(x: b.midX, y: pad + offset), 0),
            (CGPoint(x: b.midX, y: b.maxY - pad - offset), 0),
            (CGPoint(x: pad + offset, y: b.midY), .pi / 2),
            (CGPoint(x: b.maxX - pad - offset, y: b.midY), .pi / 2)
        ]
        surface.contentFilters = centers.map { center, angle in
            let lens = CIFilter.bumpDistortionLinear()
            lens.center = center
            lens.radius = Float(2 * offset)
            lens.angle = angle
            lens.scale = -1
            return lens
        }
        let inset = offset / 2
        rim.frame = bounds
        rim.lineWidth = offset
        rim.path = CGPath(roundedRect: bounds.insetBy(dx: inset, dy: inset),
                          cornerWidth: radius - inset, cornerHeight: radius - inset, transform: nil)
        let feather = CIFilter.gaussianBlur()
        feather.radius = Float(2.75 * hudScale)
        rim.filters = [feather]
    }
}
