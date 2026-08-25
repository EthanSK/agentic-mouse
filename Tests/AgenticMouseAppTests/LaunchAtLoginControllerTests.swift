import ServiceManagement
@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testLeavesCurrentEnabledSupervisorAloneAndMigratesLegacyMainApp() {
        let supervisor = RecordingAppService(status: .enabled)
        let legacy = RecordingAppService(status: .enabled)
        let store = RecordingSupervisorStore(revision: "1.0.100-106-/Applications")

        let result = makeController(supervisor, legacy, store)
            .ensureRegistered(revision: store.registeredRevision!, log: makeLog())

        XCTAssertEqual(result, "enabled")
        XCTAssertEqual(supervisor.registerCount, 0)
        XCTAssertEqual(supervisor.unregisterCount, 0)
        XCTAssertEqual(legacy.unregisterCount, 1)
    }

    func testRegistersMissingSupervisorAndThenRemovesLegacyRoute() {
        let supervisor = RecordingAppService(status: .notRegistered)
        supervisor.statusAfterRegister = .enabled
        let legacy = RecordingAppService(status: .enabled)
        let store = RecordingSupervisorStore()

        let result = makeController(supervisor, legacy, store)
            .ensureRegistered(revision: "revision", log: makeLog())

        XCTAssertEqual(result, "enabled")
        XCTAssertEqual(supervisor.registerCount, 1)
        XCTAssertEqual(legacy.unregisterCount, 1)
        XCTAssertEqual(store.registeredRevision, "revision")
    }

    func testRefreshWaitsForOldHelperToBeReapedBeforeRegisteringNewRevision() async {
        let supervisor = RecordingAppService(status: .enabled)
        supervisor.statusAfterUnregister = .notRegistered
        supervisor.statusAfterRegister = .enabled
        let legacy = RecordingAppService(status: .notRegistered)
        let store = RecordingSupervisorStore(revision: "old")
        var statuses: [String] = []

        let controller = makeController(supervisor, legacy, store)
        let result = controller.ensureRegistered(
            revision: "new",
            log: makeLog(),
            onStatusChange: { statuses.append($0) }
        )

        XCTAssertEqual(result, "refreshing")
        XCTAssertEqual(supervisor.asyncUnregisterCount, 1)
        XCTAssertEqual(supervisor.registerCount, 0)

        supervisor.completeAsyncUnregister()
        for _ in 0..<10 where statuses.isEmpty { await Task.yield() }
        XCTAssertEqual(supervisor.registerCount, 1)
        XCTAssertEqual(store.registeredRevision, "new")
        XCTAssertEqual(statuses, ["enabled"])
    }

    func testApprovalStateDoesNotRemoveWorkingLegacyLoginRoute() {
        let supervisor = RecordingAppService(status: .requiresApproval)
        let legacy = RecordingAppService(status: .enabled)
        let result = makeController(supervisor, legacy, RecordingSupervisorStore())
            .ensureRegistered(revision: "revision", log: makeLog())

        XCTAssertEqual(result, "requires approval")
        XCTAssertEqual(supervisor.registerCount, 0)
        XCTAssertEqual(legacy.unregisterCount, 0)
    }

    func testIntentionalQuitWaitsUntilSupervisorProcessWasReaped() async {
        let supervisor = RecordingAppService(status: .enabled)
        let legacy = RecordingAppService(status: .enabled)
        let store = RecordingSupervisorStore(revision: "revision")
        let controller = makeController(supervisor, legacy, store)
        var result: Result<Void, Error>?

        controller.disableForIntentionalQuit(log: makeLog()) { result = $0 }

        XCTAssertNil(result)
        XCTAssertEqual(supervisor.asyncUnregisterCount, 1)
        XCTAssertEqual(legacy.unregisterCount, 0)

        supervisor.completeAsyncUnregister()
        await Task.yield()
        guard case .success? = result else {
            return XCTFail("intentional Quit should disarm both launch routes")
        }
        XCTAssertEqual(legacy.unregisterCount, 1)
        XCTAssertNil(store.registeredRevision)
    }

    func testIntentionalQuitFailureKeepsRevisionAndReportsFailure() async {
        let supervisor = RecordingAppService(status: .enabled)
        supervisor.asyncUnregisterError = TestError.failed
        let store = RecordingSupervisorStore(revision: "revision")
        let controller = makeController(
            supervisor,
            RecordingAppService(status: .notRegistered),
            store
        )
        var result: Result<Void, Error>?

        controller.disableForIntentionalQuit(log: makeLog()) { result = $0 }
        supervisor.completeAsyncUnregister()
        await Task.yield()

        guard case .failure? = result else {
            return XCTFail("Quit must be cancelled when supervision cannot be disarmed")
        }
        XCTAssertEqual(store.registeredRevision, "revision")
    }

    func testLegacyQuitFailureOnlyClaimsRecoveryAfterVerifiedReregistration() async {
        let supervisor = RecordingAppService(status: .enabled)
        supervisor.statusAfterUnregister = .notRegistered
        supervisor.statusAfterRegister = .requiresApproval
        let legacy = RecordingAppService(status: .enabled)
        legacy.unregisterError = TestError.failed
        let store = RecordingSupervisorStore(revision: "revision")
        let controller = makeController(supervisor, legacy, store)
        var result: Result<Void, Error>?

        controller.disableForIntentionalQuit(log: makeLog()) { result = $0 }
        supervisor.completeAsyncUnregister()
        await Task.yield()

        guard case .failure? = result else {
            return XCTFail("Quit must remain cancelled when legacy cleanup fails")
        }
        XCTAssertEqual(supervisor.registerCount, 1)
        XCTAssertEqual(supervisor.status, .requiresApproval)
    }

    private func makeController(
        _ supervisor: RecordingAppService,
        _ legacy: RecordingAppService,
        _ store: RecordingSupervisorStore
    ) -> LaunchAtLoginController {
        LaunchAtLoginController(
            supervisorService: supervisor,
            legacyMainAppService: legacy,
            store: store
        )
    }

    private func makeLog() -> Log {
        Log(category: "runtime-supervisor-test", sink: RecordingLogSink())
    }
}

private final class RecordingAppService: AppServiceControlling {
    var status: SMAppService.Status
    var statusAfterRegister: SMAppService.Status?
    var statusAfterUnregister: SMAppService.Status?
    var registerError: Error?
    var unregisterError: Error?
    var asyncUnregisterError: Error?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var asyncUnregisterCount = 0
    private var asyncUnregisterCompletions: [@Sendable (Error?) -> Void] = []

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCount += 1
        if let registerError { throw registerError }
        status = statusAfterRegister ?? .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        if let unregisterError { throw unregisterError }
        status = statusAfterUnregister ?? .notRegistered
    }

    func unregister(completionHandler: @escaping @Sendable (Error?) -> Void) {
        asyncUnregisterCount += 1
        asyncUnregisterCompletions.append(completionHandler)
    }

    func completeAsyncUnregister() {
        let error = asyncUnregisterError
        if error == nil { status = statusAfterUnregister ?? .notRegistered }
        asyncUnregisterCompletions.removeFirst()(error)
    }
}

private final class RecordingSupervisorStore: SupervisorRegistrationStoring {
    var registeredRevision: String?

    init(revision: String? = nil) {
        registeredRevision = revision
    }
}

private enum TestError: Error {
    case failed
}
