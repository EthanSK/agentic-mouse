import XCTest
@testable import ScimitarKit

/// The line between *shared lighting* and *exclusive key events*.
///
/// These two things are easy to conflate and the project rules treat them very
/// differently: exclusive lighting is banned outright, while exclusive key
/// events (access level 2, documented as "exclusive key events, but shared
/// lightings") is required while multi-tap mode is active. These tests keep the
/// distinction from eroding.
final class AccessLevelSeparationTests: XCTestCase {

    func testOnlySharedAndExclusiveKeyEventsAreRepresentable() {
        // If someone adds a `.exclusiveLighting` case, this fails and they have
        // to come and read the rule.
        XCTAssertEqual(ICUEAccessLevel.shared.rawValue, 0)
        XCTAssertEqual(ICUEAccessLevel.exclusiveKeyEvents.rawValue, 2)
        XCTAssertNil(ICUEAccessLevel(rawValue: 1), "CAL_ExclusiveLightingControl must be unrepresentable")
        XCTAssertNil(ICUEAccessLevel(rawValue: 3), "CAL_ExclusiveLightingControlAndKeyEventsListening too")
    }

    func testInterceptionOnlyEverRequestsLevelTwo() throws {
        let control = FakeICUEKeyControl()
        let transport = ICUEMacroKeyTransport(
            session: control,
            deviceIdentifier: control.deviceIdentifier,
            log: Log(category: "test", sink: NullLogSink())
        )
        try transport.start()
        try transport.beginInterception()
        transport.endInterception()

        let requested = control.calls.compactMap { call -> Int32? in
            if case .requestControl(let level) = call { return level }
            return nil
        }
        XCTAssertEqual(requested, [2], "exactly one request, at the input-only level")
    }

    func testLightingKeepsWorkingWhileExclusiveKeyControlIsHeld() throws {
        // The whole justification for level 2 is that it does not take lighting.
        // Exercise both axes at once and confirm they do not interfere.
        let control = FakeICUEKeyControl()
        let transport = ICUEMacroKeyTransport(
            session: control,
            deviceIdentifier: control.deviceIdentifier,
            log: Log(category: "test", sink: NullLogSink())
        )
        let recorder = RecordingLightingController()
        let lighting = LightingCoordinator(
            controller: ThrottlingLightingController(
                wrapping: recorder,
                clock: ManualClock(),
                minimumInterval: 0
            ),
            modeStyle: ModeIndicatorStyle(pulse: nil),
            clock: ManualClock(),
            log: Log(category: "test", sink: NullLogSink())
        )

        lighting.setModeActive(true)

        try transport.start()
        try transport.beginInterception()
        XCTAssertEqual(control.currentAccessLevel, .exclusiveKeyEvents)

        XCTAssertEqual(lighting.winningSource, .modeIndicator)

        // Handing key control back must not disturb the lighting layer.
        let framesBefore = recorder.appliedFrames.count
        transport.endInterception()
        XCTAssertEqual(control.currentAccessLevel, .shared)
        XCTAssertEqual(
            recorder.appliedFrames.count,
            framesBefore,
            "releasing key control is an input-only operation and must not repaint the mouse"
        )
        XCTAssertEqual(lighting.winningSource, .modeIndicator)
    }

    func testTheModeIndicatorIsLightingOnlyAndSurvivesWithoutKeyControl() {
        // Lighting is shared, so it keeps working even if key control was never
        // granted — which is what lets a refused entry still show its reason.
        let recorder = RecordingLightingController()
        let coordinator = LightingCoordinator(
            controller: ThrottlingLightingController(
                wrapping: recorder,
                clock: ManualClock(),
                minimumInterval: 0
            ),
            modeStyle: ModeIndicatorStyle(pulse: nil),
            clock: ManualClock(),
            log: Log(category: "test", sink: NullLogSink())
        )

        coordinator.setAlert(LightingFrame(uniform: RGBColor(red: 255, green: 80, blue: 0)))
        XCTAssertEqual(coordinator.winningSource, .alert)
        coordinator.setAlert(nil)
        XCTAssertNil(coordinator.winningSource)
    }
}

/// The shared session exposes one macro-key callback slot. These cover the
/// lifecycle hazards around owning it.
final class TransportHandlerOwnershipTests: XCTestCase {

    func testAReplacementTransportKeepsReceivingEventsAfterTheOldOneStops() throws {
        let control = FakeICUEKeyControl()
        let log = Log(category: "test", sink: NullLogSink())

        let oldTransport = ICUEMacroKeyTransport(
            session: control,
            deviceIdentifier: control.deviceIdentifier,
            log: log
        )
        try oldTransport.start()

        // A reconnect builds a fresh transport before the old one is torn down.
        let newTransport = ICUEMacroKeyTransport(
            session: control,
            deviceIdentifier: control.deviceIdentifier,
            log: log
        )
        let delegate = RecordingTransportDelegate()
        newTransport.delegate = delegate
        try newTransport.start()

        // Stopping the superseded transport must not unsubscribe the live one.
        oldTransport.stop()

        control.emit(macroKeyId: 3, isPressed: true)
        XCTAssertEqual(
            delegate.events.count,
            1,
            "the replacement transport was silently unsubscribed by the old one's teardown"
        )
    }

    func testStoppingTheCurrentTransportDoesUnsubscribe() throws {
        let control = FakeICUEKeyControl()
        let transport = ICUEMacroKeyTransport(
            session: control,
            deviceIdentifier: control.deviceIdentifier,
            log: Log(category: "test", sink: NullLogSink())
        )
        let delegate = RecordingTransportDelegate()
        transport.delegate = delegate
        try transport.start()
        transport.stop()

        control.emit(macroKeyId: 3, isPressed: true)
        XCTAssertTrue(delegate.events.isEmpty, "a stopped transport must not keep receiving events")
    }

    func testHandlerOwnershipIsScopedPerSession() throws {
        let firstControl = FakeICUEKeyControl(deviceIdentifier: "first")
        let secondControl = FakeICUEKeyControl(deviceIdentifier: "second")
        let log = Log(category: "test", sink: NullLogSink())

        let first = ICUEMacroKeyTransport(
            session: firstControl,
            deviceIdentifier: firstControl.deviceIdentifier,
            log: log
        )
        let second = ICUEMacroKeyTransport(
            session: secondControl,
            deviceIdentifier: secondControl.deviceIdentifier,
            log: log
        )
        let firstDelegate = RecordingTransportDelegate()
        let secondDelegate = RecordingTransportDelegate()
        first.delegate = firstDelegate
        second.delegate = secondDelegate

        try first.start()
        try second.start()
        first.stop()

        firstControl.emit(macroKeyId: 3, isPressed: true)
        secondControl.emit(macroKeyId: 3, isPressed: true)
        XCTAssertTrue(firstDelegate.events.isEmpty)
        XCTAssertEqual(secondDelegate.events.count, 1)
    }

    func testRestartingTheSameTransportResubscribes() throws {
        let control = FakeICUEKeyControl()
        let transport = ICUEMacroKeyTransport(
            session: control,
            deviceIdentifier: control.deviceIdentifier,
            log: Log(category: "test", sink: NullLogSink())
        )
        let delegate = RecordingTransportDelegate()
        transport.delegate = delegate

        try transport.start()
        transport.stop()
        try transport.start()

        control.emit(macroKeyId: 3, isPressed: true)
        XCTAssertEqual(delegate.events.count, 1)
    }
}
