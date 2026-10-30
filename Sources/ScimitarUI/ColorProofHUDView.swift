import AppKit
import Combine
import ScimitarKit
import SwiftUI

final class ModeHUDViewModel: ObservableObject {
    @Published var isActive = false
    @Published var modeTitle = "Mouse map"
    @Published var source: MouseSource = .corsair
    @Published var selection: ModeHUDSelection?
    @Published var pointerFocus: ModeHUDPointerFocus?
    @Published var wandReviewSelection: PhysicalCell?
    @Published var legend: [ModeHUDLegendItem] = []
    @Published var accent = ScimitarKit.RGBColor(red: 94, green: 210, blue: 255)
    @Published var outlineWidth: Double?
    @Published var lightingTargets: ModeLightingTargets = []
    @Published var footerTitle = ""
    @Published var footerHint: String?
    @Published var problem: String?
    @Published var feedback: ModeHUDFeedback?
    @Published var presentationStyle: ModeHUDPresentationStyle = .neutral
    @Published var appIcons: [PhysicalCell: NSImage] = [:]
    @Published var wandRadialLayout: WandRadialLayout?
    /// Continuous centre angle of the outlined ring card. It is unwrapped
    /// against the previous one so a move between the last and first card
    /// slides the short way round instead of unwinding the whole wheel. It is
    /// updated just before `pointerFocus`, whose publication redraws it.
    private(set) var wandFocusAngle: Double = 0
    private var appliedSnapshot: ModeHUDSnapshot?
    let appVersion = AgenticMouseVersion.displayString()
    private let appIconProvider: ModeHUDAppIconProviding

    init(
        source: MouseSource,
        appIconProvider: ModeHUDAppIconProviding = WorkspaceModeHUDAppIconProvider()
    ) {
        self.source = source
        self.appIconProvider = appIconProvider
    }

    @discardableResult
    func apply(_ snapshot: ModeHUDSnapshot) -> Bool {
        if isActive == snapshot.isActive, problem == snapshot.problem,
           var previous = appliedSnapshot {
            previous.pointerFocus = snapshot.pointerFocus
            if previous == snapshot {
                appliedSnapshot = snapshot
                if pointerFocus != snapshot.pointerFocus {
                    updateWandFocusAngle(snapshot.pointerFocus, layout: snapshot.wandRadialLayout)
                    pointerFocus = snapshot.pointerFocus
                }
                return true
            }
        }
        appliedSnapshot = snapshot
        var resolvedIcons: [PhysicalCell: NSImage] = [:]
        for item in snapshot.legend {
            if let backdrop = item.appBackdrop,
               let icon = appIconProvider.icon(for: backdrop) {
                resolvedIcons[item.cell] = icon
            }
        }
        // A page or content change is a cut, not a motion: the outline lands
        // on its new card in the same frame instead of springing across a
        // half-swapped grid while AppKit remeasures the panel. Only
        // focus-only updates above keep the outline's spring and liquid pull.
        var cut = Transaction()
        cut.disablesAnimations = true
        updateWandFocusAngle(snapshot.pointerFocus, layout: snapshot.wandRadialLayout)
        withTransaction(cut) {
            isActive = snapshot.isActive
            modeTitle = snapshot.modeTitle
            source = snapshot.source
            selection = snapshot.selection
            pointerFocus = snapshot.pointerFocus
            wandReviewSelection = snapshot.wandReviewSelection
            legend = snapshot.legend
            accent = snapshot.accent
            outlineWidth = snapshot.outlineWidth
            lightingTargets = snapshot.lightingTargets
            footerTitle = snapshot.footerTitle
            footerHint = snapshot.footerHint
            problem = snapshot.problem
            presentationStyle = snapshot.presentationStyle
            appIcons = resolvedIcons
            wandRadialLayout = snapshot.wandRadialLayout
        }
        return false
    }

    private func updateWandFocusAngle(_ focus: ModeHUDPointerFocus?, layout: WandRadialLayout?) {
        guard source == .wand, let focus else { return }
        let resolved = layout ?? .inferred(legend: legend)
        let target: Double
        if let index = resolved.outerIndex(of: focus.cell) {
            target = resolved.outerAngle(at: index)
        } else if let index = resolved.ringIndex(of: focus.cell) {
            target = resolved.angle(at: index)
        } else if resolved.center == focus.cell, (focus.pullX * focus.pullX + focus.pullY * focus.pullY) > 0.04 {
            // While the centre drop leans toward a card, keep its direction so
            // the morph onto that card starts where the drop already points.
            target = WandRadialLayout.angle(x: focus.pullX, y: focus.pullY)
        } else {
            return
        }
        let turns = ((wandFocusAngle - target) / (2 * .pi)).rounded()
        wandFocusAngle = target + turns * 2 * .pi
    }

    /// Hidden panels are discarded, but this model outlives them. Forget the
    /// last session's outline and snapshot so a later problem banner or the
    /// next open can never render or diff against a stale page.
    func resetAfterHide() {
        appliedSnapshot = nil
        isActive = false
        feedback = nil
        if pointerFocus != nil { pointerFocus = nil }
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

enum ModeHUDPointerFocusMetrics {
    /// Drawn just outside the card inside the 9-point grid gutter, so the
    /// outline never changes card geometry, titles or printed labels.
    static let outset: CGFloat = 4
    static let lineWidth: CGFloat = 3.5
    static let armedDash: [CGFloat] = [9, 5]
}

/// Wand navigation cursor. Solid while moving; marching dashes once a
/// held-wheel card is armed for tilt adjustment; a coloured ratchet ring
/// while it is adjusted.
struct ModeHUDPointerFocusRing: View {
    let focus: ModeHUDPointerFocus
    var accent: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let adjustment = focus.adjustment {
            WandAdjustRing(adjustment: adjustment, accent: accent)
        } else {
            // Ticks only while armed dots are marching (`WandArmedOutlineStyle`).
            TimelineView(WandArmedOutlineStyle.schedule(for: focus, reduceMotion: reduceMotion)) { timeline in
                WandLiquidOutline(pullX: focus.pullX, pullY: focus.pullY)
                    .stroke(
                        LinearGradient(colors: [.white, .white.opacity(0.65), .white],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(
                            lineWidth: ModeHUDPointerFocusMetrics.lineWidth,
                            dash: focus.isArmed ? WandArmedOutlineStyle.dash : [],
                            dashPhase: focus.isArmed
                                ? WandArmedOutlineStyle.dashPhase(at: timeline.date, reduceMotion: reduceMotion)
                                : 0
                        )
                    )
            }
            .padding(-ModeHUDPointerFocusMetrics.outset)
            .shadow(color: Color.white.opacity(0.75), radius: 6)
            .allowsHitTesting(false)
        }
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
    /// ImageRenderer cannot render AppKit glass. Offscreen visual checks use
    /// a neutral SwiftUI fill; every live presenter keeps native glass.
    var usesNativeGlass = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var wandOutline

    private var displayAccent: Color {
        Color(model.presentationStyle.displayAccent(model.accent))
    }

    var body: some View {
        if model.source == .wand {
            wandBody
        } else {
            gridBody
        }
    }

    /// Ethan's circular wand HUD: cards and footer float over the desktop.
    /// His "square background" was the shared outer glass and perimeter;
    /// only the mouse grid retains that panel background. The same glass now
    /// shows through each wheel card alone (`WandWheelBacking`).
    private var wandBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let problem = model.problem, !problem.isEmpty {
                problemBanner(problem)
            }
            WandRadialWheel(model: model, reduceMotion: reduceMotion, usesNativeGlass: usesNativeGlass)
            footer
        }
        .padding(WandWheelMetrics.panelPadding)
        .frame(width: WandWheelMetrics.panelWidth)
    }

    private var gridBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let problem = model.problem, !problem.isEmpty {
                problemBanner(problem)
            }

            grid
                .animation(reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.78),
                           value: model.pointerFocus?.cell)
                .animation(reduceMotion ? nil : .linear(duration: 0.03),
                           value: model.pointerFocus?.pullX)
                .animation(reduceMotion ? nil : .linear(duration: 0.03),
                           value: model.pointerFocus?.pullY)
            footer
        }
        .padding(27)
        .frame(width: extendedWandGrid ? extendedWandWidth : 705)
        .background(panelBackground)
    }

    private var displayRows: [[PhysicalCell]] {
        PhysicalCell.wandRows(source: model.source, legend: model.legend)
    }
    private var extendedWandGrid: Bool { displayRows.contains { $0.count > 4 } }
    private var extendedWandWidth: CGFloat {
        let columns=displayRows.map(\.count).max() ?? 4
        let reviewDivider=model.legend.contains { $0.cell == .wandReviewChanges } ? 14 : 0
        return CGFloat(columns * 156 + (columns - 1) * 9 + 54 + reviewDivider)
    }
    private var grid: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(displayRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 9) {
                    ForEach(row, id: \.self) { cell in
                        if cell == .wandReviewChanges {
                            Rectangle().fill(Color.white.opacity(0.35)).frame(width:1,height:64).padding(.horizontal,6)
                        }
                        legendCell(for: cell).frame(width: extendedWandGrid ? 156 : nil)
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
            let reviewSelected = model.wandReviewSelection == item.cell
            let fillColor = reviewSelected ? Color(item.accent) : (item.cell.wandReviewMode != nil ? Color(red:0.055,green:0.075,blue:0.10) : Color(cardColors.fill))
            let borderColor = Color(cardColors.border)
            let foregroundColor = reviewSelected ? Color.black : (item.cell.wandReviewMode != nil ? Color.white : Color(cardColors.foreground))
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            VStack(spacing: 4.5) {
                // Click part first, then the held part ending in its motion
                // arrow (see `ModeHUDGesture`). A long mixed title shrinks a
                // little rather than truncating either half.
                Text(item.displayTitle(on: model.source).uppercased())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(ModeHUDLayoutMetrics.cardTitleMinimumScale)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(foregroundColor)
                Text(item.printedControlLabel(on: model.source).uppercased())
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(foregroundColor)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(
                "\(item.accessibilityDescription(on: model.source)), \(item.printedControlLabel(on: model.source))"
            ))
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
                    usesStrongDestinationFill: item.cell.wandReviewMode != nil || cardColors.usesStrongDestinationFill,
                    appIcon: model.appIcons[item.cell]
                )
            )
            .overlay {
                if item.cell.wandReviewMode != nil {
                    shape.fill(Color(item.accent).opacity(0.12)).allowsHitTesting(false)
                    shape.strokeBorder(Color(item.accent).opacity(0.7),lineWidth:1.5).allowsHitTesting(false)
                }
                if model.wandReviewSelection == item.cell {
                    shape.strokeBorder(Color(item.accent),lineWidth:5)
                        .padding(-5).shadow(color:Color(item.accent).opacity(0.6),radius:6).allowsHitTesting(false)
                    Image(systemName:"lock.fill").font(.system(size:11,weight:.bold))
                        .foregroundStyle(Color(item.accent)).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topTrailing).padding(7)
                }
                if model.isActive, let focus = model.pointerFocus, focus.cell == item.cell {
                    ModeHUDPointerFocusRing(focus: focus, accent: Color(item.accent))
                        .matchedGeometryEffect(id: "wand-focus", in: wandOutline)
                }
            }
        }
    }

    private var footer: some View {
        let type = ModeHUDFooterType(source: model.source)
        return HStack(spacing: 9) {
            if let feedback = model.feedback {
                Circle()
                    .fill(feedbackColor(feedback.tone))
                    .frame(width: type.dot, height: type.dot)
                Text(feedback.message.uppercased())
                    .font(.system(size: type.feedback, weight: .bold, design: .rounded))
                    .foregroundStyle(feedbackColor(feedback.tone))
                    .lineLimit(1)
                    .minimumScaleFactor(type.feedbackMinimumScale)
                    .modifier(ModeHUDFooterLegibility(isOn: type.floatsOverDesktop))
            } else {
                Text(model.modeTitle.uppercased())
                    .font(.system(size: type.title, weight: .bold, design: .rounded))
                    .foregroundStyle(displayAccent)
                    .modifier(ModeHUDFooterLegibility(isOn: type.floatsOverDesktop))
            }

            Spacer()

            if model.legend.contains(where: { $0.gesture != nil }) {
                Text(ModeHUDCopy.gestureHint(for: model.source).uppercased())
                    .font(.system(size: type.hint, weight: .medium, design: .rounded))
                    .foregroundStyle(footerSecondary(type))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .modifier(ModeHUDFooterLegibility(isOn: type.floatsOverDesktop))
            }

            Text("\(model.source.displayName.uppercased())  ·  \(model.appVersion.uppercased())")
                .font(.system(size: type.version, weight: .semibold, design: .monospaced))
                .foregroundStyle(footerSecondary(type))
                .lineLimit(1)
                .modifier(ModeHUDFooterLegibility(isOn: type.floatsOverDesktop))
        }
    }

    /// The mice's footer sits on their panel and keeps the system secondary
    /// colour. The wand's floats straight over the desktop with no panel
    /// behind it, where `.secondary` follows the system appearance and can
    /// vanish (black on a dark desktop), so it is light with a dark halo.
    private func footerSecondary(_ type: ModeHUDFooterType) -> AnyShapeStyle {
        type.floatsOverDesktop ? AnyShapeStyle(Color.white.opacity(0.88)) : AnyShapeStyle(.secondary)
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
            if usesNativeGlass {
                ModeHUDNativeGlassBackground(cornerRadius: 27)
                    .clipShape(shape)
            } else {
                shape.fill(ModeHUDNativeGlass.offscreenStandIn)
            }

            shape.strokeBorder(
                displayAccent.opacity(model.isActive ? 1 : 0.32),
                lineWidth: model.outlineWidth ?? (model.presentationStyle == .boldOpaque ? 3 : 2.75)
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
        ModeHUDNativeGlass.makeEffectView(cornerRadius: cornerRadius)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        ModeHUDNativeGlass.update(nsView, cornerRadius: cornerRadius)
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

/// Footer type sizes. The physical mice keep their desk-distance footer; the
/// wand's notification, mode and gesture-hint lines are read from a lounging
/// distance (Ethan, 2026-10-30), so they are larger. A long notification may
/// shrink back to the mice's size rather than truncate.
struct ModeHUDFooterType: Equatable {
    let feedback: CGFloat
    let title: CGFloat
    let hint: CGFloat
    let version: CGFloat
    let dot: CGFloat
    let feedbackMinimumScale: CGFloat
    /// The wand footer has no panel behind it (only its cards have glass).
    let floatsOverDesktop: Bool

    init(source: MouseSource) {
        if source == .wand {
            feedback = 17; title = 17; hint = 14; version = 13; dot = 10
            feedbackMinimumScale = 12.5 / 17; floatsOverDesktop = true
        } else {
            feedback = 12.5; title = 13.5; hint = 10; version = 12; dot = 8
            feedbackMinimumScale = 1; floatsOverDesktop = false
        }
    }
}

/// Legible over any desktop, applied only where the footer floats without a
/// panel. Card text sits on its own coloured glass, so its light halo is
/// enough there; footer text can sit on a white desktop, so it carries a
/// firmer dark edge (stacked tight shadows) plus the same soft glow. No
/// backdrop is drawn: the wand has no panel behind its footer.
struct ModeHUDFooterLegibility: ViewModifier {
    let isOn: Bool
    func body(content: Content) -> some View {
        if isOn {
            content
                .shadow(color: .black.opacity(0.9), radius: 0.6)
                .shadow(color: .black.opacity(0.9), radius: 0.6)
                .shadow(color: .black.opacity(0.55), radius: 2.5)
        } else {
            content
        }
    }
}
