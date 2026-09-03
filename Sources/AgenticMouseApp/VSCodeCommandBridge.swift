import AppKit
import Foundation

/// Invokes a small allow-listed command inside VS Code through the companion
/// extension's supported URI handler. Cursor History deliberately bypasses
/// synthetic keyboard events: Electron can accept a posted event while never
/// resolving the intended keybinding, whereas the extension calls the built-in
/// VS Code command directly.
@MainActor
final class VSCodeCommandBridge {
    enum Action: String, Equatable {
        case cursorHistoryBack = "cursor-history/back"
        case cursorHistoryForward = "cursor-history/forward"
        case toggleTerminal = "terminal/toggle"
        case addToChat = "codex/add-to-chat"

        var displayName: String {
            switch self {
            case .cursorHistoryBack, .cursorHistoryForward:
                return "Cursor History"
            case .toggleTerminal:
                return "Toggle Terminal"
            case .addToChat:
                return "Add to chat"
            }
        }

        var requiresFrontmostVSCode: Bool {
            switch self {
            case .cursorHistoryBack, .cursorHistoryForward, .toggleTerminal:
                return true
            case .addToChat:
                return false // Codex is frontmost when its mouse mode is open, while VS Code must keep the editor selection that gets added to chat. (Codex task: 01a068dc-c698-7312-bc0b-6221c39286e4)
            }
        }
    }

    struct BridgeError: Error, CustomStringConvertible, Equatable {
        let description: String
    }

    struct Target: Equatable {
        let processIdentifier: pid_t
        let applicationURL: URL
        let isActive: Bool
    }

    typealias TargetResolver = @MainActor () -> Target?
    typealias URLOpener = @MainActor (
        _ url: URL,
        _ applicationURL: URL,
        _ completion: @escaping (Error?) -> Void
    ) -> Void
    typealias Completion = @MainActor (Result<Void, BridgeError>) -> Void
    typealias InputAllowedProvider = @MainActor () -> Bool

    static let extensionIdentifier = "ethansk.agentic-mouse-vscode-bridge"
    static let targetBundleIdentifier = "com.microsoft.VSCode"

    private let targetResolver: TargetResolver
    private let openURL: URLOpener
    private let inputAllowed: InputAllowedProvider

    init(
        targetResolver: @escaping TargetResolver = VSCodeCommandBridge.resolveTarget,
        openURL: @escaping URLOpener = VSCodeCommandBridge.openInBackground,
        inputAllowed: @escaping InputAllowedProvider = { true }
    ) {
        self.targetResolver = targetResolver
        self.openURL = openURL
        self.inputAllowed = inputAllowed
    }

    func perform(
        _ action: Action,
        completion: @escaping Completion
    ) {
        guard inputAllowed() else {
            completion(.failure(BridgeError(
                description: "Mouse commands are disabled while macOS is locked"
            )))
            return
        }
        guard let target = targetResolver() else {
            completion(.failure(BridgeError(description: "VS Code is not running")))
            return
        }
        guard !action.requiresFrontmostVSCode || target.isActive else {
            completion(.failure(BridgeError(
                description: "VS Code must be frontmost for \(action.displayName)"
            )))
            return
        }
        guard let url = Self.url(for: action) else {
            completion(.failure(BridgeError(
                description: "Could not create the VS Code bridge request"
            )))
            return
        }

        openURL(url, target.applicationURL) { error in
            // LaunchServices can finish on its private open queue; updating the HUD there crashes AppKit after the first wheel action. Always return bridge results on the main queue. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(BridgeError(
                        description: "Could not reach the VS Code bridge: \(error.localizedDescription)"
                    )))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    static func url(for action: Action) -> URL? {
        URL(string: "vscode://\(extensionIdentifier)/\(action.rawValue)")
    }

    private static func resolveTarget() -> Target? {
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: targetBundleIdentifier
        )
        guard let application = applications.first(where: { !$0.isTerminated }),
              let applicationURL = application.bundleURL
        else { return nil }
        return Target(
            processIdentifier: application.processIdentifier,
            applicationURL: applicationURL,
            isActive: application.isActive
        )
    }

    private static func openInBackground(
        _ url: URL,
        _ applicationURL: URL,
        _ completion: @escaping (Error?) -> Void
    ) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { _, error in
            completion(error)
        }
    }
}
