import Foundation

// MARK: - Layout

/// Ethan's weapon-wheel wand HUD: one card in the centre and every other card
/// spaced evenly around it, so every card is the same distance from the
/// centre. The HUD draws from this layout and the wand selects from it, so
/// what is drawn is exactly what is hit.
///
/// Angles are measured clockwise from 12 o'clock in screen space (x right,
/// y down). The ring keeps the page's legend order clockwise and ends at
/// 12 o'clock. With twelve ring cards, which is Default without VS Code, each
/// numbered card (Corsair 1 to 10) therefore sits at its own clock hour.
/// Other counts, including odd ones, are spaced evenly the same way.
public struct WandRadialLayout: Equatable, Sendable {
    public let center: PhysicalCell?
    public let ring: [PhysicalCell]
    /// Ethan's outer layer: quick actions one step further out on the same
    /// wedge as their parent ring card. The ring keeps its count and angles,
    /// so outer cards never move an inner card. Ordered by parent, then
    /// clockwise within that parent's sector.
    public let outer: [WandOuterCard]

    public init(center: PhysicalCell?, ring: [PhysicalCell], outer: [WandOuterCard] = []) {
        self.center = center
        var seen: Set<PhysicalCell> = center.map { [$0] } ?? []
        let ring = ring.filter { seen.insert($0).inserted }
        self.ring = ring
        // An outer card needs its parent on this ring and its own unique cell.
        let kept = outer.filter { ring.contains($0.parent) && seen.insert($0.cell).inserted }
        self.outer = kept.enumerated().sorted { a, b in
            let pa = ring.firstIndex(of: a.element.parent)!, pb = ring.firstIndex(of: b.element.parent)!
            return pa != pb ? pa < pb : a.offset < b.offset
        }.map(\.element)
    }

    public static let empty = WandRadialLayout(center: nil, ring: [])

    public var isEmpty: Bool { center == nil && ring.isEmpty }

    /// Centre first, then the ring clockwise, then the outer layer.
    public var cells: [PhysicalCell] { (center.map { [$0] } ?? []) + ring + outer.map(\.cell) }

    public func contains(_ cell: PhysicalCell) -> Bool {
        center == cell || ring.contains(cell) || outer.contains { $0.cell == cell }
    }

    // MARK: Outer layer

    public func outerIndex(of cell: PhysicalCell) -> Int? { outer.firstIndex { $0.cell == cell } }

    /// Indices into `outer` of the cards beyond ring card `ringIndex`,
    /// clockwise; `layer` limits them to one reach (1 or 2).
    public func outerIndices(ofRing ringIndex: Int, layer: Int? = nil) -> [Int] {
        guard ring.indices.contains(ringIndex) else { return [] }
        let parent = ring[ringIndex]
        return outer.indices.filter { outer[$0].parent == parent && (layer == nil || outer[$0].layer == layer) }
    }

    /// The parent sector's share a third-layer card spans. Its band reaches
    /// past the second layer, so it keeps to the sector's side nearer a
    /// diagonal, where the fixed square wheel frame has room for it.
    public static let thirdLayerSpan = 2.0 / 3.0

    /// The angular range outer cards of `layer` share beyond ring card `parent`.
    private func band(ofRing parent: Int, layer: Int) -> (start: Double, width: Double) {
        let start = angle(at: parent) - sectorWidth / 2
        guard layer > 1 else { return (start, sectorWidth) }
        let width = sectorWidth * Self.thirdLayerSpan
        // Distance of each sector edge from its nearest diagonal (45° + k·90°).
        func offDiagonal(_ edge: Double) -> Double {
            let quarter = Double.pi / 2
            let phase = (edge - .pi / 4).truncatingRemainder(dividingBy: quarter)
            let value = phase < 0 ? phase + quarter : phase
            return min(value, quarter - value)
        }
        let towardEnd = offDiagonal(start + sectorWidth) <= offDiagonal(start)
        return (towardEnd ? start + sectorWidth - width : start, width)
    }

    /// The ring index of an outer card's parent.
    public func parentRingIndex(ofOuter index: Int) -> Int? {
        guard outer.indices.contains(index) else { return nil }
        return ring.firstIndex(of: outer[index].parent)
    }

    /// An outer card shares its parent's sector with the siblings on its own
    /// layer, split evenly (a third-layer card keeps `thirdLayerSpan` of it).
    public func outerHalfWidth(at index: Int) -> Double {
        guard let parent = parentRingIndex(ofOuter: index) else { return sectorWidth / 2 }
        let layer = outer[index].layer
        return band(ofRing: parent, layer: layer).width / Double(max(1, outerIndices(ofRing: parent, layer: layer).count)) / 2
    }

    /// Centre angle of outer card `index`, radians clockwise from 12 o'clock.
    public func outerAngle(at index: Int) -> Double {
        guard let parent = parentRingIndex(ofOuter: index) else { return 0 }
        let layer = outer[index].layer
        let siblings = outerIndices(ofRing: parent, layer: layer)
        let position = siblings.firstIndex(of: index) ?? 0
        let half = outerHalfWidth(at: index)
        return band(ofRing: parent, layer: layer).start + half * Double(2 * position + 1)
    }

    public func ringIndex(of cell: PhysicalCell) -> Int? { ring.firstIndex(of: cell) }

    /// Angular width of one ring card, in radians.
    public var sectorWidth: Double { 2 * .pi / Double(max(1, ring.count)) }

    /// Centre angle of ring card `index`, in radians clockwise from
    /// 12 o'clock, normalised to (0, 2π].
    public func angle(at index: Int) -> Double {
        Double(index + 1) * sectorWidth
    }

    /// Screen-space unit vector from the centre toward ring card `index`.
    public func direction(at index: Int) -> (x: Double, y: Double) {
        let theta = angle(at: index)
        return (sin(theta), -cos(theta))
    }

    /// Ring card whose sector contains `theta` (radians, clockwise from up).
    public func nearestIndex(toAngle theta: Double) -> Int? {
        guard !ring.isEmpty, theta.isFinite else { return nil }
        let turns = (theta / sectorWidth - 1).rounded()
        let count = ring.count
        return ((Int(turns) % count) + count) % count
    }

    /// Clockwise angle of a screen-space vector, in radians in [0, 2π).
    public static func angle(x: Double, y: Double) -> Double {
        let theta = atan2(x, -y)
        return theta < 0 ? theta + 2 * .pi : theta
    }

    /// Signed shortest angular difference `a - b`, in (-π, π].
    public static func angularDifference(_ a: Double, _ b: Double) -> Double {
        var value = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
        if value <= -.pi { value += 2 * .pi }
        if value > .pi { value -= 2 * .pi }
        return value
    }
}

/// One wand-only quick action in Ethan's outer layer (2026-10-29): "per wedge
/// like a secondary, like quick version or related button if you just go out
/// one more layer but on the same wedge." Its parent is a semantic card, not
/// a ring position, so it stays with that card whatever the ring holds.
public struct WandOuterCard: Equatable, Sendable {
    /// Ethan: "we can actually have them be different heights depending on
    /// their utility". Height is radial thickness; width is the parent sector.
    public enum Height: Equatable, Sendable {
        case thin, large
    }

    public let cell: PhysicalCell
    public let parent: PhysicalCell
    public let height: Height
    /// 1: one reach beyond the ring. 2: one reach beyond the first layer on
    /// the same wedge (Ethan's "third layer wedge", 2026-10-30).
    public let layer: Int

    public init(cell: PhysicalCell, parent: PhysicalCell, height: Height, layer: Int = 1) {
        self.cell = cell
        self.parent = parent
        self.height = height
        self.layer = min(2, max(1, layer))
    }
}

/// The canonical outer-layer definitions. Only cards present in the page's
/// legend are drawn and selectable, so Review changes / Stage files appear
/// only while VS Code is frontmost (when the home legend carries them).
/// The physical mice have no outer layer.
public enum WandOuterLayer {
    public static let home: [WandOuterCard] = [
        // Ethan: "a very thin thing just outside of keys mode always".
        WandOuterCard(cell: .wandUndo, parent: .keysModeEntry, height: .thin),
        // Ethan (2026-10-30): "space should be on the second layer of enter,
        // not copy paste" (superseding "move space outside of copy paste").
        WandOuterCard(cell: .wandSpace, parent: PhysicalCell(rawValue: 7)!, height: .thin),
        // Fill the vacant second layer; Zoom keeps its existing third layer.
        WandOuterCard(cell: .wandBrightness, parent: .modePickerEntry, height: .thin),
        // Ethan: "maybe it should be a third layer wedge. Yeah, because that's
        // where zoom is normally" — Utility's Zoom. New Codex chat used to sit
        // in the layer between; it moved into the ring (2026-10-30), and Zoom
        // keeps its third-layer place, reach and band so muscle memory holds.
        WandOuterCard(cell: .wandZoom, parent: .modePickerEntry, height: .thin, layer: 2),
        // Ethan: "two wedges for outside of VS Code mode when we're in VS
        // Code ... the review and stage buttons ... bigger ones".
        WandOuterCard(cell: .wandReviewChanges, parent: .frontmostAppModeSelector, height: .large),
        WandOuterCard(cell: .wandReviewFiles, parent: .frontmostAppModeSelector, height: .large),
    ]

    /// Select all stays in its existing Utility slot. Reach outward for
    /// Backspace, then Copy; Keys keeps its separate ordinary Backspace key.
    public static let utility: [WandOuterCard] = [
        WandOuterCard(cell: .wandBackspace, parent: .selectAll, height: .thin),
        WandOuterCard(cell: .wandCopy, parent: .selectAll, height: .thin, layer: 2),
    ]

    /// The outer layer a wand page carries; only cards in its legend are drawn.
    public static func cards(page: ModePickerPage, isHome: Bool) -> [WandOuterCard] {
        if isHome { return home }
        return page == .modes ? utility : []
    }

    /// Cells that live only in the outer layer and never take a ring slot.
    public static let cells: Set<PhysicalCell> = Set((home + utility).map(\.cell))
}

public extension WandRadialLayout {
    /// The one definition of each wand page's wheel.
    ///
    /// * Home puts Switch App in the centre, so a tap with no movement still
    ///   switches app. Every other home card, including Play/Pause and the
    ///   VS Code review cards when present, goes around it in legend order.
    /// * Child pages put their own exit in the centre: on an app page that is
    ///   cell 2, otherwise cell 10. A wand exit returns to the parent page.
    ///   App pages also map cell 10 to the same exit, so that duplicate is
    ///   left out of the ring rather than taking a second slot.
    /// * Unassigned Spare cards stay on the physical mouse grids but are left
    ///   out of the wand ring, so every wand slot does something.
    /// * Home adds the outer layer (`WandOuterLayer.home`) for the cards its
    ///   legend carries. Outer cards never enter the ring, so the twelve home
    ///   ring cards keep their clock positions whatever app is frontmost.
    static func wandMenu(
        legend: [ModeHUDLegendItem],
        page: ModePickerPage,
        isHome: Bool,
        appTarget: AppSpecificTarget? = nil
    ) -> WandRadialLayout {
        let center: PhysicalCell = isHome ? .switchApp : WandSelectionController.startCell(for: page)
        let duplicateExits: Set<PhysicalCell> = !isHome && (page == .appSpecific || page == .chromeWebsites)
            ? [.modeExit]
            : []
        let outer = WandOuterLayer.cards(page: page, isHome: isHome).filter { card in legend.contains { $0.cell == card.cell } }
        return menu(legend: legend, center: center, omitting: duplicateExits, outer: outer,
                    order: WandRingOrder.order(page: page, isHome: isHome, appTarget: appTarget))
    }

    static func menu(
        legend: [ModeHUDLegendItem],
        center: PhysicalCell?,
        omitting omitted: Set<PhysicalCell> = [],
        outer: [WandOuterCard] = [],
        order: [PhysicalCell]? = nil
    ) -> WandRadialLayout {
        let centre = center.flatMap { cell in legend.contains { $0.cell == cell } ? cell : nil }
        var ring = legend
            .filter { $0.cell != centre && !omitted.contains($0.cell) && !$0.isUnassignedSpare
                && !WandOuterLayer.cells.contains($0.cell) }
            .map(\.cell)
        if let order {
            // The page's grouped order first; anything it does not name keeps
            // legend order after it, so a new card is never dropped.
            let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            ring = ring.enumerated().sorted { a, b in
                let ra = rank[a.element] ?? order.count + a.offset, rb = rank[b.element] ?? order.count + b.offset
                return ra < rb
            }.map(\.element)
        }
        return WandRadialLayout(center: centre, ring: ring, outer: outer)
    }

    /// Presentation fallback for a hand-built wand snapshot that carries no
    /// layout. The coordinator always supplies `wandMenu`; this only keeps a
    /// stray snapshot drawable. Home is recognised by its wand-only
    /// Play/Pause slot; anything else centres its universal exit.
    static func inferred(legend: [ModeHUDLegendItem]) -> WandRadialLayout {
        let isHome = legend.contains { $0.cell == .wandPlayPause }
        let outer = isHome ? WandOuterLayer.home.filter { card in legend.contains { $0.cell == card.cell } } : []
        return menu(legend: legend, center: isHome ? .switchApp : .modeExit, outer: outer,
                    order: isHome ? WandRingOrder.home : nil)
    }
}

/// Ethan's grouped wand wheels (2026-10-30): "back and forward should be next
/// to each other in the top level. And I think keys mode and utility mode
/// should be together, as well as app mode at the top ... do similar
/// arrangement in other submenus where it makes obvious sense"; and in Keys,
/// "up, down, left and right need to be near each other". This supersedes the
/// physical-grid order the wand wheel used to keep. Each list runs clockwise
/// from one sector past 12 o'clock, so its last card sits at 12. The physical
/// mice keep their own grids; this order is the wand wheel's only.
public enum WandRingOrder {
    private static func cells(_ raw: [Int]) -> [PhysicalCell] { raw.map { PhysicalCell(rawValue: $0)! } }

    /// Modes at the top (Keys, app, Utility), media on the right (Play/Pause
    /// immediately clockwise of Utility, then YouTube), navigation at the
    /// bottom right with Back left of Forward, and editing on the left
    /// (Enter, Copy / Paste, New Codex chat), then Close beside Keys.
    /// Ethan (2026-10-30): "screenshot removal then and put the new Codex chat
    /// thing there"; the wand's screenshot is its mouse button triple-click.
    public static let home: [PhysicalCell] = [.modePickerEntry, .wandPlayPause]
        + cells([6, 1, 5, 8, 7, 4]) + [.wandCodexNewChat] + cells([10, 9, 2])

    /// Arrow keys across the top in reading order (← ↑ ↓ →), then text
    /// editing (Backspace on the level 3 o'clock wedge, where its long word
    /// reads largest, then Space and Shift), shortcuts (Undo, Save), Keypad
    /// and Tracks.
    public static let keys: [PhysicalCell] = [
        KeysModeAction.arrowDown.cell, KeysModeAction.arrowRight.cell,
        KeysModeAction.pressBackspace.cell, KeysModeAction.insertSpace.cell, KeysModeAction.holdShift.cell,
        KeysModeAction.undo.cell, KeysModeAction.save.cell,
        .keypadModeSelector, .mediaTracksWheelControl,
        KeysModeAction.arrowLeft.cell, KeysModeAction.arrowUp.cell,
    ]

    /// Like home: Keys, Choose App Specific and Extra Utilities at the top;
    /// display values (Zoom, Brightness) then desktop and windows (Mission /
    /// Desktop, Spaces, Magnet), then the one-press utilities.
    public static let utility: [PhysicalCell] = [
        .extraUtilitiesSelector, .zoomWheelControl, .brightnessWheelControl,
        .systemOverviewWheelControl, .spacesWheelControl, .magnetWheelControl,
        .selectAll, PhysicalCell(rawValue: 7)!, PhysicalCell(rawValue: 8)!,
        .keysModeSelector, .appSpecificModeSelector,
    ]

    /// Codex: model settings together (Speed, Reasoning Effort), Pin and
    /// Enter, the chat cards together, then the voice pair.
    public static let codex: [PhysicalCell] = cells([1, 4, 3, 7, 5, 6, 9, 8, 11, 12])

    public static func order(page: ModePickerPage, isHome: Bool, appTarget: AppSpecificTarget?) -> [PhysicalCell]? {
        if isHome { return home }
        switch page {
        case .keys: return keys
        case .modes: return utility
        case .appSpecific where appTarget == .codex: return codex
        default: return nil
        }
    }
}

public extension ModeHUDLegendItem {
    /// Every legend builder labels an unassigned control exactly "Spare".
    var isUnassignedSpare: Bool {
        destinationModeAccent == nil && actionTitle == "Spare"
    }
}

// MARK: - Navigation

/// How the wand steers its weapon wheel.
///
/// Wand rotation moves a virtual stick. The centre card is held until the
/// stick travels `reachDegrees` from the centre; the ring card in that
/// direction is then chosen. A ring card is held until the stick comes back
/// within `centerReturnDegrees`, so the band in between absorbs tremor at the
/// centre boundary. Around the ring, the stick must pass a sector edge by
/// `angularHysteresis` of a sector (at most `maximumHysteresisDegrees`)
/// before the neighbour takes over, so tremor on an edge never flickers.
/// Ring cards change only while the stick is out at the reach radius,
/// where its angle is reliable. The stick saturates at `maximumDegrees`: an over-long sweep never winds
/// up, and a reversal acts at once.
///
/// Outer layer (Ethan: "you have to go up twice to get there ... you don't
/// want to break your muscle memory"): on a ring card that has outer cards,
/// the stick may travel on to `outerReachDegrees` to choose the outer card in
/// that direction, and comes back to the ring card below
/// `outerReturnDegrees`. Ring cards without outer cards keep the ring's
/// `maximumDegrees` saturation, so ordinary aiming is unchanged.
public struct WandRadialTuning: Equatable, Sendable {
    public var reachDegrees: Double
    public var centerReturnDegrees: Double
    public var maximumDegrees: Double
    /// Where a hold that starts on a ring card begins, between reach and
    /// maximum, so a small first movement neither drops to the centre nor
    /// needs to unwind saturation.
    public var restingDegrees: Double
    public var angularHysteresis: Double
    public var maximumHysteresisDegrees: Double
    public var outerReachDegrees: Double
    public var outerReturnDegrees: Double
    public var outerMaximumDegrees: Double
    public var outerRestingDegrees: Double
    /// The third layer, one more reach beyond a first-layer card, with the
    /// same return band below it.
    public var thirdReachDegrees: Double
    public var thirdReturnDegrees: Double
    public var thirdMaximumDegrees: Double
    public var thirdRestingDegrees: Double

    public init(
        // Ethan (2026-10-31): "The sensitivity on the HUD between switching
        // things needs to be higher ... it's kind of hard sometimes to get the
        // full range." Every radius is about three quarters of its former
        // value (7/4/11/9, 16/13/19/17, 24/21/27/25 degrees), so each reach
        // and the travel around the ring need a quarter less wand rotation.
        // Bands, saturation and hysteresis keep their proportions, so a
        // reversal at the edge still acts at once and nothing winds up.
        reachDegrees: Double = 5.5,
        centerReturnDegrees: Double = 3,
        maximumDegrees: Double = 8.5,
        restingDegrees: Double = 7,
        angularHysteresis: Double = 0.22,
        maximumHysteresisDegrees: Double = 9,
        outerReachDegrees: Double = 12,
        outerReturnDegrees: Double = 10,
        outerMaximumDegrees: Double = 14.5,
        outerRestingDegrees: Double = 13,
        thirdReachDegrees: Double = 18,
        thirdReturnDegrees: Double = 16,
        thirdMaximumDegrees: Double = 20.5,
        thirdRestingDegrees: Double = 19
    ) {
        self.reachDegrees = reachDegrees
        self.centerReturnDegrees = centerReturnDegrees
        self.maximumDegrees = maximumDegrees
        self.restingDegrees = restingDegrees
        self.angularHysteresis = angularHysteresis
        self.maximumHysteresisDegrees = maximumHysteresisDegrees
        self.outerReachDegrees = outerReachDegrees
        self.outerReturnDegrees = outerReturnDegrees
        self.outerMaximumDegrees = outerMaximumDegrees
        self.outerRestingDegrees = outerRestingDegrees
        self.thirdReachDegrees = thirdReachDegrees
        self.thirdReturnDegrees = thirdReturnDegrees
        self.thirdMaximumDegrees = thirdMaximumDegrees
        self.thirdRestingDegrees = thirdRestingDegrees
    }

    /// Bounded copy: radii stay ordered and positive, and the angular band
    /// can never swallow a whole sector.
    var sanitized: WandRadialTuning {
        func bounded(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        let reach = bounded(reachDegrees, 1...60, 5.5)
        let back = bounded(centerReturnDegrees, 0.25...(reach * 0.9), min(3, reach * 0.9))
        let maximum = bounded(maximumDegrees, (reach + 0.5)...120, max(8.5, reach + 0.5))
        let resting = bounded(restingDegrees, reach...maximum, (reach + maximum) / 2)
        // The outer band lies wholly beyond the ring's own saturation.
        let outerReach = bounded(outerReachDegrees, (maximum + 1)...180, max(12, maximum + 1))
        let outerBack = bounded(outerReturnDegrees, (maximum + 0.5)...(outerReach - 0.5), max(maximum + 0.5, outerReach - 3))
        let outerMaximum = bounded(outerMaximumDegrees, (outerReach + 0.5)...240, outerReach + 3)
        let outerResting = bounded(outerRestingDegrees, outerReach...outerMaximum, (outerReach + outerMaximum) / 2)
        // The third band lies wholly beyond the first layer's saturation.
        let thirdReach = bounded(thirdReachDegrees, (outerMaximum + 1)...200, max(18, outerMaximum + 1))
        let thirdBack = bounded(thirdReturnDegrees, (outerMaximum + 0.5)...(thirdReach - 0.5), max(outerMaximum + 0.5, thirdReach - 3))
        let thirdMaximum = bounded(thirdMaximumDegrees, (thirdReach + 0.5)...260, thirdReach + 3)
        let thirdResting = bounded(thirdRestingDegrees, thirdReach...thirdMaximum, (thirdReach + thirdMaximum) / 2)
        return WandRadialTuning(
            reachDegrees: reach,
            centerReturnDegrees: back,
            maximumDegrees: maximum,
            restingDegrees: resting,
            angularHysteresis: bounded(angularHysteresis, 0...0.45, 0.22),
            maximumHysteresisDegrees: bounded(maximumHysteresisDegrees, 0...30, 9),
            outerReachDegrees: outerReach,
            outerReturnDegrees: outerBack,
            outerMaximumDegrees: outerMaximum,
            outerRestingDegrees: outerResting,
            thirdReachDegrees: thirdReach,
            thirdReturnDegrees: thirdBack,
            thirdMaximumDegrees: thirdMaximum,
            thirdRestingDegrees: thirdResting
        )
    }
}

/// Pure weapon-wheel cursor over one `WandRadialLayout`.
public struct WandRadialNavigator: Equatable, Sendable {
    public let layout: WandRadialLayout
    public let tuning: WandRadialTuning
    /// Virtual stick, in degrees of wand rotation, screen axes.
    public private(set) var positionX: Double
    public private(set) var positionY: Double
    /// nil while the centre card is selected.
    public private(set) var ringIndex: Int?
    /// Index into `layout.outer` while an outer card beyond `ringIndex` is selected.
    public private(set) var outerIndex: Int?

    public init?(
        layout: WandRadialLayout,
        start: PhysicalCell,
        tuning: WandRadialTuning = .init()
    ) {
        guard !layout.isEmpty else { return nil }
        self.layout = layout
        self.tuning = tuning.sanitized
        if let outer = layout.outerIndex(of: start), let parent = layout.parentRingIndex(ofOuter: outer) {
            ringIndex = parent
            outerIndex = outer
        } else if let index = layout.ringIndex(of: start) {
            ringIndex = index
        } else if layout.center != nil {
            ringIndex = nil
        } else {
            ringIndex = 0
        }
        let resting = Self.restingPosition(ringIndex: ringIndex, outerIndex: outerIndex, layout: layout, tuning: self.tuning)
        positionX = resting.x
        positionY = resting.y
    }

    /// Where the stick rests for a card: the centre, or along the card's
    /// direction at `restingDegrees`.
    public static func restingPosition(
        of cell: PhysicalCell,
        in layout: WandRadialLayout,
        tuning: WandRadialTuning = .init()
    ) -> (x: Double, y: Double) {
        let outer = layout.outerIndex(of: cell)
        let ring = outer.flatMap { layout.parentRingIndex(ofOuter: $0) } ?? layout.ringIndex(of: cell)
        return restingPosition(ringIndex: ring, outerIndex: outer, layout: layout, tuning: tuning.sanitized)
    }

    private static func restingPosition(
        ringIndex: Int?,
        outerIndex: Int? = nil,
        layout: WandRadialLayout,
        tuning: WandRadialTuning
    ) -> (x: Double, y: Double) {
        if let outerIndex {
            let theta = layout.outerAngle(at: outerIndex)
            let resting = layout.outer[outerIndex].layer > 1 ? tuning.thirdRestingDegrees : tuning.outerRestingDegrees
            return (sin(theta) * resting, -cos(theta) * resting)
        }
        guard let ringIndex else { return (0, 0) }
        let direction = layout.direction(at: ringIndex)
        return (direction.x * tuning.restingDegrees, direction.y * tuning.restingDegrees)
    }

    public var focusedCell: PhysicalCell {
        if let outerIndex { return layout.outer[outerIndex].cell }
        if let ringIndex { return layout.ring[ringIndex] }
        return layout.center ?? layout.ring[0]
    }

    /// The current ring card has outer cards, so the stick may travel on.
    private var ringHasOuter: Bool {
        guard let ringIndex else { return false }
        return !layout.outerIndices(ofRing: ringIndex).isEmpty
    }

    /// The current ring card has a third layer beyond its first.
    private var ringHasThird: Bool {
        guard let ringIndex else { return false }
        return !layout.outerIndices(ofRing: ringIndex, layer: 2).isEmpty
    }

    private var saturation: Double {
        ringHasThird ? tuning.thirdMaximumDegrees : ringHasOuter ? tuning.outerMaximumDegrees : tuning.maximumDegrees
    }

    /// The widest band any card on this wheel allows.
    private var widestSaturation: Double {
        if layout.outer.contains(where: { $0.layer > 1 }) { return tuning.thirdMaximumDegrees }
        return layout.outer.isEmpty ? tuning.maximumDegrees : tuning.outerMaximumDegrees
    }

    private var radius: Double { (positionX * positionX + positionY * positionY).squareRoot() }

    private var hysteresisRadians: Double {
        min(tuning.angularHysteresis * layout.sectorWidth, tuning.maximumHysteresisDegrees * .pi / 180)
    }

    /// Applies one bias-corrected angular delta. Returns true only when the
    /// selected card changed.
    @discardableResult
    public mutating func apply(deltaX: Double, deltaY: Double) -> Bool {
        guard deltaX.isFinite, deltaY.isFinite else { return false }
        positionX += deltaX
        positionY += deltaY
        // The widest band first, so the reach this sample made is judged
        // before the card's own saturation pulls the stick back.
        saturate(to: widestSaturation)
        let previous = focusedCell
        resolve()
        // A ring card without an outer band keeps the ring's saturation, so
        // ordinary aiming is exactly as before and never strands the stick out.
        saturate(to: saturation)
        return previous != focusedCell
    }

    private mutating func saturate(to limit: Double) {
        let length = radius
        if length > limit {
            let scale = limit / length
            positionX *= scale
            positionY *= scale
        }
    }

    private mutating func resolve() {
        let length = radius
        let theta = WandRadialLayout.angle(x: positionX, y: positionY)
        guard let current = ringIndex else {
            // On the centre: only a deliberate reach picks a ring card.
            outerIndex = nil
            if length >= tuning.reachDegrees {
                ringIndex = layout.nearestIndex(toAngle: theta)
                resolveOuter(length: length, theta: theta)
            }
            return
        }
        if layout.center != nil, length < tuning.centerReturnDegrees {
            ringIndex = nil
            outerIndex = nil
            return
        }
        // Close to the centre the stick's angle swings wildly with tiny
        // motion, so only a stick out at the ring may change ring cards.
        guard length >= tuning.reachDegrees else {
            outerIndex = nil
            return
        }
        let offset = WandRadialLayout.angularDifference(theta, layout.angle(at: current))
        if abs(offset) > layout.sectorWidth / 2 + hysteresisRadians {
            ringIndex = layout.nearestIndex(toAngle: theta)
            outerIndex = nil
        }
        resolveOuter(length: length, theta: theta)
    }

    /// The outer band beyond the current ring card: a second deliberate reach
    /// outward chooses the sibling in that direction; coming back below the
    /// return radius drops to the ring card.
    private mutating func resolveOuter(length: Double, theta: Double) {
        guard let ringIndex else { outerIndex = nil; return }
        let first = layout.outerIndices(ofRing: ringIndex, layer: 1)
        let third = layout.outerIndices(ofRing: ringIndex, layer: 2)
        guard !first.isEmpty || !third.isEmpty else { outerIndex = nil; return }
        // On the third layer: below its return radius, back to the first.
        var leavingThird = false
        if let current = outerIndex, third.contains(current) {
            if length >= tuning.thirdReturnDegrees {
                outerIndex = third.count > 1 ? switchSibling(current, in: third, theta: theta) : current
                return
            }
            outerIndex = nil
            leavingThird = true
        }
        var firstLayer: Int?
        if let current = outerIndex, first.contains(current) {
            if length >= tuning.outerReturnDegrees {
                firstLayer = first.count > 1 ? switchSibling(current, in: first, theta: theta) : current
            }
        } else if length >= (leavingThird ? tuning.outerReturnDegrees : tuning.outerReachDegrees) {
            firstLayer = nearestOuter(first, theta: theta)
        }
        outerIndex = firstLayer
        // A further deliberate reach from the first layer chooses the third.
        if firstLayer != nil || first.isEmpty, !third.isEmpty, length >= tuning.thirdReachDegrees {
            outerIndex = nearestOuter(third, theta: theta)
        }
    }

    /// The sibling in the stick's direction, once it passes a hysteresis band.
    private func switchSibling(_ current: Int, in siblings: [Int], theta: Double) -> Int? {
        let half = layout.outerHalfWidth(at: current)
        let band = min(tuning.angularHysteresis * half * 2, tuning.maximumHysteresisDegrees * .pi / 180)
        let offset = WandRadialLayout.angularDifference(theta, layout.outerAngle(at: current))
        return abs(offset) > half + band ? nearestOuter(siblings, theta: theta) : current
    }

    private func nearestOuter(_ siblings: [Int], theta: Double) -> Int? {
        siblings.min { a, b in
            abs(WandRadialLayout.angularDifference(theta, layout.outerAngle(at: a)))
                < abs(WandRadialLayout.angularDifference(theta, layout.outerAngle(at: b)))
        }
    }

    /// Screen-space pull toward the card that would come next, length ≤ 1.
    ///
    /// On the centre it points where the stick points, growing toward the
    /// reach. On a ring card it combines travel toward a neighbour (along the
    /// ring, ±1 at the hysteresis edge) with travel back toward the centre
    /// (1 at the return radius). Just after any change it leans back toward
    /// the card that was left, exactly like the grid outline after a snap.
    public var pull: (x: Double, y: Double) {
        let length = radius
        guard let ringIndex else {
            let scale = 1 / tuning.reachDegrees
            return Self.clampedUnit(x: positionX * scale, y: positionY * scale)
        }
        if let outerIndex {
            // Along toward a sibling (or out of the parent sector), and back
            // toward the ring card at the outer return radius.
            let theta = layout.outerAngle(at: outerIndex)
            let direction = (x: sin(theta), y: -cos(theta))
            let tangent = (x: -direction.y, y: direction.x)
            let offset = WandRadialLayout.angularDifference(WandRadialLayout.angle(x: positionX, y: positionY), theta)
            let edge = layout.outerHalfWidth(at: outerIndex) + hysteresisRadians
            let along = max(-1, min(1, offset / max(edge, 0.0001)))
            let isThird = layout.outer[outerIndex].layer > 1
            let reach = isThird ? tuning.thirdReachDegrees : tuning.outerReachDegrees
            let back = isThird ? tuning.thirdReturnDegrees : tuning.outerReturnDegrees
            var inward = max(0, min(1, (reach - length) / (reach - back)))
            if !isThird, ringHasThird {
                // Past the first layer's saturation the outline leans out
                // toward the third card, so the third reach is visible.
                inward -= max(0, min(1, (length - tuning.outerMaximumDegrees)
                    / (tuning.thirdReachDegrees - tuning.outerMaximumDegrees)))
            }
            return Self.clampedUnit(
                x: tangent.x * along - direction.x * inward,
                y: tangent.y * along - direction.y * inward
            )
        }
        let direction = layout.direction(at: ringIndex)
        let tangent = (x: -direction.y, y: direction.x) // clockwise along the ring
        var along = 0.0
        if length > 0 {
            let theta = WandRadialLayout.angle(x: positionX, y: positionY)
            let offset = WandRadialLayout.angularDifference(theta, layout.angle(at: ringIndex))
            let edge = layout.sectorWidth / 2 + hysteresisRadians
            // Inside the band the ring cannot change, so travel toward a
            // neighbour fades out on the way in and is full at the reach.
            let band = max(0, min(1, (length - tuning.centerReturnDegrees)
                / (tuning.reachDegrees - tuning.centerReturnDegrees)))
            let confidence = band * band * (3 - 2 * band)
            along = layout.ring.count > 1 ? max(-1, min(1, offset / edge)) * confidence : 0
        }
        let span = tuning.reachDegrees - tuning.centerReturnDegrees
        var inward = layout.center == nil ? 0 : max(0, min(1, (tuning.reachDegrees - length) / span))
        if ringHasOuter {
            // Beyond the ring's ordinary saturation the outline leans out
            // toward the outer card, so the next reach is visible. With no
            // first-layer card (Utility, whose Zoom is a third-layer card),
            // that next reach is the third.
            let next = layout.outerIndices(ofRing: ringIndex, layer: 1).isEmpty
                ? tuning.thirdReachDegrees : tuning.outerReachDegrees
            inward -= max(0, min(1, (length - tuning.maximumDegrees) / (next - tuning.maximumDegrees)))
        }
        return Self.clampedUnit(
            x: tangent.x * along - direction.x * inward,
            y: tangent.y * along - direction.y * inward
        )
    }

    public var pointerFocus: ModeHUDPointerFocus {
        let value = pull
        return ModeHUDPointerFocus(cell: focusedCell, pullX: value.x, pullY: value.y)
    }

    private static func clampedUnit(x: Double, y: Double) -> (x: Double, y: Double) {
        let length = (x * x + y * y).squareRoot()
        guard length > 1 else { return (x, y) }
        return (x / length, y / length)
    }
}
