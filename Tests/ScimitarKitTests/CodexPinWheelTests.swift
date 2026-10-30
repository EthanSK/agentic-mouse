import XCTest
@testable import ScimitarKit

final class CodexPinWheelTests: XCTestCase {
    func testPinIsAModifierClickRatherThanAWheelControlOnBothMice() {
        XCTAssertEqual(CodexMode.pinToggleCell.printedSide(on: .corsair), 3)
        XCTAssertEqual(CodexMode.pinToggleCell.printedSide(on: .razer), 1)
        for source in MouseSource.allCases {
            XCTAssertEqual(CodexMode.pinModifierCell.printedSide(on: source), 2)
        }
        XCTAssertNil(WheelChordControl.appSpecificControl(for: .codex, cell: CodexMode.pinToggleCell))
        XCTAssertEqual(CodexModeAction.action(for: CodexMode.pinToggleCell), .togglePin)
        XCTAssertEqual(WheelChordControl.appSpecificControl(for: .claude, cell: ClaudeMode.pinToggleCell), .claudePin)
    }
}
