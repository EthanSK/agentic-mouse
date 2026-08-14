@testable import ScimitarKit
import XCTest

final class AgenticMouseVersionTests: XCTestCase {
    func testDisplayStringIdentifiesReleaseAndExactBuild() {
        XCTAssertEqual(
            AgenticMouseVersion.displayString(
                marketingVersion: "1.4.0",
                buildVersion: "27"
            ),
            "v1.4.0 (27)"
        )
    }

    func testDisplayStringNeverInventsMissingVersionMetadata() {
        XCTAssertEqual(
            AgenticMouseVersion.displayString(marketingVersion: "1.4.0", buildVersion: nil),
            "v1.4.0"
        )
        XCTAssertEqual(
            AgenticMouseVersion.displayString(marketingVersion: nil, buildVersion: "27"),
            "build 27"
        )
        XCTAssertEqual(
            AgenticMouseVersion.displayString(marketingVersion: nil, buildVersion: nil),
            "development build"
        )
    }
}
