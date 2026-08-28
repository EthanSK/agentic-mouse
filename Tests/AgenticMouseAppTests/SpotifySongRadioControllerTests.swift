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
        releaseCapture.mutate { $0 = true }
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
        SpotifySongRadioAutomation(
            capture: { .success(snapshot) },
            startRadio: { _ in .success(()) },
            currentTrackURI: { .success(snapshot.trackURI) },
            seek: { position in seek(position); return .success(()) },
            restorePlaybackState: { state in
                restorePlaybackState(state)
                return .success(())
            },
            now: { now },
            sleep: { _ in }
        )
    }

    private func snapshot(
        position: TimeInterval = 40,
        duration: TimeInterval = 200,
        playbackState: SpotifySongRadioPlaybackState = .playing,
        capturedAtUptime: TimeInterval = 100
    ) -> SpotifySongRadioSnapshot {
        SpotifySongRadioSnapshot(
            trackURI: "spotify:track:AbC123",
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
}
