import XCTest
@testable import ScimitarKit

/// The primary input route: raw exact-device macro-key events, and the
/// transactional interception that makes multi-tap mode modal.
final class ICUEMacroKeyTransportTests: XCTestCase {

    private var keyControl: FakeICUEKeyControl!
    private var transport: ICUEMacroKeyTransport!
    private var delegate: RecordingTransportDelegate!
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        clock = ManualClock()
        keyControl = FakeICUEKeyControl(deviceIdentifier: "scimitar-under-test")
        transport = ICUEMacroKeyTransport(
            session: keyControl,
            deviceIdentifier: "scimitar-under-test",
            clock: clock,
            log: Log(category: "test", sink: NullLogSink())
        )
        delegate = RecordingTransportDelegate()
        transport.delegate = delegate
    }

    // MARK: - Exact-device filtering

    func testEventsFromTheSelectedDeviceAreDelivered() throws {
        try transport.start()
        keyControl.emit(macroKeyId: 5, isPressed: true)

        XCTAssertEqual(delegate.events.count, 1)
        XCTAssertEqual(delegate.events.first?.binding, .icueMacroKey(5))
        XCTAssertEqual(delegate.events.first?.phase, .press)
    }

    func testEventsFromAnyOtherCorsairDeviceAreDiscarded() throws {
        try transport.start()
        keyControl.emit(macroKeyId: 5, isPressed: true, from: "some-other-mouse")
        keyControl.emit(macroKeyId: 3, isPressed: true, from: "a-keyboard-with-g-keys")

        XCTAssertTrue(
            delegate.events.isEmpty,
            "only the exact selected Scimitar may drive the mode"
        )
    }

    func testMacroKeysOutsideTheConfiguredGridAreIgnored() throws {
        try transport.start()
        keyControl.emit(macroKeyId: 17, isPressed: true)
        XCTAssertTrue(delegate.events.isEmpty)
    }

    func testDuplicatePressesAreCollapsed() throws {
        try transport.start()
        keyControl.emit(macroKeyId: 2, isPressed: true)
        keyControl.emit(macroKeyId: 2, isPressed: true)   // auto-repeat style
        keyControl.emit(macroKeyId: 2, isPressed: false)

        XCTAssertEqual(delegate.events.map(\.phase), [.press, .release])
    }

    func testAReleaseWithoutAPressIsIgnored() throws {
        try transport.start()
        keyControl.emit(macroKeyId: 2, isPressed: false)
        XCTAssertTrue(delegate.events.isEmpty)
    }

    func testLaterPressRecoversWhenThePreviousReleaseWasLost() throws {
        try transport.start()
        keyControl.emit(macroKeyId: 12, isPressed: true)
        clock.advance(by: 2)
        keyControl.emit(macroKeyId: 12, isPressed: true)

        XCTAssertEqual(delegate.events.map(\.phase), [.press, .release, .press])
        XCTAssertEqual(delegate.events.map(\.binding), Array(repeating: .icueMacroKey(12), count: 3))
    }

    // MARK: - Readiness

    func testPreflightPassesWhenEverythingIsHealthy() throws {
        try transport.start()
        XCTAssertTrue(transport.preflight().isReady)
    }

    func testPreflightFailsWhenTheMouseDoesNotReportAllTwelveButtons() throws {
        try transport.start()
        keyControl.macroKeys = Array(1...8)
        let readiness = transport.preflight()
        XCTAssertFalse(readiness.isReady)
        XCTAssertTrue(readiness.reasons.contains { $0.contains("macro keys") })
    }

    func testPreflightFailsWhenICUEIsNotConnected() {
        keyControl.isSessionUsable = false
        let readiness = transport.preflight()
        XCTAssertFalse(readiness.isReady)
        XCTAssertTrue(readiness.reasons.contains { $0.contains("iCUE") })
    }

    // MARK: - Transactional interception

    func testBeginInterceptionTakesInputOnlyExclusivityAndClaimsAllTwelveKeys() throws {
        try transport.start()
        try transport.beginInterception()

        XCTAssertTrue(transport.isInterceptionEnabled)
        XCTAssertEqual(keyControl.interceptedKeys, Set(1...12))
        XCTAssertEqual(
            keyControl.currentAccessLevel,
            .exclusiveKeyEvents,
            "must be CAL_ExclusiveKeyEventsListening — input only, lighting stays shared"
        )
    }

    func testTheRequestedAccessLevelIsExactlyTwo() throws {
        try transport.start()
        try transport.beginInterception()
        XCTAssertTrue(
            keyControl.calls.contains(.requestControl(level: 2)),
            "level 1 and 3 include exclusive lighting and are forbidden"
        )
        XCTAssertFalse(keyControl.calls.contains(.requestControl(level: 1)))
        XCTAssertFalse(keyControl.calls.contains(.requestControl(level: 3)))
    }

    func testEndInterceptionUnconfiguresEveryKeyAndReleasesControl() throws {
        try transport.start()
        try transport.beginInterception()
        transport.endInterception()

        XCTAssertFalse(transport.isInterceptionEnabled)
        XCTAssertTrue(keyControl.interceptedKeys.isEmpty)
        XCTAssertEqual(keyControl.currentAccessLevel, .shared)
        XCTAssertTrue(keyControl.isFullyReleased)
    }

    func testEndInterceptionIsIdempotent() throws {
        try transport.start()
        try transport.beginInterception()
        transport.endInterception()
        keyControl.resetCalls()
        transport.endInterception()

        XCTAssertTrue(keyControl.calls.isEmpty, "a second teardown must be a no-op")
    }

    // MARK: - All-or-nothing rollback

    func testRefusedKeyControlLeavesNothingBehind() throws {
        try transport.start()
        keyControl.requestControlCode = 7   // CE_NotAllowed

        XCTAssertThrowsError(try transport.beginInterception()) { error in
            guard case InputTransportError.keyControlRefused(let code) = error else {
                return XCTFail("expected keyControlRefused, got \(error)")
            }
            XCTAssertEqual(code, 7)
        }

        XCTAssertFalse(transport.isInterceptionEnabled)
        XCTAssertTrue(keyControl.interceptedKeys.isEmpty)
        XCTAssertEqual(keyControl.currentAccessLevel, .shared)
    }

    func testAFailureHalfwayThroughRollsBackEveryKeyAlreadyClaimed() throws {
        try transport.start()
        keyControl.configureCodes[7] = 4    // CE_InvalidArguments on the 7th key

        XCTAssertThrowsError(try transport.beginInterception()) { error in
            guard case InputTransportError.interceptionIncomplete(let configured, let failedKey, _) = error else {
                return XCTFail("expected interceptionIncomplete, got \(error)")
            }
            XCTAssertEqual(failedKey, 7)
            XCTAssertEqual(configured, 6, "keys 1…6 had been claimed")
        }

        XCTAssertTrue(
            keyControl.interceptedKeys.isEmpty,
            "a partial transaction must not survive; keys 1…6 have to be released again"
        )
        XCTAssertEqual(keyControl.currentAccessLevel, .shared)
        XCTAssertFalse(transport.isInterceptionEnabled)
        XCTAssertTrue(keyControl.isFullyReleased)
    }

    func testRollbackUnconfiguresInReverseOrder() throws {
        try transport.start()
        keyControl.configureCodes[4] = 4

        XCTAssertThrowsError(try transport.beginInterception())

        let unconfigured = keyControl.calls.compactMap { call -> Int? in
            if case .configure(let key, let intercepted) = call, !intercepted { return key }
            return nil
        }
        XCTAssertEqual(unconfigured, [3, 2, 1], "the last thing claimed is the first thing given back")
    }

    func testReleaseFailureDisconnectsRatherThanClaimingAnUnsafeRollbackSucceeded() throws {
        try transport.start()
        try transport.beginInterception()
        keyControl.releaseControlCode = 6

        transport.endInterception()

        XCTAssertTrue(keyControl.calls.contains(.disconnectForSafety))
        XCTAssertTrue(keyControl.isFullyReleased)
        XCTAssertFalse(keyControl.isSessionUsable)
        XCTAssertFalse(transport.isRunning)
        XCTAssertFalse(transport.isInterceptionEnabled)
    }

    func testUnconfigureFailureIsStillRestoredBySuccessfulControlRelease() throws {
        try transport.start()
        try transport.beginInterception()
        keyControl.unconfigureCodes[7] = 6

        transport.endInterception()

        XCTAssertFalse(keyControl.calls.contains(.disconnectForSafety))
        XCTAssertTrue(keyControl.isFullyReleased)
        XCTAssertTrue(transport.configuredKeys.isEmpty)
    }

    func testBeginInterceptionFailsClosedWhenTheMouseLosesButtonsMidSession() throws {
        try transport.start()
        keyControl.macroKeys = Array(1...11)

        XCTAssertThrowsError(try transport.beginInterception()) { error in
            guard case InputTransportError.macroKeysUnavailable(let expected, let found) = error else {
                return XCTFail("expected macroKeysUnavailable, got \(error)")
            }
            XCTAssertEqual(expected, 12)
            XCTAssertEqual(found, 11)
        }
        XCTAssertEqual(keyControl.currentAccessLevel, .shared, "control is never requested if the preflight fails")
    }

    func testBeginInterceptionRefusesWhenTheSessionIsDown() throws {
        try transport.start()
        keyControl.isSessionUsable = false
        XCTAssertThrowsError(try transport.beginInterception()) { error in
            XCTAssertEqual(error as? InputTransportError, .sessionNotConnected)
        }
    }

    // MARK: - Cleanup paths

    func testStoppingTheTransportAlsoReleasesInterception() throws {
        try transport.start()
        try transport.beginInterception()
        transport.stop()

        XCTAssertTrue(keyControl.isFullyReleased)
        XCTAssertFalse(transport.isRunning)
    }

    func testSessionLossClearsLocalStateWithoutCallingIntoADeadSdk() throws {
        try transport.start()
        try transport.beginInterception()
        keyControl.resetCalls()

        transport.handleSessionLoss()

        XCTAssertFalse(transport.isInterceptionEnabled)
        XCTAssertFalse(transport.isRunning)
        XCTAssertTrue(
            keyControl.calls.isEmpty,
            "there is no point calling an SDK that has already gone away"
        )
    }

    func testDeallocationReleasesInterception() throws {
        var scoped: ICUEMacroKeyTransport? = ICUEMacroKeyTransport(
            session: keyControl,
            deviceIdentifier: "scimitar-under-test",
            clock: clock,
            log: Log(category: "test", sink: NullLogSink())
        )
        try scoped?.start()
        try scoped?.beginInterception()
        XCTAssertEqual(keyControl.interceptedKeys.count, 12)

        scoped = nil
        XCTAssertTrue(keyControl.isFullyReleased, "even a dropped transport must hand the mouse back")
    }

    // MARK: - Scope

    func testOnlyTheTwelveSideButtonsAreEverConfigured() throws {
        try transport.start()
        try transport.beginInterception()

        let configured = Set(keyControl.calls.compactMap { call -> Int? in
            if case .configure(let key, _) = call { return key }
            return nil
        })
        XCTAssertEqual(
            configured,
            Set(1...12),
            "the wheel, the main clicks and the DPI Toggle button are not macro keys and must stay untouched"
        )
    }
}

// MARK: - Helpers

final class RecordingTransportDelegate: InputTransportDelegate {
    private(set) var events: [PhysicalInputEvent] = []
    private(set) var failures: [Error] = []

    func inputTransport(_ transport: InputTransport, didReceive event: PhysicalInputEvent) {
        events.append(event)
    }

    func inputTransport(_ transport: InputTransport, didFailWith error: Error) {
        failures.append(error)
    }
}
