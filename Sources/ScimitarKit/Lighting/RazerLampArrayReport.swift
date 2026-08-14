import Foundation

/// The exact standard HID LampArray contract exposed by the 2020 left-handed
/// Naga. These values are descriptor-derived, not Razer vendor commands.
public enum RazerNagaLampArray {
    public static let vendorID = 0x1532
    public static let productID = 0x008D
    public static let usagePage = 0x59
    public static let usage = 0x01
    public static let expectedLampCount: UInt16 = 3
    public static let mouseKind: UInt32 = 2
    public static let maximumFeatureReportLength = 64

    /// Byte-for-byte descriptor read from the exact `1532:008d` LampArray
    /// interface on macOS. Runtime control fails closed if firmware exposes a
    /// different layout rather than guessing field offsets.
    public static let expectedReportDescriptor: [UInt8] = {
        let hex = "05590901a10185010902a1020903150027ffff000075109501b10309040905090609070908150027ffffff7f75209505b103c085020920a1020921150027ffff000075109501b102c085030922a1020921150027ffff000075109501b10209230924092509270926150027ffffff7f75209505b10209280929092a092c092d150026ff0075089505b102c085040950a102090309551500250875089502b1020921150027ffff000075109508b102095109520953095109520953095109520953095109520953095109520953095109520953095109520953095109520953150026ff0075089518b102c085050960a10209551500250875089501b10209610962150027ffff000075109502b102095109520953150026ff0075089503b102c085060970a10209711500250175089501b102c085070600ff150026ff0009027508953fb102c0"
        return stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)!
        }
    }()
}

public struct LampArrayAttributes: Equatable, Sendable {
    public let lampCount: UInt16
    public let boundingBoxWidthMicrometres: UInt32
    public let boundingBoxHeightMicrometres: UInt32
    public let boundingBoxDepthMicrometres: UInt32
    public let kind: UInt32
    public let minimumUpdateIntervalMicroseconds: UInt32

    public static func parse(_ report: [UInt8]) throws -> LampArrayAttributes {
        guard report.count >= 23 else {
            throw RazerLampArrayError.malformedAttributes("report 1 is only \(report.count) bytes")
        }
        guard report[0] == 1 else {
            throw RazerLampArrayError.malformedAttributes("expected report ID 1, got \(report[0])")
        }

        return LampArrayAttributes(
            lampCount: report.littleEndianUInt16(at: 1),
            boundingBoxWidthMicrometres: report.littleEndianUInt32(at: 3),
            boundingBoxHeightMicrometres: report.littleEndianUInt32(at: 7),
            boundingBoxDepthMicrometres: report.littleEndianUInt32(at: 11),
            kind: report.littleEndianUInt32(at: 15),
            minimumUpdateIntervalMicroseconds: report.littleEndianUInt32(at: 19)
        )
    }
}

public struct LampAttributes: Equatable, Sendable {
    public let lampID: UInt16
    public let positionXMicrometres: UInt32
    public let positionYMicrometres: UInt32
    public let positionZMicrometres: UInt32
    public let updateLatencyMicroseconds: UInt32
    public let purposes: UInt32
    public let redLevelCount: UInt8
    public let greenLevelCount: UInt8
    public let blueLevelCount: UInt8
    public let isProgrammable: Bool
    public let inputBinding: UInt8

    public static func parse(_ report: [UInt8]) throws -> LampAttributes {
        guard report.count >= 28 else {
            throw RazerLampArrayError.malformedAttributes("report 3 is only \(report.count) bytes")
        }
        guard report[0] == 3 else {
            throw RazerLampArrayError.malformedAttributes("expected report ID 3, got \(report[0])")
        }
        return LampAttributes(
            lampID: report.littleEndianUInt16(at: 1),
            positionXMicrometres: report.littleEndianUInt32(at: 3),
            positionYMicrometres: report.littleEndianUInt32(at: 7),
            positionZMicrometres: report.littleEndianUInt32(at: 11),
            updateLatencyMicroseconds: report.littleEndianUInt32(at: 15),
            purposes: report.littleEndianUInt32(at: 19),
            redLevelCount: report[23],
            greenLevelCount: report[24],
            blueLevelCount: report[25],
            isProgrammable: report[26] != 0,
            inputBinding: report[27]
        )
    }
}

public enum RazerLampArrayReport {
    public static let updateComplete: UInt8 = 1 << 0
    public static let attributesLength = 23
    public static let rangeUpdateLength = 9
    public static let controlLength = 2

    public static func parseAutonomousMode(_ report: [UInt8]) throws -> Bool {
        guard report.count >= controlLength else {
            throw RazerLampArrayError.malformedAttributes("report 6 is only \(report.count) bytes")
        }
        guard report[0] == 6 else {
            throw RazerLampArrayError.malformedAttributes("expected report ID 6, got \(report[0])")
        }
        return report[1] != 0
    }

    /// HID feature report 6: LampArrayControl / AutonomousMode.
    public static func autonomousMode(_ enabled: Bool) -> [UInt8] {
        [6, enabled ? 1 : 0]
    }

    /// HID feature report 5: LampRangeUpdate for every lamp on this exact mouse.
    /// The exact descriptor contains flags, two 16-bit lamp IDs, and RGB only;
    /// it does not declare an intensity channel.
    public static func solidColor(
        _ color: RGBColor,
        lampCount: UInt16 = RazerNagaLampArray.expectedLampCount
    ) throws -> [UInt8] {
        guard lampCount > 0 else {
            throw RazerLampArrayError.unsupportedDevice("LampCount is zero")
        }
        return try Self.color(
            color,
            fromLamp: 0,
            throughLamp: lampCount - 1,
            lampCount: lampCount,
            updateComplete: true
        )
    }

    /// HID feature report 5 for one validated contiguous lamp range.
    public static func color(
        _ color: RGBColor,
        fromLamp firstLamp: UInt16,
        throughLamp lastLamp: UInt16,
        lampCount: UInt16 = RazerNagaLampArray.expectedLampCount,
        updateComplete: Bool
    ) throws -> [UInt8] {
        guard lampCount > 0 else {
            throw RazerLampArrayError.unsupportedDevice("LampCount is zero")
        }
        guard firstLamp <= lastLamp, lastLamp < lampCount else {
            throw RazerLampArrayError.unsupportedDevice(
                "invalid lamp range \(firstLamp)...\(lastLamp) for \(lampCount) lamps"
            )
        }
        return [
            5,
            updateComplete ? Self.updateComplete : 0,
            UInt8(truncatingIfNeeded: firstLamp),
            UInt8(truncatingIfNeeded: firstLamp >> 8),
            UInt8(truncatingIfNeeded: lastLamp),
            UInt8(truncatingIfNeeded: lastLamp >> 8),
            color.red,
            color.green,
            color.blue,
        ]
    }
}

public enum RazerLampArrayError: Error, Equatable, CustomStringConvertible {
    case deviceNotFound
    case multipleDevices(Int)
    case openFailed(String)
    case readFailed(reportID: UInt8, status: String)
    case writeFailed(reportID: UInt8, status: String)
    case malformedAttributes(String)
    case unsupportedDevice(String)

    public var description: String {
        switch self {
        case .deviceNotFound: return "exact Razer LampArray interface not found"
        case .multipleDevices(let count): return "expected one exact Razer LampArray interface, found \(count)"
        case .openFailed(let status): return "could not open exact Razer LampArray interface (\(status))"
        case .readFailed(let reportID, let status): return "feature report \(reportID) read failed (\(status))"
        case .writeFailed(let reportID, let status): return "feature report \(reportID) write failed (\(status))"
        case .malformedAttributes(let detail): return "invalid LampArray attributes: \(detail)"
        case .unsupportedDevice(let detail): return "unsupported LampArray: \(detail)"
        }
    }
}

private extension Array where Element == UInt8 {
    func littleEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func littleEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
