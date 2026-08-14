import Foundation
import ScimitarKit
import ServiceManagement

protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
}

extension SMAppService: LoginItemServicing {}

/// Keeps the menu-bar helper available after login without a Dock icon or a
/// separate LaunchAgent. macOS remains the source of truth for approval.
@MainActor
final class LaunchAtLoginController {
    private let service: LoginItemServicing

    init(service: LoginItemServicing = SMAppService.mainApp) {
        self.service = service
    }

    func ensureRegistered(log: Log) -> String {
        switch service.status {
        case .enabled:
            return "enabled"
        case .requiresApproval:
            log.notice("Launch at login requires approval in System Settings")
            return "requires approval"
        case .notFound, .notRegistered:
            // Current macOS can report notFound before the installed main app
            // has completed its first registration. register() provides the
            // authoritative result and a useful error if the bundle is invalid.
            do {
                try service.register()
                switch service.status {
                case .enabled:
                    log.info("Launch at login registered")
                    return "enabled"
                case .requiresApproval:
                    log.notice("Launch at login registered and requires approval")
                    return "requires approval"
                case .notFound:
                    return "unavailable"
                case .notRegistered:
                    return "not registered"
                @unknown default:
                    return "unknown"
                }
            } catch {
                log.error("Launch at login registration failed: \(error)")
                return "registration failed"
            }
        @unknown default:
            return "unknown"
        }
    }
}
