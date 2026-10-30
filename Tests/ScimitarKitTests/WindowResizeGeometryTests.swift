import XCTest
@testable import ScimitarKit

final class WindowResizeGeometryTests: XCTestCase {
    let screen = CGRect(x: -1200, y: -800, width: 2000, height: 1400)
    let initial = CGRect(x: -1000, y: -500, width: 800, height: 600)

    func testBothAxesKeepFractionalPointerAnchorAndReverseExactly() throws {
        for fraction in [0.0, 0.1, 0.5, 0.9] {
            let pointer = CGPoint(x: initial.minX + initial.width * fraction,
                                  y: initial.minY + initial.height * fraction)
            let geometry = try XCTUnwrap(WindowResizeGeometry(frame: initial, pointer: pointer, bounds: screen))
            for axis in [WindowResizeAxis.width, .height] {
                let enlarged = try XCTUnwrap(geometry.frame(from: initial, axis: axis, delta: 24))
                if axis == .width {
                    XCTAssertEqual(enlarged.minX + enlarged.width * fraction, pointer.x, accuracy: 0.001)
                    XCTAssertEqual(enlarged.height, initial.height)
                    XCTAssertEqual(enlarged.minY, initial.minY)
                } else {
                    XCTAssertEqual(enlarged.minY + enlarged.height * fraction, pointer.y, accuracy: 0.001)
                    XCTAssertEqual(enlarged.width, initial.width)
                    XCTAssertEqual(enlarged.minX, initial.minX)
                }
                XCTAssertEqual(try XCTUnwrap(geometry.frame(from: enlarged, axis: axis, delta: -24)), initial)
            }
        }
    }

    func testScreenBoundsLimitGrowthWithoutLosingAnchor() throws {
        let geometry = try XCTUnwrap(WindowResizeGeometry(frame: initial, pointer: CGPoint(x: -920, y: -440), bounds: screen))
        for axis in [WindowResizeAxis.width, .height] {
            let grown = try XCTUnwrap(geometry.frame(from: initial, axis: axis, delta: 10000))
            XCTAssertGreaterThanOrEqual(grown.minX, screen.minX)
            XCTAssertLessThanOrEqual(grown.maxX, screen.maxX + 0.001)
            XCTAssertGreaterThanOrEqual(grown.minY, screen.minY)
            XCTAssertLessThanOrEqual(grown.maxY, screen.maxY + 0.001)
        }
    }

    func testAppClampedSizeStillUsesOriginalAnchor() throws {
        let geometry = try XCTUnwrap(WindowResizeGeometry(frame: initial, pointer: CGPoint(x: -800, y: -350), bounds: screen))
        let actual = CGRect(x: -1000, y: -500, width: 700, height: 600)
        let result = geometry.anchored(actual, axis: .width)
        XCTAssertEqual(result.minX, -975)
        XCTAssertEqual(result.minX + result.width * 0.25, -800)
    }

    func testRejectInvalidFramesAndPointerOutsideWindow() {
        XCTAssertNil(WindowResizeGeometry(frame: .zero, pointer: .zero, bounds: screen))
        XCTAssertNil(WindowResizeGeometry(frame: initial, pointer: CGPoint(x: 700, y: 500), bounds: screen))
    }
}
