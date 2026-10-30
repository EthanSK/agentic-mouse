import XCTest
@testable import ScimitarKit

final class WandGridEdgeTests: XCTestCase {
    private let rows = PhysicalCell.displayRowsTopToBottom(for: .wand)

    func testEveryCellClampsAcrossAllFourEdges() throws {
        for row in rows.indices {
            for column in rows[row].indices {
                for (dx, dy, dc, dr) in [(8.0, 0.0, 1, 0), (-8, 0, -1, 0),
                                          (0, 7, 0, 1), (0, -7, 0, -1)] {
                    var grid = try XCTUnwrap(WandGridNavigator(rows: rows, start: rows[row][column]))
                    let nextRow = min(2, max(0, row + dr))
                    let nextColumn = min(3, max(0, column + dc))
                    XCTAssertEqual(grid.apply(deltaX: dx, deltaY: dy), nextRow != row || nextColumn != column)
                    XCTAssertEqual(grid.focusedCell, rows[nextRow][nextColumn])
                    XCTAssertEqual(grid.pointerFocus.pullX, 0, accuracy: 0.001)
                    XCTAssertEqual(grid.pointerFocus.pullY, 0, accuracy: 0.001)
                }
            }
        }
    }

    func testCornerDiscardsOutwardTravelAndReversesWithoutHiddenOvershoot() throws {
        var grid = try XCTUnwrap(WandGridNavigator(rows: rows, start: rows[0][0]))
        grid.apply(deltaX: -800, deltaY: -700)
        XCTAssertEqual(grid.focusedCell, rows[0][0])
        XCTAssertEqual(grid.pointerFocus.pullX, 0)
        XCTAssertEqual(grid.pointerFocus.pullY, 0)
        grid.apply(deltaX: 8, deltaY: 7)
        XCTAssertEqual(grid.focusedCell, rows[1][1])
    }

    func testLongSweepStopsAtEdgeAndDoesNotQueueMovement() throws {
        var grid = try XCTUnwrap(WandGridNavigator(rows: rows, start: rows[1][0]))
        grid.apply(deltaX: 10000, deltaY: 0)
        XCTAssertEqual(grid.focusedCell, rows[1][3])
        for _ in 0..<20 { XCTAssertFalse(grid.apply(deltaX: 0, deltaY: 0)) }
        grid.apply(deltaX: -8, deltaY: 0)
        XCTAssertEqual(grid.focusedCell, rows[1][2])
    }

    func testSingleRowOrColumnIgnoresTheAbsentAxis() throws {
        var row = try XCTUnwrap(WandGridNavigator(rows: [rows[0]], start: rows[0][0]))
        row.apply(deltaX: -8, deltaY: 1000)
        XCTAssertEqual(row.focusedCell, rows[0][0])
        var column = try XCTUnwrap(WandGridNavigator(rows: rows.map { [$0[0]] }, start: rows[1][0]))
        column.apply(deltaX: 1000, deltaY: -7)
        XCTAssertEqual(column.focusedCell, rows[0][0])
    }
}
