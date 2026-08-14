import XCTest
@testable import ScimitarKit

private final class FakeRazerLampArrayTransport: RazerLampArrayTransport {
    var attributesReport: [UInt8]
    var lampAttributesReport = validRazerLampAttributes()
    var autonomousModeReport: [UInt8] = [6, 1]
    var openError: Error?
    var readError: Error?
    var failingWriteReportID: UInt8?
    var failingWriteNumbers: Set<Int> = []
    private(set) var openCount = 0
    private(set) var closeCount = 0
    private(set) var writes: [[UInt8]] = []
    var descriptor = RazerNagaLampArray.expectedReportDescriptor

    init(attributesReport: [UInt8] = validRazerLampArrayAttributes()) {
        self.attributesReport = attributesReport
    }

    func open() throws {
        openCount += 1
        if let openError { throw openError }
    }

    func readFeatureReport(id: UInt8, maximumLength: Int) throws -> [UInt8] {
        if let readError { throw readError }
        let report: [UInt8]
        switch id {
        case 1: report = attributesReport
        case 3: report = lampAttributesReport
        case 6: report = autonomousModeReport
        default: report = [id]
        }
        return Array(report.prefix(maximumLength))
    }

    func reportDescriptor() throws -> [UInt8] { descriptor }

    func writeFeatureReport(_ report: [UInt8]) throws {
        writes.append(report)
        if report.first == failingWriteReportID || failingWriteNumbers.contains(writes.count) {
            throw RazerLampArrayError.writeFailed(reportID: report.first ?? 0, status: "fake")
        }
    }

    func close() { closeCount += 1 }
}

private func validRazerLampAttributes() -> [UInt8] {
    [
        3,
        0, 0,
        1, 0, 0, 0,
        2, 0, 0, 0,
        3, 0, 0, 0,
        0x35, 0x82, 0, 0,
        1, 0, 0, 0,
        255, 255, 255,
        1,
        0,
    ]
}

private func validRazerLampArrayAttributes() -> [UInt8] {
    var report = [UInt8](repeating: 0, count: 64)
    let prefix: [UInt8] = [
        1,
        3, 0,
        0x5E, 0x23, 0x01, 0x00,
        0x6A, 0xD0, 0x01, 0x00,
        0x76, 0xA7, 0x00, 0x00,
        2, 0, 0, 0,
        0x35, 0x82, 0, 0,
    ]
    report.replaceSubrange(0..<prefix.count, with: prefix)
    return report
}

final class RazerLampArrayReportTests: XCTestCase {
    func testParsesTheReadOnlyAttributesObservedFromTheExactMouse() throws {
        let attributes = try LampArrayAttributes.parse(validRazerLampArrayAttributes())
        XCTAssertEqual(attributes.lampCount, 3)
        XCTAssertEqual(attributes.boundingBoxWidthMicrometres, 74_590)
        XCTAssertEqual(attributes.boundingBoxHeightMicrometres, 118_890)
        XCTAssertEqual(attributes.boundingBoxDepthMicrometres, 42_870)
        XCTAssertEqual(attributes.kind, 2)
        XCTAssertEqual(attributes.minimumUpdateIntervalMicroseconds, 33_333)
    }

    func testEncodesDescriptorDerivedFeatureReportsIncludingTheReportID() throws {
        XCTAssertEqual(RazerLampArrayReport.autonomousMode(false), [6, 0])
        XCTAssertEqual(RazerLampArrayReport.autonomousMode(true), [6, 1])
        XCTAssertEqual(
            try RazerLampArrayReport.solidColor(RGBColor(red: 0xA1, green: 0xB2, blue: 0xC3)),
            [5, 1, 0, 0, 2, 0, 0xA1, 0xB2, 0xC3]
        )
        XCTAssertEqual(
            try RazerLampArrayReport.color(
                RGBColor(red: 0x11, green: 0x22, blue: 0x33),
                fromLamp: 1,
                throughLamp: 1,
                updateComplete: false
            ),
            [5, 0, 1, 0, 1, 0, 0x11, 0x22, 0x33]
        )
        XCTAssertEqual(RazerLampArrayReport.attributesLength, 23)
        XCTAssertEqual(RazerLampArrayReport.rangeUpdateLength, 9)
        XCTAssertEqual(RazerLampArrayReport.controlLength, 2)
        XCTAssertEqual(RazerNagaLampArray.expectedReportDescriptor.last, 0xC0)
    }

    func testRejectsWrongReportIDAndZeroLamps() {
        var attributes = validRazerLampArrayAttributes()
        attributes[0] = 3
        XCTAssertThrowsError(try LampArrayAttributes.parse(attributes))
        XCTAssertThrowsError(
            try RazerLampArrayReport.solidColor(.white, lampCount: 0)
        )
        XCTAssertThrowsError(
            try RazerLampArrayReport.color(
                .white,
                fromLamp: 2,
                throughLamp: 1,
                updateComplete: true
            )
        )
    }

    func testParsesDescriptorOrderedLampAttributesAndAutonomousMode() throws {
        let lamp = try LampAttributes.parse(validRazerLampAttributes())
        XCTAssertEqual(lamp.lampID, 0)
        XCTAssertEqual(lamp.positionXMicrometres, 1)
        XCTAssertEqual(lamp.positionYMicrometres, 2)
        XCTAssertEqual(lamp.positionZMicrometres, 3)
        XCTAssertEqual(lamp.updateLatencyMicroseconds, 33_333)
        XCTAssertEqual(lamp.purposes, 1)
        XCTAssertEqual(lamp.redLevelCount, 255)
        XCTAssertTrue(lamp.isProgrammable)
        XCTAssertTrue(try RazerLampArrayReport.parseAutonomousMode([6, 1]))
        XCTAssertFalse(try RazerLampArrayReport.parseAutonomousMode([6, 0]))
    }
}

final class RazerLampArrayControllerTests: XCTestCase {
    func testProbeValidatesAndReadsWithoutAnyFeatureWrite() throws {
        let transport = FakeRazerLampArrayTransport()
        let controller = RazerLampArrayController(
            transport: transport,
            log: Log(category: "test", sink: NullLogSink())
        )

        let attributes = try controller.probe()

        XCTAssertEqual(attributes.lampCount, 3)
        XCTAssertTrue(transport.writes.isEmpty)
        XCTAssertEqual(transport.openCount, 1)
        controller.release()
        XCTAssertEqual(transport.closeCount, 1)
    }

    func testReadOnlyProbeReportsLampProgrammabilityAndAutonomousMode() throws {
        let transport = FakeRazerLampArrayTransport()
        let controller = RazerLampArrayController(
            transport: transport,
            log: Log(category: "test", sink: NullLogSink())
        )

        let lamp = try controller.readCurrentLampAttributes()
        let autonomous = try controller.readAutonomousMode()

        XCTAssertTrue(lamp.isProgrammable)
        XCTAssertEqual(lamp.lampID, 0)
        XCTAssertTrue(autonomous)
        XCTAssertTrue(transport.writes.isEmpty)
    }

    func testFirstColourInterrogatesDisablesAutonomousAndPaintsAllThreeLamps() {
        let transport = FakeRazerLampArrayTransport()
        let controller = RazerLampArrayController(
            transport: transport,
            log: Log(category: "test", sink: NullLogSink()),
            sleepMicroseconds: { _ in XCTFail("first colour should not throttle") }
        )

        XCTAssertTrue(controller.setColor(RGBColor(red: 255, green: 0, blue: 0)))
        XCTAssertEqual(transport.openCount, 1)
        XCTAssertEqual(
            transport.writes,
            [
                [6, 0],
                [5, 1, 0, 0, 2, 0, 255, 0, 0],
            ]
        )
    }

    func testSubsequentColourKeepsOneOpenLeaseAndRespectsMinimumInterval() {
        let transport = FakeRazerLampArrayTransport()
        var sleeps: [UInt32] = []
        let controller = RazerLampArrayController(
            transport: transport,
            log: Log(category: "test", sink: NullLogSink()),
            sleepMicroseconds: { sleeps.append($0) }
        )

        XCTAssertTrue(controller.setColor(.white))
        XCTAssertTrue(controller.setColor(.black))
        XCTAssertEqual(transport.openCount, 1)
        XCTAssertEqual(transport.writes.map { $0[0] }, [6, 5, 5])
        XCTAssertEqual(sleeps.count, 1)
        XCTAssertGreaterThan(sleeps[0], 0)
        XCTAssertLessThanOrEqual(sleeps[0], 33_333)
    }

    func testFrameWritesThreeIndividualLampsAndCommitsOnlyTheLast() {
        let transport = FakeRazerLampArrayTransport()
        let controller = RazerLampArrayController(
            transport: transport,
            log: Log(category: "test", sink: NullLogSink()),
            sleepMicroseconds: { _ in }
        )

        XCTAssertTrue(controller.setFrame([
            RGBColor(red: 255, green: 0, blue: 0),
            RGBColor(red: 0, green: 255, blue: 0),
            RGBColor(red: 0, green: 0, blue: 255),
        ]))

        XCTAssertEqual(
            transport.writes,
            [
                [6, 0],
                [5, 0, 0, 0, 0, 0, 255, 0, 0],
                [5, 0, 1, 0, 1, 0, 0, 255, 0],
                [5, 1, 2, 0, 2, 0, 0, 0, 255],
            ]
        )
    }

    func testFrameRefusesWrongLampCountBeforeAnyWrite() {
        let transport = FakeRazerLampArrayTransport()
        let controller = RazerLampArrayController(
            transport: transport,
            log: Log(category: "test", sink: NullLogSink())
        )

        XCTAssertFalse(controller.setFrame([.white, .white]))
        XCTAssertTrue(transport.writes.isEmpty)
        XCTAssertEqual(transport.closeCount, 1)
    }

    func testReleaseRestoresAutonomousModeAndCloses() {
        let transport = FakeRazerLampArrayTransport()
        let controller = RazerLampArrayController(
            transport: transport,
            log: Log(category: "test", sink: NullLogSink())
        )
        XCTAssertTrue(controller.setColor(.white))

        controller.release()

        XCTAssertEqual(transport.writes.last, [6, 1])
        XCTAssertEqual(transport.closeCount, 1)
    }

    func testTransparentMeansRestoreAndNeverPaintsBlack() {
        let transport = FakeRazerLampArrayTransport()
        let controller = RazerLampArrayController(
            transport: transport,
            log: Log(category: "test", sink: NullLogSink())
        )
        XCTAssertTrue(controller.setColor(.white))

        XCTAssertFalse(controller.setColor(.transparent))

        XCTAssertEqual(transport.writes.map { $0[0] }, [6, 5, 6])
        XCTAssertFalse(transport.writes.contains { $0.first == 5 && $0.suffix(3) == [0, 0, 0] })
    }

    func testFailedColourAttemptsAutonomousRollbackAndCloses() {
        let transport = FakeRazerLampArrayTransport()
        transport.failingWriteReportID = 5
        let controller = RazerLampArrayController(
            transport: transport,
            log: Log(category: "test", sink: NullLogSink())
        )

        XCTAssertFalse(controller.setColor(.white))
        XCTAssertEqual(transport.writes.map { $0[0] }, [6, 5, 6])
        XCTAssertEqual(transport.writes.last, [6, 1])
        XCTAssertEqual(transport.closeCount, 1)
    }

    func testUnexpectedLampCountRefusesEveryWrite() {
        var attributes = validRazerLampArrayAttributes()
        attributes[1] = 4
        let transport = FakeRazerLampArrayTransport(attributesReport: attributes)
        let controller = RazerLampArrayController(
            transport: transport,
            log: Log(category: "test", sink: NullLogSink())
        )

        XCTAssertFalse(controller.setColor(.white))
        XCTAssertTrue(transport.writes.isEmpty)
        XCTAssertEqual(transport.closeCount, 1)
    }

    func testUnexpectedDescriptorRefusesEveryWrite() {
        let transport = FakeRazerLampArrayTransport()
        transport.descriptor.removeLast()
        let controller = RazerLampArrayController(
            transport: transport,
            log: Log(category: "test", sink: NullLogSink())
        )

        XCTAssertFalse(controller.setColor(.white))
        XCTAssertTrue(transport.writes.isEmpty)
        XCTAssertEqual(transport.closeCount, 1)
    }

    func testRestoreRetriesThreeTimesAndSurfacesTheFailure() {
        let transport = FakeRazerLampArrayTransport()
        let controller = RazerLampArrayController(
            transport: transport,
            log: Log(category: "test", sink: NullLogSink())
        )
        var problems: [String] = []
        controller.onProblem = { problems.append($0) }
        XCTAssertTrue(controller.setColor(.white))
        transport.failingWriteNumbers = [3, 4, 5]

        controller.release()

        XCTAssertEqual(transport.writes.map { $0[0] }, [6, 5, 6, 6, 6])
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].contains("restore"))
        XCTAssertEqual(transport.closeCount, 1)
    }

    func testIOHIDAdapterMatchesOnlyTheExactLampArrayAndNeverSeizes() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/ScimitarKit/Lighting/RazerLampArrayIOHIDTransport.swift"
            )
        )
        for required in [
            "kIOHIDVendorIDKey",
            "kIOHIDProductIDKey",
            "kIOHIDPrimaryUsagePageKey",
            "kIOHIDPrimaryUsageKey",
        ] {
            XCTAssertTrue(source.contains(required), required)
        }
        XCTAssertFalse(source.contains("kIOHIDOptionsTypeSeizeDevice"))
    }
}
