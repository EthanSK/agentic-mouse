import ServiceManagement
@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testLeavesEnabledServiceAlone() {
        let service = RecordingLoginItemService(status: .enabled)
        let result = makeController(service).ensureRegistered(log: makeLog())

        XCTAssertEqual(result, "enabled")
        XCTAssertEqual(service.registerCount, 0)
    }

    func testRegistersMissingService() {
        let service = RecordingLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .enabled
        let result = makeController(service).ensureRegistered(log: makeLog())

        XCTAssertEqual(result, "enabled")
        XCTAssertEqual(service.registerCount, 1)
    }

    func testDoesNotRetryApprovalState() {
        let service = RecordingLoginItemService(status: .requiresApproval)
        let result = makeController(service).ensureRegistered(log: makeLog())

        XCTAssertEqual(result, "requires approval")
        XCTAssertEqual(service.registerCount, 0)
    }

    func testAttemptsRegistrationWhenInitialStatusIsNotFound() {
        let service = RecordingLoginItemService(status: .notFound)
        service.statusAfterRegister = .enabled
        let result = makeController(service).ensureRegistered(log: makeLog())

        XCTAssertEqual(result, "enabled")
        XCTAssertEqual(service.registerCount, 1)
    }

    private func makeController(_ service: RecordingLoginItemService) -> LaunchAtLoginController {
        LaunchAtLoginController(service: service)
    }

    private func makeLog() -> Log {
        Log(category: "launch-at-login-test", sink: RecordingLogSink())
    }
}

private final class RecordingLoginItemService: LoginItemServicing {
    var status: SMAppService.Status
    var statusAfterRegister: SMAppService.Status?
    var registerCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let statusAfterRegister {
            status = statusAfterRegister
        }
    }
}
