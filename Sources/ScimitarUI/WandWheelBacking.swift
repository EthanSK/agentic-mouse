import AppKit
import CoreGraphics
import QuartzCore
import SwiftUI

/// The native glass configuration every Agentic Mouse HUD surface uses. The
/// grid's outer panel and the wand wheel's card-shaped backing share it, so the
/// clear, untinted Liquid Glass contract lives in one place.
enum ModeHUDNativeGlass {
    /// ImageRenderer cannot draw AppKit glass. Offscreen visual checks use
    /// this neutral fill wherever a live HUD shows native glass.
    static let offscreenStandIn = Color(white: 0.11)

    static func makeEffectView(cornerRadius: CGFloat) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            // Clear is AppKit's most transparent native glass style. Leaving
            // the tint nil and the substrate unobscured preserves the full
            // system-provided lensing response to desktop content behind this
            // transparent, non-activating HUD window.
            glass.style = .clear
            glass.tintColor = nil
            glass.cornerRadius = cornerRadius
            glass.contentView = NSView()
            return glass
        }

        let fallback = NSVisualEffectView()
        fallback.material = .hudWindow
        fallback.blendingMode = .behindWindow
        fallback.state = .active
        fallback.wantsLayer = true
        fallback.layer?.cornerRadius = cornerRadius
        return fallback
    }

    static func update(_ view: NSView, cornerRadius: CGFloat) {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            glass.style = .clear
            glass.tintColor = nil
            glass.cornerRadius = cornerRadius
        } else {
            view.layer?.cornerRadius = cornerRadius
        }
    }
}

// MARK: - Silhouette

/// Every card the wheel draws, as one shape: the centre disc and each ring
/// wedge, in the wheel frame's own coordinates. Gutters, the gap between the
/// disc and the ring, and everything outside the ring are not part of it.
/// Cards never overlap, so their outlines simply combine.
struct WandWheelSilhouette: Shape {
    let geometry: WandWheelGeometry
    let includesCenter: Bool
    let ringIndices: [Int]
    var outerIndices: [Int] = []
    /// The native mask follows the same spring as the cards, including both
    /// the returning card and the newly selected card during a quick reversal.
    var lifted: WandWheelGeometry.Slot? = nil
    var liftValues: [Double]? = nil

    var targetLiftValues: [Double] {
        var values = [Double](repeating: 0, count: 1 + geometry.layout.ring.count + geometry.layout.outer.count)
        if let lifted { values[liftIndex(lifted)] = 1 }
        return values
    }

    private func liftIndex(_ slot: WandWheelGeometry.Slot) -> Int {
        switch slot {
        case .center: return 0
        case .ring(let index): return 1 + index
        case .outer(let index): return 1 + geometry.layout.ring.count + index
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func add(_ card: Path, slot: WandWheelGeometry.Slot) {
            let index = liftIndex(slot)
            let amount = liftValues.flatMap { index < $0.count ? $0[index] : nil } ?? (slot == lifted ? 1 : 0)
            guard amount != 0 else { return path.addPath(card) }
            var pose = WandCardLift.pose(for: slot, lifted: true, in: geometry)
            pose.scale = 1 + (pose.scale - 1) * amount
            pose.offset.width *= amount
            pose.offset.height *= amount
            path.addPath(card.applying(WandCardLift.transform(pose, size: geometry.size)))
        }
        if includesCenter {
            add(WandCenterDiscShape(radius: WandWheelMetrics.centerRadius).path(in: rect), slot: .center)
        }
        for index in ringIndices {
            add(WandWedgeShape(wedge: geometry.wedge(at: index)).path(in: rect), slot: .ring(index))
        }
        for index in outerIndices {
            add(WandWedgeShape(wedge: geometry.outerWedge(at: index)).path(in: rect), slot: .outer(index))
        }
        return path
    }
}

/// Rasterizes the silhouette as a mask: opaque inside a card, transparent
/// everywhere else. `path` uses SwiftUI's y-down coordinates within `canvas`;
/// the returned image's first row is the top of the wheel.
enum WandWheelMask {
    /// SwiftUI paths are y-down; the hosted AppKit layer is y-up. Transform
    /// the same card contours directly instead of allocating and painting a
    /// full Retina bitmap at every frame of the existing card-lift spring.
    static func vectorPath(of path: CGPath, canvas: CGSize, size: CGSize) -> CGPath? {
        guard canvas.width > 0, canvas.height > 0, size.width > 0, size.height > 0 else { return nil }
        var transform = CGAffineTransform(a: size.width / canvas.width, b: 0,
                                         c: 0, d: -size.height / canvas.height,
                                         tx: 0, ty: size.height)
        return path.copy(using: &transform)
    }

    static func image(of path: CGPath, canvas: CGSize, size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, canvas.width > 0, canvas.height > 0,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        // Bitmap contexts are y-up. Flip once so the y-down path lands with
        // the wheel's top in the image's first row.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(width) / canvas.width, y: -CGFloat(height) / canvas.height)
        context.addPath(path)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        return context.makeImage()
    }
}

// MARK: - Backing

/// Ethan: each wedge's background "should still be as if it were on top of
/// the normal background that we just removed ... just for that wedge, it's
/// like masked". One shared glass surface, the same one the grid panel uses,
/// sits under the whole wheel and shows only through the cards. Card fills,
/// artwork and borders draw above it exactly as they did over the old panel.
/// A scalar for every card lets SwiftUI retain the displayed pose when input
/// changes mid-spring. Interpolating only the selected index would jump on reversal.
struct WandGlassLiftValues: VectorArithmetic {
    var values: [Double]
    static let zero = Self(values: [])
    static func + (lhs: Self, rhs: Self) -> Self { combine(lhs, rhs, sign: 1) }
    static func - (lhs: Self, rhs: Self) -> Self { combine(lhs, rhs, sign: -1) }
    private static func combine(_ lhs: Self, _ rhs: Self, sign: Double) -> Self {
        Self(values: (0..<max(lhs.values.count, rhs.values.count)).map {
            ($0 < lhs.values.count ? lhs.values[$0] : 0) + sign * ($0 < rhs.values.count ? rhs.values[$0] : 0)
        })
    }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

struct WandWheelBacking: View, Animatable {
    let silhouette: WandWheelSilhouette
    let size: CGFloat
    let usesNativeGlass: Bool
    var animatableData: WandGlassLiftValues

    init(silhouette: WandWheelSilhouette, size: CGFloat, usesNativeGlass: Bool) {
        self.silhouette = silhouette
        self.size = size
        self.usesNativeGlass = usesNativeGlass
        self.animatableData = WandGlassLiftValues(values: silhouette.targetLiftValues)
    }

    private var animatedSilhouette: WandWheelSilhouette {
        var result = silhouette
        result.liftValues = animatableData.values
        return result
    }

    var body: some View {
        Group {
            if usesNativeGlass {
                WandWheelGlassBacking(
                    silhouette: animatedSilhouette.path(in: CGRect(x: 0, y: 0, width: size, height: size)).cgPath,
                    canvas: CGSize(width: size, height: size)
                )
            } else {
                animatedSilhouette.fill(ModeHUDNativeGlass.offscreenStandIn)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

private struct WandWheelGlassBacking: NSViewRepresentable {
    let silhouette: CGPath
    let canvas: CGSize

    func makeNSView(context: Context) -> WandMaskedGlassView {
        let view = WandMaskedGlassView(frame: NSRect(origin: .zero, size: canvas))
        view.setSilhouette(silhouette, canvas: canvas)
        return view
    }

    func updateNSView(_ nsView: WandMaskedGlassView, context: Context) {
        nsView.setSilhouette(silhouette, canvas: canvas)
    }
}

/// Native glass clipped to the wheel's cards. SwiftUI clipping is not relied
/// on for a hosted AppKit view: macOS 26 glass is masked by its container's
/// layer using a vector mask, and the older visual-effect fallback uses its
/// documented `maskImage`. Both follow the same card contours and orientation.
/// Without a usable mask the glass stays hidden, so
/// the wheel can never fall back to a square or circular plate.
final class WandMaskedGlassView: NSView {
    private let effect = ModeHUDNativeGlass.makeEffectView(cornerRadius: 0)
    private let maskLayer = CAShapeLayer()
    private var silhouette: CGPath?
    private var canvas: CGSize = .zero

    /// The mask is rebuilt only when the cards, size or backing scale change,
    /// never while the outline moves.
    private struct MaskKey: Equatable {
        let path: CGPath
        let canvas: CGSize
        let size: CGSize
        let scale: CGFloat

        static func == (lhs: MaskKey, rhs: MaskKey) -> Bool {
            CFEqual(lhs.path, rhs.path) && lhs.canvas == rhs.canvas && lhs.size == rhs.size && lhs.scale == rhs.scale
        }
    }
    private var appliedMask: MaskKey?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        effect.isHidden = true
        effect.frame = bounds
        effect.autoresizingMask = [.width, .height]
        addSubview(effect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setSilhouette(_ path: CGPath, canvas: CGSize) {
        if let silhouette, CFEqual(silhouette, path), canvas == self.canvas { return }
        silhouette = path
        self.canvas = canvas
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        effect.frame = bounds
        applyMask()
    }

    private func applyMask() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard let silhouette, bounds.width > 0, bounds.height > 0 else {
            effect.isHidden = true
            return
        }
        let key = MaskKey(path: silhouette, canvas: canvas, size: bounds.size, scale: scale)
        guard key != appliedMask else { return }
        if #available(macOS 26.0, *) {
            guard let path = WandWheelMask.vectorPath(of: silhouette, canvas: canvas, size: bounds.size) else {
                effect.isHidden = true; appliedMask = nil; return
            }
            // SwiftUI already supplies each animated lift pose. An implicit
            // Core Animation transition here would chase those poses again.
            // Only presentation work changes; navigation and its timing do not.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            maskLayer.path = path
            maskLayer.fillColor = NSColor.white.cgColor
            maskLayer.frame = layer?.bounds ?? bounds
            layer?.mask = maskLayer
            CATransaction.commit()
        } else if let fallback = effect as? NSVisualEffectView {
            guard let image = WandWheelMask.image(of: silhouette, canvas: canvas, size: bounds.size, scale: scale) else {
                effect.isHidden = true; appliedMask = nil; return
            }
            fallback.maskImage = NSImage(cgImage: image, size: bounds.size)
        }
        effect.isHidden = false
        appliedMask = key
    }
}
