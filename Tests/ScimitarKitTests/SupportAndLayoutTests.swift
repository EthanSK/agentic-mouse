import CICUEBridge
import XCTest
@testable import ScimitarKit

/// Keymap geometry, HUD derivation, redaction, colour utilities and config.
final class KeymapGeometryTests: XCTestCase {

    func testThePhysicalGridIsFourColumnsOfThree() {
        // Corsair numbers the pad front-to-back in columns of three.
        XCTAssertEqual(MultiTapKey.k1.physicalColumn, 0)
        XCTAssertEqual(MultiTapKey.k3.physicalColumn, 0)
        XCTAssertEqual(MultiTapKey.k4.physicalColumn, 1)
        XCTAssertEqual(MultiTapKey.k12.physicalColumn, 3)

        XCTAssertEqual(MultiTapKey.k1.physicalRow, 0)
        XCTAssertEqual(MultiTapKey.k2.physicalRow, 1)
        XCTAssertEqual(MultiTapKey.k3.physicalRow, 2)
    }

    func testRotatingTheGridGivesAPhoneKeypadWithMatchingNumbers() {
        // Physical column N becomes keypad row N, and the printed numbers
        // already line up — that coincidence is why the mapping is learnable.
        for key in MultiTapKey.allCases {
            XCTAssertEqual(key.keypadRow, key.physicalColumn)
            XCTAssertEqual(key.keypadColumn, key.physicalRow)
        }

        XCTAssertEqual(MultiTapKey.k1.keypadLegend, "1")
        XCTAssertEqual(MultiTapKey.k9.keypadLegend, "9")
        XCTAssertEqual(MultiTapKey.k10.keypadLegend, "*")
        XCTAssertEqual(MultiTapKey.k11.keypadLegend, "0")
        XCTAssertEqual(MultiTapKey.k12.keypadLegend, "#")
    }

    func testEveryButtonHasABehaviour() {
        for key in MultiTapKey.allCases {
            XCTAssertNotNil(MultiTapKeymap.classic[key], "button \(key.rawValue) must do something")
        }
    }

    func testButtonTwelveIsTheDedicatedExit() {
        XCTAssertEqual(MultiTapKeymap.classic.exitKey, .k12)
        XCTAssertEqual(MultiTapKeymap.classic[.k12]?.tapAction, .exitMode)
        XCTAssertTrue(MultiTapKeymap.classic[.k12]!.cycle.isEmpty, "the toggle must never type a letter")
    }

    func testTheFinalColumnCarriesTheCommands() {
        XCTAssertEqual(MultiTapKeymap.classic[.k10]?.tapAction, .backspace)
        XCTAssertEqual(MultiTapKeymap.classic[.k10]?.holdAction, .shiftCycle)
        XCTAssertEqual(MultiTapKeymap.classic[.k11]?.tapAction, .space)
        XCTAssertEqual(MultiTapKeymap.classic[.k11]?.holdAction, .newline)
        XCTAssertEqual(MultiTapKeymap.classic[.k11]?.numericCharacter, "0")
    }

    func testEveryLetterKeyHasItsDigitOnHold() {
        for key in [MultiTapKey.k1, .k2, .k3, .k4, .k5, .k6, .k7, .k8, .k9] {
            XCTAssertEqual(
                MultiTapKeymap.classic[key]?.numericCharacter,
                Character(String(key.rawValue)),
                "holding \(key.rawValue) must give the digit \(key.rawValue)"
            )
        }
    }

    func testCaseFoldingOfTheCycle() {
        let spec = MultiTapKeymap.classic[.k2]!
        XCTAssertEqual(spec.character(atCycleIndex: 0, shift: .lower), "a")
        XCTAssertEqual(spec.character(atCycleIndex: 0, shift: .upper), "A")
        XCTAssertEqual(spec.character(atCycleIndex: 1, shift: .initialCaps), "B")
        XCTAssertEqual(spec.character(atCycleIndex: 0, shift: .numeric), "2")
    }

    func testCycleIndexWrapsInBothDirections() {
        let spec = MultiTapKeymap.classic[.k2]!
        XCTAssertEqual(spec.character(atCycleIndex: 3, shift: .lower), "a")
        XCTAssertEqual(spec.character(atCycleIndex: -1, shift: .lower), "c")
    }

    func testShiftStateCycleIsAFourStepLoop() {
        var state = ShiftState.lower
        var seen: [ShiftState] = []
        for _ in 0..<4 {
            state = state.next
            seen.append(state)
        }
        XCTAssertEqual(seen, [.initialCaps, .upper, .numeric, .lower])
    }
}

final class HUDLayoutTests: XCTestCase {

    func testEveryHUDCardReservesHorizontalSpaceInsideItsBorder() {
        XCTAssertEqual(ModeHUDLayoutMetrics.cardHorizontalContentInset, 12)
    }

    private func snapshot(
        state: MultiTapState = MultiTapState(),
        now: TimeInterval = 0,
        source: MouseSource = .corsair
    ) -> HUDSnapshot {
        HUDSnapshot(
            isActive: true,
            source: source,
            keymap: .classic,
            state: state,
            multiTapTimeout: 0.9,
            now: now
        )
    }

    func testGridMatchesThePhysicalMouseLayout() {
        let grid = HUDLayout.grid(for: snapshot())
        XCTAssertEqual(grid.count, 3)
        XCTAssertEqual(grid[0].map(\.key.rawValue), [3, 6, 9, 12])
        XCTAssertEqual(grid[1].map(\.key.rawValue), [2, 5, 8, 11])
        XCTAssertEqual(grid[2].map(\.key.rawValue), [1, 4, 7, 10])
    }

    func testRazerGridMirrorsColumnsWithoutChangingCanonicalKeys() {
        var runtime = snapshot(source: .razer)
        runtime.keymap = .modesKeypad
        runtime.toggleKey = .k10
        let grid = HUDLayout.grid(for: runtime, toggleKey: runtime.toggleKey)
        XCTAssertEqual(grid[0].map(\.key.rawValue), [12, 9, 6, 3])
        XCTAssertEqual(grid[1].map(\.key.rawValue), [11, 8, 5, 2])
        XCTAssertEqual(grid[2].map(\.key.rawValue), [10, 7, 4, 1])
        XCTAssertEqual(grid[0].map(\.legend), ["10", "7", "4", "1"])
        XCTAssertEqual(grid[1].map(\.legend), ["11", "8", "5", "2"])
        XCTAssertEqual(grid[2].map(\.legend), ["12", "9", "6", "3"])
    }

    func testCellsCarryThePhoneLegendAndTheLetters() {
        let cell = HUDLayout.cell(for: .k7, snapshot: snapshot())
        XCTAssertEqual(cell.legend, "7")
        XCTAssertEqual(cell.cycle, ["p", "q", "r", "s"])
    }

    func testTheHudShowsWhichTapYouAreOn() {
        var state = MultiTapState(shift: .lower)
        state.pendingKey = .k7
        state.pendingCharacter = "r"
        state.pendingCycleIndex = 2
        state.pendingCycleLength = 4

        let cell = HUDLayout.cell(for: .k7, snapshot: snapshot(state: state))
        XCTAssertTrue(cell.isPending)
        XCTAssertEqual(cell.activeCycleIndex, 2)
        XCTAssertEqual(HUDLayout.pendingDescription(for: snapshot(state: state)), "r  ·  tap 3 of 4")
    }

    func testCellsFollowTheCaseState() {
        var state = MultiTapState(shift: .upper)
        XCTAssertEqual(HUDLayout.cell(for: .k2, snapshot: snapshot(state: state)).cycle, ["A", "B", "C"])

        state.shift = .numeric
        let numeric = HUDLayout.cell(for: .k2, snapshot: snapshot(state: state))
        XCTAssertEqual(numeric.caption, "2", "in 123 mode the HUD must not claim the key still types ABC")
    }

    func testTheToggleCellIsMarked() {
        XCTAssertTrue(HUDLayout.cell(for: .k12, snapshot: snapshot()).isModeToggle)
        XCTAssertFalse(HUDLayout.cell(for: .k1, snapshot: snapshot()).isModeToggle)
    }

    func testRuntimeKeypadMarksUniversalCellTenAndRestoresCellThreeDEF() {
        var runtime = snapshot()
        runtime.keymap = .modesKeypad
        runtime.toggleKey = .k10

        XCTAssertTrue(HUDLayout.cell(for: .k10, snapshot: runtime, toggleKey: runtime.toggleKey).isModeToggle)
        XCTAssertFalse(HUDLayout.cell(for: .k12, snapshot: runtime, toggleKey: runtime.toggleKey).isModeToggle)
        XCTAssertEqual(runtime.keymap[.k3]?.caption, "DEF")
        XCTAssertEqual(runtime.keymap[.k3]?.cycle, ["d", "e", "f"])
        XCTAssertEqual(runtime.keymap[.k11]?.caption, "SPACE")
        XCTAssertEqual(runtime.keymap[.k11]?.tapAction, .space)
        XCTAssertEqual(runtime.keymap[.k12]?.caption, "BACKSPACE")
        XCTAssertEqual(runtime.keymap[.k12]?.tapAction, .backspace)
        XCTAssertEqual(runtime.keymap[.k12]?.holdAction, .newline)
        XCTAssertEqual(HUDLayout.grid(for: runtime, toggleKey: runtime.toggleKey)[0].map(\.legend), ["3", "6", "9", "12"])
    }

    func testPunctuationPreviewPreservesEveryClassicPhoneSymbol() {
        let cell = HUDLayout.cell(for: .k1, snapshot: snapshot())

        XCTAssertEqual(cell.cycle, [".", ",", "?", "!", "'", "\"", "-", ":", ";", "/", "(", ")", "@"])
        XCTAssertEqual(cell.cycle.count, 13)
    }

    func testCancellationIsExplained() {
        var state = MultiTapState()
        state.lastCancellation = .targetChanged
        XCTAssertEqual(
            HUDLayout.pendingDescription(for: snapshot(state: state)),
            "Focus moved — pending letter discarded."
        )
    }

    func testARefusedTargetIsExplained() {
        var state = MultiTapState()
        state.targetRefusal = .notEditable
        XCTAssertTrue(HUDLayout.pendingDescription(for: snapshot(state: state)).contains("does not accept text"))
    }

    func testStatusLineShowsTheCaseIndicator() {
        let state = MultiTapState(shift: .initialCaps)
        XCTAssertTrue(HUDLayout.statusLine(for: snapshot(state: state)).contains("Abc"))
    }
}

final class RedactionTests: XCTestCase {

    func testTagsAreStableAndShort() {
        XCTAssertEqual(Redaction.tag("hello"), Redaction.tag("hello"))
        XCTAssertEqual(Redaction.tag("hello").count, 8)
        XCTAssertNotEqual(Redaction.tag("hello"), Redaction.tag("hellp"))
    }

    func testIdentifiersAndHostsNeverLeakTheOriginal() {
        let identifier = "CORSAIR-SCIMITAR-SERIAL-1234567890"
        let host = "192.168.1.42"
        XCTAssertFalse(Redaction.identifier(identifier).contains("1234567890"))
        XCTAssertFalse(Redaction.identifier(identifier).contains("SCIMITAR"))
        XCTAssertFalse(Redaction.host(host).contains("192"))
        XCTAssertFalse(Redaction.host(host).contains("42"))
    }

    func testSecretsAreNeverEchoed() {
        let key = "abcdefghijklmnopqrstuvwxyz1234567890ABCD"
        let redacted = Redaction.secret(key)
        XCTAssertFalse(redacted.contains(key))
        XCTAssertFalse(redacted.contains("abcdefgh"))
        XCTAssertEqual(Redaction.secret(nil), "<unset>")
        XCTAssertEqual(Redaction.secret(""), "<unset>")
    }

    func testModelNamesAreSanitisedButReadable() {
        XCTAssertEqual(Redaction.model("CORSAIR SCIMITAR ELITE WIRELESS SE"), "CORSAIR SCIMITAR ELITE WIRELESS SE")
        XCTAssertEqual(Redaction.model(""), "<unknown model>")
        XCTAssertFalse(Redaction.model("Model\u{0}\u{1}Name").contains("\u{0}"))
    }

    func testDeviceSummariesCarryOnlyRedactedIdentifiers() {
        let device = ICUEDevice(
            identifier: "secret-device-id",
            model: "CORSAIR SCIMITAR ELITE WIRELESS SE",
            ledCount: 2,
            channelCount: 0,
            typeMask: 2
        )
        XCTAssertFalse(device.summary.redactedIdentifier.contains("secret-device-id"))
        XCTAssertTrue(device.redactedIdentifier.hasPrefix("id:"))
    }
}

final class RGBColorTests: XCTestCase {

    func testHexRoundTrip() {
        XCTAssertEqual(RGBColor(hex: "#FF00A8"), RGBColor(red: 255, green: 0, blue: 168))
        XCTAssertEqual(RGBColor(hex: "FF00A8"), RGBColor(red: 255, green: 0, blue: 168))
        XCTAssertEqual(RGBColor(hex: "#F0A"), RGBColor(red: 255, green: 0, blue: 170))
        XCTAssertEqual(RGBColor(hex: "#FF00A880")?.alpha, 0x80)
        XCTAssertEqual(RGBColor(red: 255, green: 0, blue: 168).hexString, "#FF00A8")
    }

    func testInvalidHexIsRejected() {
        XCTAssertNil(RGBColor(hex: "nope"))
        XCTAssertNil(RGBColor(hex: "#12345"))
        XCTAssertNil(RGBColor(hex: ""))
    }

    func testBrightnessScalingClampsAndPreservesAlpha() {
        let color = RGBColor(red: 200, green: 100, blue: 50, alpha: 128)
        XCTAssertEqual(color.scaledBrightness(0.5), RGBColor(red: 100, green: 50, blue: 25, alpha: 128))
        XCTAssertEqual(color.scaledBrightness(-5), RGBColor(red: 0, green: 0, blue: 0, alpha: 128))
        XCTAssertEqual(color.scaledBrightness(5), color)
    }

    func testTransparentIsTheReleaseSignal() {
        XCTAssertEqual(RGBColor.transparent.alpha, 0)
    }
}

final class ConfigurationTests: XCTestCase {

    func testDefaultsAreTheSafeChoices() {
        let configuration = AppConfiguration.default
        XCTAssertEqual(configuration.multiTap.echoPolicy, .commitOnly)
        XCTAssertEqual(configuration.multiTap.focusChangePolicy, .cancelPending)
        XCTAssertEqual(configuration.input.transport, .icueMacroKey)
        XCTAssertEqual(configuration.input.toggleKey, 10)
        XCTAssertEqual(configuration.input.gridMacroKeys, Array(1...12))
        XCTAssertEqual(configuration.input.horizontalScrollLinesPerRatchet, 4)
        XCTAssertTrue(configuration.defaultMapHint.enabled)
        XCTAssertEqual(configuration.defaultMapHint.doubleClickInterval, 0.34)
        XCTAssertEqual(configuration.defaultMapHint.displayDuration, 0)
    }

    func testEverySourceOwnedHUDUsesTheMouseHandedCorner() {
        XCTAssertEqual(
            AppConfiguration.HUDConfiguration.sourceCorner(for: .corsair),
            .bottomRight
        )
        XCTAssertEqual(
            AppConfiguration.HUDConfiguration.sourceCorner(for: .razer),
            .bottomLeft
        )
        XCTAssertEqual(MouseSource.allCases.count, 2)
    }

    func testOlderConfigWithoutDefaultMapHintUsesTheCurrentEnabledDefault() throws {
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.defaultMapHint.enabled)
        XCTAssertEqual(decoded.defaultMapHint, AppConfiguration.default.defaultMapHint)
    }

    func testOlderConfigWithoutHorizontalScrollSensitivityUsesNormalFastDefault() throws {
        let data = Data(#"{"input":{"transport":"icueMacroKey"}}"#.utf8)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)

        XCTAssertEqual(decoded.input.horizontalScrollLinesPerRatchet, 4)
    }

    func testConfigurationRoundTripsThroughJSON() throws {
        var configuration = AppConfiguration.default
        configuration.input.fallbackBindings = ["k1": .mouseButton(3)]

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)
        XCTAssertEqual(decoded, configuration)
    }

    func testValidationFlagsTheRiskyChoices() {
        var configuration = AppConfiguration.default
        configuration.multiTap.echoPolicy = .livePreview
        configuration.input.transport = .cgEventTap
        configuration.lighting.layerPriority = 100

        let warnings = ConfigurationLoader.validate(configuration)
        XCTAssertTrue(warnings.contains { $0.contains("livePreview") })
        XCTAssertTrue(warnings.contains { $0.contains("cgEventTap") })
        XCTAssertTrue(warnings.contains { $0.contains("layerPriority") })
    }

    func testValidationExplainsWhenMultiTapHasNoMouseColourIndicator() {
        var configuration = AppConfiguration.default
        configuration.multiTap.enabled = true
        configuration.lighting.enabled = false

        let warnings = ConfigurationLoader.validate(configuration)
        XCTAssertTrue(warnings.contains { $0.contains("cannot show the configured mode colour") })
    }

    func testValidationCatchesAToggleOutsideTheGrid() {
        var configuration = AppConfiguration.default
        configuration.input.toggleKey = 13
        XCTAssertTrue(ConfigurationLoader.validate(configuration).contains { $0.contains("toggleKey") })
    }

    func testFallbackBindingsReverseToAllTwelveLogicalKeys() {
        var input = AppConfiguration.InputConfiguration()
        input.fallbackBindings = Dictionary(uniqueKeysWithValues: MultiTapKey.allCases.map {
            ("k\($0.rawValue)", .mouseButton($0.rawValue + 2))
        })

        let reversed = input.fallbackLogicalBindings
        XCTAssertEqual(reversed?[.mouseButton(3)], .k1)
        XCTAssertEqual(reversed?[.mouseButton(14)], .k12)
        XCTAssertEqual(reversed?.count, 12)
    }

    func testFallbackBindingsRejectMissingOrDuplicateSignals() {
        var input = AppConfiguration.InputConfiguration()
        input.fallbackBindings = ["k1": .mouseButton(3)]
        XCTAssertNil(input.fallbackLogicalBindings)

        input.fallbackBindings = Dictionary(uniqueKeysWithValues: MultiTapKey.allCases.map {
            ("k\($0.rawValue)", .mouseButton($0.rawValue + 2))
        })
        input.fallbackBindings["k12"] = input.fallbackBindings["k11"]
        XCTAssertNil(input.fallbackLogicalBindings)
    }

    func testFallbackBindingsRejectSignalsTheEventTapCannotObserve() {
        var input = AppConfiguration.InputConfiguration()
        input.fallbackBindings = Dictionary(uniqueKeysWithValues: MultiTapKey.allCases.map {
            ("k\($0.rawValue)", .mouseButton($0.rawValue + 2))
        })

        input.fallbackBindings["k4"] = .icueMacroKey(4)
        XCTAssertNil(input.fallbackLogicalBindings)
        input.fallbackBindings["k4"] = .mouseButton(0)
        XCTAssertNil(input.fallbackLogicalBindings)
        input.fallbackBindings["k4"] = .mouseButton(32)
        XCTAssertNil(input.fallbackLogicalBindings)
        input.fallbackBindings["k4"] = .keyCode(128, modifiers: [])
        XCTAssertNil(input.fallbackLogicalBindings)
    }

    func testSanitizationRestoresSafeTimingColourAndHUDRanges() {
        var configuration = AppConfiguration.default
        configuration.lighting.modeIndicatorPulsePeriod = -1
        configuration.lighting.modeIndicatorPulseDepth = 9
        configuration.lighting.maximumWritesPerSecond = 0
        configuration.multiTap.multiTapTimeout = -1
        configuration.multiTap.holdThreshold = 0
        configuration.multiTap.autoExitAfterIdle = -1
        configuration.multiTap.toggleDebounce = -1
        configuration.colorProof.autoExitAfterIdle = -1
        configuration.colorProof.absoluteTimeout = -1
        configuration.defaultMapHint.doubleClickInterval = 10
        configuration.defaultMapHint.displayDuration = -1
        configuration.hud.margin = -20
        configuration.hud.opacity = 4

        let result = ConfigurationLoader.sanitize(configuration)
        XCTAssertEqual(result.configuration.lighting.maximumWritesPerSecond, 30)
        XCTAssertEqual(result.configuration.multiTap.multiTapTimeout, 0.9)
        XCTAssertEqual(result.configuration.colorProof.autoExitAfterIdle, 0)
        XCTAssertEqual(result.configuration.colorProof.absoluteTimeout, 0)
        XCTAssertEqual(result.configuration.defaultMapHint.doubleClickInterval, 0.34)
        XCTAssertEqual(result.configuration.defaultMapHint.displayDuration, 0)
        XCTAssertEqual(result.configuration.hud.opacity, 0.96)
        XCTAssertGreaterThanOrEqual(result.warnings.count, 11)
    }

    func testColorProofZeroTimeoutsAreValidAndMeanExplicitExitOnly() {
        var configuration = AppConfiguration.default
        configuration.colorProof.autoExitAfterIdle = 0
        configuration.colorProof.absoluteTimeout = 0

        let result = ConfigurationLoader.sanitize(configuration)

        XCTAssertEqual(result.configuration.colorProof.autoExitAfterIdle, 0)
        XCTAssertEqual(result.configuration.colorProof.absoluteTimeout, 0)
        XCTAssertFalse(result.warnings.contains { $0.contains("colorProof") })
    }

    func testSanitizationRequiresTheAuditedGridAndARealSideButtonToggle() {
        var configuration = AppConfiguration.default
        configuration.input.gridMacroKeys = [1, 2, 2, 13]
        configuration.input.toggleKey = 99

        let result = ConfigurationLoader.sanitize(configuration)
        XCTAssertEqual(result.configuration.input.gridMacroKeys, Array(1...12))
        XCTAssertEqual(result.configuration.input.toggleKey, 10)
        XCTAssertTrue(result.warnings.contains { $0.contains("gridMacroKeys") })
        XCTAssertTrue(result.warnings.contains { $0.contains("toggleKey") })
    }

    func testHorizontalScrollSensitivityIsAdjustableWithinItsBoundedRange() {
        var configuration = AppConfiguration.default
        configuration.input.horizontalScrollLinesPerRatchet = 9

        let result = ConfigurationLoader.sanitize(configuration)

        XCTAssertEqual(result.configuration.input.horizontalScrollLinesPerRatchet, 9)
        XCTAssertFalse(result.warnings.contains { $0.contains("horizontalScrollLinesPerRatchet") })
    }

    func testSanitizationRestoresUnsafeHorizontalScrollSensitivity() {
        for unsafeValue in [0, 13] {
            var configuration = AppConfiguration.default
            configuration.input.horizontalScrollLinesPerRatchet = unsafeValue

            let result = ConfigurationLoader.sanitize(configuration)

            XCTAssertEqual(result.configuration.input.horizontalScrollLinesPerRatchet, 4)
            XCTAssertTrue(
                result.warnings.contains { $0.contains("horizontalScrollLinesPerRatchet") }
            )
        }
    }

    func testRuntimeConfigurationForcesTheUniversalExitCell() {
        var configuration = AppConfiguration.default
        configuration.input.toggleKey = 12

        let result = ConfigurationLoader.sanitize(configuration)

        XCTAssertEqual(result.configuration.input.toggleKey, 10)
        XCTAssertEqual(MultiTapKeymap.modesKeypad[.k10]?.tapAction, .exitMode)
        XCTAssertNotEqual(MultiTapKeymap.modesKeypad[.k12]?.tapAction, .exitMode)
        XCTAssertTrue(result.warnings.contains { $0.contains("universal runtime-mode exit") })
    }

    func testInputBindingCodableRoundTrip() throws {
        let bindings: [InputBinding] = [
            .icueMacroKey(12),
            .mouseButton(4),
            .keyCode(0x69, modifiers: [.command, .shift])
        ]
        for binding in bindings {
            let data = try JSONEncoder().encode(binding)
            XCTAssertEqual(try JSONDecoder().decode(InputBinding.self, from: data), binding)
        }
    }

    func testUnknownBindingKindIsRejected() {
        let json = #"{"kind":"telepathy"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(InputBinding.self, from: Data(json.utf8)))
    }
}

final class ICUECStringTests: XCTestCase {
    func testConnectRecoveryOnlyResetsInvalidOperation() {
        XCTAssertTrue(
            ICUEConnectRecoveryPolicy.shouldResetAndRetry(
                error: Int32(SC_ICUE_INVALID_OPERATION.rawValue)
            )
        )
        XCTAssertFalse(
            ICUEConnectRecoveryPolicy.shouldResetAndRetry(
                error: Int32(SC_ICUE_NOT_CONNECTED.rawValue)
            )
        )
        XCTAssertFalse(
            ICUEConnectRecoveryPolicy.shouldResetAndRetry(
                error: Int32(SC_ICUE_NOT_ALLOWED.rawValue)
            )
        )
    }

    func testFixedCStringStopsAtTheFirstNul() {
        var bytes: (CChar, CChar, CChar, CChar, CChar) = (65, 66, 0, 88, 89)
        XCTAssertEqual(ICUESession.string(from: &bytes), "AB")
    }

    func testFixedCStringWithoutANulNeverReadsPastTheTuple() {
        var bytes: (CChar, CChar, CChar, CChar) = (65, 66, 67, 68)
        XCTAssertEqual(ICUESession.string(from: &bytes), "ABCD")
    }
}

final class LogRedactionTests: XCTestCase {

    func testRecordingSinkCapturesWhatWasLogged() {
        let sink = RecordingLogSink()
        let log = Log(category: "test", sink: sink)
        log.info("device \(Redaction.identifier("very-secret-id"))")

        XCTAssertEqual(sink.entries.count, 1)
        XCTAssertFalse(sink.entries[0].message.contains("very-secret-id"))
    }

    func testTransportLogsDoNotContainTheRawDeviceIdentifier() throws {
        let sink = RecordingLogSink()
        let control = FakeICUEKeyControl(deviceIdentifier: "RAW-DEVICE-IDENTIFIER-0001")
        let transport = ICUEMacroKeyTransport(
            session: control,
            deviceIdentifier: "RAW-DEVICE-IDENTIFIER-0001",
            log: Log(category: "input", sink: sink)
        )
        try transport.start()
        try transport.beginInterception()
        transport.endInterception()

        for entry in sink.entries {
            XCTAssertFalse(
                entry.message.contains("RAW-DEVICE-IDENTIFIER-0001"),
                "device identifiers must never appear in logs"
            )
        }
    }
}
