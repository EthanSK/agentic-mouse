import XCTest
@testable import ScimitarKit

/// Precedence, restoration, deduplication, throttling and device selection.
final class LightingArbiterTests: XCTestCase {

    private let hueFrame = LightingFrame(logo: RGBColor(red: 10, green: 20, blue: 30),
                                         side: RGBColor(red: 40, green: 50, blue: 60))
    private let modeFrame = LightingFrame(uniform: RGBColor(red: 255, green: 0, blue: 168))
    private let alertFrame = LightingFrame(uniform: RGBColor(red: 255, green: 80, blue: 0))

    func testNothingConfiguredMeansReleaseTheLayer() {
        let arbiter = LightingArbiter()
        XCTAssertNil(arbiter.resolved)
        XCTAssertNil(arbiter.winningSource)
    }

    func testHueShowsWhenItIsTheOnlySource() {
        var arbiter = LightingArbiter()
        arbiter.set(.hueMirror, frame: hueFrame)
        XCTAssertEqual(arbiter.resolved, hueFrame)
        XCTAssertEqual(arbiter.winningSource, .hueMirror)
    }

    func testModeIndicatorOutranksHue() {
        var arbiter = LightingArbiter()
        arbiter.set(.hueMirror, frame: hueFrame)
        arbiter.set(.modeIndicator, frame: modeFrame)
        XCTAssertEqual(arbiter.resolved, modeFrame)
        XCTAssertEqual(arbiter.winningSource, .modeIndicator)
    }

    func testAlertOutranksEverything() {
        var arbiter = LightingArbiter()
        arbiter.set(.hueMirror, frame: hueFrame)
        arbiter.set(.modeIndicator, frame: modeFrame)
        arbiter.set(.alert, frame: alertFrame)
        XCTAssertEqual(arbiter.resolved, alertFrame)
    }

    func testClearingTheModeFallsBackToHue() {
        var arbiter = LightingArbiter()
        arbiter.set(.hueMirror, frame: hueFrame)
        arbiter.set(.modeIndicator, frame: modeFrame)
        arbiter.clear(.modeIndicator)
        XCTAssertEqual(arbiter.resolved, hueFrame)
    }

    func testClearingHueWhileTheModeIsActiveKeepsTheIndicator() {
        var arbiter = LightingArbiter()
        arbiter.set(.hueMirror, frame: hueFrame)
        arbiter.set(.modeIndicator, frame: modeFrame)
        arbiter.clear(.hueMirror)
        XCTAssertEqual(arbiter.resolved, modeFrame)
    }

    func testPriorityOrderIsTotalAndStable() {
        XCTAssertGreaterThan(LightingSource.alert.priority, LightingSource.modeIndicator.priority)
        XCTAssertGreaterThan(LightingSource.modeIndicator.priority, LightingSource.hueMirror.priority)
    }
}

final class ModeIndicatorTests: XCTestCase {

    func testTheIndicatorOverridesBothZones() {
        let style = ModeIndicatorStyle(pulse: nil)
        let frame = style.frame(at: 0)
        XCTAssertNotNil(frame[.logo])
        XCTAssertNotNil(frame[.side])
        XCTAssertNotEqual(frame[.logo], frame[.side], "the two zones differ so the mouse reads as 'in a mode'")
    }

    func testPulseIsDeterministicInTime() {
        let pulse = PulseStyle(period: 2, depth: 0.5)
        XCTAssertEqual(pulse.factor(at: 0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(pulse.factor(at: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(pulse.factor(at: 2), 1.0, accuracy: 0.0001)
        XCTAssertEqual(pulse.factor(at: 0.5), pulse.factor(at: 1.5), accuracy: 0.0001)
    }

    func testPulseWithZeroDepthIsAConstant() {
        XCTAssertEqual(PulseStyle(period: 2, depth: 0).factor(at: 0.7), 1.0, accuracy: 0.0001)
    }

    func testPulseNeverGoesFullyDarkAtTheDefaultDepth() {
        let style = ModeIndicatorStyle()
        for time in stride(from: 0.0, to: 3.2, by: 0.1) {
            let frame = style.frame(at: time)
            XCTAssertGreaterThan(
                frame[.side]!.relativeLuminance + frame[.logo]!.relativeLuminance,
                0.01,
                "the mode must stay visible throughout the pulse"
            )
        }
    }
}

final class LightingCoordinatorTests: XCTestCase {

    private var recorder: RecordingLightingController!
    private var throttle: ThrottlingLightingController!
    private var clock: ManualClock!
    private var coordinator: LightingCoordinator!

    private let roomFrame = LightingFrame(logo: RGBColor(red: 200, green: 120, blue: 40),
                                          side: RGBColor(red: 30, green: 60, blue: 200))

    override func setUp() {
        super.setUp()
        clock = ManualClock()
        recorder = RecordingLightingController()
        throttle = ThrottlingLightingController(wrapping: recorder, clock: clock, minimumInterval: 0)
        coordinator = LightingCoordinator(
            controller: throttle,
            modeStyle: ModeIndicatorStyle(pulse: nil),
            clock: clock,
            log: Log(category: "test", sink: NullLogSink())
        )
    }

    func testHueFramesReachTheDevice() {
        coordinator.updateHueFrame(roomFrame)
        XCTAssertEqual(recorder.appliedFrames.last, roomFrame)
    }

    func testModeOverridesHue() {
        coordinator.updateHueFrame(roomFrame)
        coordinator.setModeActive(true)

        XCTAssertEqual(coordinator.winningSource, .modeIndicator)
        XCTAssertNotEqual(recorder.appliedFrames.last, roomFrame)
    }

    func testHueKeepsUpdatingWhileTheModeIsActiveAndTheNewestFrameIsRestoredOnExit() {
        coordinator.updateHueFrame(roomFrame)
        coordinator.setModeActive(true)

        // The room changes while the mouse is showing the mode colour.
        let newerFrame = LightingFrame(uniform: RGBColor(red: 5, green: 250, blue: 5))
        clock.advance(by: 1)
        coordinator.updateHueFrame(newerFrame)

        XCTAssertEqual(coordinator.cachedHueFrame, newerFrame, "Hue must keep being cached under the override")
        XCTAssertEqual(coordinator.winningSource, .modeIndicator, "but it must not show yet")

        clock.advance(by: 1)
        coordinator.setModeActive(false)

        XCTAssertEqual(
            recorder.appliedFrames.last,
            newerFrame,
            "leaving the mode restores the *newest* room colour, not the one from when the mode started"
        )
    }

    func testHueGoingAwayWhileTheModeIsActiveReleasesTheLayerOnExit() {
        coordinator.updateHueFrame(roomFrame)
        coordinator.setModeActive(true)
        coordinator.updateHueFrame(nil)     // bridge unreachable
        coordinator.setModeActive(false)

        XCTAssertEqual(recorder.appliedFrames.last, .released)
        XCTAssertGreaterThan(recorder.releaseCount, 0)
    }

    func testReleaseEverythingClearsTheLayer() {
        coordinator.updateHueFrame(roomFrame)
        coordinator.releaseEverything()

        XCTAssertGreaterThan(recorder.releaseCount, 0)
        XCTAssertNil(coordinator.winningSource)
    }

    func testSessionLossThenRestoreRepaintsFromCache() {
        coordinator.updateHueFrame(roomFrame)
        coordinator.handleSessionLost()
        XCTAssertNil(coordinator.winningSource)

        recorder.reset()
        coordinator.handleSessionRestored()
        XCTAssertEqual(recorder.appliedFrames.last, roomFrame)
    }

    func testModeSurvivesAnICUEReconnect() {
        coordinator.setModeActive(true)
        coordinator.handleSessionLost()
        coordinator.handleSessionRestored()
        XCTAssertEqual(coordinator.winningSource, .modeIndicator)
    }

    func testModeExitEventuallyRestoresHueWhenRateLimited() {
        let delayedRecorder = RecordingLightingController()
        let delayedThrottle = ThrottlingLightingController(
            wrapping: delayedRecorder,
            clock: clock,
            minimumInterval: 0.1
        )
        let deferredScheduler = ManualTickScheduler()
        let delayedCoordinator = LightingCoordinator(
            controller: delayedThrottle,
            modeStyle: ModeIndicatorStyle(pulse: nil),
            clock: clock,
            log: Log(category: "test", sink: NullLogSink()),
            deferredFlushScheduler: deferredScheduler
        )

        delayedCoordinator.updateHueFrame(roomFrame)
        delayedCoordinator.setModeActive(true)
        clock.advance(by: 0.11)
        deferredScheduler.fire()
        XCTAssertNotEqual(delayedRecorder.appliedFrames.last, roomFrame)

        delayedCoordinator.setModeActive(false)
        XCTAssertTrue(delayedThrottle.hasDeferredFrame)
        clock.advance(by: 0.11)
        deferredScheduler.fire()

        XCTAssertEqual(delayedRecorder.appliedFrames.last, roomFrame)
        XCTAssertFalse(delayedThrottle.hasDeferredFrame)
    }
}

final class ThrottlingLightingControllerTests: XCTestCase {

    func testIdenticalFramesAreNeverResent() throws {
        let recorder = RecordingLightingController()
        let clock = ManualClock()
        let throttle = ThrottlingLightingController(wrapping: recorder, clock: clock, minimumInterval: 0)

        let frame = LightingFrame(uniform: .white)
        try throttle.apply(frame)
        try throttle.apply(frame)
        try throttle.apply(frame)

        XCTAssertEqual(recorder.appliedFrames.count, 1)
        XCTAssertEqual(throttle.suppressedCount, 2)
    }

    func testWritesAreRateLimited() throws {
        let recorder = RecordingLightingController()
        let clock = ManualClock()
        let throttle = ThrottlingLightingController(wrapping: recorder, clock: clock, minimumInterval: 0.1)

        try throttle.apply(LightingFrame(uniform: .white))
        try throttle.apply(LightingFrame(uniform: .black))     // too soon
        XCTAssertEqual(recorder.appliedFrames.count, 1)

        clock.advance(by: 0.2)
        try throttle.flushDeferred()
        XCTAssertEqual(recorder.appliedFrames.count, 2, "the held-back frame is not lost, just delayed")
        XCTAssertEqual(recorder.appliedFrames.last, LightingFrame(uniform: .black))
    }

    func testReturningToTheCurrentFrameCancelsAStaleDeferredFrame() throws {
        let recorder = RecordingLightingController()
        let clock = ManualClock()
        let throttle = ThrottlingLightingController(wrapping: recorder, clock: clock, minimumInterval: 0.1)
        let current = LightingFrame(uniform: .white)

        try throttle.apply(current)
        try throttle.apply(LightingFrame(uniform: .black))
        try throttle.apply(current)
        clock.advance(by: 0.2)
        try throttle.flushDeferred()

        XCTAssertEqual(recorder.appliedFrames, [current])
        XCTAssertFalse(throttle.hasDeferredFrame)
    }

    func testInvalidatingTheCacheForcesTheNextWrite() throws {
        let recorder = RecordingLightingController()
        let throttle = ThrottlingLightingController(
            wrapping: recorder,
            clock: ManualClock(),
            minimumInterval: 0
        )
        let frame = LightingFrame(uniform: .white)

        try throttle.apply(frame)
        throttle.invalidateCache()
        try throttle.apply(frame)

        XCTAssertEqual(recorder.appliedFrames.count, 2, "after a reconnect the device's real state is unknown")
    }
}

final class ReleasedFrameTests: XCTestCase {

    func testReleasedFrameIsFullyTranslucent() {
        XCTAssertTrue(LightingFrame.released.isReleased)
        for zone in MouseZone.allCases {
            XCTAssertEqual(LightingFrame.released[zone]?.alpha, 0)
        }
    }

    func testBlackoutIsNotTheSameAsReleased() {
        XCTAssertFalse(LightingFrame.blackout.isReleased)
        XCTAssertEqual(LightingFrame.blackout[.logo]?.alpha, 255)
    }
}

final class DeviceSelectorTests: XCTestCase {

    private func device(_ model: String, id: String, leds: Int = 2) -> ICUEDevice {
        ICUEDevice(identifier: id, model: model, ledCount: leds, channelCount: 0, typeMask: 2)
    }

    func testSelectsTheScimitarByModel() {
        let devices = [
            device("CORSAIR HARPOON RGB WIRELESS", id: "a"),
            device("CORSAIR SCIMITAR ELITE WIRELESS SE", id: "b")
        ]
        let result = DeviceSelector.select(from: devices, using: .scimitar)
        XCTAssertEqual(result.device?.identifier, "b")
    }

    func testFailsClosedWhenNothingMatches() {
        let devices = [device("CORSAIR HARPOON RGB WIRELESS", id: "a")]
        let result = DeviceSelector.select(from: devices, using: .scimitar)
        XCTAssertNil(result.device)
        if case .noMatch(let count) = result { XCTAssertEqual(count, 1) } else { XCTFail("expected noMatch") }
    }

    func testFailsClosedWithNoDevicesAtAll() {
        let result = DeviceSelector.select(from: [], using: .scimitar)
        XCTAssertNil(result.device)
    }

    func testRefusesToGuessBetweenTwoMatchingMice() {
        let devices = [
            device("CORSAIR SCIMITAR ELITE WIRELESS SE", id: "a"),
            device("CORSAIR SCIMITAR RGB ELITE", id: "b")
        ]
        let result = DeviceSelector.select(from: devices, using: .scimitar)
        XCTAssertNil(result.device, "two Scimitars must not be resolved by luck")
        if case .ambiguous(let count) = result { XCTAssertEqual(count, 2) } else { XCTFail("expected ambiguous") }
    }

    func testADeviceTagPinsOneExactUnitWithoutStoringItsRealId() {
        let devices = [
            device("CORSAIR SCIMITAR ELITE WIRELESS SE", id: "unit-one"),
            device("CORSAIR SCIMITAR ELITE WIRELESS SE", id: "unit-two")
        ]
        let matcher = DeviceMatcher(deviceTag: Redaction.tag("unit-two"))
        let result = DeviceSelector.select(from: devices, using: matcher)

        XCTAssertEqual(result.device?.identifier, "unit-two")
        XCTAssertNotEqual(matcher.deviceTag, "unit-two", "the config stores only a hash")
    }

    func testDisplayedRedactedIdentifierIsAcceptedAsDeviceTag() {
        let target = device("CORSAIR SCIMITAR ELITE WIRELESS SE", id: "unit-two")
        let matcher = DeviceMatcher(deviceTag: target.redactedIdentifier.uppercased())

        XCTAssertTrue(matcher.matches(target), "the copy-ready id:xxxxxxxx doctor value must work directly")
    }

    func testSelectionIsDeterministicWhenAmbiguityIsExplicitlyAllowed() {
        let devices = [
            device("CORSAIR SCIMITAR ELITE WIRELESS SE", id: "a", leds: 2),
            device("CORSAIR SCIMITAR RGB ELITE", id: "b", leds: 5)
        ]
        let matcher = DeviceMatcher(requiresUniqueMatch: false)
        XCTAssertEqual(DeviceSelector.select(from: devices, using: matcher).device?.identifier, "b")
        XCTAssertEqual(
            DeviceSelector.select(from: devices.reversed(), using: matcher).device?.identifier,
            "b",
            "enumeration order must not change the answer"
        )
    }

    func testAuthoritativeDisconnectExclusionSurvivesStaleEnumeration() {
        let staleDisconnected = device("CORSAIR SCIMITAR ELITE WIRELESS SE", id: "a")
        let healthyReplacement = device("CORSAIR SCIMITAR ELITE WIRELESS SE", id: "b")

        let result = DeviceSelector.select(
            from: [staleDisconnected, healthyReplacement],
            excluding: ["a"],
            using: .scimitar
        )

        XCTAssertEqual(result.device?.identifier, "b")
    }
}

final class ICUELightingControllerSelectionTests: XCTestCase {
    private let logo = UInt32(0x40001)
    private let side = UInt32(0x40002)

    func testAmbiguityReleasesStillReachablePreviousMouse() throws {
        let session = FakeLightingSession()
        session.currentDevices = [device("a")]
        session.currentLEDs["a"] = leds
        let controller = makeController(session: session)
        _ = controller.refreshDevice()
        try controller.apply(LightingFrame(uniform: .white))

        session.currentDevices = [device("a"), device("b")]
        session.currentLEDs["b"] = leds
        _ = controller.refreshDevice()

        XCTAssertEqual(session.colorWrites.last?.deviceIdentifier, "a")
        XCTAssertTrue(session.colorWrites.last?.colors.allSatisfy { $0.color.alpha == 0 } == true)
        XCTAssertNil(controller.device)
    }

    func testSwitchingSelectionReleasesOldMouseBeforeSelectingNewOne() throws {
        let session = FakeLightingSession()
        session.currentDevices = [device("a", ledCount: 2)]
        session.currentLEDs["a"] = leds
        let controller = makeController(
            session: session,
            matcher: DeviceMatcher(requiresUniqueMatch: false)
        )
        _ = controller.refreshDevice()
        try controller.apply(LightingFrame(uniform: .white))

        session.currentDevices = [device("a", ledCount: 2), device("b", ledCount: 4)]
        session.currentLEDs["b"] = leds
        _ = controller.refreshDevice()

        XCTAssertEqual(session.colorWrites.last?.deviceIdentifier, "a")
        XCTAssertTrue(session.colorWrites.last?.colors.allSatisfy { $0.color.alpha == 0 } == true)
        XCTAssertEqual(controller.device?.redactedIdentifier, Redaction.identifier("b"))
    }

    func testExplicitlyDisconnectedMouseIsForgottenWithoutAWrite() throws {
        let session = FakeLightingSession()
        session.currentDevices = [device("a")]
        session.currentLEDs["a"] = leds
        let controller = makeController(session: session)
        _ = controller.refreshDevice()
        try controller.apply(LightingFrame(uniform: .white))
        let writesBeforeDisconnect = session.colorWrites.count

        _ = controller.refreshDevice(excluding: ["a"])

        XCTAssertEqual(session.colorWrites.count, writesBeforeDisconnect)
        XCTAssertNil(controller.device)
    }

    func testFailedPreviousMouseReleaseDisconnectsTheSDKClient() throws {
        let session = FakeLightingSession()
        session.currentDevices = [device("a")]
        session.currentLEDs["a"] = leds
        let controller = makeController(session: session)
        _ = controller.refreshDevice()
        try controller.apply(LightingFrame(uniform: .white))

        session.setColorsCode = 6
        session.currentDevices = [device("a"), device("b")]
        session.currentLEDs["b"] = leds
        _ = controller.refreshDevice()

        XCTAssertEqual(session.safetyDisconnectCount, 1)
        XCTAssertEqual(session.state, .closed)
        XCTAssertNil(controller.device, "a replacement must not be selected after an unproven old-layer release")
    }

    func testSameMouseTopologyChangeReleasesPreviouslyKnownLuids() throws {
        let session = FakeLightingSession()
        session.currentDevices = [device("a")]
        session.currentLEDs["a"] = leds
        let controller = makeController(session: session)
        _ = controller.refreshDevice()
        try controller.apply(LightingFrame(uniform: .white))

        session.currentLEDs["a"] = [ICUELed(luid: logo, x: 0, y: 0)]
        _ = controller.refreshDevice()

        XCTAssertEqual(Set(session.colorWrites.last?.colors.map(\.luid) ?? []), [logo, side])
        XCTAssertTrue(session.colorWrites.last?.colors.allSatisfy { $0.color.alpha == 0 } == true)
    }

    func testDirectReleaseFailureDisconnectsInsteadOfLeavingAStaleLayer() throws {
        let session = FakeLightingSession()
        session.currentDevices = [device("a")]
        session.currentLEDs["a"] = leds
        let controller = makeController(session: session)
        _ = controller.refreshDevice()
        try controller.apply(LightingFrame(uniform: .white))

        session.setColorsCode = 6
        try controller.release()

        XCTAssertEqual(session.safetyDisconnectCount, 1)
        XCTAssertEqual(session.state, .closed)
    }

    private var leds: [ICUELed] {
        [ICUELed(luid: logo, x: 0, y: 0), ICUELed(luid: side, x: 1, y: 0)]
    }

    private func device(_ identifier: String, ledCount: Int = 2) -> ICUEDevice {
        ICUEDevice(
            identifier: identifier,
            model: "CORSAIR SCIMITAR ELITE WIRELESS SE",
            ledCount: ledCount,
            channelCount: 0,
            typeMask: 2
        )
    }

    private func makeController(
        session: FakeLightingSession,
        matcher: DeviceMatcher = .scimitar
    ) -> ICUELightingController {
        ICUELightingController(
            sessionFacade: session,
            matcher: matcher,
            log: Log(category: "test", sink: NullLogSink())
        )
    }
}

private final class FakeLightingSession: ICUELightingSession {
    struct ColorWrite {
        let deviceIdentifier: String
        let colors: [(luid: UInt32, color: ScimitarKit.RGBColor)]
    }

    var isLibraryLoaded = true
    var state: ICUESessionState = .connected
    var currentDevices: [ICUEDevice] = []
    var currentLEDs: [String: [ICUELed]] = [:]
    var colorWrites: [ColorWrite] = []
    var setColorsCode: Int32 = 0
    var safetyDisconnectCount = 0

    func devices(typeMask: Int32) -> [ICUEDevice] { currentDevices }
    func leds(of deviceIdentifier: String) -> [ICUELed] { currentLEDs[deviceIdentifier] ?? [] }
    func setLayerPriority(_ priority: UInt32) -> Int32 { 0 }
    func setColors(
        deviceIdentifier: String,
        colors: [(luid: UInt32, color: ScimitarKit.RGBColor)]
    ) -> Int32 {
        colorWrites.append(ColorWrite(deviceIdentifier: deviceIdentifier, colors: colors))
        return setColorsCode
    }
    func disconnectForLightingSafety() {
        safetyDisconnectCount += 1
        state = .closed
    }
}
