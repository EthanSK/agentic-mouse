import AppKit
import CoreGraphics
import ScimitarKit

// MARK: - Room inside a card

/// How much horizontal room a card offers its text at each height.
///
/// Ring cards are wedges: narrow toward the centre and wide at the rim, and
/// tilted everywhere except 3, 6, 9 and 12 o'clock. Laying text out line by
/// line in that real shape lets each line use the width its own height has,
/// instead of one rectangle that only fits the narrowest part.
struct WandCardRoom {
    enum Shape {
        case wedge(WandWedge)
        case disc(radius: CGFloat)
    }

    let shape: Shape
    /// Inset beside text and above or below it, for this room.
    var sideMargin: CGFloat = Self.horizontalMargin
    var endMargin: CGFloat = Self.verticalMargin

    /// The shared 12-point inset applies beside text; above and below it,
    /// half of it is enough. A curved or slanted border interpolates.
    static let horizontalMargin = ModeHUDLayoutMetrics.cardHorizontalContentInset
    static let verticalMargin = ModeHUDLayoutMetrics.cardHorizontalContentInset / 2
    /// Thin outer bands are a third of a ring card's depth, so a ring card's
    /// insets would spend most of their room; they keep about half of them.
    static let outerSideMargin: CGFloat = 7
    static let outerEndMargin: CGFloat = 4
    /// An adjustable outer band keeps this much more at each end for its
    /// adjustment arrows (`WandAdjustArrowPlacement`), so they never cover it.
    static let outerArrowRoom: CGFloat = 22

    private static func margin(normalX: CGFloat, side: CGFloat, end: CGFloat) -> CGFloat {
        end + (side - end) * min(1, abs(normalX))
    }

    /// Largest x reached at height `y` inside a circle of `radius`, keeping
    /// the direction-dependent margin from it.
    private static func circleReach(radius: CGFloat, y: CGFloat, side: CGFloat, end: CGFloat) -> CGFloat? {
        var x: CGFloat = 0
        var inset = end
        for _ in 0..<3 {
            let r = radius - inset
            guard r > abs(y) else { return nil }
            x = sqrt(r * r - y * y)
            inset = margin(normalX: x / max(radius, 1), side: side, end: end)
        }
        let r = radius - inset
        guard r > abs(y) else { return nil }
        return min(x, sqrt(r * r - y * y))
    }

    /// Half-width of the inner hole at height `y`, including its margin.
    private static func holeReach(radius: CGFloat, y: CGFloat, side: CGFloat, end: CGFloat) -> CGFloat {
        var x: CGFloat = 0
        var inset = end
        for _ in 0..<3 {
            let r = radius + inset
            guard r > abs(y) else { return 0 }
            x = sqrt(r * r - y * y)
            inset = margin(normalX: x / max(r, 1), side: side, end: end)
        }
        let r = radius + inset
        return r > abs(y) ? max(x, sqrt(r * r - y * y)) : 0
    }

    /// Allowed horizontal spans at height `y`, in wheel-centred coordinates.
    func spans(atY y: CGFloat) -> [ClosedRange<CGFloat>] {
        switch shape {
        case .disc(let radius):
            guard let x = Self.circleReach(radius: radius, y: y, side: sideMargin, end: endMargin) else { return [] }
            return [(-x)...x]
        case .wedge(let wedge):
            guard let outer = Self.circleReach(radius: wedge.outer, y: y, side: sideMargin, end: endMargin) else { return [] }
            let hole = Self.holeReach(radius: wedge.inner, y: y, side: sideMargin, end: endMargin)
            var ranges: [ClosedRange<CGFloat>] = hole > 0
                ? (hole < outer ? [(-outer)...(-hole), hole...outer] : [])
                : [(-outer)...outer]
            var low = -CGFloat.infinity, high = CGFloat.infinity
            func clip(normal n: CGPoint, offset k: CGFloat) -> Bool {
                // n.x * x + n.y * y >= k
                if abs(n.x) < 1e-9 { return n.y * y >= k }
                let bound = (k - n.y * y) / n.x
                if n.x > 0 { low = max(low, bound) } else { high = min(high, bound) }
                return true
            }
            if wedge.halfWidth < .pi / 2 {
                let start = WandWedge.tangent(wedge.centerAngle - wedge.halfWidth)
                let end = WandWedge.tangent(wedge.centerAngle + wedge.halfWidth)
                let endInward = CGPoint(x: -end.x, y: -end.y)
                guard clip(normal: start, offset: wedge.halfGap + Self.margin(normalX: start.x, side: sideMargin, end: endMargin)),
                      clip(normal: endInward, offset: wedge.halfGap + Self.margin(normalX: endInward.x, side: sideMargin, end: endMargin))
                else { return [] }
            } else {
                // One or two cards: keep the half of the ring the card faces.
                guard clip(normal: WandWedge.radial(wedge.centerAngle), offset: 0) else { return [] }
            }
            ranges = ranges.compactMap { range in
                let lo = max(range.lowerBound, low), hi = min(range.upperBound, high)
                return lo < hi ? lo...hi : nil
            }
            return ranges
        }
    }

    /// Room for a line centred on `column` spanning `top...bottom`: twice the
    /// smallest distance to either side at any height the line covers.
    func width(column: CGFloat, top: CGFloat, bottom: CGFloat) -> CGFloat {
        // Every border's width changes monotonically between these: arcs and
        // slanted edges reach their narrowest at a line's ends, and the inner
        // hole is widest level with the wheel centre.
        var heights = [top, bottom, (top + bottom) / 2]
        if top < 0 && bottom > 0 { heights.append(0) }
        var half = CGFloat.infinity
        for y in heights {
            guard let span = spans(atY: y).first(where: { $0.contains(column) }) else { return 0 }
            half = min(half, column - span.lowerBound, span.upperBound - column)
        }
        return max(0, half * 2)
    }
}

// MARK: - Typography

enum WandCardTypography {
    /// Ring titles share one size up to this; the few that cannot reach the
    /// shared size shrink on their own. Roomy pages reach it; crowded pages
    /// are limited by their cards instead. Ethan (2026-10-30) uses the wand
    /// lounging well back from the screen, so the cap is set by the cards'
    /// own room rather than by a desk-distance size (was 26 and 30).
    static let maximumRingSize: CGFloat = 30
    static let maximumCenterSize: CGFloat = 34
    /// Outer-layer cards are secondary but read from the same distance.
    static let maximumOuterSize: CGFloat = 28
    static let minimumOuterSize: CGFloat = 12
    static let minimumSize: CGFloat = 11
    static let step: CGFloat = 0.5
    static let lineHeight: CGFloat = 1.18
    static let maximumLines = 5
    /// A tilted block reads well as one to three short lines; a taller tilted
    /// block reads as a slanted paragraph, so it stays flat instead.
    static let maximumTiltedLines = 3
    static let labelSize: CGFloat = 11
    static let labelRow: CGFloat = labelSize * 1.3
    static let spacing: CGFloat = 4
    static let lockRow: CGFloat = 14
    /// SwiftUI draws the rounded face a little wider than AppKit measures it.
    static let measurementMargin: CGFloat = 1.05
    /// A label may shrink to this before it no longer fits.
    static let labelMinimumScale: CGFloat = 0.8
    /// How far under the median a title may fall before it no longer sets the shared size.
    static let outlierPoints: CGFloat = 3
    /// Spare width that still counts as a comfortable fit when centring.
    static let comfortableSlack: CGFloat = 6
    /// Text may tilt to follow its card (exactly along the card's axis or
    /// across it), but never past this, so it stays easy to read and never
    /// turns upside down or reads downward.
    static let maximumTilt: Double = 40 * .pi / 180
    /// Flat text is easier to read, so a card tilts only where that lets its
    /// title grow by both of these, and only if it is still at least
    /// `tiltGain` larger at the size finally drawn.
    static let tiltGain: CGFloat = 1.5
    static let tiltGainRatio: CGFloat = 1.1
    /// Each extra row makes a title slower to read and splits its phrase
    /// ("Switch | App · | Choose"), so a title uses more rows only where that
    /// makes it clearly larger, by both of these. At any one size the fewest
    /// rows that fit always win.
    static let extraRowGain: CGFloat = 2
    /// How much closer to the card's visual centre an extra row must bring a
    /// title, at the same size, to be worth it: about an eighth of a ring
    /// card's 190-point depth, so near-centred one-row titles stay one row.
    static let balancedPlacementGain: CGFloat = 24
    static let extraRowGainRatio: CGFloat = 1.15

    /// Whether reaching `more` points with extra rows beats `fewer` points
    /// with fewer rows.
    static func extraRowsEarnSpace(more: CGFloat, fewer: CGFloat?) -> Bool {
        guard let fewer else { return true }
        return more >= max(fewer + extraRowGain, fewer * extraRowGainRatio)
    }

    /// Whether a card whose tilted title can reach `tilted` points should
    /// tilt instead of reaching `flat` points level (nil: level text does not
    /// fit at all).
    static func tiltEarnsSpace(tilted: CGFloat, flat: CGFloat?) -> Bool {
        guard let flat else { return true }
        return tilted >= max(flat + tiltGain, flat * tiltGainRatio)
    }

    /// `.never` keeps every title flat, for comparison and tests.
    enum TiltPolicy: String { case never, whenLarger }

    static func titleFont(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    static func labelFont() -> NSFont { NSFont.monospacedSystemFont(ofSize: labelSize, weight: .medium) }

    /// A secondary line under a title (the wand home's "Double click to
    /// close"): smaller than titles but read from the same lounging distance.
    static let captionSize: CGFloat = 15
    static let captionRow: CGFloat = captionSize * 1.25

    static func captionFont() -> NSFont {
        let base = NSFont.systemFont(ofSize: captionSize, weight: .medium)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: captionSize) } ?? base
    }

    static func labelFont(_ style: WandCardText.LabelStyle) -> NSFont { style == .caption ? captionFont() : labelFont() }
    static func labelRow(_ style: WandCardText.LabelStyle) -> CGFloat { style == .caption ? captionRow : labelRow }

    static func width(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width * measurementMargin
    }

    /// Sizes from the largest down; binary search picks one.
    static func sizes(maximum: CGFloat, minimum: CGFloat = minimumSize) -> [CGFloat] {
        stride(from: maximum, through: minimum, by: -step).map { $0 }
    }

    /// The smallest tilted size that could earn a tilt over level text
    /// reaching `flat`, on the size grid.
    static func smallestWorthwhileTilt(flat: CGFloat?) -> CGFloat {
        guard let flat else { return minimumSize }
        let needed = max(flat + tiltGain, flat * tiltGainRatio)
        return max(minimumSize, (needed / step).rounded(.up) * step)
    }
}

// MARK: - One card's text

/// A card's title split into whole-word lines, each with its own position,
/// and the printed label underneath. Coordinates are relative to the wheel centre.
struct WandCardText: Equatable {
    struct Line: Equatable {
        let text: String
        let center: CGPoint
        /// Room the line was given; its measured text never exceeds it.
        let room: CGFloat
        let measured: CGFloat
    }

    let titleSize: CGFloat
    let lineHeight: CGFloat
    let lines: [Line]
    let label: Line
    let lock: CGPoint?
    /// Clockwise tilt in radians. Rows are laid out in a frame turned back by
    /// this much and drawn turned by it, about the wheel centre.
    var rotation: Double = 0
    /// The line under the title: a printed mouse label or a readable caption.
    enum LabelStyle: Hashable { case printed, caption }
    var labelStyle: LabelStyle = .printed

    /// A laid-out point as drawn, relative to the wheel centre.
    func drawn(_ point: CGPoint) -> CGPoint {
        guard rotation != 0 else { return point }
        let c = CGFloat(cos(rotation)), s = CGFloat(sin(rotation))
        return CGPoint(x: point.x * c - point.y * s, y: point.x * s + point.y * c)
    }

    /// Every row's corners as drawn, relative to the wheel centre.
    var drawnCorners: [[CGPoint]] {
        rows.map { row in
            [CGPoint(x: row.minX, y: row.minY), CGPoint(x: row.maxX, y: row.minY),
             CGPoint(x: row.maxX, y: row.maxY), CGPoint(x: row.minX, y: row.maxY)].map(drawn)
        }
    }

    /// Every row's measured box in the laid-out frame, relative to the wheel centre.
    var rows: [CGRect] {
        var boxes = lines.map {
            CGRect(x: $0.center.x - $0.measured / 2, y: $0.center.y - lineHeight / 2, width: $0.measured, height: lineHeight)
        }
        let row = WandCardTypography.labelRow(labelStyle)
        boxes.append(CGRect(x: label.center.x - label.measured / 2, y: label.center.y - row / 2,
                            width: label.measured, height: row))
        if let lock {
            boxes.append(CGRect(x: lock.x - 7, y: lock.y - WandCardTypography.lockRow / 2, width: 14, height: WandCardTypography.lockRow))
        }
        return boxes
    }

    var bounds: CGRect { rows.dropFirst().reduce(rows[0]) { $0.union($1) } }
}

/// Lays out one card's title and label inside its real shape.
final class WandCardTextLayout {
    let title: String
    let label: String
    let lock: Bool
    let room: WandCardRoom
    /// Candidate block centres, relative to the wheel centre.
    let anchors: [CGPoint]
    /// The tilt this layout is drawn at; `room` and `anchors` are already
    /// turned back by it.
    let rotation: Double
    /// Most title rows allowed; nil uses the shared flat and tilted limits.
    let maximumLines: Int?

    private let words: [String]
    /// Whether each word joins the one before it without a space (the second
    /// half of a slash compound such as Play/Pause).
    private let attached: [Bool]
    private let labelWidth: CGFloat
    let labelStyle: WandCardText.LabelStyle
    private var memo: [CGFloat: [Fitted]] = [:]

    /// The card's visual centre in the same frame as `anchors`. Ethan: "do a
    /// better job making text ... be a bit more centered in the wedges". Of
    /// the placements that fit comfortably, the one nearest this point wins.
    let center: CGPoint?

    init(title: String, label: String, lock: Bool, room: WandCardRoom, anchors: [CGPoint], rotation: Double = 0,
         center: CGPoint? = nil, maximumLines: Int? = nil, labelStyle: WandCardText.LabelStyle = .printed) {
        self.title = title
        self.label = label
        self.lock = lock
        self.room = room
        self.anchors = center.map { [$0] + anchors } ?? anchors
        self.rotation = rotation
        self.center = center
        self.maximumLines = maximumLines
        let tokens = Self.breakableTokens(title)
        words = tokens.map(\.text)
        attached = tokens.map(\.attached)
        self.labelStyle = labelStyle
        labelWidth = WandCardTypography.width(label, font: WandCardTypography.labelFont(labelStyle))
    }

    /// Wrapping points for a title: every space (see `breakableWords`), and
    /// also just after the slash of a slash compound whose halves are both
    /// words of two or more characters ("Play/" then "Pause"). The slash stays
    /// at the end of the first row, exactly as in "Copy /" then "Paste", so a
    /// long compound in a narrow wedge can use two large rows instead of one
    /// small one. Nothing is reworded or hyphenated.
    static func breakableTokens(_ title: String) -> [(text: String, attached: Bool)] {
        var tokens: [(text: String, attached: Bool)] = []
        for word in breakableWords(title) {
            var parts: [String] = []
            var rest = Substring(word)
            while let slash = rest.firstIndex(of: "/") {
                let head = rest[..<slash], tail = rest[rest.index(after: slash)...]
                guard head.count >= 2, tail.count >= 2, !tail.hasPrefix(" "), !head.hasSuffix(" "),
                      head.last?.isLetter == true, tail.first?.isLetter == true
                else { break }
                parts.append(String(head) + "/")
                rest = tail
            }
            parts.append(String(rest))
            for (index, part) in parts.enumerated() { tokens.append((part, index > 0)) }
        }
        return tokens
    }

    /// A lone separator (·, /, +) stays with the word before it, so no line
    /// ever starts with one ("YouTube ·" then "Hold 2× /"). A card's motion
    /// arrow (`ModeHUDGesture`) does too, so it never sits on a line alone.
    static func breakableWords(_ title: String) -> [String] {
        var words: [String] = []
        for token in title.split(separator: " ").map(String.init) {
            if let last = words.last, token.count == 1, "·/+&|-–—↕↓↑↔".contains(token) {
                words[words.count - 1] = last + " " + token
            } else {
                words.append(token)
            }
        }
        return words
    }

    private struct Measure {
        let words: [CGFloat]
        let space: CGFloat
    }

    private func measure(size: CGFloat) -> Measure {
        let font = WandCardTypography.titleFont(size: size)
        return Measure(words: words.map { WandCardTypography.width($0, font: font) },
                       space: WandCardTypography.width(" ", font: font))
    }

    /// The most rows this layout may use.
    var rowLimit: Int {
        maximumLines ?? (rotation == 0 ? WandCardTypography.maximumLines : WandCardTypography.maximumTiltedLines)
    }

    /// The best layout at `size` within `rows` (default: the row limit): the
    /// fewest rows that fit anywhere, then the anchor that leaves the most
    /// spare room on the tightest line, nearest the card's centre.
    func layout(size: CGFloat, rows: Int? = nil) -> WandCardText? {
        // Every anchor's own fewest-row placement is found once per size; a
        // row cap only limits which of them may be chosen.
        let fitted: [Fitted]
        if let known = memo[size] { fitted = known } else {
            fitted = search(size: size, rows: rowLimit)
            memo[size] = fitted
        }
        return choose(fitted.filter { $0.text.lines.count <= (rows ?? rowLimit) })
    }

    private struct Fitted {
        let text: WandCardText
        let slack: CGFloat
        let anchor: CGPoint
    }

    private func search(size: CGFloat, rows maximumLines: Int) -> [Fitted] {
        guard !words.isEmpty, maximumLines >= 1 else { return [] }
        let measured = measure(size: size)
        var fitted: [Fitted] = []
        for anchor in anchors {
            for count in 1...maximumLines {
                guard let candidate = fit(measured, size: size, anchor: anchor, lines: count) else { continue }
                fitted.append(Fitted(text: candidate.text, slack: candidate.slack, anchor: anchor))
                break
            }
        }
        return fitted
    }

    /// Fewer rows read faster, so the fewest rows that fit win, placed near
    /// the card's visual centre. A single row may become two only where it
    /// fits just far off centre and two rows bring the block clearly back
    /// (`balancedPlacementGain`): Codex's bottom-wedge "New chat" fits on one
    /// row only against the wide outer arc, but sits centred as "New | chat"
    /// at the same size. Taller stacks never grow for placement, since that
    /// splits a phrase ("⇧ | Hold | Shift") without a matching gain.
    private func choose(_ fitted: [Fitted]) -> WandCardText? {
        guard let fewest = fitted.map(\.text.lines.count).min(),
              let primary = pick(fitted.filter { $0.text.lines.count == fewest }) else { return nil }
        guard let center, fewest == 1,
              let balanced = pick(fitted.filter { $0.text.lines.count == 2 }) else { return primary.text }
        func distance(_ value: Fitted) -> CGFloat { hypot(value.anchor.x - center.x, value.anchor.y - center.y) }
        return distance(primary) - distance(balanced) >= WandCardTypography.balancedPlacementGain
            ? balanced.text : primary.text
    }

    private func pick(_ fitted: [Fitted]) -> Fitted? {
        guard let roomiest = fitted.max(by: { $0.slack < $1.slack }) else { return nil }
        guard let center else { return roomiest }
        // Comfortable placements (a few points spare, or as spare as any)
        // compete on how close the block sits to the card's visual centre.
        let comfortable = min(WandCardTypography.comfortableSlack, roomiest.slack)
        return fitted.filter { $0.slack >= comfortable }
            .min { hypot($0.anchor.x - center.x, $0.anchor.y - center.y) < hypot($1.anchor.x - center.x, $1.anchor.y - center.y) }
            ?? roomiest
    }

    private func fit(_ measured: Measure, size: CGFloat, anchor: CGPoint, lines count: Int)
        -> (text: WandCardText, slack: CGFloat)? {
        let lineHeight = size * WandCardTypography.lineHeight
        let lockHeight = lock ? WandCardTypography.lockRow + WandCardTypography.spacing : 0
        // The wand has no printed mouse label, so its rows use that space.
        let labelRow = WandCardTypography.labelRow(labelStyle)
        let labelHeight = label.isEmpty ? 0 : WandCardTypography.spacing + labelRow
        let height = lockHeight + CGFloat(count) * lineHeight + labelHeight
        var y = anchor.y - height / 2
        var lockCenter: CGPoint?
        if lock {
            guard room.width(column: anchor.x, top: y, bottom: y + WandCardTypography.lockRow) >= 16 else { return nil }
            lockCenter = CGPoint(x: anchor.x, y: y + WandCardTypography.lockRow / 2)
            y += lockHeight
        }
        var index = 0
        var lines: [WandCardText.Line] = []
        var slack = CGFloat.infinity
        for _ in 0..<count {
            guard index < words.count else { return nil }
            let available = room.width(column: anchor.x, top: y, bottom: y + lineHeight)
            guard measured.words[index] <= available else { return nil }
            let rowStart = index
            var widths = [measured.words[index]]
            index += 1
            while index < words.count {
                let added = (attached[index] ? 0 : measured.space) + measured.words[index]
                guard widths.reduce(0, +) + added <= available else { break }
                widths.append(added)
                index += 1
            }
            // A slash compound splits only when it starts its row (it is
            // wider than a row on its own); otherwise it moves down whole:
            // "Exit · Hold | for Pin/Unpin", never "… for Pin/ | Unpin".
            if index < words.count, attached[index] {
                var head = index
                while head > 0, attached[head] { head -= 1 }
                if head > rowStart {
                    widths.removeLast(index - head)
                    index = head
                }
            }
            let width = widths.reduce(0, +)
            let text = (rowStart..<index).map { ($0 > rowStart && !attached[$0] ? " " : "") + words[$0] }.joined()
            lines.append(.init(text: text, center: CGPoint(x: anchor.x, y: y + lineHeight / 2), room: available, measured: width))
            slack = min(slack, available - width)
            y += lineHeight
        }
        // Whole words only: every word is placed, and every row is used.
        guard index == words.count, lines.count == count else { return nil }
        if label.isEmpty {
            let none = WandCardText.Line(text: "", center: CGPoint(x: anchor.x, y: y - lineHeight / 2), room: 0, measured: 0)
            return (WandCardText(titleSize: size, lineHeight: lineHeight, lines: lines, label: none, lock: lockCenter,
                                 rotation: rotation), slack)
        }
        y += WandCardTypography.spacing
        let labelRoom = room.width(column: anchor.x, top: y, bottom: y + labelRow)
        // A caption is read, not glanced at: it never shrinks to fit.
        let labelScale = labelStyle == .caption ? 1 : WandCardTypography.labelMinimumScale
        guard labelWidth * labelScale <= labelRoom else { return nil }
        let label = WandCardText.Line(text: self.label, center: CGPoint(x: anchor.x, y: y + labelRow / 2),
                                      room: labelRoom, measured: min(labelWidth, labelRoom))
        return (WandCardText(titleSize: size, lineHeight: lineHeight, lines: lines, label: label, lock: lockCenter,
                             rotation: rotation, labelStyle: labelStyle), slack)
    }

    /// Largest size from `minimum` up to `maximum` at which the title fits
    /// anywhere in at most `rows` rows.
    func largestSize(maximum: CGFloat, minimum: CGFloat = WandCardTypography.minimumSize, rows: Int? = nil) -> CGFloat? {
        let sizes = WandCardTypography.sizes(maximum: maximum, minimum: minimum)
        guard !sizes.isEmpty else { return nil }
        var low = 0, high = sizes.count - 1
        guard layout(size: sizes[high], rows: rows) != nil else { return nil }
        // sizes descend: find the first index that fits.
        while low < high {
            let middle = (low + high) / 2
            if layout(size: sizes[middle], rows: rows) != nil { high = middle } else { low = middle + 1 }
        }
        // Wrapping is not strictly monotonic; never return a size that fails.
        var index = low
        while index < sizes.count, layout(size: sizes[index], rows: rows) == nil { index += 1 }
        return index < sizes.count ? sizes[index] : nil
    }

    /// The size a title should reach: the largest it fits at with the fewest
    /// rows whose size more rows cannot clearly beat
    /// (`extraRowsEarnSpace`), so "VS Code mode" keeps two rows rather than
    /// splitting into three for a point or two.
    func readableSize(maximum: CGFloat, minimum: CGFloat = WandCardTypography.minimumSize) -> CGFloat? {
        guard let overall = largestSize(maximum: maximum, minimum: minimum),
              let used = layout(size: overall)?.lines.count, used > 1 else {
            return largestSize(maximum: maximum, minimum: minimum)
        }
        // Sizes that extra rows could not clearly beat start here.
        let threshold = min(overall / WandCardTypography.extraRowGainRatio, overall - WandCardTypography.extraRowGain)
        let floor = max(minimum, (threshold / WandCardTypography.step).rounded(.down) * WandCardTypography.step)
        for rows in 1..<used {
            guard let size = largestSize(maximum: overall, minimum: min(overall, floor), rows: rows) else { continue }
            if !WandCardTypography.extraRowsEarnSpace(more: overall, fewer: size) { return size }
        }
        return overall
    }
}

// MARK: - The wheel's plan

/// Where every card's text goes and how large it is, for one wheel. Built
/// once per page and title set, then reused while the outline moves, so
/// focus updates never repeat text measurement.
///
/// Ring titles share one size so the wheel reads as one even set. The shared
/// size is what three quarters of the titles can reach, not the smallest, so
/// a few long titles never shrink every other card; titles that cannot reach
/// it shrink on their own. Every title keeps whole words.
struct WandWheelPlan: Equatable {
    struct Card: Equatable {
        let text: WandCardText?
        let titleSize: CGFloat
    }

    let center: Card?
    let ring: [Card]
    let sharedSize: CGFloat
    /// One per `layout.outer` card, in the same order.
    var outer: [Card] = []

    /// The planned title drawn in `slot`, if any.
    func text(for slot: WandWheelGeometry.Slot) -> WandCardText? {
        switch slot {
        case .center: return center?.text
        case .ring(let index): return index < ring.count ? ring[index].text : nil
        case .outer(let index): return index < outer.count ? outer[index].text : nil
        }
    }

    private static var cache: [String: WandWheelPlan] = [:]

    struct Entry: Hashable {
        let title: String
        let label: String
        var labelStyle: WandCardText.LabelStyle = .printed
        /// The wand can adjust this card, so an outer band leaves arrow room.
        var reservesArrows = false
    }

    static func plan(
        for geometry: WandWheelGeometry,
        cards: [PhysicalCell: Entry],
        locked: PhysicalCell? = nil,
        tilt policy: WandCardTypography.TiltPolicy = .whenLarger
    ) -> WandWheelPlan {
        let layout = geometry.layout
        let key = layout.cells.map { cell -> String in
            let entry = cards[cell]
            return "\(cell.rawValue)\u{1F}\(entry?.title ?? "")\u{1F}\(entry?.label ?? "")\u{1F}\(entry?.labelStyle == .caption)\u{1F}\(entry?.reservesArrows == true)\u{1F}\(cell == locked)"
        }.joined(separator: "\u{1E}") + "#\(layout.center?.rawValue ?? 0)#\(layout.ring.count)#\(policy.rawValue)"
            + "#" + layout.outer.map { "\($0.cell.rawValue)>\($0.parent.rawValue)\($0.height == .large ? "L" : "T")\($0.layer)" }
            .joined(separator: ",")
        if let cached = cache[key] { return cached }

        var center: Card?
        if let cell = layout.center, let entry = cards[cell] {
            let text = WandCardTextLayout(title: entry.title, label: entry.label, lock: cell == locked,
                                          room: WandCardRoom(shape: .disc(radius: WandWheelMetrics.centerRadius)),
                                          anchors: [.zero, CGPoint(x: 0, y: -6), CGPoint(x: 0, y: 6)], center: .zero,
                                          labelStyle: entry.labelStyle)
            let size = text.readableSize(maximum: WandCardTypography.maximumCenterSize) ?? WandCardTypography.minimumSize
            center = Card(text: text.layout(size: size), titleSize: size)
        }

        // Flat text first. A card tilts only where that makes its title
        // clearly larger, so the wheel stays mostly level and easy to read.
        let flats: [WandCardTextLayout?] = layout.ring.indices.map { index in
            guard let entry = cards[layout.ring[index]] else { return nil }
            return WandCardTextLayout(title: entry.title, label: entry.label, lock: layout.ring[index] == locked,
                                      room: WandCardRoom(shape: .wedge(geometry.wedge(at: index))),
                                      anchors: geometry.textAnchors(at: index),
                                      center: geometry.textCenter(for: geometry.wedge(at: index)))
        }
        let tilted: [[WandCardTextLayout]] = layout.ring.indices.map { index in
            guard policy == .whenLarger, let entry = cards[layout.ring[index]] else { return [] }
            return geometry.textTilts(at: index).map { tilt in
                let local = geometry.wedge(at: index, angle: layout.angle(at: index) - tilt)
                return WandCardTextLayout(title: entry.title, label: entry.label, lock: layout.ring[index] == locked,
                                          room: WandCardRoom(shape: .wedge(local)),
                                          anchors: geometry.textAnchors(for: local), rotation: tilt,
                                          center: geometry.textCenter(for: local))
            }
        }
        let maximum = WandCardTypography.maximumRingSize
        let flatBest = flats.map { $0?.readableSize(maximum: maximum) }
        let tiltBest: [CGFloat?] = layout.ring.indices.map { index in
            // Search only sizes that could earn a tilt; a card already as
            // large as allowed has none.
            let floor = WandCardTypography.smallestWorthwhileTilt(flat: flatBest[index])
            guard floor <= maximum else { return nil }
            return tilted[index].compactMap { $0.readableSize(maximum: maximum, minimum: floor) }.max()
        }
        let best: [CGFloat?] = layout.ring.indices.map { index in
            guard let tilt = tiltBest[index], WandCardTypography.tiltEarnsSpace(tilted: tilt, flat: flatBest[index])
            else { return flatBest[index] }
            return tilt
        }
        // A title far below the rest (more than 3 pt under the median) is an
        // outlier: it shrinks on its own and never pulls the shared size down.
        func sharedSize(_ sizes: [CGFloat?]) -> CGFloat {
            let reached = sizes.compactMap { $0 }.sorted()
            let median = reached.isEmpty ? maximum : reached[reached.count / 2]
            let pool = reached.filter { $0 >= median - WandCardTypography.outlierPoints }
            return pool.isEmpty ? maximum : pool[pool.count / 4]
        }
        // A tilt that lifts an outlier just into that pool would otherwise
        // lower the quartile for every level neighbour (Finder home: 30 → 27.5
        // pt for nine cards); tilting never shrinks the rest of the wheel.
        let shared = max(sharedSize(best), sharedSize(flatBest))
        let ring: [Card] = layout.ring.indices.map { index in
            guard let flat = flats[index] else { return Card(text: nil, titleSize: shared) }
            let size = min(shared, best[index] ?? WandCardTypography.minimumSize)
            // Check the gain again at the size actually drawn: a card the
            // shared size holds back may gain too little to be worth tilting.
            let flatSize = flatBest[index].map { min(size, $0) }
            var choices: [() -> WandCardText?] = []
            if best[index] != flatBest[index], size - (flatSize ?? 0) >= WandCardTypography.tiltGain {
                // Gentlest tilt first.
                choices += tilted[index].map { layout in { layout.layout(size: size) } }
            }
            if let flatSize { choices.append { flat.layout(size: flatSize) } }
            choices.append { flat.layout(size: WandCardTypography.minimumSize) }
            let text = choices.lazy.compactMap { $0() }.first
            return Card(text: text, titleSize: text?.titleSize ?? size)
        }
        var plan = WandWheelPlan(center: center, ring: ring, sharedSize: shared)
        plan.outer = WandOuterCardText.plan(for: geometry, titles: layout.outer.map { cards[$0.cell]?.title },
                                            reservesArrows: layout.outer.map { cards[$0.cell]?.reservesArrows == true }, tilt: policy)
        if cache.count > 48 { cache.removeAll() }
        cache[key] = plan
        return plan
    }
}

/// An outer-layer card's title, fitted by the same room-based rules as the
/// ring: whole words (and slash breaks) inside the band's real shape, with
/// the row economy, as large as it allows. Each band offers level text, text
/// along the band and text across it; the gentlest reading wins unless a
/// steeper one earns the same clear gain a ring card needs to tilt. Bands
/// are thin, so a reading may be steeper than a ring card's limit (any
/// upright angle), which is why it must earn its place. Outer cards are
/// wand-only, so they carry no printed mouse label.
enum WandOuterCardText {
    static var maximumSize: CGFloat { WandCardTypography.maximumOuterSize }
    static var minimumSize: CGFloat { WandCardTypography.minimumOuterSize }

    /// Every reading of one band (level first, then gentlest tilt first) and
    /// the size each reaches.
    struct Candidates {
        let readings: [WandCardTextLayout]
        let reach: [CGFloat?]

        var flat: WandCardTextLayout { readings[0] }
        var flatBest: CGFloat? { reach[0] }

        /// The chosen reading and the size it reaches.
        var best: (size: CGFloat, reading: Int)? {
            var chosen: (size: CGFloat, reading: Int)? = flatBest.map { ($0, 0) }
            for index in readings.indices.dropFirst() {
                guard let size = reach[index] else { continue }
                if WandCardTypography.tiltEarnsSpace(tilted: size, flat: chosen?.size) { chosen = (size, index) }
            }
            return chosen
        }

        /// The layout at `size` in `reading`, falling back to the others.
        func text(size: CGFloat, reading: Int) -> WandCardText? {
            let order = [reading] + readings.indices.filter { $0 != reading }
            for index in order { if let text = readings[index].layout(size: size) { return text } }
            for index in order { if let text = readings[index].layout(size: WandOuterCardText.minimumSize) { return text } }
            return nil
        }
    }

    static func candidates(title: String, wedge: WandWedge, lines maximumLines: Int, reservesArrows: Bool = false,
                           tilt policy: WandCardTypography.TiltPolicy = .whenLarger) -> Candidates {
        let side = WandCardRoom.outerSideMargin + (reservesArrows ? WandCardRoom.outerArrowRoom : 0)
        func room(_ wedge: WandWedge) -> WandCardRoom {
            WandCardRoom(shape: .wedge(wedge), sideMargin: side, endMargin: WandCardRoom.outerEndMargin)
        }
        var readings = [WandCardTextLayout(title: title, label: "", lock: false, room: room(wedge),
                                           anchors: WandWheelGeometry.outerTextAnchors(for: wedge),
                                           center: WandWheelGeometry.bandMiddle(of: wedge), maximumLines: maximumLines)]
        if policy == .whenLarger {
            var tilts: [Double] = []
            for value in [WandWheelGeometry.upright(wedge.centerAngle), WandWheelGeometry.upright(wedge.centerAngle - .pi / 2)]
            where abs(value) > 0.02 && !tilts.contains(where: { abs($0 - value) < 0.02 }) {
                tilts.append(value)
            }
            for rotation in tilts.sorted(by: { abs($0) < abs($1) }) {
                // Laid out turned back by `rotation`.
                var local = wedge
                local.centerAngle = wedge.centerAngle - rotation
                readings.append(WandCardTextLayout(title: title, label: "", lock: false, room: room(local),
                                                   anchors: WandWheelGeometry.outerTextAnchors(for: local), rotation: rotation,
                                                   center: WandWheelGeometry.bandMiddle(of: local), maximumLines: maximumLines))
            }
        }
        let reach = readings.map { $0.readableSize(maximum: maximumSize, minimum: minimumSize) }
        return Candidates(readings: readings, reach: reach)
    }

    /// One card on its own, at the largest size its band allows.
    static func layout(title: String, wedge: WandWedge, lines maximumLines: Int) -> WandCardText? {
        let options = candidates(title: title, wedge: wedge, lines: maximumLines)
        guard let best = options.best else { return options.text(size: minimumSize, reading: 0) }
        return options.text(size: best.size, reading: best.reading)
    }

    /// Every outer card of a wheel. Siblings sharing one parent wedge and
    /// layer share one size, so a pair such as Review changes / Stage files
    /// reads as a set.
    static func plan(for geometry: WandWheelGeometry, titles: [String?], reservesArrows: [Bool] = [],
                     tilt policy: WandCardTypography.TiltPolicy = .whenLarger) -> [WandWheelPlan.Card] {
        let layout = geometry.layout
        let options: [Candidates?] = layout.outer.indices.map { index in
            guard index < titles.count, let title = titles[index], !title.isEmpty else { return nil }
            return candidates(title: title, wedge: geometry.outerWedge(at: index),
                              lines: layout.outer[index].height == .large ? 2 : 1,
                              reservesArrows: index < reservesArrows.count && reservesArrows[index], tilt: policy)
        }
        return layout.outer.indices.map { index in
            guard let own = options[index] else { return WandWheelPlan.Card(text: nil, titleSize: minimumSize) }
            let siblings = layout.outer.indices.filter {
                layout.outer[$0].parent == layout.outer[index].parent && layout.outer[$0].layer == layout.outer[index].layer
            }
            let shared = siblings.compactMap { options[$0]?.best?.size }.min() ?? minimumSize
            let best = own.best
            let size = min(shared, best?.size ?? minimumSize)
            // Re-check at the shared size, as the ring does: a steeper
            // reading gains nothing where a gentler one reaches this size.
            let reading = own.readings.indices.first { own.reach[$0].map { $0 >= size - 1e-9 } ?? false } ?? best?.reading ?? 0
            let text = own.text(size: size, reading: reading)
            return WandWheelPlan.Card(text: text, titleSize: text?.titleSize ?? size)
        }
    }
}

extension WandWheelGeometry {
    /// The middle of a band, where a short outer title looks centred.
    static func bandMiddle(of wedge: WandWedge) -> CGPoint {
        let direction = WandWedge.radial(wedge.centerAngle)
        let radius = (wedge.inner + wedge.outer) / 2
        return CGPoint(x: direction.x * radius, y: direction.y * radius)
    }

    /// Candidate centres across a thin band: its middle, a little in and out,
    /// and a little either way along it.
    static func outerTextAnchors(for wedge: WandWedge) -> [CGPoint] {
        let direction = WandWedge.radial(wedge.centerAngle)
        let tangent = WandWedge.tangent(wedge.centerAngle)
        let thickness = wedge.outer - wedge.inner
        var anchors: [CGPoint] = []
        for fraction in [0.5, 0.42, 0.58] as [CGFloat] {
            let radius = wedge.inner + thickness * fraction
            let reach = radius * CGFloat(sin(min(wedge.halfWidth, .pi / 2))) * 0.25
            for shift in [0, -0.5, 0.5] as [CGFloat] {
                anchors.append(CGPoint(x: direction.x * radius + tangent.x * reach * shift,
                                       y: direction.y * radius + tangent.y * reach * shift))
            }
        }
        return anchors
    }

    /// Candidate text-block centres along a ring card, relative to the wheel
    /// centre: along its centre line from the inner to the outer part, and a
    /// little either side of it for tilted cards.
    func textAnchors(at index: Int) -> [CGPoint] {
        textAnchors(for: wedge(at: index))
    }

    /// The wedge's area centroid, where a block of text looks centred.
    func textCenter(for wedge: WandWedge) -> CGPoint {
        let r = Double(wedge.inner), big = Double(wedge.outer), half = wedge.halfWidth
        let sinc = half > 1e-6 ? sin(half) / half : 1
        let radius = (2.0 / 3.0) * (big * big * big - r * r * r) / max(1e-6, big * big - r * r) * sinc
        let direction = WandWedge.radial(wedge.centerAngle)
        return CGPoint(x: direction.x * CGFloat(radius), y: direction.y * CGFloat(radius))
    }

    func textAnchors(for wedge: WandWedge) -> [CGPoint] {
        let direction = WandWedge.radial(wedge.centerAngle)
        let tangent = WandWedge.tangent(wedge.centerAngle)
        let thickness = wedge.outer - wedge.inner
        var anchors: [CGPoint] = []
        for fraction in stride(from: CGFloat(0.3), through: 0.8, by: 0.1) {
            let radius = wedge.inner + thickness * fraction
            let reach = radius * CGFloat(sin(min(wedge.halfWidth, .pi / 2))) * 0.5
            for shift in [0, -0.3, 0.3] as [CGFloat] {
                anchors.append(CGPoint(x: direction.x * radius + tangent.x * reach * shift,
                                       y: direction.y * radius + tangent.y * reach * shift))
            }
        }
        return anchors
    }

    /// Tilts worth trying for a ring card, gentlest first: exactly along the
    /// card's axis or exactly across it, whichever of those reads upright
    /// within `maximumTilt`. A partial tilt that follows neither would look
    /// random beside its neighbours, so it is never offered. Cards at 12, 3,
    /// 6 and 9 o'clock are already aligned with flat text.
    func textTilts(at index: Int) -> [Double] {
        let theta = layout.angle(at: index)
        let limit = WandCardTypography.maximumTilt + 1e-9
        var tilts: [Double] = []
        for aligned in [Self.upright(theta), Self.upright(theta - .pi / 2)]
        where abs(aligned) > 0.02 && abs(aligned) <= limit && !tilts.contains(where: { abs($0 - aligned) < 0.02 }) {
            tilts.append(aligned)
        }
        return tilts.sorted { abs($0) < abs($1) }
    }

    /// The same line direction, turned to read left to right: (−90°, 90°].
    static func upright(_ value: Double) -> Double {
        var v = value.truncatingRemainder(dividingBy: .pi)
        if v > .pi / 2 + 1e-9 { v -= .pi }
        if v <= -.pi / 2 + 1e-9 { v += .pi }
        return v
    }
}
