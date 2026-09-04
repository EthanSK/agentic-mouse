import AppKit
import ApplicationServices
import Foundation

enum SpotifySongRadioTarget {
    static let bundleIdentifier = "com.spotify.client"
}

/// Refuses Song Radio when Spotify says another Connect device owns playback.
///
/// Spotify can show a local `Play` button while music is still playing elsewhere.
/// Reading only the transport state would therefore let a local Apple Event seize the
/// remote session. This reader never activates Spotify or performs an AX action; it
/// completes a read-only traversal before each playback-changing command.
final class SpotifyPlaybackDeviceGuard: @unchecked Sendable {
    private static let remoteBannerPrefix = "Playing on "
    private static let maximumElementCount = 6_000

    private let queue = DispatchQueue(
        label: "com.ethan.agentic-mouse.spotify-playback-device"
    )

    @MainActor
    func confirmLocalPlayback() async -> Result<Void, SpotifySongRadioError> {
        await observation().map { _ in () }
    }

    @MainActor
    func confirmRadioContext(named title: String) async -> Result<Bool, SpotifySongRadioError> {
        await observation().map { $0.contextTitle == title }
    }

    @MainActor
    private func observation() async -> Result<PlayerObservation, SpotifySongRadioError> {
        guard let processIdentifier = NSRunningApplication.runningApplications(
            withBundleIdentifier: SpotifySongRadioTarget.bundleIdentifier
        ).first?.processIdentifier else {
            return .failure(.spotifyNotRunning)
        }
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Self.inspect(processIdentifier))
            }
        }
    }

    static func containsRemotePlaybackBanner(_ labels: [String]) -> Bool {
        labels.contains { label in
            label.trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix(remoteBannerPrefix)
        }
    }

    struct PlayerObservation {
        private(set) var sawNowPlayingBar = false
        private(set) var sawTransport = false
        private(set) var sawDeviceControl = false
        private(set) var contextTitles: Set<String> = []

        var contextTitle: String? {
            contextTitles.count == 1 ? contextTitles.first : nil
        }

        var isComplete: Bool {
            sawNowPlayingBar && sawTransport && sawDeviceControl
        }

        mutating func observe(labels: [String], inNowPlayingBar: Bool, inPlayerControls: Bool) {
            guard inNowPlayingBar else { return }
            sawNowPlayingBar = true
            sawDeviceControl = sawDeviceControl || labels.contains("Connect to a device")
            guard inPlayerControls else { return }
            sawTransport = sawTransport || labels.contains("Play") || labels.contains("Pause")
            // A displayed radio page has its own shuffle button even while the old playlist still plays. Only the bottom player's label proves playback context. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
            for label in labels {
                for prefix in ["Enable Shuffle for ", "Disable Shuffle for "] where label.hasPrefix(prefix) {
                    let title = String(label.dropFirst(prefix.count))
                    if !title.isEmpty { contextTitles.insert(title) }
                }
            }
        }
    }

    private struct ElementIdentity: Hashable {
        let element: AXUIElement

        static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }

    private static func inspect(
        _ processIdentifier: pid_t
    ) -> Result<PlayerObservation, SpotifySongRadioError> {
        guard AXIsProcessTrusted() else { return .failure(.playbackDeviceUnknown) }
        let application = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.08)

        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success,
        let windows = windowsValue as? [AXUIElement],
        !windows.isEmpty else {
            return .failure(.playbackDeviceUnknown)
        }

        var pending = windows.map { (element: $0, inNowPlayingBar: false, inPlayerControls: false) }
        var visited = Set<ElementIdentity>()
        var observation = PlayerObservation()
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        var index = 0
        while index < pending.count, index < maximumElementCount {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                return .failure(.playbackDeviceUnknown)
            }
            let entry = pending[index]
            index += 1
            let element = entry.element
            guard visited.insert(ElementIdentity(element: element)).inserted else { continue }
            let elementLabels = labels(of: element)
            if containsRemotePlaybackBanner(elementLabels) {
                return .failure(.playbackOnAnotherDevice)
            }
            let inNowPlayingBar = entry.inNowPlayingBar || elementLabels.contains("Now playing bar")
            let inPlayerControls = entry.inPlayerControls || (inNowPlayingBar && elementLabels.contains("Player controls"))
            observation.observe(labels: elementLabels, inNowPlayingBar: inNowPlayingBar, inPlayerControls: inPlayerControls)
            switch children(of: element) {
            case .success(let children):
                pending.append(contentsOf: children.map { ($0, inNowPlayingBar, inPlayerControls) })
            case .unsupported:
                break
            case .failed:
                return .failure(.playbackDeviceUnknown)
            }
        }
        // An unexposed Chromium tree can finish with only a few empty nodes. Absence of a remote banner is not local-device proof without the actual player controls.
        guard index == pending.count, observation.isComplete else { return .failure(.playbackDeviceUnknown) }
        return .success(observation)
    }

    private enum ChildrenResult {
        case success([AXUIElement])
        case unsupported
        case failed
    }

    private static func labels(of element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXValueAttribute]
            .compactMap { name in
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(
                    element,
                    name as CFString,
                    &value
                ) == .success else { return nil }
                return value as? String
            }
    }

    private static func children(of element: AXUIElement) -> ChildrenResult {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) {
        case .success:
            return .success(value as? [AXUIElement] ?? [])
        case .attributeUnsupported, .noValue:
            return .unsupported
        default:
            return .failed
        }
    }
}
