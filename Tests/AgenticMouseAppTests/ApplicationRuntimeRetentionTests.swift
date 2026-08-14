import XCTest
@testable import AgenticMouseApp

final class ApplicationRuntimeRetentionTests: XCTestCase {
    func testRetainDisablesAutomaticTerminationExactlyOnce() {
        let controller = AutomaticTerminationControllerSpy()
        var retention = ApplicationRuntimeRetention()

        retention.retain(using: controller)
        retention.retain(using: controller)

        XCTAssertTrue(retention.isRetained)
        XCTAssertTrue(controller.automaticTerminationSupportEnabled)
        XCTAssertEqual(controller.events, [
            "automatic-termination-support=true",
            "disable=\(ApplicationRuntimeRetention.reason)",
        ])
        XCTAssertEqual(controller.reasons, [ApplicationRuntimeRetention.reason])
    }
}

private final class AutomaticTerminationControllerSpy: AutomaticTerminationControlling {
    var automaticTerminationSupportEnabled = false {
        didSet {
            events.append(
                "automatic-termination-support=\(automaticTerminationSupportEnabled)"
            )
        }
    }
    private(set) var events: [String] = []
    private(set) var reasons: [String] = []

    func disableAutomaticTermination(_ reason: String) {
        events.append("disable=\(reason)")
        reasons.append(reason)
    }
}
