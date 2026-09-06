import XCTest
@testable import ScimitarKit

final class CodexPinWheelTests: XCTestCase {
    func testScreenshotCellAndPhysicalWheelDirectionsOnBothMice() {
        XCTAssertEqual(CodexMode.screenshotPinWheelCell.printedSide(on: .corsair), 3)
        XCTAssertEqual(CodexMode.screenshotPinWheelCell.printedSide(on: .razer), 1)
        XCTAssertEqual(WheelChordControl.appSpecificControl(for: .codex, cell: CodexMode.screenshotPinWheelCell), .codexPin)
        XCTAssertNil(CodexModeAction.action(for: CodexMode.screenshotPinWheelCell))
        XCTAssertEqual(WheelChordControl.codexPin.codexPinAction(for: .down), .pin)
        XCTAssertEqual(WheelChordControl.codexPin.codexPinAction(for: .up), .unpin)
    }

    func testWheelUseSuppressesScreenshotAndLatchesRepeatedRatchetsUntilRelease() {
        for source in MouseSource.allCases {
            let state = WheelChordStateMachine()
            state.setActive(.codexPin, for: source)
            XCTAssertEqual(state.release(.codexPin, for: source)?.didObserveWheelInput, false)
            state.setActive(.codexPin, for: source)
            guard case .consume(let step) = state.route(verticalDelta: -1, isContinuous: false) else {
                return XCTFail("First ratchet must dispatch")
            }
            XCTAssertEqual(step.control.codexPinAction(for: step.direction), .pin)
            guard case .consumeAfterFirstHoldAction = state.route(verticalDelta: -1, isContinuous: false) else {
                return XCTFail("Repeated ratchet must stay consumed")
            }
            XCTAssertEqual(state.release(.codexPin, for: source)?.didObserveWheelInput, true)
            XCTAssertEqual(state.route(verticalDelta: -1, isContinuous: false), .passThrough)
        }
    }

    func testAmbiguousAndPhasedWheelInputAlsoSuppressScreenshot() {
        let state = WheelChordStateMachine()
        state.setActive(.codexPin, for: .corsair)
        state.setActive(.codexPin, for: .razer)
        XCTAssertEqual(state.route(verticalDelta: 1, isContinuous: false), .consumeAmbiguous)
        XCTAssertEqual(state.release(.codexPin, for: .corsair)?.didObserveWheelInput, true)
        XCTAssertEqual(state.release(.codexPin, for: .razer)?.didObserveWheelInput, true)
        state.setActive(.codexPin, for: .razer)
        XCTAssertEqual(state.route(verticalDelta: 1, isContinuous: true, scrollPhase: 2), .passThrough)
        XCTAssertEqual(state.release(.codexPin, for: .razer)?.didObserveWheelInput, true)
    }
}
