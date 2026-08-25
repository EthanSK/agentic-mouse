import Foundation
import ScimitarKit
import ServiceManagement

protocol AppServiceControlling: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func unregister(completionHandler: @escaping @Sendable (Error?) -> Void)
}

extension SMAppService: AppServiceControlling {}

protocol SupervisorRegistrationStoring: AnyObject {
    var registeredRevision: String? { get set }
}

final class UserDefaultsSupervisorRegistrationStore: SupervisorRegistrationStoring {
    private static let key = "runtimeSupervisorRegisteredRevision"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var registeredRevision: String? {
        get { defaults.string(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

enum RuntimeSupervisorRegistrationError: Error {
    case recoveryCouldNotBeRestored
}

/// Registers the signed nested login item that stays alive and relaunches the
/// main menu-bar app only when its process unexpectedly disappears.
///
/// This replaces `SMAppService.mainApp`: that API starts the app at login but
/// does not supervise it during the logged-in session. The nested helper also
/// starts at login, remains non-activating, and is explicitly unregistered and
/// reaped before the user chooses Quit so an intentional exit stays intentional.
@MainActor
final class LaunchAtLoginController {
    nonisolated static let supervisorBundleIdentifier =
        "com.ethan.agentic-mouse.runtime-supervisor"

    private let supervisorService: AppServiceControlling
    private let legacyMainAppService: AppServiceControlling
    private let store: SupervisorRegistrationStoring
    private var activeRevision: String?
    private var isRefreshing = false
    private var isDisarmingForQuit = false

    init(
        supervisorService: AppServiceControlling = SMAppService.loginItem(
            identifier: LaunchAtLoginController.supervisorBundleIdentifier
        ),
        legacyMainAppService: AppServiceControlling = SMAppService.mainApp,
        store: SupervisorRegistrationStoring = UserDefaultsSupervisorRegistrationStore()
    ) {
        self.supervisorService = supervisorService
        self.legacyMainAppService = legacyMainAppService
        self.store = store
    }

    func ensureRegistered(
        revision: String,
        log: Log,
        onStatusChange: @escaping (String) -> Void = { _ in }
    ) -> String {
        activeRevision = revision

        switch supervisorService.status {
        case .requiresApproval:
            log.notice("Runtime self-recovery requires approval in System Settings")
            return "requires approval"
        case .enabled where store.registeredRevision == revision:
            migrateLegacyMainAppRegistration(log: log)
            return "enabled"
        case .enabled:
            guard !isRefreshing else { return "refreshing" }
            isRefreshing = true
            log.info("Refreshing runtime self-recovery for revision \(revision)")
            supervisorService.unregister { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isRefreshing = false
                    if let error {
                        log.error("Runtime self-recovery refresh failed while unregistering: \(error)")
                        onStatusChange("refresh failed")
                        return
                    }
                    onStatusChange(self.registerSupervisor(revision: revision, log: log))
                }
            }
            return "refreshing"
        case .notFound, .notRegistered:
            return registerSupervisor(revision: revision, log: log)
        @unknown default:
            return "unknown"
        }
    }

    /// Removes every launch route before an explicit user Quit. Service
    /// Management's completion fires only after the running login-item helper
    /// has been killed, which closes the final supervisor-tick relaunch race.
    func disableForIntentionalQuit(
        log: Log,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard !isDisarmingForQuit else {
            completion(.failure(RuntimeSupervisorRegistrationError.recoveryCouldNotBeRestored))
            return
        }
        isDisarmingForQuit = true

        let finish: @Sendable (Error?) -> Void = { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isDisarmingForQuit = false
                if let error {
                    log.error("Could not disable runtime self-recovery for Quit: \(error)")
                    completion(.failure(error))
                    return
                }
                self.finishIntentionalQuitDisarm(log: log, completion: completion)
            }
        }

        switch supervisorService.status {
        case .enabled, .requiresApproval:
            supervisorService.unregister(completionHandler: finish)
        case .notRegistered, .notFound:
            finish(nil)
        @unknown default:
            finish(RuntimeSupervisorRegistrationError.recoveryCouldNotBeRestored)
        }
    }

    private func registerSupervisor(revision: String, log: Log) -> String {
        do {
            try supervisorService.register()
        } catch {
            log.error("Runtime self-recovery registration failed: \(error)")
            return "registration failed"
        }

        switch supervisorService.status {
        case .enabled:
            store.registeredRevision = revision
            migrateLegacyMainAppRegistration(log: log)
            log.info("Runtime self-recovery enabled")
            return "enabled"
        case .requiresApproval:
            log.notice("Runtime self-recovery registered and requires approval")
            return "requires approval"
        case .notFound:
            return "unavailable"
        case .notRegistered:
            return "not registered"
        @unknown default:
            return "unknown"
        }
    }

    private func finishIntentionalQuitDisarm(
        log: Log,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        do {
            try unregisterIfNeeded(legacyMainAppService)
        } catch {
            do {
                try supervisorService.register()
                guard supervisorService.status == .enabled else {
                    throw RuntimeSupervisorRegistrationError.recoveryCouldNotBeRestored
                }
                if let activeRevision { store.registeredRevision = activeRevision }
            } catch {
                log.error("Could not restore runtime self-recovery after Quit cancellation: \(error)")
            }
            log.error("Could not disable the legacy login route for Quit: \(error)")
            completion(.failure(error))
            return
        }

        store.registeredRevision = nil
        log.info("Runtime self-recovery disabled and helper reaped for intentional Quit")
        completion(.success(()))
    }

    private func migrateLegacyMainAppRegistration(log: Log) {
        do {
            let wasRegistered = legacyMainAppService.status == .enabled
                || legacyMainAppService.status == .requiresApproval
            try unregisterIfNeeded(legacyMainAppService)
            if wasRegistered {
                log.info("Removed legacy main-app login registration after enabling supervision")
            }
        } catch {
            // The single-instance guard prevents duplicate startup side effects,
            // so keep the working supervisor and make this cleanup visible.
            log.notice("Legacy main-app login registration could not be removed: \(error)")
        }
    }

    private func unregisterIfNeeded(_ service: AppServiceControlling) throws {
        switch service.status {
        case .enabled, .requiresApproval:
            try service.unregister()
        case .notRegistered, .notFound:
            return
        @unknown default:
            return
        }
    }
}
