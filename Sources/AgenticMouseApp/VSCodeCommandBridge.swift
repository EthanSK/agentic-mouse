import AppKit
import Foundation
import ScimitarKit

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

        var displayName: String {
            switch self {
            case .cursorHistoryBack, .cursorHistoryForward:
                return "Cursor History"
            case .toggleTerminal:
                return "Toggle Terminal"
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
    static let betterGitExtensionIdentifier = "ethansk.better-git-vscode"
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
        guard let url = Self.url(for: action) else {
            completion(.failure(BridgeError(
                description: "Could not create the VS Code bridge request"
            )))
            return
        }
        perform(url: url, displayName: action.displayName, completion: completion)
    }

    func performStageSelection(
        _ direction: VSCodeStageSelectionDirection,
        source: MouseSource,
        completion: @escaping Completion
    ) {
        guard let url = Self.stageSelectionURL(direction: direction, source: source) else {
            completion(.failure(BridgeError(
                description: "Could not create the Better Git stage selection request"
            )))
            return
        }
        perform(url: url, displayName: "Stage Selection", completion: completion)
    }

    func performStagePreviewNavigation(
        _ direction: VSCodeStagePreviewDirection,
        source: MouseSource,
        completion: @escaping Completion
    ) {
        guard let url = Self.stagePreviewNavigationURL(direction: direction, source: source) else {
            completion(.failure(BridgeError(
                description: "Could not create the Better Git preview navigation request"
            )))
            return
        }
        perform(url: url, displayName: "Stage Preview Navigation", completion: completion)
    }

    func performStagePreviewMode(
        _ active: Bool,
        source: MouseSource,
        initial: Bool = false,
        completion: @escaping Completion
    ) {
        guard let url = Self.stagePreviewModeURL(active: active, source: source, initial: initial) else {
            completion(.failure(BridgeError(
                description: "Could not create the Better Git preview navigation request"
            )))
            return
        }
        perform(url: url, displayName: "Stage Preview Navigation", completion: completion)
    }

    private func perform(
        url: URL,
        displayName: String,
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
        guard target.isActive else {
            completion(.failure(BridgeError(
                description: "VS Code must be frontmost for \(displayName)"
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

    static func stageSelectionURL(
        direction: VSCodeStageSelectionDirection,
        source: MouseSource
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "vscode"
        components.host = betterGitExtensionIdentifier
        components.path = "/mouse-stage-selection/\(direction.rawValue)"
        components.queryItems = [URLQueryItem(name: "source", value: source.rawValue)]
        return components.url
    }

    static func stagePreviewNavigationURL(
        direction: VSCodeStagePreviewDirection,
        source: MouseSource
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "vscode"
        components.host = betterGitExtensionIdentifier
        components.path = "/mouse-stage-preview/\(direction.rawValue)"
        components.queryItems = [URLQueryItem(name: "source", value: source.rawValue)]
        return components.url
    }

    static func stagePreviewModeURL(active: Bool, source: MouseSource, initial: Bool = false) -> URL? {
        var components = URLComponents()
        components.scheme = "vscode"
        components.host = betterGitExtensionIdentifier
        components.path = "/mouse-stage-preview-mode/\(active ? "on" : "off")"
        components.queryItems = [URLQueryItem(name: "source", value: source.rawValue)]
        // Only an atomic Eyes-begin hold may label its redundant bootstrap.
        // Legacy begins still need their unmarked URI, including on Better Git 146.
        if active && initial { components.queryItems?.append(URLQueryItem(name: "initial", value: "1")) }
        return components.url
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
