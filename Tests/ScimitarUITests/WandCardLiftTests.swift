import AppKit
import ScimitarKit
import SwiftUI
@testable import ScimitarUI
import XCTest

/// Ethan: the outlined wedge should "zoom in a bit gradually" and "animate
/// to be higher", and card text needs an outline that suits its colour.
final class WandCardLiftTests: XCTestCase {
    /// Default home without VS Code: thirteen ring cards, the most crowded
    /// ordinary wheel.
    private let layout = WandRadialLayout(
        center: .switchApp,
        ring: PhysicalCell.all.filter { $0 != .switchApp } + [.wandPlayPause, .wandReviewChanges]
    )
    private var geometry: WandWheelGeometry { WandWheelGeometry(layout: layout) }

    private func lifted(_ index: Int) -> [CGPoint] {
        let pose = WandCardLift.pose(for: .ring(index), lifted: true, in: geometry)
        let transform = WandCardLift.transform(pose, size: geometry.size)
        return geometry.wedge(at: index).outline().map { point in
            let absolute = CGPoint(x: point.x + geometry.center.x, y: point.y + geometry.center.y).applying(transform)
            return CGPoint(x: absolute.x - geometry.center.x, y: absolute.y - geometry.center.y)
        }
    }

    func testRestingCardsDoNotMove() {
        for slot in [WandWheelGeometry.Slot.center, .ring(0), .ring(5)] {
            let pose = WandCardLift.pose(for: slot, lifted: false, in: geometry)
            XCTAssertEqual(pose.scale, 1)
            XCTAssertEqual(pose.offset, .zero)
            XCTAssertTrue(WandCardLift.transform(pose, size: geometry.size).isIdentity)
        }
    }

    func testALiftedRingCardRisesAndGrowsWithoutLeavingTheWheelOrTouchingItsNeighbours() {
        for index in layout.ring.indices {
            let wedge = geometry.wedge(at: index)
            let points = lifted(index)
            let radii = points.map { hypot($0.x, $0.y) }
            // The window includes the panel padding and nothing clips the
            // wheel, so the lifted outline and its glow must stay inside it.
            XCTAssertLessThan(radii.max()! + WandWheelMetrics.focusOutset + ModeHUDPointerFocusMetrics.lineWidth,
                              geometry.size / 2 + WandWheelMetrics.panelPadding - 8,
                              "card \(index) and its outline stay inside the panel")
            XCTAssertGreaterThan(radii.min()!, WandWheelMetrics.centerRadius * WandCardLift.scale + 8,
                                 "card \(index) stays clear of a lifted centre card")
            XCTAssertGreaterThan(radii.max()!, WandWheelMetrics.outerRadius, "it really rises")
            for point in points {
                let offset = WandRadialLayout.angularDifference(
                    WandRadialLayout.angle(x: Double(point.x), y: Double(point.y)), wedge.centerAngle)
                XCTAssertLessThan(abs(offset), wedge.halfWidth, "card \(index) never crosses into a neighbour's sector")
            }
        }
    }

    func testTheCentreOnlyGrowsAndTheOutlineRidesWithItsCard() {
        let centre = WandCardLift.pose(for: .center, lifted: true, in: geometry)
        XCTAssertEqual(centre.offset, .zero)
        XCTAssertEqual(centre.anchor, .center)
        XCTAssertLessThan(WandWheelMetrics.centerRadius * centre.scale, WandWheelMetrics.innerRadius)
        for index in layout.ring.indices {
            XCTAssertEqual(WandCardLift.pose(for: .ring(index), lifted: true, in: geometry, angle: layout.angle(at: index)),
                           WandCardLift.pose(for: .ring(index), lifted: true, in: geometry))
        }
    }

    func testTheTransformMatchesScaleAboutTheAnchorThenRise() {
        let pose = WandCardLift.pose(for: .ring(3), lifted: true, in: geometry)
        let anchor = CGPoint(x: pose.anchor.x * geometry.size, y: pose.anchor.y * geometry.size)
        let moved = anchor.applying(WandCardLift.transform(pose, size: geometry.size))
        XCTAssertEqual(moved.x, anchor.x + pose.offset.width, accuracy: 1e-9)
        XCTAssertEqual(moved.y, anchor.y + pose.offset.height, accuracy: 1e-9)
        XCTAssertEqual(hypot(pose.offset.width, pose.offset.height), WandCardLift.rise, accuracy: 1e-9)
    }

    /// The glass behind a lifted card follows it, so the card never slides
    /// off its own backing.
    func testTheMaskBacksTheLiftedPose() throws {
        let size = CGSize(width: geometry.size, height: geometry.size)
        func alpha(lifted: WandWheelGeometry.Slot?, at point: CGPoint) throws -> CGFloat {
            let silhouette = WandWheelSilhouette(geometry: geometry, includesCenter: true,
                                                 ringIndices: Array(layout.ring.indices), lifted: lifted)
            let image = try XCTUnwrap(WandWheelMask.image(of: silhouette.path(in: CGRect(origin: .zero, size: size)).cgPath,
                                                           canvas: size, size: size, scale: 1))
            return NSBitmapImageRep(cgImage: image).colorAt(x: Int(point.x), y: Int(point.y))?.alphaComponent ?? -1
        }
        let direction = WandWedge.radial(layout.angle(at: 2))
        let beyondRest = CGPoint(x: geometry.center.x + direction.x * (WandWheelMetrics.outerRadius + 4),
                                 y: geometry.center.y + direction.y * (WandWheelMetrics.outerRadius + 4))
        XCTAssertLessThan(try alpha(lifted: nil, at: beyondRest), 0.05)
        XCTAssertGreaterThan(try alpha(lifted: .ring(2), at: beyondRest), 0.95)
    }

    func testReduceMotionLiftsWithoutTravel() {
        XCTAssertNil(WandCardLift.animation(reduceMotion: true))
        XCTAssertNotNil(WandCardLift.animation(reduceMotion: false))
    }

    func testTheHaloContrastsWithItsText() {
        XCTAssertEqual(WandCardTextHalo.haloColor(foregroundIsDark: false), .black, "white card text gets a dark outline")
        XCTAssertEqual(WandCardTextHalo.haloColor(foregroundIsDark: true), .white, "selected review text is black")
    }
}
