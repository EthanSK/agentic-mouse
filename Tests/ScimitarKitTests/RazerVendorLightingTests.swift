import Foundation
import XCTest
@testable import ScimitarKit

private final class FakeRazerVendorTransport: RazerVendorTransport {
    var openCount = 0
    var closeCount = 0
    var requests: [[UInt8]] = []
    var statuses: [RazerVendorResponseStatus] = []

    func open() throws { openCount += 1 }

    func exchange(_ request: [UInt8]) throws -> [UInt8] {
        requests.append(request)
        var response = request
        response[0] = statuses.isEmpty ? RazerVendorResponseStatus.successful.rawValue : statuses.removeFirst().rawValue
        return response
    }

    func close() { closeCount += 1 }
}

final class RazerVendorReportTests: XCTestCase {
    func testStaticRedPacketMatchesExact008dProtocolVector() {
        let packet = RazerVendorReport.staticColor(
            RGBColor(red: 0xFF, green: 0x00, blue: 0x00),
            zone: .scrollWheel
        )

        XCTAssertEqual(packet.count, 90)
        XCTAssertEqual(
            packet.hex,
            "001f000000090f02000101000001ff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fa00"
        )
        XCTAssertEqual(packet[8], RazerNagaVendorProtocol.noStore)
        XCTAssertEqual(packet[88], RazerVendorReport.checksum(of: packet))
    }

    func testStaticPacketsTargetAllThreeExactZones() {
        XCTAssertEqual(
            RazerNagaVendorProtocol.Zone.allCases.map(\.rawValue),
            [0x01, 0x04, 0x10]
        )
        for zone in RazerNagaVendorProtocol.Zone.allCases {
            let packet = RazerVendorReport.staticColor(.white, zone: zone)
            XCTAssertEqual(packet[1], 0x1F)
            XCTAssertEqual(packet[5], 0x09)
            XCTAssertEqual(packet[6], 0x0F)
            XCTAssertEqual(packet[7], 0x02)
            XCTAssertEqual(packet[8], 0x00, "runtime lighting must stay NOSTORE")
            XCTAssertEqual(packet[9], zone.rawValue)
            XCTAssertEqual(packet[10], 0x01)
            XCTAssertEqual(Array(packet[14...16]), [0xFF, 0xFF, 0xFF])
        }
    }

    func testSpectrumPacketIsTransientAndChecksummed() {
        let packet = RazerVendorReport.spectrum(zone: .thumbGrid)
        XCTAssertEqual(packet.count, 90)
        XCTAssertEqual(packet[5], 0x06)
        XCTAssertEqual(packet[8], 0x00)
        XCTAssertEqual(packet[9], 0x10)
        XCTAssertEqual(packet[10], 0x03)
        XCTAssertEqual(packet[88], RazerVendorReport.checksum(of: packet))
    }

    func testCustomEffectActivationIsTransientAndUsesExact008dVector() {
        let packet = RazerVendorReport.activateCustomEffect()

        XCTAssertEqual(packet.count, 90)
        XCTAssertEqual(packet[1], 0x1F)
        XCTAssertEqual(packet[5], 0x0C)
        XCTAssertEqual(Array(packet[6...10]), [0x0F, 0x02, 0x00, 0x00, 0x08])
        XCTAssertEqual(
            packet.hex,
            "001f0000000c0f0200000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000900"
        )
        XCTAssertEqual(packet[8], RazerNagaVendorProtocol.noStore)
        XCTAssertEqual(packet[88], RazerVendorReport.checksum(of: packet))
    }

    func testSolidCustomFrameFillsExactOneByThreeMatrix() {
        let packet = RazerVendorReport.customFrame(
            RGBColor(red: 0x12, green: 0x34, blue: 0x56)
        )

        XCTAssertEqual(packet.count, 90)
        XCTAssertEqual(packet[1], 0x1F)
        XCTAssertEqual(packet[5], 0x0E)
        XCTAssertEqual(Array(packet[6...12]), [0x0F, 0x03, 0x00, 0x00, 0x00, 0x00, 0x02])
        XCTAssertEqual(
            Array(packet[13...21]),
            [0x12, 0x34, 0x56, 0x12, 0x34, 0x56, 0x12, 0x34, 0x56]
        )
        XCTAssertEqual(
            packet.hex,
            "001f0000000e0f0300000000021234561234561234560000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000"
        )
        XCTAssertEqual(packet[88], RazerVendorReport.checksum(of: packet))
    }

    func testDistinctCustomFrameUsesWheelLogoGridOrder() {
        let packet = RazerVendorReport.customFrame(
            scrollWheel: RGBColor(red: 0x11, green: 0x22, blue: 0x33),
            logo: RGBColor(red: 0x44, green: 0x55, blue: 0x66),
            thumbGrid: RGBColor(red: 0x77, green: 0x88, blue: 0x99)
        )

        XCTAssertEqual(
            Array(packet[13...21]),
            [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99]
        )
        XCTAssertEqual(packet[88], RazerVendorReport.checksum(of: packet))
    }

    func testResponseParserRejectsWrongTransactionAndCommand() throws {
        var response = RazerVendorReport.staticColor(.white, zone: .logo)
        response[0] = RazerVendorResponseStatus.successful.rawValue
        let request = response
        XCTAssertEqual(
            try RazerVendorResponse.parse(response, matching: request).status,
            .successful
        )

        response[1] = 0x3F
        XCTAssertThrowsError(try RazerVendorResponse.parse(response, matching: request))
        response[1] = 0x1F
        response[7] = 0x03
        XCTAssertThrowsError(try RazerVendorResponse.parse(response, matching: request))
    }

    func testResponseParserAcceptsMatchingCustomFrameCommand() throws {
        let request = RazerVendorReport.customFrame(.white)
        var response = request
        response[0] = RazerVendorResponseStatus.successful.rawValue

        let parsed = try RazerVendorResponse.parse(response, matching: request)
        XCTAssertEqual(parsed.status, .successful)
        XCTAssertEqual(parsed.commandID, RazerNagaVendorProtocol.customFrameCommandID)
    }
}

final class RazerVendorLightingControllerTests: XCTestCase {
    func testFirstColorActivatesCustomThenWritesFrameAndReleaseRestoresSpectrum() {
        let transport = FakeRazerVendorTransport()
        let controller = RazerVendorLightingController(transport: transport, retryDelay: { _ in })

        XCTAssertTrue(controller.setColor(RGBColor(red: 0x12, green: 0x34, blue: 0x56)))
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests.map { $0[7] }, [0x02, 0x03])
        XCTAssertEqual(Array(transport.requests[1][13...21]), [
            0x12, 0x34, 0x56,
            0x12, 0x34, 0x56,
            0x12, 0x34, 0x56,
        ])

        controller.release()

        XCTAssertEqual(transport.requests.count, 5)
        XCTAssertEqual(transport.requests.suffix(3).map { $0[10] }, [0x03, 0x03, 0x03])
        XCTAssertEqual(transport.closeCount, 1)
    }

    func testSubsequentColorWritesOneFrameWithoutReactivatingCustomEffect() {
        let transport = FakeRazerVendorTransport()
        let controller = RazerVendorLightingController(transport: transport, retryDelay: { _ in })

        XCTAssertTrue(controller.setColor(.white))
        XCTAssertTrue(controller.setColor(RGBColor(red: 0xAA, green: 0xBB, blue: 0xCC)))

        XCTAssertEqual(transport.requests.map { $0[7] }, [0x02, 0x03, 0x03])
        XCTAssertEqual(Array(transport.requests[2][13...21]), [
            0xAA, 0xBB, 0xCC,
            0xAA, 0xBB, 0xCC,
            0xAA, 0xBB, 0xCC,
        ])
    }

    func testModeAppearanceUsesWheelAndLogoForModeAndGridForLastAction() {
        let transport = FakeRazerVendorTransport()
        let controller = RazerVendorLightingController(
            transport: transport,
            brightnessScale: 1.0,
            retryDelay: { _ in }
        )
        let mode = ScimitarKit.RGBColor(red: 0xA0, green: 0x20, blue: 0xF0)
        let action = ScimitarKit.RGBColor(red: 0x10, green: 0xE0, blue: 0x80)

        XCTAssertTrue(controller.setModeAppearance(modeColor: mode, actionColor: action))
        XCTAssertEqual(transport.requests.map { $0[7] }, [0x02, 0x03])
        XCTAssertEqual(Array(transport.requests[1][13...21]), [
            0xA0, 0x20, 0xF0,
            0xA0, 0x20, 0xF0,
            0x10, 0xE0, 0x80,
        ])

        XCTAssertTrue(controller.setModeAppearance(modeColor: mode, actionColor: .white))
        XCTAssertEqual(transport.requests.map { $0[7] }, [0x02, 0x03, 0x03])
        XCTAssertEqual(Array(transport.requests[2][13...21]), [
            0xA0, 0x20, 0xF0,
            0xA0, 0x20, 0xF0,
            0xFF, 0xFF, 0xFF,
        ])
    }

    func testRejectedDistinctFrameRestoresThenFallsBackToUniformModeColor() {
        let transport = FakeRazerVendorTransport()
        transport.statuses = [
            .successful, .notSupported,
            .successful, .successful, .successful,
            .successful, .successful,
        ]
        let controller = RazerVendorLightingController(
            transport: transport,
            retryDelay: { _ in }
        )
        let mode = ScimitarKit.RGBColor(red: 0xAA, green: 0x44, blue: 0x11)

        XCTAssertTrue(
            controller.setModeAppearance(
                modeColor: mode,
                actionColor: ScimitarKit.RGBColor(red: 0x00, green: 0xFF, blue: 0x00)
            )
        )
        XCTAssertEqual(transport.requests.count, 7)
        XCTAssertEqual(transport.requests[1][7], 0x03)
        XCTAssertEqual(transport.requests[2...4].map { $0[10] }, [0x03, 0x03, 0x03])
        XCTAssertEqual(Array(transport.requests[6][13...21]), [
            0xAA, 0x44, 0x11,
            0xAA, 0x44, 0x11,
            0xAA, 0x44, 0x11,
        ])
        XCTAssertEqual(transport.closeCount, 1)
    }

    func testConfiguredIdleWhiteUsesCustomFrameAtStartupAndAfterModeExit() {
        let transport = FakeRazerVendorTransport()
        let controller = RazerVendorLightingController(
            transport: transport,
            idleColor: .white,
            retryDelay: { _ in }
        )

        XCTAssertTrue(controller.restoreIdle())
        XCTAssertEqual(transport.requests.map { $0[7] }, [0x02, 0x03])
        XCTAssertEqual(Array(transport.requests[1][13...21]), Array(repeating: 0xFF, count: 9))

        XCTAssertTrue(controller.setColor(RGBColor(red: 0xFF, green: 0, blue: 0)))
        XCTAssertTrue(controller.setColor(nil))

        XCTAssertEqual(transport.requests.map { $0[7] }, [0x02, 0x03, 0x03, 0x03])
        XCTAssertEqual(Array(transport.requests[3][13...21]), Array(repeating: 0xFF, count: 9))
        XCTAssertEqual(transport.closeCount, 0)

        controller.release()
        XCTAssertEqual(transport.requests.suffix(3).map { $0[10] }, [0x03, 0x03, 0x03])
        XCTAssertEqual(transport.closeCount, 1)
    }

    func testConfiguredBrightnessScalesIdleAndModeFramesWithoutChangingProtocol() {
        let transport = FakeRazerVendorTransport()
        let controller = RazerVendorLightingController(
            transport: transport,
            idleColor: .white,
            idleOutputColor: RGBColor(red: 124, green: 129, blue: 130),
            brightnessScale: 0.50,
            retryDelay: { _ in }
        )

        XCTAssertTrue(controller.restoreIdle())
        XCTAssertEqual(Array(transport.requests[1][13...21]), [
            124, 129, 130,
            124, 129, 130,
            124, 129, 130,
        ])

        XCTAssertTrue(controller.setColor(RGBColor(red: 0xFF, green: 0x80, blue: 0)))
        XCTAssertEqual(Array(transport.requests[2][13...21]), [
            0x80, 0x40, 0x00,
            0x80, 0x40, 0x00,
            0x80, 0x40, 0x00,
        ])

        controller.release()
    }

    func testBusyResponseRetriesThenSucceeds() {
        let transport = FakeRazerVendorTransport()
        transport.statuses = [.busy, .successful, .successful]
        var delays: [TimeInterval] = []
        let controller = RazerVendorLightingController(
            transport: transport,
            retryDelay: { delays.append($0) }
        )

        XCTAssertTrue(controller.setColor(.white))
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(delays, [0.010])
    }

    func testFailureRestoresEveryZoneAndCloses() {
        let transport = FakeRazerVendorTransport()
        transport.statuses = [
            .successful, .notSupported,
            .successful, .successful, .successful,
        ]
        let controller = RazerVendorLightingController(transport: transport, retryDelay: { _ in })

        XCTAssertFalse(controller.setColor(.white))
        XCTAssertEqual(transport.requests.count, 5)
        XCTAssertEqual(transport.requests.suffix(3).map { $0[10] }, [0x03, 0x03, 0x03])
        XCTAssertEqual(transport.closeCount, 1)
    }

    func testRealTransportSourceNeverSeizesAnInputInterface() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let swiftSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/ScimitarKit/Lighting/RazerVendorUSBTransport.swift"
            )
        )
        let cSource = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/CRazerUSBTransport/CRazerUSBTransport.c"
            )
        )
        XCTAssertFalse(swiftSource.contains("kIOHIDOptionsTypeSeizeDevice"))
        XCTAssertFalse(
            swiftSource.contains("UInt32(kIOReturn"),
            "negative IOKit statuses must never use a trapping unsigned conversion"
        )
        XCTAssertTrue(swiftSource.contains("Int32(truncatingIfNeeded: kIOReturnNotFound)"))
        XCTAssertFalse(cSource.contains("USBInterfaceOpen"))
        XCTAssertFalse(cSource.contains("ResetDevice"))
    }
}

private extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
