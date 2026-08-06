import XCTest
@testable import ScimitarKit

/// Colour conversion, two-cluster aggregation, exact LUID mapping, and the
/// event-stream parsing/merging rules.
final class HueColorConversionTests: XCTestCase {

    func testWarmWhiteIsWarm() {
        // 2700 K ≈ 370 mirek.
        let color = HueColorConverter.fromMirek(370)
        XCTAssertGreaterThan(color.red, color.green)
        XCTAssertGreaterThan(color.green, color.blue)
        XCTAssertGreaterThan(color.red, 200)
    }

    func testCoolWhiteIsCool() {
        let color = HueColorConverter.fromMirek(153)   // ≈ 6500 K
        XCTAssertGreaterThanOrEqual(color.blue, color.red - 20)
    }

    func testColourTemperatureRampIsMonotonicInBlueness() {
        var previousRatio = -Double.infinity
        for kelvin in stride(from: 2000.0, through: 6500.0, by: 500) {
            let color = HueColorConverter.fromKelvin(kelvin)
            let ratio = Double(color.blue) / max(1, Double(color.red))
            XCTAssertGreaterThan(ratio, previousRatio, "\(kelvin)K should be bluer than the step before")
            previousRatio = ratio
        }
    }

    func testPrimariesLandOnTheRightHue() {
        let red = HueColorConverter.fromChromaticity(x: 0.675, y: 0.322)
        XCTAssertGreaterThan(red.red, 200)
        XCTAssertLessThan(red.green, 120)

        let green = HueColorConverter.fromChromaticity(x: 0.409, y: 0.518)
        XCTAssertGreaterThan(green.green, 200)

        let blue = HueColorConverter.fromChromaticity(x: 0.167, y: 0.04)
        XCTAssertGreaterThan(blue.blue, 200)
        XCTAssertLessThan(blue.red, 120)
    }

    func testDegenerateChromaticityFallsBackToWhiteInsteadOfDividingByZero() {
        XCTAssertEqual(HueColorConverter.fromChromaticity(x: 0.3, y: 0), .white)
        XCTAssertEqual(HueColorConverter.fromChromaticity(x: .nan, y: .nan), .white)
    }

    func testOutOfGamutColoursDesaturateRatherThanClip() {
        // A chromaticity outside sRGB must still yield a sane, non-black colour.
        let color = HueColorConverter.fromChromaticity(x: 0.7, y: 0.28)
        XCTAssertGreaterThan(Int(color.red) + Int(color.green) + Int(color.blue), 100)
    }

    // MARK: - Brightness policy

    func testBrightnessFloorKeepsADimLampVisible() {
        let policy = HueMirrorPolicy(brightnessFloor: 0.2)
        let state = HueLightState(identifier: "a", isOn: true, brightnessPercent: 1, mirek: 370, mirekValid: true)
        XCTAssertGreaterThanOrEqual(HueColorConverter.effectiveBrightness(for: state, policy: policy), 0.2)
    }

    func testFullBrightnessReachesTheCeiling() {
        let policy = HueMirrorPolicy(brightnessFloor: 0.1, brightnessCeiling: 1.0)
        let state = HueLightState(identifier: "a", isOn: true, brightnessPercent: 100)
        XCTAssertEqual(HueColorConverter.effectiveBrightness(for: state, policy: policy), 1.0, accuracy: 0.0001)
    }

    func testBrightnessIsMonotonic() {
        let policy = HueMirrorPolicy.default
        var previous = -1.0
        for percent in stride(from: 0.0, through: 100.0, by: 10) {
            let state = HueLightState(identifier: "a", isOn: true, brightnessPercent: percent)
            let value = HueColorConverter.effectiveBrightness(for: state, policy: policy)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }

    func testALampWithNoDimmingReportIsTreatedAsFullOutput() {
        let state = HueLightState(identifier: "a", isOn: true, brightnessPercent: nil)
        XCTAssertEqual(HueColorConverter.effectiveBrightness(for: state, policy: .default), 1.0, accuracy: 0.001)
    }

    func testAPlainDimmableBulbIsTreatedAsWarmWhite() {
        let state = HueLightState(identifier: "a", isOn: true, brightnessPercent: 100)
        let color = HueColorConverter.baseColor(for: state)
        XCTAssertGreaterThan(color.red, color.blue, "no colour information should mean 2700 K, not blue-white")
    }

    // MARK: - Off policy

    func testOffLampContributesNothingUnderTheDefaultPolicy() {
        let state = HueLightState(identifier: "a", isOn: false)
        XCTAssertNil(HueColorConverter.contribution(for: state, policy: .default))
    }

    func testDimLastColourPolicyKeepsAFaintHint() {
        let policy = HueMirrorPolicy(offPolicy: .dimLastColor, dimFactor: 0.1)
        let state = HueLightState(
            identifier: "a",
            isOn: false,
            brightnessPercent: 100,
            chromaticity: .init(x: 0.675, y: 0.322)
        )
        let color = HueColorConverter.contribution(for: state, policy: policy)
        XCTAssertNotNil(color)
        XCTAssertLessThan(color!.relativeLuminance, 0.2)
    }
}

// MARK: - Clusters

final class HueClusterTests: XCTestCase {

    private let assignments = [
        HueLightAssignment(resourceIdentifier: "candle", cluster: .candleAndSofa, label: "Candle"),
        HueLightAssignment(resourceIdentifier: "sofa", cluster: .candleAndSofa, label: "Sofa"),
        HueLightAssignment(resourceIdentifier: "luster-a", cluster: .deskLusters, label: "Luster A"),
        HueLightAssignment(resourceIdentifier: "luster-b", cluster: .deskLusters, label: "Luster B")
    ]

    private func on(_ id: String, x: Double, y: Double, brightness: Double = 100) -> HueLightState {
        HueLightState(
            identifier: id,
            isOn: true,
            brightnessPercent: brightness,
            chromaticity: .init(x: x, y: y)
        )
    }

    // MARK: Exact zone mapping

    func testClustersMapToTheExactAuditedLuids() {
        XCTAssertEqual(HueCluster.candleAndSofa.zone, .side)
        XCTAssertEqual(HueCluster.deskLusters.zone, .logo)
        XCTAssertEqual(MouseZone.side.luid, 0x40002)
        XCTAssertEqual(MouseZone.logo.luid, 0x40001)
        XCTAssertEqual(MouseZone.side.displayName, "MouseSideLed")
        XCTAssertEqual(MouseZone.logo.displayName, "MouseLogoLed")
    }

    func testFrameResolvesOntoTheDevicesReportedLuids() {
        let frame = LightingFrame(
            logo: RGBColor(red: 1, green: 2, blue: 3),
            side: RGBColor(red: 4, green: 5, blue: 6)
        )
        let resolved = frame.resolve(availableLuids: [0x40001, 0x40002])

        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved[0].luid, 0x40001)
        XCTAssertEqual(resolved[0].color, RGBColor(red: 1, green: 2, blue: 3))
        XCTAssertEqual(resolved[1].luid, 0x40002)
        XCTAssertEqual(resolved[1].color, RGBColor(red: 4, green: 5, blue: 6))
    }

    func testOnlyLuidsTheDeviceReportsAreEverWritten() {
        let frame = LightingFrame(uniform: .white)
        XCTAssertEqual(frame.resolve(availableLuids: [0x40002]).map(\.luid), [0x40002])
        XCTAssertTrue(frame.resolve(availableLuids: []).isEmpty)
    }

    func testAnUnrecognisedLuidIsLeftToICUERatherThanPaintedWithAnotherZone() {
        let frame = LightingFrame(logo: .white, side: .black)
        let resolved = frame.resolve(availableLuids: [0x40003])
        XCTAssertTrue(resolved.isEmpty)
    }

    func testAPartialFrameReleasesAnyKnownZoneWhoseColourIsMissing() {
        let frame = LightingFrame(colors: [.side: .white])
        let resolved = frame.resolve(availableLuids: [MouseZone.logo.luid, MouseZone.side.luid])

        XCTAssertEqual(resolved[0].color, .transparent)
        XCTAssertEqual(resolved[1].color, .white)
    }

    // MARK: Aggregation

    func testTwoClustersAreIndependent() {
        let states = [
            "candle": on("candle", x: 0.675, y: 0.322),      // red
            "sofa": on("sofa", x: 0.675, y: 0.322),          // red
            "luster-a": on("luster-a", x: 0.167, y: 0.04),   // blue
            "luster-b": on("luster-b", x: 0.167, y: 0.04)    // blue
        ]
        let frame = HueClusterAggregator.frame(assignments: assignments, states: states)!

        XCTAssertGreaterThan(frame[.side]!.red, frame[.side]!.blue, "candle+sofa are red → side LED")
        XCTAssertGreaterThan(frame[.logo]!.blue, frame[.logo]!.red, "the lusters are blue → logo LED")
    }

    func testMixingIsDoneInLinearLightNotInGammaSpace() {
        // Red + green must give a bright yellow, not a muddy dark olive.
        let states = [
            "candle": on("candle", x: 0.675, y: 0.322),
            "sofa": on("sofa", x: 0.409, y: 0.518)
        ]
        let color = HueClusterAggregator.color(
            for: .candleAndSofa,
            assignments: assignments,
            states: states
        )!
        XCTAssertGreaterThan(color.red, 120)
        XCTAssertGreaterThan(color.green, 120)
        XCTAssertLessThan(color.blue, 120)
    }

    func testABrightLampDominatesADimOne() {
        let states = [
            "candle": on("candle", x: 0.675, y: 0.322, brightness: 100),  // bright red
            "sofa": on("sofa", x: 0.167, y: 0.04, brightness: 1)          // barely-on blue
        ]
        let color = HueClusterAggregator.color(
            for: .candleAndSofa,
            assignments: assignments,
            states: states
        )!
        XCTAssertGreaterThan(color.red, color.blue, "brightness must weight the mix")
    }

    func testAClusterWithEveryLampOffRendersBlack() {
        let states = [
            "candle": HueLightState(identifier: "candle", isOn: false),
            "sofa": HueLightState(identifier: "sofa", isOn: false),
            "luster-a": on("luster-a", x: 0.675, y: 0.322)
        ]
        let frame = HueClusterAggregator.frame(
            assignments: assignments,
            states: states,
            policy: HueMirrorPolicy(offPolicy: .blackout)
        )!

        XCTAssertEqual(frame[.side], .black, "candle+sofa are off → the side LED goes dark")
        XCTAssertNotEqual(frame[.logo], .black, "the lusters are unaffected")
    }

    func testDimLastColorUsesTheLastLitClusterColor() {
        let policy = HueMirrorPolicy(offPolicy: .dimLastColor, dimFactor: 0.1)
        let last = ScimitarKit.RGBColor(red: 200, green: 100, blue: 50)
        let frame = HueClusterAggregator.frame(
            assignments: assignments,
            states: [:],
            policy: policy,
            lastLitColors: [.candleAndSofa: last]
        )

        XCTAssertEqual(frame?[.side], last.scaledBrightness(0.1))
    }

    func testPlaceholderLightsAreNeverTreatedAsConfigured() {
        let placeholders = [
            HueLightAssignment(
                resourceIdentifier: "REPLACE_ME_LIGHT_ID",
                cluster: .candleAndSofa,
                label: "Candle"
            )
        ]
        XCTAssertTrue(placeholders[0].isPlaceholder)
        XCTAssertNil(HueClusterAggregator.frame(assignments: placeholders, states: [:]))
    }

    func testNoConfiguredLightsMeansReleaseTheLayer() {
        XCTAssertNil(HueClusterAggregator.frame(assignments: [], states: [:]))
    }

    func testAMissingLightIsSimplyAbsentFromTheMix() {
        let states = ["candle": on("candle", x: 0.675, y: 0.322)]
        let frame = HueClusterAggregator.frame(assignments: assignments, states: states)!
        XCTAssertNotNil(frame[.side])
        XCTAssertEqual(frame[.logo], .black, "the lusters were never seen, so that zone stays dark")
    }
}

// MARK: - Wire format

final class HueWireFormatTests: XCTestCase {

    func testParsesAFullLightSnapshot() throws {
        let json = """
        {"errors":[],"data":[
          {"id":"aaa","type":"light","metadata":{"name":"Candle"},
           "on":{"on":true},"dimming":{"brightness":42.5},
           "color":{"xy":{"x":0.31,"y":0.33}},
           "color_temperature":{"mirek":366,"mirek_valid":false}}
        ]}
        """
        let states = try HueWireFormat.parseLightStates(Data(json.utf8))
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states[0].identifier, "aaa")
        XCTAssertTrue(states[0].isOn)
        XCTAssertEqual(states[0].brightnessPercent!, 42.5, accuracy: 0.001)
        XCTAssertEqual(states[0].chromaticity!.x, 0.31, accuracy: 0.001)
        XCTAssertFalse(states[0].mirekValid)
    }

    func testSurfacesBridgeErrors() {
        let json = #"{"errors":[{"description":"unauthorized user"}],"data":[]}"#
        XCTAssertThrowsError(try HueWireFormat.parseLightStates(Data(json.utf8))) { error in
            XCTAssertEqual(error as? HueWireFormat.DecodingFailure, .bridgeError("unauthorized user"))
        }
    }

    func testParsesEventDeltas() {
        let json = """
        [{"creationtime":"2026-08-06T00:00:00Z","id":"e1","type":"update",
          "data":[{"id":"aaa","type":"light","dimming":{"brightness":10}}]}]
        """
        let deltas = HueWireFormat.parseEventDeltas(Data(json.utf8))
        XCTAssertEqual(deltas.count, 1)
        XCTAssertEqual(deltas[0].identifier, "aaa")
        XCTAssertEqual(deltas[0].brightnessPercent!, 10, accuracy: 0.001)
        XCTAssertNil(deltas[0].isOn)
        XCTAssertNil(deltas[0].chromaticity)
    }

    func testIgnoresNonLightResourcesAndEmptyDeltas() {
        let json = """
        [{"type":"update","data":[
          {"id":"m1","type":"motion","motion":{"motion":true}},
          {"id":"aaa","type":"light"}
        ]}]
        """
        XCTAssertTrue(HueWireFormat.parseEventDeltas(Data(json.utf8)).isEmpty)
    }

    func testGarbageIsIgnoredRatherThanCrashing() {
        XCTAssertTrue(HueWireFormat.parseEventDeltas(Data("not json".utf8)).isEmpty)
    }

    // MARK: Merging

    func testABrightnessOnlyDeltaKeepsTheExistingColour() {
        let base = HueLightState(
            identifier: "aaa",
            isOn: true,
            brightnessPercent: 100,
            chromaticity: .init(x: 0.675, y: 0.322)
        )
        let merged = base.merging(HueLightDelta(identifier: "aaa", brightnessPercent: 20))

        XCTAssertEqual(merged.chromaticity, base.chromaticity, "a dim event must not wash the colour out")
        XCTAssertEqual(merged.brightnessPercent!, 20, accuracy: 0.001)
        XCTAssertTrue(merged.isOn)
    }

    func testAnOnOffDeltaKeepsEverythingElse() {
        let base = HueLightState(
            identifier: "aaa",
            isOn: true,
            brightnessPercent: 80,
            chromaticity: .init(x: 0.4, y: 0.4)
        )
        let merged = base.merging(HueLightDelta(identifier: "aaa", isOn: false))
        XCTAssertFalse(merged.isOn)
        XCTAssertEqual(merged.brightnessPercent!, 80, accuracy: 0.001)
        XCTAssertEqual(merged.chromaticity, base.chromaticity)
    }

    func testAColourDeltaSupersedesColourTemperature() {
        let base = HueLightState(identifier: "aaa", isOn: true, mirek: 370, mirekValid: true)
        let merged = base.merging(
            HueLightDelta(identifier: "aaa", chromaticity: .init(x: 0.675, y: 0.322))
        )
        XCTAssertFalse(merged.mirekValid)
        XCTAssertNotNil(merged.chromaticity)
    }

    func testAColourTemperatureDeltaSupersedesColour() {
        let base = HueLightState(
            identifier: "aaa",
            isOn: true,
            chromaticity: .init(x: 0.675, y: 0.322)
        )
        let merged = base.merging(HueLightDelta(identifier: "aaa", mirek: 250, mirekValid: true))
        XCTAssertTrue(merged.mirekValid)
        XCTAssertNil(merged.chromaticity)
    }
}
