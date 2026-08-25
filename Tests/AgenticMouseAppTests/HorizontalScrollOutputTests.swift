@testable import AgenticMouseApp
import ScimitarKit
import XCTest

final class HorizontalScrollOutputTests: XCTestCase {
    func testNormalFastDefaultEmitsFourHorizontalLinesPerAcceptedRatchet() {
        let lines = AppConfiguration.InputConfiguration.defaultHorizontalScrollLinesPerRatchet

        XCTAssertEqual(lines, 4)
        XCTAssertEqual(
            ScrollWheelChordMonitor.horizontalWheelDelta(.up, linesPerRatchet: lines),
            -4
        )
        XCTAssertEqual(
            ScrollWheelChordMonitor.horizontalWheelDelta(.down, linesPerRatchet: lines),
            4
        )
    }

    func testCustomSensitivityPreservesAcceptedDirection() {
        XCTAssertEqual(
            ScrollWheelChordMonitor.horizontalWheelDelta(.up, linesPerRatchet: 9),
            -9
        )
        XCTAssertEqual(
            ScrollWheelChordMonitor.horizontalWheelDelta(.down, linesPerRatchet: 9),
            9
        )
    }

    func testOutputRejectsUnsanitizedMagnitude() {
        XCTAssertNil(ScrollWheelChordMonitor.horizontalWheelDelta(.up, linesPerRatchet: 0))
        XCTAssertNil(ScrollWheelChordMonitor.horizontalWheelDelta(.down, linesPerRatchet: 13))
    }
}
