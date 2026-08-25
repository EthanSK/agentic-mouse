import AppKit
import Combine
import ScimitarKit
import SwiftUI

final class ModeHUDViewModel: ObservableObject {
    @Published var isActive = false
    @Published var modeTitle = "Mouse map"
    @Published var source: MouseSource = .corsair
    @Published var selection: ModeHUDSelection?
    @Published var legend: [ModeHUDLegendItem] = []
    @Published var accent = ScimitarKit.RGBColor(red: 94, green: 210, blue: 255)
    @Published var lightingTargets: ModeLightingTargets = []
    @Published var footerTitle = ""
    @Published var footerHint: String?
    @Published var problem: String?
    @Published var feedback: ModeHUDFeedback?
    @Published var presentationStyle: ModeHUDPresentationStyle = .neutral
    @Published var appIcons: [PhysicalCell: NSImage] = [:]
    let appVersion = AgenticMouseVersion.displayString()
    private let appIconProvider: ModeHUDAppIconProviding

    init(
        source: MouseSource,
        appIconProvider: ModeHUDAppIconProviding = WorkspaceModeHUDAppIconProvider()
    ) {
        self.source = source
        self.appIconProvider = appIconProvider
    }

    func apply(_ snapshot: ModeHUDSnapshot) {
        isActive = snapshot.isActive
        modeTitle = snapshot.modeTitle
        source = snapshot.source
        selection = snapshot.selection
        legend = snapshot.legend
        accent = snapshot.accent
        lightingTargets = snapshot.lightingTargets
        footerTitle = snapshot.footerTitle
        footerHint = snapshot.footerHint
        problem = snapshot.problem
        presentationStyle = snapshot.presentationStyle
        var resolvedIcons: [PhysicalCell: NSImage] = [:]
        for item in snapshot.legend {
            if let backdrop = item.appBackdrop,
               let icon = appIconProvider.icon(for: backdrop) {
                resolvedIcons[item.cell] = icon
            }
        }
        appIcons = resolvedIcons
    }
}

protocol ModeHUDAppIconProviding {
    func icon(for backdrop: ModeHUDAppBackdrop) -> NSImage?
}

/// Resolves the real installed app icon without persisting artwork or copying
/// it into Agentic Mouse. The exact running-app path wins; configured manual
/// targets resolve their existing canonical bundle identifier through AppKit.
/// Resolves and samples installed app icons once per stable identity. Both the
/// icon and its representative accent stay in memory only, so repeated HUD
/// refreshes and focus changes do no file lookup or image analysis.
public final class WorkspaceModeHUDAppIconProvider: ModeHUDAppIconProviding {
    private struct CachedStyle {
        let icon: NSImage
        let accent: ScimitarKit.RGBColor?
    }

    private let fileExists: (String) -> Bool
    private let applicationURLForBundleIdentifier: (String) -> URL?
    private let iconForFile: (String) -> NSImage
    private var cacheByApplicationPath: [String: CachedStyle] = [:]
    private var resolvedPathByIdentity: [ModeHUDAppBackdrop: String] = [:]

    public init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) {
        fileExists = fileManager.fileExists(atPath:)
        applicationURLForBundleIdentifier = workspace.urlForApplication(withBundleIdentifier:)
        iconForFile = workspace.icon(forFile:)
    }

    init(
        fileExists: @escaping (String) -> Bool,
        applicationURLForBundleIdentifier: @escaping (String) -> URL?,
        iconForFile: @escaping (String) -> NSImage
    ) {
        self.fileExists = fileExists
        self.applicationURLForBundleIdentifier = applicationURLForBundleIdentifier
        self.iconForFile = iconForFile
    }

    func icon(for backdrop: ModeHUDAppBackdrop) -> NSImage? {
        style(for: backdrop)?.icon
    }

    /// Returns a vivid representative colour when the icon can be sampled.
    /// Callers retain their deterministic app accent when this returns nil.
    public func accent(for backdrop: ModeHUDAppBackdrop) -> ScimitarKit.RGBColor? {
        style(for: backdrop)?.accent
    }

    private func style(for backdrop: ModeHUDAppBackdrop) -> CachedStyle? {
        if let resolvedPath = resolvedPathByIdentity[backdrop],
           let cached = cacheByApplicationPath[resolvedPath] {
            return cached
        }

        let applicationPath: String?
        if let exactPath = backdrop.applicationPath,
           fileExists(exactPath) {
            applicationPath = exactPath
        } else if let bundleIdentifier = backdrop.bundleIdentifier {
            applicationPath = applicationURLForBundleIdentifier(bundleIdentifier)?.path
        } else {
            applicationPath = nil
        }
        guard let applicationPath else { return nil }
        resolvedPathByIdentity[backdrop] = applicationPath
        if let cached = cacheByApplicationPath[applicationPath] { return cached }

        let source = iconForFile(applicationPath)
        let icon = (source.copy() as? NSImage) ?? source
        icon.size = NSSize(width: 512, height: 512)
        let style = CachedStyle(
            icon: icon,
            accent: ModeHUDAppIconAccentExtractor.representativeAccent(from: source)
        )
        cacheByApplicationPath[applicationPath] = style
        return style
    }
}

/// Samples a tiny 32 × 32 raster, ignores transparent pixels, and chooses the
/// strongest populated chromatic cluster. This avoids the muddy brown/grey a
/// raw whole-icon average produces while remaining bounded to 1,024 pixels per
/// app and running only on a cache miss.
enum ModeHUDAppIconAccentExtractor {
    private struct BucketKey: Hashable {
        let hue: Int
        let saturation: Int
        let brightness: Int
    }

    private struct Bucket {
        var weight = 0.0
        var red = 0.0
        var green = 0.0
        var blue = 0.0

        mutating func add(_ color: NSColor, weight sampleWeight: Double) {
            weight += sampleWeight
            red += Double(color.redComponent) * sampleWeight
            green += Double(color.greenComponent) * sampleWeight
            blue += Double(color.blueComponent) * sampleWeight
        }
    }

    static func representativeAccent(from image: NSImage) -> ScimitarKit.RGBColor? {
        guard let raster = rasterize(image) else { return nil }
        var chromatic: [BucketKey: Bucket] = [:]
        var neutralWeight = 0.0
        var neutralLuminance = 0.0

        for y in 0..<raster.pixelsHigh {
            for x in 0..<raster.pixelsWide {
                guard let sampled = raster.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB)
                else { continue }
                let alpha = Double(sampled.alphaComponent)
                guard alpha >= 0.18 else { continue }

                let red = Double(sampled.redComponent)
                let green = Double(sampled.greenComponent)
                let blue = Double(sampled.blueComponent)
                let maximum = max(red, green, blue)
                let minimum = min(red, green, blue)
                let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0

                neutralWeight += alpha
                neutralLuminance += (0.2126 * red + 0.7152 * green + 0.0722 * blue) * alpha

                guard saturation >= 0.18, maximum >= 0.12 else { continue }
                let hue = hue(red: red, green: green, blue: blue, maximum: maximum, minimum: minimum)
                let key = BucketKey(
                    hue: min(23, Int(hue * 24)),
                    saturation: min(2, Int(saturation * 3)),
                    brightness: min(2, Int(maximum * 3))
                )
                let weight = alpha * (0.35 + 0.65 * saturation) * (0.65 + 0.35 * maximum)
                var bucket = chromatic[key, default: Bucket()]
                bucket.add(sampled, weight: weight)
                chromatic[key] = bucket
            }
        }

        if let winner = chromatic.values.max(by: { $0.weight < $1.weight }),
           winner.weight > 0 {
            let red = winner.red / winner.weight
            let green = winner.green / winner.weight
            let blue = winner.blue / winner.weight
            return normalizedAccent(red: red, green: green, blue: blue)
        }

        guard neutralWeight > 0 else { return nil }
        // Neutral icons still receive a legible grey identity rather than an
        // invisible near-black or blown-out white perimeter and mouse colour.
        let luminance = max(0.55, min(0.88, neutralLuminance / neutralWeight))
        return ScimitarKit.RGBColor(
            unitRed: luminance,
            unitGreen: luminance,
            unitBlue: luminance
        )
    }

    private static func rasterize(_ image: NSImage) -> NSBitmapImageRep? {
        let size = 32
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        image.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.flushGraphics()
        return bitmap
    }

    private static func normalizedAccent(
        red: Double,
        green: Double,
        blue: Double
    ) -> ScimitarKit.RGBColor {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0
        let hue = hue(red: red, green: green, blue: blue, maximum: maximum, minimum: minimum)
        return hsv(
            hue: hue,
            saturation: max(0.58, min(0.92, saturation * 1.08)),
            brightness: max(0.72, min(0.96, maximum))
        )
    }

    private static func hue(
        red: Double,
        green: Double,
        blue: Double,
        maximum: Double,
        minimum: Double
    ) -> Double {
        let delta = maximum - minimum
        guard delta > 0 else { return 0 }
        let raw: Double
        if maximum == red {
            raw = (green - blue) / delta
        } else if maximum == green {
            raw = 2 + (blue - red) / delta
        } else {
            raw = 4 + (red - green) / delta
        }
        let turns = raw / 6
        return turns < 0 ? turns + 1 : turns
    }

    private static func hsv(
        hue: Double,
        saturation: Double,
        brightness: Double
    ) -> ScimitarKit.RGBColor {
        let sectorValue = (hue - floor(hue)) * 6
        let sector = Int(floor(sectorValue)) % 6
        let fraction = sectorValue - floor(sectorValue)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - fraction * saturation)
        let t = brightness * (1 - (1 - fraction) * saturation)
        let rgb: (Double, Double, Double)
        switch sector {
        case 0: rgb = (brightness, t, p)
        case 1: rgb = (q, brightness, p)
        case 2: rgb = (p, brightness, t)
        case 3: rgb = (p, q, brightness)
        case 4: rgb = (t, p, brightness)
        default: rgb = (brightness, p, q)
        }
        return ScimitarKit.RGBColor(unitRed: rgb.0, unitGreen: rgb.1, unitBlue: rgb.2)
    }
}

enum ModeHUDAppBackdropMetrics {
    /// Preserve recognizable icon structure while still letting it behave as
    /// atmosphere behind the app-mode trigger label.
    static let scale: CGFloat = 1.14
    static let blurRadius: CGFloat = 8
}

struct ModeHUDView: View {
    @ObservedObject var model: ModeHUDViewModel

    private var displayAccent: Color {
        Color(model.presentationStyle.displayAccent(model.accent))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let problem = model.problem, !problem.isEmpty {
                problemBanner(problem)
            }

            grid
            footer
        }
        .padding(27)
        .frame(width: 705)
        .background(panelBackground)
    }

    private var grid: some View {
        VStack(spacing: 9) {
            ForEach(Array(PhysicalCell.displayRowsTopToBottom(for: model.source).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 9) {
                    ForEach(row, id: \.self) { cell in
                        legendCell(for: cell)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func legendCell(for cell: PhysicalCell) -> some View {
        if let item = model.legend.first(where: { $0.cell == cell }) {
            let selected = item.cell == model.selection?.cell
            let cardColors = ModeHUDCardColors(
                modeAccent: model.accent,
                actionAccent: item.accent,
                destinationModeAccent: item.destinationModeAccent,
                presentationStyle: model.presentationStyle
            )
            let borderTreatment = ModeHUDCardBorderTreatment(
                isSelected: selected,
                isModeNavigation: item.destinationModeAccent != nil
            )
            let fillColor = Color(cardColors.fill)
            let borderColor = Color(cardColors.border)
            let foregroundColor = Color(cardColors.foreground)
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            VStack(spacing: 4.5) {
                Text(item.actionTitle.uppercased())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(foregroundColor)
                Text(item.printedControlLabel(on: model.source).uppercased())
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(foregroundColor)
            }
            .padding(.horizontal, ModeHUDLayoutMetrics.cardHorizontalContentInset)
            .frame(maxWidth: .infinity, minHeight: 66)
            .padding(.vertical, 12)
            .background(
                cardBackground(
                    shape: shape,
                    fillColor: fillColor,
                    borderColor: borderColor,
                    borderTreatment: borderTreatment,
                    selected: selected,
                    usesStrongDestinationFill: cardColors.usesStrongDestinationFill,
                    appIcon: model.appIcons[item.cell]
                )
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            if let feedback = model.feedback {
                Circle()
                    .fill(feedbackColor(feedback.tone))
                    .frame(width: 8, height: 8)
                Text(feedback.message.uppercased())
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(feedbackColor(feedback.tone))
                    .lineLimit(1)
            } else {
                Text(model.modeTitle.uppercased())
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(displayAccent)
            }

            Spacer()

            Text("\(model.source.displayName.uppercased())  ·  \(model.appVersion.uppercased())")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func feedbackColor(_ tone: ModeHUDFeedback.Tone) -> Color {
        switch tone {
        case .confirmed:
            return Color(red: 0.25, green: 0.95, blue: 0.55)
        case .informational:
            return Color(red: 0.36, green: 0.78, blue: 1.0)
        case .notConfirmed:
            return Color(red: 1.0, green: 0.68, blue: 0.22)
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 27, style: .continuous)
        ZStack {
            ModeHUDNativeGlassBackground(cornerRadius: 27)
                .clipShape(shape)

            shape.strokeBorder(
                displayAccent.opacity(model.isActive ? 1 : 0.32),
                lineWidth: model.presentationStyle == .boldOpaque ? 3 : 2.75
            )
        }
    }

    @ViewBuilder
    private func cardBackground(
        shape: RoundedRectangle,
        fillColor: Color,
        borderColor: Color,
        borderTreatment: ModeHUDCardBorderTreatment,
        selected: Bool,
        usesStrongDestinationFill: Bool,
        appIcon: NSImage?
    ) -> some View {
        ZStack {
            shape.fill(cardFill(
                fillColor,
                selected: selected,
                usesStrongDestinationFill: usesStrongDestinationFill
            ))

            if let appIcon {
                GeometryReader { geometry in
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .scaleEffect(ModeHUDAppBackdropMetrics.scale)
                        .saturation(1.35)
                        .contrast(1.08)
                        .blur(radius: ModeHUDAppBackdropMetrics.blurRadius, opaque: true)
                }
                .clipShape(shape)

                // Keep the real icon recognisable as atmosphere without
                // smearing away its identity or competing with the label.
                shape.fill(Color.black.opacity(0.28))
                shape.fill(fillColor.opacity(0.18))
            }

            shape.strokeBorder(
                borderColor.opacity(borderTreatment.opacity),
                lineWidth: borderTreatment.lineWidth
            )
        }
        .clipShape(shape)
    }

    private func cardFill(
        _ color: Color,
        selected: Bool,
        usesStrongDestinationFill: Bool
    ) -> Color {
        switch model.presentationStyle {
        case .neutral:
            if usesStrongDestinationFill {
                return color
            }
            return color.opacity(selected ? 0.58 : 0.24)
        case .boldOpaque:
            return color
        }
    }

    private func problemBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 16.5, weight: .medium))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 10.5)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            )
    }
}

/// Uses macOS 26's real AppKit Liquid Glass for the outer panel only. The
/// action cards remain ordinary SwiftUI fills above it: calmer opaque action
/// tints preserve grouping, while mode-navigation cards keep full-strength
/// destination colours. Older macOS releases retain a native AppKit
/// visual-effect material as the compatibility path.
private struct ModeHUDNativeGlassBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
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

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            glass.style = .clear
            glass.tintColor = nil
            glass.cornerRadius = cornerRadius
        } else {
            nsView.layer?.cornerRadius = cornerRadius
        }
    }
}

private extension Color {
    init(_ rgb: ScimitarKit.RGBColor) {
        self.init(
            red: Double(rgb.red) / 255.0,
            green: Double(rgb.green) / 255.0,
            blue: Double(rgb.blue) / 255.0,
            opacity: Double(rgb.alpha) / 255.0
        )
    }
}
