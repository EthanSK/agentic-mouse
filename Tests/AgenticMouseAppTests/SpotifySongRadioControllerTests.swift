@testable import AgenticMouseApp
import ScimitarKit
import XCTest

@MainActor
final class SpotifySongRadioControllerTests: XCTestCase {
    func testStationURIAcceptsOnlyExactSpotifyTrackURIs() {
        XCTAssertEqual(
            SpotifySongRadioController.stationURI(for: "spotify:track:AbC123"),
            "spotify:station:track:AbC123"
        )
        XCTAssertNil(SpotifySongRadioController.stationURI(for: "spotify:episode:AbC123"))
        XCTAssertNil(SpotifySongRadioController.stationURI(for: "spotify:track:"))
        XCTAssertNil(SpotifySongRadioController.stationURI(for: "spotify:track:abc/123"))
    }

    func testPlayingTrackRestoresElapsedAdjustedPositionAndPlayingState() async {
        let seeks = LockedBox<[TimeInterval]>([])
        let restoredStates = LockedBox<[SpotifySongRadioPlaybackState]>([])
        let completion = expectation(description: "song radio completes")
        var receivedResult: Result<Void, SpotifySongRadioError>?
        let controller = SpotifySongRadioController(
            spotifyIsRunning: { true },
            inputAllowed: { true },
            automation: automation(
                snapshot: snapshot(
                    position: 40,
                    duration: 200,
                    playbackState: .playing,
                    capturedAtUptime: 100
                ),
                now: 104,
                seek: { position in seeks.mutate { $0.append(position) } },
                restorePlaybackState: { state in restoredStates.mutate { $0.append(state) } }
            )
        )
        controller.onCompletion = { _, result in
            receivedResult = result
            completion.fulfill()
        }

        XCTAssertEqual(controller.start(source: .corsair), .accepted)
        await fulfillment(of: [completion], timeout: 1)

        assertSuccess(receivedResult)
        XCTAssertEqual(seeks.value, [44])
        XCTAssertEqual(restoredStates.value, [.playing])
    }

    func testPausedTrackDoesNotAddElapsedTimeAndReturnsToPaused() async {
        let seeks = LockedBox<[TimeInterval]>([])
        let restoredStates = LockedBox<[SpotifySongRadioPlaybackState]>([])
        let completion = expectation(description: "paused song radio completes")
        var receivedResult: Result<Void, SpotifySongRadioError>?
        let controller = SpotifySongRadioController(
            spotifyIsRunning: { true },
            inputAllowed: { true },
            automation: automation(
                snapshot: snapshot(
                    position: 40,
                    duration: 200,
                    playbackState: .paused,
                    capturedAtUptime: 100
                ),
                now: 116,
                seek: { position in seeks.mutate { $0.append(position) } },
                restorePlaybackState: { state in restoredStates.mutate { $0.append(state) } }
            )
        )
        controller.onCompletion = { _, result in
            receivedResult = result
            completion.fulfill()
        }

        XCTAssertEqual(controller.start(source: .razer), .accepted)
        await fulfillment(of: [completion], timeout: 1)

        assertSuccess(receivedResult)
        XCTAssertEqual(seeks.value, [40])
        XCTAssertEqual(restoredStates.value, [.paused])
    }

    func testNearEndRefusesBeforeChangingSpotify() async {
        let startCount = LockedBox(0)
        let completion = expectation(description: "near-end refusal completes")
        var receivedResult: Result<Void, SpotifySongRadioError>?
        var injected = automation(
            snapshot: snapshot(
                position: 197,
                duration: 200,
                playbackState: .playing,
                capturedAtUptime: 100
            ),
            now: 100
        )
        injected.startRadio = { _ in
            startCount.mutate { $0 += 1 }
            return .success(())
        }
        let controller = SpotifySongRadioController(
            spotifyIsRunning: { true },
            inputAllowed: { true },
            automation: injected
        )
        controller.onCompletion = { _, result in
            receivedResult = result
            completion.fulfill()
        }

        XCTAssertEqual(controller.start(source: .corsair), .accepted)
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(startCount.value, 0)
        XCTAssertEqual(failure(receivedResult), .positionTooNearEnd)
    }

    func testRemotePlaybackIsRefusedBeforeInspectingOrChangingSpotify() async {
        let captureCount = LockedBox(0)
        let startCount = LockedBox(0)
        let completion = expectation(description: "remote playback refusal completes")
        var receivedResult: Result<Void, SpotifySongRadioError>?
        let capturedSnapshot = snapshot()
        var injected = automation(snapshot: capturedSnapshot, now: 100)
        injected.confirmLocalPlayback = { .failure(.playbackOnAnotherDevice) }
        injected.capture = {
            captureCount.mutate { $0 += 1 }
            return .success(capturedSnapshot)
        }
        injected.startRadio = { _ in
            startCount.mutate { $0 += 1 }
            return .success(())
        }
        let controller = SpotifySongRadioController(
            spotifyIsRunning: { true },
            inputAllowed: { true },
            automation: injected
        )
        controller.onCompletion = { _, result in
            receivedResult = result
            completion.fulfill()
        }

        XCTAssertEqual(controller.start(source: .corsair), .accepted)
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(captureCount.value, 0)
        XCTAssertEqual(startCount.value, 0)
        XCTAssertEqual(failure(receivedResult), .playbackOnAnotherDevice)
    }

    func testPlaybackDeviceIsRecheckedImmediatelyBeforeRadioStarts() async {
        let guardCount = LockedBox(0)
        let startCount = LockedBox(0)
        let completion = expectation(description: "second device guard completes")
        var receivedResult: Result<Void, SpotifySongRadioError>?
        var injected = automation(snapshot: snapshot(), now: 100)
        injected.confirmLocalPlayback = {
            let count = guardCount.mutateAndReturn { value in
                value += 1
                return value
            }
            return count == 1 ? .success(()) : .failure(.playbackOnAnotherDevice)
        }
        injected.startRadio = { _ in
            startCount.mutate { $0 += 1 }
            return .success(())
        }
        let controller = SpotifySongRadioController(
            spotifyIsRunning: { true },
            inputAllowed: { true },
            automation: injected
        )
        controller.onCompletion = { _, result in
            receivedResult = result
            completion.fulfill()
        }

        XCTAssertEqual(controller.start(source: .razer), .accepted)
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(guardCount.value, 2)
        XCTAssertEqual(startCount.value, 0)
        XCTAssertEqual(failure(receivedResult), .playbackOnAnotherDevice)
    }

    func testRemoteBannerWinsEvenWhenTheTransportLabelSaysPlay() {
        XCTAssertTrue(SpotifyPlaybackDeviceGuard.containsRemotePlaybackBanner([
            "Play",
            "Playing on Another Mac",
        ]))
        XCTAssertFalse(SpotifyPlaybackDeviceGuard.containsRemotePlaybackBanner([
            "Pause",
            "Connect to a device",
        ]))
    }

    func testSecondRequestIsRejectedWhileFirstRequestIsInFlight() async {
        let captureStarted = expectation(description: "capture starts")
        let releaseCapture = LockedBox(false)
        let delayedSnapshot = snapshot()
        var injected = automation(snapshot: delayedSnapshot, now: 100)
        injected.capture = {
            captureStarted.fulfill()
            while !releaseCapture.value {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            return .success(delayedSnapshot)
        }
        let controller = SpotifySongRadioController(
            spotifyIsRunning: { true },
            inputAllowed: { true },
            automation: injected
        )

        XCTAssertEqual(controller.start(source: .corsair), .accepted)
        await fulfillment(of: [captureStarted], timeout: 1)
        XCTAssertEqual(controller.start(source: .corsair), .busy)

        controller.cancel()
        XCTAssertEqual(controller.start(source: .razer), .busy)
        releaseCapture.mutate { $0 = true }
    }

    func testUnchangedSongWaitsForPlayerRadioContextBeforeSeeking() async {
        let time = LockedBox<TimeInterval>(100)
        let contextChecks = LockedBox(0)
        let seeks = LockedBox<[TimeInterval]>([])
        let completion = expectation(description: "context transition")
        var result: Result<Void, SpotifySongRadioError>?
        var injected = automation(snapshot: snapshot(), now: 100, seek: { position in seeks.mutate { $0.append(position) } })
        injected.now = { time.value }
        injected.sleep = { _ in time.mutate { $0 += 1 } }
        injected.confirmRadioContext = { title in
            XCTAssertEqual(title, "Test song Radio")
            let count = contextChecks.mutateAndReturn { $0 += 1; return $0 }
            if count < 3 { XCTAssertTrue(seeks.value.isEmpty) }
            return .success(count >= 3)
        }
        let controller = SpotifySongRadioController(spotifyIsRunning: { true }, automation: injected)
        controller.onCompletion = { _, value in result = value; completion.fulfill() }
        XCTAssertEqual(controller.start(source: .corsair), .accepted)
        await fulfillment(of: [completion], timeout: 1)
        assertSuccess(result)
        XCTAssertEqual(seeks.value, [42])
        XCTAssertEqual(contextChecks.value, 4)
    }

    func testRadioPageWithoutPlaybackContextChangeTimesOutWithoutSeeking() async {
        let time = LockedBox<TimeInterval>(100)
        let seeks = LockedBox<[TimeInterval]>([])
        let completion = expectation(description: "context timeout")
        var result: Result<Void, SpotifySongRadioError>?
        var injected = automation(snapshot: snapshot(), now: 100, seek: { position in seeks.mutate { $0.append(position) } })
        injected.now = { time.value }
        injected.sleep = { _ in time.mutate { $0 += 1 } }
        injected.confirmRadioContext = { _ in .success(false) }
        let controller = SpotifySongRadioController(spotifyIsRunning: { true }, automation: injected, loadTimeout: 2)
        controller.onCompletion = { _, value in result = value; completion.fulfill() }
        _ = controller.start(source: .corsair)
        await fulfillment(of: [completion], timeout: 1)
        XCTAssertEqual(failure(result), .radioDidNotLoad)
        XCTAssertTrue(seeks.value.isEmpty)
    }

    func testDeviceTransferAfterRadioCommandPreventsSeekAndStateRestore() async {
        let checks = LockedBox(0)
        let completion = expectation(description: "device transferred")
        var result: Result<Void, SpotifySongRadioError>?
        var injected = automation(snapshot: snapshot(), now: 100, seek: { _ in XCTFail("must not seek remote device") }, restorePlaybackState: { _ in XCTFail("must not play remote device") })
        injected.confirmLocalPlayback = {
            let count = checks.mutateAndReturn { $0 += 1; return $0 }
            return count < 3 ? .success(()) : .failure(.playbackOnAnotherDevice)
        }
        let controller = SpotifySongRadioController(spotifyIsRunning: { true }, automation: injected)
        controller.onCompletion = { _, value in result = value; completion.fulfill() }
        _ = controller.start(source: .corsair)
        await fulfillment(of: [completion], timeout: 1)
        XCTAssertEqual(failure(result), .playbackOnAnotherDevice)
    }

    func testPausedPositionBelowTwoSecondsIsRestoredExactly() async {
        let seeks = LockedBox<[TimeInterval]>([])
        let commands = LockedBox<[String]>([])
        let completion = expectation(description: "early paused position")
        let controller = SpotifySongRadioController(spotifyIsRunning: { true }, automation: automation(
            snapshot: snapshot(position: 0.75, playbackState: .paused), now: 108,
            seek: { position in seeks.mutate { $0.append(position) }; commands.mutate { $0.append("seek") } },
            restorePlaybackState: { state in
                XCTAssertEqual(state, .paused)
                commands.mutate { $0.append("pause") }
            }
        ))
        controller.onCompletion = { _, _ in completion.fulfill() }
        _ = controller.start(source: .razer)
        await fulfillment(of: [completion], timeout: 1)
        XCTAssertEqual(seeks.value, [0.75])
        XCTAssertEqual(commands.value, ["pause", "seek"])
    }

    func testSparseAccessibilityTreeAndPageShuffleAreNotPlayerProof() {
        var observation = SpotifyPlaybackDeviceGuard.PlayerObservation()
        XCTAssertFalse(observation.isComplete)
        observation.observe(labels: ["Play", "Connect to a device", "Enable Shuffle for Test song Radio"], inNowPlayingBar: false, inPlayerControls: false)
        XCTAssertFalse(observation.isComplete)
        XCTAssertNil(observation.contextTitle)
        observation.observe(labels: ["Now playing bar", "Connect to a device"], inNowPlayingBar: true, inPlayerControls: false)
        observation.observe(labels: ["Pause", "Enable Shuffle for Old playlist"], inNowPlayingBar: true, inPlayerControls: true)
        XCTAssertTrue(observation.isComplete)
        XCTAssertEqual(observation.contextTitle, "Old playlist")
        observation.observe(labels: ["Disable Shuffle for Test song Radio"], inNowPlayingBar: true, inPlayerControls: true)
        XCTAssertNil(observation.contextTitle)
    }

    func testLockedSessionRejectsBeforeInspectingSpotify() {
        let spotifyChecks = LockedBox(0)
        let controller = SpotifySongRadioController(
            spotifyIsRunning: {
                spotifyChecks.mutate { $0 += 1 }
                return true
            },
            inputAllowed: { false },
            automation: automation(snapshot: snapshot(), now: 100)
        )

        XCTAssertEqual(controller.start(source: .corsair), .inputBlocked)
        XCTAssertEqual(spotifyChecks.value, 0)
    }

    func testMissingSpotifyIsReportedBeforeStartingAutomation() {
        let controller = SpotifySongRadioController(
            spotifyIsRunning: { false },
            inputAllowed: { true },
            automation: automation(snapshot: snapshot(), now: 100)
        )

        XCTAssertEqual(controller.start(source: .corsair), .spotifyNotRunning)
    }

    private func automation(
        snapshot: SpotifySongRadioSnapshot,
        now: TimeInterval,
        seek: @escaping @Sendable (TimeInterval) -> Void = { _ in },
        restorePlaybackState: @escaping @Sendable (
            SpotifySongRadioPlaybackState
        ) -> Void = { _ in }
    ) -> SpotifySongRadioAutomation {
        let position = LockedBox(snapshot.position)
        let playbackState = LockedBox(snapshot.playbackState)
        return SpotifySongRadioAutomation(
            confirmLocalPlayback: { .success(()) },
            capture: { .success(SpotifySongRadioSnapshot(
                trackURI: snapshot.trackURI, trackName: snapshot.trackName,
                position: position.value, duration: snapshot.duration,
                playbackState: playbackState.value, capturedAtUptime: snapshot.capturedAtUptime
            )) },
            startRadio: { _ in .success(()) },
            currentTrackURI: { .success(snapshot.trackURI) },
            confirmRadioContext: { _ in .success(true) },
            seek: { target in position.mutate { $0 = target }; seek(target); return .success(()) },
            restorePlaybackState: { state in
                playbackState.mutate { $0 = state }
                restorePlaybackState(state)
                return .success(())
            },
            now: { now },
            sleep: { _ in }
        )
    }

    func testSuccessfulSeekResponseWithoutPlayheadChangeIsNotSuccess() async {
        let completion = expectation(description: "seek not applied")
        var result: Result<Void, SpotifySongRadioError>?
        var injected = automation(snapshot: snapshot(), now: 106)
        injected.seek = { _ in .success(()) }
        let controller = SpotifySongRadioController(spotifyIsRunning: { true }, automation: injected)
        controller.onCompletion = { _, value in result = value; completion.fulfill() }
        _ = controller.start(source: .corsair)
        await fulfillment(of: [completion], timeout: 1)
        XCTAssertEqual(failure(result), .positionNotRestored)
    }

    private func snapshot(
        position: TimeInterval = 40,
        duration: TimeInterval = 200,
        playbackState: SpotifySongRadioPlaybackState = .playing,
        capturedAtUptime: TimeInterval = 100
    ) -> SpotifySongRadioSnapshot {
        SpotifySongRadioSnapshot(
            trackURI: "spotify:track:AbC123",
            trackName: "Test song",
            position: position,
            duration: duration,
            playbackState: playbackState,
            capturedAtUptime: capturedAtUptime
        )
    }

    private func assertSuccess(
        _ result: Result<Void, SpotifySongRadioError>?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            return XCTFail("expected success, got \(String(describing: result))", file: file, line: line)
        }
    }

    private func failure(
        _ result: Result<Void, SpotifySongRadioError>?
    ) -> SpotifySongRadioError? {
        guard case .failure(let error) = result else { return nil }
        return error
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storedValue)
    }

    func mutateAndReturn<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&storedValue)
    }
}
