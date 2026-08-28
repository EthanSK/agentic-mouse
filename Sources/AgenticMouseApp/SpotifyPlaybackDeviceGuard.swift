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

    private static func inspect(
        _ processIdentifier: pid_t
    ) -> Result<Void, SpotifySongRadioError> {
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

        var pending = windows
        var index = 0
        while index < pending.count, index < maximumElementCount {
            let element = pending[index]
            index += 1
            if containsRemotePlaybackBanner(labels(of: element)) {
                return .failure(.playbackOnAnotherDevice)
            }
            switch children(of: element) {
            case .success(let children):
                pending.append(contentsOf: children)
            case .unsupported:
                break
            case .failed:
                return .failure(.playbackDeviceUnknown)
            }
        }
        guard index == pending.count else { return .failure(.playbackDeviceUnknown) }
        return .success(())
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
