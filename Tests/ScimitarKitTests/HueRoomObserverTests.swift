import XCTest
@testable import ScimitarKit

/// Snapshot → stream → coalesce → deduplicate, and the read-only guarantee.
final class HueRoomObserverTests: XCTestCase {

    private let assignments = [
        HueLightAssignment(resourceIdentifier: "candle", cluster: .candleAndSofa, label: "Candle"),
        HueLightAssignment(resourceIdentifier: "sofa", cluster: .candleAndSofa, label: "Sofa"),
        HueLightAssignment(resourceIdentifier: "luster-a", cluster: .deskLusters, label: "Luster A"),
        HueLightAssignment(resourceIdentifier: "luster-b", cluster: .deskLusters, label: "Luster B")
    ]

    private func snapshotJSON() -> Data {
        Data("""
        {"errors":[],"data":[
          {"id":"candle","type":"light","on":{"on":true},"dimming":{"brightness":80},
           "color":{"xy":{"x":0.675,"y":0.322}}},
          {"id":"sofa","type":"light","on":{"on":true},"dimming":{"brightness":80},
           "color":{"xy":{"x":0.675,"y":0.322}}},
          {"id":"luster-a","type":"light","on":{"on":true},"dimming":{"brightness":60},
           "color":{"xy":{"x":0.167,"y":0.04}}},
          {"id":"luster-b","type":"light","on":{"on":true},"dimming":{"brightness":60},
           "color":{"xy":{"x":0.167,"y":0.04}}},
          {"id":"kitchen","type":"light","on":{"on":true},"dimming":{"brightness":100}}
        ]}
        """.utf8)
    }

    private func makeObserver(
        transport: StubHueTransport,
        coalescing: TimeInterval = 0.01,
        resnapshot: TimeInterval = 300
    ) -> HueRoomObserver {
        HueRoomObserver(
            transport: transport,
            configuration: .init(
                assignments: assignments,
                coalescingInterval: coalescing,
                resnapshotInterval: resnapshot
            ),
            log: Log(category: "test", sink: NullLogSink())
        )
    }

    // MARK: - Read-only contract

    func testOnlyGetRequestsAreEverIssued() async throws {
        let transport = StubHueTransport()
        transport.responses["light"] = .success(snapshotJSON())
        let observer = makeObserver(transport: transport)

        let frames = FrameCollector()
        await observer.setHandlers(
            onFrame: { frame in Task { await frames.append(frame) } },
            onStatus: { _ in }
        )
        await observer.start()
        try await Task.sleep(nanoseconds: 120_000_000)
        await observer.stop()

        // The only thing the observer ever asks the bridge for is a read of the
        // light collection. `HueReadOnlyTransport` has no put/post/delete member
        // at all, so this is a structural guarantee rather than a convention:
        // no code path in the project can change a light.
        XCTAssertEqual(transport.requestedPaths, ["light"])
    }

    // MARK: - Snapshot

    func testInitialSnapshotProducesATwoZoneFrame() async throws {
        let transport = StubHueTransport()
        transport.responses["light"] = .success(snapshotJSON())
        let observer = makeObserver(transport: transport)

        let frames = FrameCollector()
        await observer.setHandlers(
            onFrame: { frame in Task { await frames.append(frame) } },
            onStatus: { _ in }
        )
        await observer.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        let latest = await frames.latest
        let frame = try XCTUnwrap(latest ?? nil)
        XCTAssertGreaterThan(frame[.side]!.red, frame[.side]!.blue, "candle+sofa are red")
        XCTAssertGreaterThan(frame[.logo]!.blue, frame[.logo]!.red, "the lusters are blue")

        await observer.stop()
    }

    func testLightsOutsideTheConfiguredRoomAreIgnored() async throws {
        let transport = StubHueTransport()
        transport.responses["light"] = .success(snapshotJSON())
        let observer = makeObserver(transport: transport)
        await observer.setHandlers(onFrame: { _ in }, onStatus: { _ in })
        await observer.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        let states = await observer.currentStates
        XCTAssertNil(states["kitchen"], "the bridge streams the whole house; only the room matters")
        XCTAssertEqual(states.count, 4)

        await observer.stop()
    }

    // MARK: - Deltas

    func testABrightnessDeltaIsMergedRatherThanReplacingState() async throws {
        let transport = StubHueTransport()
        transport.responses["light"] = .success(snapshotJSON())
        let observer = makeObserver(transport: transport)
        await observer.setHandlers(onFrame: { _ in }, onStatus: { _ in })
        await observer.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        transport.emit(Data("""
        [{"type":"update","data":[{"id":"candle","type":"light","dimming":{"brightness":5}}]}]
        """.utf8))
        try await Task.sleep(nanoseconds: 120_000_000)

        let states = await observer.currentStates
        XCTAssertEqual(states["candle"]?.brightnessPercent ?? 0, 5, accuracy: 0.001)
        XCTAssertNotNil(states["candle"]?.chromaticity, "the colour must survive a brightness-only event")

        await observer.stop()
    }

    func testUnchangedFramesAreSuppressed() async throws {
        let transport = StubHueTransport()
        transport.responses["light"] = .success(snapshotJSON())
        let observer = makeObserver(transport: transport)

        let frames = FrameCollector()
        await observer.setHandlers(
            onFrame: { frame in Task { await frames.append(frame) } },
            onStatus: { _ in }
        )
        await observer.start()
        try await Task.sleep(nanoseconds: 150_000_000)
        let baseline = await frames.count

        // Re-send exactly the state the observer already has.
        for _ in 0..<5 {
            transport.emit(Data("""
            [{"type":"update","data":[{"id":"candle","type":"light","dimming":{"brightness":80}}]}]
            """.utf8))
        }
        try await Task.sleep(nanoseconds: 150_000_000)

        let finalCount = await frames.count
        XCTAssertEqual(finalCount, baseline, "identical state must never reach iCUE")
        await observer.stop()
    }

    func testABurstOfFadeEventsIsCoalesced() async throws {
        let transport = StubHueTransport()
        transport.responses["light"] = .success(snapshotJSON())
        let observer = makeObserver(transport: transport, coalescing: 0.08)

        let frames = FrameCollector()
        await observer.setHandlers(
            onFrame: { frame in Task { await frames.append(frame) } },
            onStatus: { _ in }
        )
        await observer.start()
        try await Task.sleep(nanoseconds: 150_000_000)
        let baseline = await frames.count

        // Twenty steps of a fade, as the bridge really sends them.
        for step in stride(from: 80, through: 20, by: -3) {
            transport.emit(Data("""
            [{"type":"update","data":[
              {"id":"candle","type":"light","dimming":{"brightness":\(step)}},
              {"id":"sofa","type":"light","dimming":{"brightness":\(step)}}
            ]}]
            """.utf8))
        }
        try await Task.sleep(nanoseconds: 250_000_000)

        let produced = await frames.count - baseline
        XCTAssertGreaterThan(produced, 0, "the fade must still be visible")
        XCTAssertLessThan(produced, 8, "but it must not become one iCUE write per event")

        await observer.stop()
    }

    // MARK: - Failure

    func testNothingConfiguredReleasesTheLayerImmediately() async throws {
        let transport = StubHueTransport()
        let observer = HueRoomObserver(
            transport: transport,
            configuration: .init(assignments: []),
            log: Log(category: "test", sink: NullLogSink())
        )

        let frames = FrameCollector()
        await observer.setHandlers(
            onFrame: { frame in Task { await frames.append(frame) } },
            onStatus: { _ in }
        )
        await observer.start()
        try await Task.sleep(nanoseconds: 80_000_000)

        let status = await observer.currentStatus
        XCTAssertEqual(status, .notConfigured)
        let latest = await frames.latest
        XCTAssertEqual(latest, .some(nil), "no configuration means hand the mouse back to iCUE")
    }

    func testAnUnreachableBridgeReleasesTheLayerRatherThanFreezing() async throws {
        let transport = StubHueTransport()
        transport.defaultResponse = .failure(HueTransportError.network("host unreachable"))
        let observer = makeObserver(transport: transport)

        let frames = FrameCollector()
        await observer.setHandlers(
            onFrame: { frame in Task { await frames.append(frame) } },
            onStatus: { _ in }
        )
        await observer.start()
        try await Task.sleep(nanoseconds: 200_000_000)

        let latest = await frames.latest
        XCTAssertEqual(latest, .some(nil), "a stale room colour must not be left frozen on the mouse")

        await observer.stop()
    }

    func testStoppingReleasesTheLayer() async throws {
        let transport = StubHueTransport()
        transport.responses["light"] = .success(snapshotJSON())
        let observer = makeObserver(transport: transport)

        let frames = FrameCollector()
        await observer.setHandlers(
            onFrame: { frame in Task { await frames.append(frame) } },
            onStatus: { _ in }
        )
        await observer.start()
        try await Task.sleep(nanoseconds: 150_000_000)
        await observer.stop()
        try await Task.sleep(nanoseconds: 60_000_000)

        let latest = await frames.latest
        XCTAssertEqual(latest, .some(nil))
    }

    func testStoppingDuringACoalescingWindowCannotReacquireTheLightingLayer() async throws {
        let transport = StubHueTransport()
        transport.responses["light"] = .success(snapshotJSON())
        let observer = makeObserver(transport: transport, coalescing: 0.2)
        let frames = FrameCollector()
        await observer.setHandlers(
            onFrame: { frame in Task { await frames.append(frame) } },
            onStatus: { _ in }
        )
        await observer.start()
        try await Task.sleep(nanoseconds: 150_000_000)
        transport.emit(Data("""
        [{"type":"update","data":[{
          "id":"candle","type":"light","dimming":{"brightness":5}
        }]}]
        """.utf8))
        try await Task.sleep(nanoseconds: 30_000_000)

        await observer.stop()
        try await Task.sleep(nanoseconds: 20_000_000)
        let countAfterStop = await frames.count
        try await Task.sleep(nanoseconds: 240_000_000)

        let finalCount = await frames.count
        let latest = await frames.latest
        XCTAssertEqual(finalCount, countAfterStop, "a cancelled fade task must not publish after stop")
        XCTAssertEqual(latest, .some(nil), "stop must remain the final release frame")
    }

    func testStreamFailureDuringCoalescingCannotRepaintAStaleFrame() async throws {
        let transport = StubHueTransport()
        transport.responses["light"] = .success(snapshotJSON())
        let observer = makeObserver(transport: transport, coalescing: 0.2)
        let frames = FrameCollector()
        await observer.setHandlers(
            onFrame: { frame in Task { await frames.append(frame) } },
            onStatus: { _ in }
        )
        await observer.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        transport.emit(Data("""
        [{"type":"update","data":[{
          "id":"candle","type":"light","dimming":{"brightness":5}
        }]}]
        """.utf8))
        try await Task.sleep(nanoseconds: 30_000_000)
        transport.finishStream(throwing: HueTransportError.network("link dropped"))
        try await Task.sleep(nanoseconds: 80_000_000)
        let countAfterRelease = await frames.count
        try await Task.sleep(nanoseconds: 220_000_000)

        let finalCount = await frames.count
        let latest = await frames.latest
        XCTAssertEqual(finalCount, countAfterRelease, "cancelled coalescing work must stay cancelled during reconnect backoff")
        XCTAssertEqual(latest, .some(nil), "the disconnect release must remain the final frame")
        await observer.stop()
    }

    func testRestartingTheSameObserverRepublishesTheSnapshot() async throws {
        let transport = StubHueTransport()
        transport.responses["light"] = .success(snapshotJSON())
        let observer = makeObserver(transport: transport)
        let frames = FrameCollector()
        await observer.setHandlers(
            onFrame: { frame in Task { await frames.append(frame) } },
            onStatus: { _ in }
        )

        await observer.start()
        try await Task.sleep(nanoseconds: 150_000_000)
        await observer.stop()
        let afterStop = await frames.count
        await observer.start()
        try await Task.sleep(nanoseconds: 150_000_000)

        let afterRestart = await frames.count
        XCTAssertGreaterThan(afterRestart, afterStop, "restart must repaint even when the room is unchanged")
        await observer.stop()
    }

    func testConfiguredLightMissingFromSnapshotCanRecoverFromAnEvent() async throws {
        let transport = StubHueTransport()
        transport.responses["light"] = .success(Data("""
        {"errors":[],"data":[
          {"id":"sofa","type":"light","on":{"on":true},"dimming":{"brightness":80}}
        ]}
        """.utf8))
        let observer = makeObserver(transport: transport)
        await observer.setHandlers(onFrame: { _ in }, onStatus: { _ in })
        await observer.start()
        try await Task.sleep(nanoseconds: 120_000_000)

        transport.emit(Data("""
        [{"type":"update","data":[{
          "id":"candle","type":"light","on":{"on":true},
          "dimming":{"brightness":35},"color":{"xy":{"x":0.675,"y":0.322}}
        }]}]
        """.utf8))
        try await Task.sleep(nanoseconds: 80_000_000)

        let states = await observer.currentStates
        XCTAssertEqual(states["candle"]?.isOn, true)
        XCTAssertEqual(states["candle"]?.brightnessPercent, 35)
        await observer.stop()
    }

    func testDelayedPeriodicSnapshotCannotOverwriteANewerStreamDelta() async throws {
        let transport = StubHueTransport()
        transport.responses["light"] = .success(snapshotJSON())
        transport.responseDelays[2] = 180_000_000
        let observer = makeObserver(transport: transport, resnapshot: 0.2)
        await observer.setHandlers(onFrame: { _ in }, onStatus: { _ in })
        await observer.start()

        // Let the initial snapshot finish and the delayed periodic GET begin.
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertGreaterThanOrEqual(transport.requestedPaths.count, 2)
        transport.emit(Data("""
        [{"type":"update","data":[{
          "id":"candle","type":"light","dimming":{"brightness":5}
        }]}]
        """.utf8))
        try await Task.sleep(nanoseconds: 220_000_000)

        let states = await observer.currentStates
        XCTAssertEqual(states["candle"]?.brightnessPercent, 5)
        await observer.stop()
    }
}

/// Actor so the `@Sendable` frame handler can collect results safely.
private actor FrameCollector {
    private var frames: [LightingFrame?] = []

    func append(_ frame: LightingFrame?) { frames.append(frame) }
    var count: Int { frames.count }
    var latest: LightingFrame?? { frames.last }
}
