import AppKit
import ScimitarKit
import SwiftUI
@testable import ScimitarUI
import XCTest

/// Ethan: each wedge's background "should still be as if it were on top of
/// the normal background that we just removed ... just for that wedge, it's
/// like masked". The backing covers exactly the drawn cards.
final class WandWheelBackingTests: XCTestCase {
    func testVectorMaskPreservesEveryContourAndClearGapAtDifferentSizes() throws {
        let g = geometry
        for fraction in [0.0, 0.3, 0.7, 1.0] {
            var silhouette = WandWheelSilhouette(geometry: g, includesCenter: true,
                                                  ringIndices: Array(layout.ring.indices))
            silhouette.liftValues = [Double](repeating: fraction, count: layout.ring.count + 1)
            let source = silhouette.path(in: CGRect(x: 0, y: 0, width: g.size, height: g.size)).cgPath
            for scale in [0.35, 0.43125, 0.5, 1.0] {
                let size = CGSize(width: g.size * scale, height: g.size * scale)
                let vector = try XCTUnwrap(WandWheelMask.vectorPath(of: source,
                    canvas: CGSize(width: g.size, height: g.size), size: size))
                for x in stride(from: 5.0, to: Double(g.size), by: 17) {
                    for y in stride(from: 5.0, to: Double(g.size), by: 19) {
                        XCTAssertEqual(source.contains(CGPoint(x: x, y: y)),
                            vector.contains(CGPoint(x: x * scale, y: (g.size - y) * scale)))
                    }
                }
            }
        }
    }

    func testGlassMaskHasAnIntermediatePoseAndCanReverse() {
        let g = geometry
        var card = WandWheelSilhouette(geometry: g, includesCenter: true, ringIndices: [])
        let rest = card.path(in: .zero).boundingRect
        card.lifted = .center
        let raised = card.path(in: .zero).boundingRect
        card.liftValues = [0.5]
        let half = card.path(in: .zero).boundingRect
        XCTAssertEqual(half.width, (rest.width + raised.width) / 2, accuracy: 0.001)
        XCTAssertGreaterThan(half.width, rest.width)
        XCTAssertLessThan(half.width, raised.width)
        var returning = WandGlassLiftValues(values: [0.5, 0.25])
        returning.scale(by: 0.5)
        XCTAssertEqual(returning.values, [0.25, 0.125])
        XCTAssertEqual((returning + .zero).values, returning.values)
        XCTAssertEqual((returning - returning).magnitudeSquared, 0)
    }
    private let layout = WandRadialLayout(center: .modeExit, ring: PhysicalCell.all.filter { $0 != .modeExit })
    private var geometry: WandWheelGeometry { WandWheelGeometry(layout: layout) }

    private func mask(ring: [Int]? = nil, center: Bool = true, scale: CGFloat = 1) throws -> NSBitmapImageRep {
        let size = CGSize(width: geometry.size, height: geometry.size)
        let silhouette = WandWheelSilhouette(geometry: geometry, includesCenter: center,
                                             ringIndices: ring ?? Array(layout.ring.indices))
        let path = silhouette.path(in: CGRect(origin: .zero, size: size)).cgPath
        let image = try XCTUnwrap(WandWheelMask.image(of: path, canvas: size, size: size, scale: scale))
        return NSBitmapImageRep(cgImage: image)
    }

    private func point(angle: Double, radius: CGFloat) -> CGPoint {
        let direction = WandWedge.radial(angle)
        return CGPoint(x: geometry.center.x + direction.x * radius, y: geometry.center.y + direction.y * radius)
    }

    private func alpha(_ bitmap: NSBitmapImageRep, _ point: CGPoint, scale: CGFloat = 1) -> CGFloat {
        bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.alphaComponent ?? -1
    }

    private var middle: CGFloat { (WandWheelMetrics.innerRadius + WandWheelMetrics.outerRadius) / 2 }

    func testMaskCoversEveryCardAndNothingBetweenThem() throws {
        let bitmap = try mask()
        for index in layout.ring.indices {
            XCTAssertGreaterThan(alpha(bitmap, point(angle: layout.angle(at: index), radius: middle)), 0.95, "card \(index)")
            let gutter = layout.angle(at: index) + layout.sectorWidth / 2
            XCTAssertLessThan(alpha(bitmap, point(angle: gutter, radius: middle)), 0.05, "gutter after \(index)")
        }
        XCTAssertGreaterThan(alpha(bitmap, geometry.center), 0.95, "centre card")
        let ringGap = (WandWheelMetrics.centerRadius + WandWheelMetrics.innerRadius) / 2
        XCTAssertLessThan(alpha(bitmap, point(angle: layout.angle(at: 0), radius: ringGap)), 0.05,
                          "the gap between the centre and the ring stays clear")
        XCTAssertLessThan(alpha(bitmap, CGPoint(x: 6, y: 6)), 0.05, "no square plate")
        XCTAssertLessThan(alpha(bitmap, point(angle: 0.3, radius: WandWheelMetrics.outerRadius + 8)), 0.05,
                          "no circular plate beyond the ring")
    }

    /// With an odd ring the wheel is not vertically symmetric: a card's
    /// vertical mirror lands exactly in a gutter. An upside-down mask would
    /// back the gutters and leave the cards bare.
    func testMaskIsTheRightWayUp() throws {
        XCTAssertEqual(layout.ring.count % 2, 1)
        let bitmap = try mask()
        let card = point(angle: layout.angle(at: 0), radius: middle)
        XCTAssertGreaterThan(alpha(bitmap, card), 0.95)
        XCTAssertLessThan(alpha(bitmap, CGPoint(x: card.x, y: geometry.size - card.y)), 0.05)
    }

    func testMaskFollowsOnlyTheDrawnCardsAtEveryScale() throws {
        let bitmap = try mask(ring: [0, 2], center: false, scale: 2)
        XCTAssertEqual(bitmap.pixelsWide, Int(geometry.size * 2))
        XCTAssertGreaterThan(alpha(bitmap, point(angle: layout.angle(at: 0), radius: middle), scale: 2), 0.95)
        XCTAssertLessThan(alpha(bitmap, point(angle: layout.angle(at: 1), radius: middle), scale: 2), 0.05,
                          "a card that is not drawn is not backed")
        XCTAssertLessThan(alpha(bitmap, geometry.center, scale: 2), 0.05)
    }
}

/// Ethan: "make the dotted outline ... like moving dynamics, like cool, like
/// a snake around it".
final class WandArmedOutlineStyleTests: XCTestCase {
    private let cell = PhysicalCell(rawValue: 4)!

    func testOnlyAnArmedWaitingCardMarches() {
        XCTAssertTrue(WandArmedOutlineStyle.marches(.init(cell: cell, isArmed: true), reduceMotion: false))
        XCTAssertFalse(WandArmedOutlineStyle.marches(.init(cell: cell), reduceMotion: false), "hover stays solid")
        XCTAssertFalse(WandArmedOutlineStyle.marches(.init(cell: cell, adjustment: ModeHUDWheelAdjustment()), reduceMotion: false),
                       "the adjustment ratchet keeps its own detent notches")
        XCTAssertFalse(WandArmedOutlineStyle.marches(.init(cell: cell, isArmed: true), reduceMotion: true))
    }

    func testDotsKeepTheirPatternAndTravelSteadily() {
        XCTAssertEqual(WandArmedOutlineStyle.dash, ModeHUDPointerFocusMetrics.armedDash)
        XCTAssertEqual(WandArmedOutlineStyle.dashPeriod, ModeHUDPointerFocusMetrics.armedDash.reduce(0, +))
        let period = WandArmedOutlineStyle.dashPeriod
        let cycle = Double(period / WandArmedOutlineStyle.speed)
        let start = Date(timeIntervalSinceReferenceDate: 1_000.13)
        for offset in stride(from: 0.0, through: 2.0, by: 0.07) {
            let phase = WandArmedOutlineStyle.dashPhase(at: start.addingTimeInterval(offset), reduceMotion: false)
            XCTAssertLessThanOrEqual(phase, 0)
            XCTAssertGreaterThan(phase, -period)
        }
        let a = WandArmedOutlineStyle.dashPhase(at: start, reduceMotion: false)
        XCTAssertEqual(WandArmedOutlineStyle.dashPhase(at: start.addingTimeInterval(cycle), reduceMotion: false), a, accuracy: 0.001)
        let b = WandArmedOutlineStyle.dashPhase(at: start.addingTimeInterval(0.05), reduceMotion: false)
        var travelled = (a - b).truncatingRemainder(dividingBy: period)
        if travelled < 0 { travelled += period }
        XCTAssertEqual(travelled, WandArmedOutlineStyle.speed * 0.05, accuracy: 0.001, "a falling phase moves the dots clockwise")
    }

    func testReduceMotionShowsTheSameDotsStandingStill() {
        for seconds in [0.0, 12.34, 99.9] {
            XCTAssertEqual(WandArmedOutlineStyle.dashPhase(at: Date(timeIntervalSinceReferenceDate: seconds), reduceMotion: true), 0)
        }
    }
}
