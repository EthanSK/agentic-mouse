@testable import AgenticMouseApp
import CoreGraphics
import XCTest

final class SyntheticKeyboardChordTests: XCTestCase {
    func testModifierAndKeyDescriptionsUsePhysicalEventTypes() {
        let descriptions: [SyntheticKeyboardChordPoster.Event] = [
            .modifier(keyCode: 59, flags: [.maskControl], at: 0),
            .key(keyCode: 124, flags: [.maskControl], isDown: true, at: 0.006),
            .key(keyCode: 124, flags: [.maskControl], isDown: false, at: 0.026),
            .modifier(keyCode: 59, flags: [], at: 0.032),
        ]

        XCTAssertEqual(descriptions.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        XCTAssertEqual(descriptions.map(\.keyCode), [59, 124, 124, 59])
        XCTAssertEqual(descriptions.map(\.timestampOffset), [0, 0.006, 0.026, 0.032])
    }

    @MainActor
    func testMissingEventSourceFailsBeforeSleepingOrPosting() {
        var sleeps: [TimeInterval] = []
        let poster = SyntheticKeyboardChordPoster(
            source: nil,
            sleeper: { sleeps.append($0) }
        )

        XCTAssertFalse(poster.post([
            .key(keyCode: 8, flags: [.maskCommand], isDown: true, at: 0),
        ]))
        XCTAssertTrue(sleeps.isEmpty)
    }
}
