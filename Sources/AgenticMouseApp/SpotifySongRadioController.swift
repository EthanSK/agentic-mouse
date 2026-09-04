import AppKit
import Foundation
import ScimitarKit

enum SpotifySongRadioPlaybackState: String, Equatable, Sendable {
    case paused
    case playing
}

struct SpotifySongRadioSnapshot: Equatable, Sendable {
    let trackURI: String
    let trackName: String
    let position: TimeInterval
    let duration: TimeInterval
    let playbackState: SpotifySongRadioPlaybackState
    let capturedAtUptime: TimeInterval
}

enum SpotifySongRadioError: Error, Equatable, Sendable {
    case appleEventsPermissionMissing
    case automationTimedOut
    case cancelled
    case currentItemUnavailable
    case playbackDeviceUnknown
    case playbackOnAnotherDevice
    case positionTooNearEnd
    case positionNotRestored
    case radioDidNotLoad
    case scriptingFailed
    case spotifyNotRunning
    case trackChanged
    case unsupportedCurrentItem

    var userMessage: String {
        switch self {
        case .appleEventsPermissionMissing:
            return "Allow Agentic Mouse to control Spotify"
        case .automationTimedOut:
            return "Spotify did not respond"
        case .cancelled:
            return "Song Radio was cancelled"
        case .currentItemUnavailable:
            return "Spotify has no current song"
        case .playbackDeviceUnknown:
            return "Could not confirm Spotify is playing on this Mac"
        case .playbackOnAnotherDevice:
            return "Spotify is playing on another device"
        case .positionTooNearEnd:
            return "The song is too close to ending"
        case .positionNotRestored:
            return "Spotify did not restore the playhead or playback state"
        case .radioDidNotLoad:
            return "Song Radio did not load"
        case .scriptingFailed:
            return "Spotify could not start Song Radio"
        case .spotifyNotRunning:
            return "Open Spotify first"
        case .trackChanged:
            return "Spotify changed songs before the position was restored"
        case .unsupportedCurrentItem:
            return "Song Radio needs a Spotify track"
        }
    }
}

struct SpotifySongRadioAutomation: Sendable {
    var confirmLocalPlayback: @Sendable () async -> Result<Void, SpotifySongRadioError>
    var capture: @Sendable () async -> Result<SpotifySongRadioSnapshot, SpotifySongRadioError>
    var startRadio: @Sendable (_ trackURI: String) async -> Result<Void, SpotifySongRadioError>
    var currentTrackURI: @Sendable () async -> Result<String, SpotifySongRadioError>
    var confirmRadioContext: @Sendable (_ title: String) async -> Result<Bool, SpotifySongRadioError>
    var seek: @Sendable (_ position: TimeInterval) async -> Result<Void, SpotifySongRadioError>
    var restorePlaybackState: @Sendable (
        _ state: SpotifySongRadioPlaybackState
    ) async -> Result<Void, SpotifySongRadioError>
    var now: @Sendable () -> TimeInterval
    var sleep: @Sendable (_ duration: TimeInterval) async -> Void

    static func live() -> Self {
        let client = SpotifyAppleScriptClient()
        let deviceGuard = SpotifyPlaybackDeviceGuard()
        return Self(
            confirmLocalPlayback: { await deviceGuard.confirmLocalPlayback() },
            capture: { await client.capture() },
            startRadio: { await client.startRadio(trackURI: $0) },
            currentTrackURI: { await client.currentTrackURI() },
            confirmRadioContext: { await deviceGuard.confirmRadioContext(named: $0) },
            seek: { await client.seek(to: $0) },
            restorePlaybackState: { await client.restorePlaybackState($0) },
            now: { ProcessInfo.processInfo.systemUptime },
            sleep: { duration in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            }
        )
    }
}

/// Runs one user-requested Spotify Song Radio transition without blocking the HUD.
///
/// Each Apple Event is separated by an input/session check. Lock, sleep, shutdown,
/// or cancellation therefore prevents any later seek or playback-state command even
/// when an Apple Event that was already in flight cannot itself be withdrawn.
@MainActor
final class SpotifySongRadioController {
    enum StartResult: Equatable {
        case accepted
        case busy
        case inputBlocked
        case spotifyNotRunning
    }

    var onCompletion: ((MouseSource, Result<Void, SpotifySongRadioError>) -> Void)?

    private let spotifyIsRunning: () -> Bool
    private let inputAllowed: () -> Bool
    private let automation: SpotifySongRadioAutomation
    private let loadTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private(set) var activeSource: MouseSource?

    init(
        spotifyIsRunning: @escaping () -> Bool = {
            !NSRunningApplication.runningApplications(
                withBundleIdentifier: SpotifySongRadioTarget.bundleIdentifier
            ).isEmpty
        },
        inputAllowed: @escaping () -> Bool = { true },
        automation: SpotifySongRadioAutomation = .live(),
        loadTimeout: TimeInterval = 35,
        pollInterval: TimeInterval = 0.25
    ) {
        self.spotifyIsRunning = spotifyIsRunning
        self.inputAllowed = inputAllowed
        self.automation = automation
        self.loadTimeout = loadTimeout
        self.pollInterval = pollInterval
    }

    func start(source: MouseSource) -> StartResult {
        guard inputAllowed() else { return .inputBlocked }
        guard spotifyIsRunning() else { return .spotifyNotRunning }
        guard task == nil else { return .busy }

        generation &+= 1
        let currentGeneration = generation
        activeSource = source
        task = Task { [weak self] in
            guard let self else { return }
            let result = await self.performTransition()
            self.task = nil
            self.activeSource = nil
            guard currentGeneration == self.generation else { return }
            self.onCompletion?(source, result)
        }
        return .accepted
    }

    func cancel(source: MouseSource? = nil) {
        if let source, activeSource != source { return }
        generation &+= 1
        task?.cancel()
        // An in-flight Apple Event cannot be withdrawn. Keep the busy latch until it returns so cancellation cannot overlap a second playback request.
    }

    private func performTransition() async -> Result<Void, SpotifySongRadioError> {
        guard mayContinue else { return .failure(.cancelled) }
        if case .failure(let error) = await automation.confirmLocalPlayback() {
            return .failure(error)
        }
        guard mayContinue else { return .failure(.cancelled) }
        let snapshot: SpotifySongRadioSnapshot
        switch await automation.capture() {
        case .success(let captured):
            snapshot = captured
        case .failure(let error):
            return .failure(error)
        }

        guard Self.stationURI(for: snapshot.trackURI) != nil else {
            return .failure(.unsupportedCurrentItem)
        }
        guard snapshot.position < snapshot.duration - 5 else {
            return .failure(.positionTooNearEnd)
        }
        guard mayContinue else { return .failure(.cancelled) }
        if case .failure(let error) = await automation.confirmLocalPlayback() {
            return .failure(error)
        }
        guard mayContinue else { return .failure(.cancelled) }
        if case .failure(let error) = await automation.startRadio(snapshot.trackURI) {
            return .failure(error)
        }

        let deadline = automation.now() + loadTimeout
        while automation.now() < deadline {
            guard mayContinue else { return .failure(.cancelled) }
            switch await automation.currentTrackURI() {
            case .success(snapshot.trackURI):
                // The seed URI is already current before the command. Wait for the actual player's radio label, not the open radio page or unchanged song. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
                switch await automation.confirmRadioContext(snapshot.trackName + " Radio") {
                case .success(true): return await restore(snapshot)
                case .success(false): break
                case .failure(let error): return .failure(error)
                }
            case .success:
                return .failure(.trackChanged)
            case .failure(.currentItemUnavailable):
                break
            case .failure(let error):
                return .failure(error)
            }
            await automation.sleep(pollInterval)
        }
        return .failure(.radioDidNotLoad)
    }

    private func restore(
        _ snapshot: SpotifySongRadioSnapshot
    ) async -> Result<Void, SpotifySongRadioError> {
        guard mayContinue else { return .failure(.cancelled) }
        if case .failure(let error) = await automation.confirmLocalPlayback() {
            return .failure(error)
        }
        guard mayContinue else { return .failure(.cancelled) }
        // Starting a radio plays immediately. Pause before seeking a paused snapshot, otherwise the playhead advances again while later checks run.
        if case .failure(let error) = await automation.restorePlaybackState(snapshot.playbackState) {
            return .failure(error)
        }
        guard mayContinue else { return .failure(.cancelled) }
        if case .failure(let error) = await automation.confirmLocalPlayback() {
            return .failure(error)
        }
        var target = snapshot.position
        if snapshot.playbackState == .playing {
            target += max(0, automation.now() - snapshot.capturedAtUptime)
        }
        guard target < snapshot.duration - 5 else {
            return .failure(.positionTooNearEnd)
        }
        guard mayContinue else { return .failure(.cancelled) }
        if case .failure(let error) = await automation.seek(target) {
            return .failure(error)
        }
        let seekCompletedAtUptime = automation.now()
        guard mayContinue else { return .failure(.cancelled) }
        switch await automation.capture() {
        case .success(let restored):
            guard restored.trackURI == snapshot.trackURI else { return .failure(.trackChanged) }
            let elapsed = snapshot.playbackState == .playing
                ? max(0, restored.capturedAtUptime - seekCompletedAtUptime) : 0
            guard restored.playbackState == snapshot.playbackState,
                  abs(restored.position - (target + elapsed)) <= 2
            else { return .failure(.positionNotRestored) } // A successful seek Apple Event is not proof the player applied it; read back position/state before showing success.
            guard mayContinue else { return .failure(.cancelled) }
            switch await automation.confirmRadioContext(snapshot.trackName + " Radio") {
            case .success(true): return .success(())
            case .success(false): return .failure(.radioDidNotLoad)
            case .failure(let error): return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }

    private var mayContinue: Bool {
        !Task.isCancelled && inputAllowed()
    }

    nonisolated static func stationURI(for trackURI: String) -> String? {
        let parts = trackURI.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0] == "spotify",
              parts[1] == "track",
              !parts[2].isEmpty,
              parts[2].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }
        return "spotify:station:track:\(parts[2])"
    }
}

private struct SpotifyAppleScriptFailure: Error, Sendable {
    let number: Int
}

/// Executes Spotify's documented AppleScript dictionary on one private queue.
///
/// `NSAppleScript` is created and consumed entirely on that queue, so no
/// non-Sendable Apple Event descriptor crosses into the main actor.
private final class SpotifyAppleScriptClient: @unchecked Sendable {
    static let bundleIdentifier = SpotifySongRadioTarget.bundleIdentifier

    private let queue = DispatchQueue(label: "com.ethan.agentic-mouse.spotify-song-radio")

    func capture() async -> Result<SpotifySongRadioSnapshot, SpotifySongRadioError> {
        let source = """
        with timeout of 5 seconds
            tell application id "\(Self.bundleIdentifier)"
                if player state is stopped then error number -1728
                set capturedURI to spotify url of current track
                set capturedPosition to player position
                set capturedDuration to duration of current track
                set capturedState to player state as text
                set capturedName to name of current track
            end tell
            set AppleScript's text item delimiters to ASCII character 31
            return {capturedURI, capturedPosition, capturedDuration, capturedState, capturedName} as text
        end timeout
        """
        switch await execute(source) {
        case .success(let value):
            let fields = value.split(separator: Character(UnicodeScalar(31)), omittingEmptySubsequences: false)
            guard fields.count == 5,
                  let position = TimeInterval(fields[1]),
                  let durationMilliseconds = TimeInterval(fields[2]),
                  position.isFinite, position >= 0,
                  durationMilliseconds.isFinite, durationMilliseconds > 0,
                  !fields[4].isEmpty,
                  let state = SpotifySongRadioPlaybackState(rawValue: String(fields[3]))
            else { return .failure(.currentItemUnavailable) }
            return .success(SpotifySongRadioSnapshot(
                trackURI: String(fields[0]),
                trackName: String(fields[4]),
                position: position,
                duration: durationMilliseconds / 1_000,
                playbackState: state,
                capturedAtUptime: ProcessInfo.processInfo.systemUptime
            ))
        case .failure(let failure):
            return .failure(Self.map(failure, unavailableIsExpected: true))
        }
    }

    func startRadio(trackURI: String) async -> Result<Void, SpotifySongRadioError> {
        guard let stationURI = SpotifySongRadioController.stationURI(for: trackURI) else {
            return .failure(.unsupportedCurrentItem)
        }
        return await executeVoid("""
        with timeout of 45 seconds
            tell application id "\(Self.bundleIdentifier)" to play track "\(trackURI)" in context "\(stationURI)"
        end timeout
        """)
    }

    func currentTrackURI() async -> Result<String, SpotifySongRadioError> {
        switch await execute("""
        with timeout of 5 seconds
            tell application id "\(Self.bundleIdentifier)" to return spotify url of current track
        end timeout
        """) {
        case .success(let uri):
            return .success(uri)
        case .failure(let failure):
            return .failure(Self.map(failure, unavailableIsExpected: true))
        }
    }

    func seek(to position: TimeInterval) async -> Result<Void, SpotifySongRadioError> {
        let seconds = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), position)
        return await executeVoid("""
        with timeout of 5 seconds
            tell application id "\(Self.bundleIdentifier)" to set player position to \(seconds)
        end timeout
        """)
    }

    func restorePlaybackState(
        _ state: SpotifySongRadioPlaybackState
    ) async -> Result<Void, SpotifySongRadioError> {
        let command = state == .playing ? "play" : "pause"
        return await executeVoid("""
        with timeout of 5 seconds
            tell application id "\(Self.bundleIdentifier)" to \(command)
        end timeout
        """)
    }

    private func executeVoid(_ source: String) async -> Result<Void, SpotifySongRadioError> {
        switch await execute(source) {
        case .success:
            return .success(())
        case .failure(let failure):
            return .failure(Self.map(failure, unavailableIsExpected: false))
        }
    }

    private func execute(_ source: String) async -> Result<String, SpotifyAppleScriptFailure> {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(returning: .failure(
                        SpotifyAppleScriptFailure(number: 0)
                    ))
                    return
                }
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error)
                if let number = error?["NSAppleScriptErrorNumber"] as? NSNumber {
                    continuation.resume(returning: .failure(
                        SpotifyAppleScriptFailure(number: number.intValue)
                    ))
                } else {
                    continuation.resume(returning: .success(result.stringValue ?? ""))
                }
            }
        }
    }

    private static func map(
        _ failure: SpotifyAppleScriptFailure,
        unavailableIsExpected: Bool
    ) -> SpotifySongRadioError {
        switch failure.number {
        case -1743:
            return .appleEventsPermissionMissing
        case -1712:
            return .automationTimedOut
        case -1728 where unavailableIsExpected:
            return .currentItemUnavailable
        default:
            return .scriptingFailed
        }
    }
}
