import Foundation

/// Exact Razer vendor-protocol contract for the 2020 left-handed Naga.
///
/// This is a clean Swift implementation of the wire format documented for
/// `1532:008d` by OpenRazer. It intentionally emits only transient (`NOSTORE`)
/// lighting commands; Agentic Mouse never writes the Naga's onboard profile.
public enum RazerNagaVendorProtocol {
    public static let vendorID: UInt16 = 0x1532
    public static let productID: UInt16 = 0x008D
    public static let reportLength = 90
    public static let transactionID: UInt8 = 0x1F
    public static let interfaceIndex: UInt16 = 0
    public static let exchangeDelayMicroseconds: UInt32 = 800

    public static let noStore: UInt8 = 0x00
    public static let commandClass: UInt8 = 0x0F
    public static let effectCommandID: UInt8 = 0x02
    public static let customFrameCommandID: UInt8 = 0x03

    public enum Zone: UInt8, CaseIterable, Sendable {
        case scrollWheel = 0x01
        case logo = 0x04
        case thumbGrid = 0x10
    }
}

public enum RazerVendorResponseStatus: UInt8, Equatable, Sendable {
    case newCommand = 0x00
    case busy = 0x01
    case successful = 0x02
    case failure = 0x03
    case timeout = 0x04
    case notSupported = 0x05
}

public struct RazerVendorResponse: Equatable, Sendable {
    public let status: RazerVendorResponseStatus
    public let transactionID: UInt8
    public let commandClass: UInt8
    public let commandID: UInt8

    public static func parse(
        _ bytes: [UInt8],
        matching request: [UInt8]
    ) throws -> RazerVendorResponse {
        guard bytes.count == RazerNagaVendorProtocol.reportLength else {
            throw RazerVendorError.malformedResponse("expected 90 bytes, got \(bytes.count)")
        }
        guard request.count == RazerNagaVendorProtocol.reportLength else {
            throw RazerVendorError.malformedResponse(
                "request expected 90 bytes, got \(request.count)"
            )
        }
        guard let status = RazerVendorResponseStatus(rawValue: bytes[0]) else {
            throw RazerVendorError.malformedResponse(
                String(format: "unknown status 0x%02X", bytes[0])
            )
        }
        guard bytes[1] == request[1] else {
            throw RazerVendorError.malformedResponse(
                String(format: "transaction ID 0x%02X did not match 0x%02X", bytes[1], request[1])
            )
        }
        guard bytes[2] == 0, bytes[3] == 0 else {
            throw RazerVendorError.malformedResponse("unexpected remaining-packet count")
        }
        guard bytes[6] == request[6], bytes[7] == request[7]
        else {
            throw RazerVendorError.malformedResponse(
                String(
                    format: "response command 0x%02X/0x%02X did not match 0x%02X/0x%02X",
                    bytes[6], bytes[7], request[6], request[7]
                )
            )
        }
        return RazerVendorResponse(
            status: status,
            transactionID: bytes[1],
            commandClass: bytes[6],
            commandID: bytes[7]
        )
    }
}

public enum RazerVendorReport {
    private static let staticEffect: UInt8 = 0x01
    private static let spectrumEffect: UInt8 = 0x03
    private static let customEffect: UInt8 = 0x08

    public static func staticColor(_ color: RGBColor, zone: RazerNagaVendorProtocol.Zone) -> [UInt8] {
        var report = effectBase(dataSize: 0x09, zone: zone.rawValue, effect: staticEffect)
        report[13] = 0x01
        report[14] = color.red
        report[15] = color.green
        report[16] = color.blue
        finish(&report)
        return report
    }

    public static func spectrum(zone: RazerNagaVendorProtocol.Zone) -> [UInt8] {
        var report = effectBase(dataSize: 0x06, zone: zone.rawValue, effect: spectrumEffect)
        finish(&report)
        return report
    }

    /// Select the transient custom-matrix buffer for the exact Naga.
    ///
    /// OpenRazer exposes this command for PID `008d` and pairs it with a 1×3
    /// row frame. Keep the storage byte at `NOSTORE`; Agentic Mouse must never
    /// write a runtime mode colour into the mouse's onboard profile.
    public static func activateCustomEffect() -> [UInt8] {
        var report = effectBase(dataSize: 0x0C, zone: 0x00, effect: customEffect)
        finish(&report)
        return report
    }

    /// Fill the exact device's single three-column lighting row with one RGB.
    public static func customFrame(_ color: RGBColor) -> [UInt8] {
        customFrame(scrollWheel: color, logo: color, thumbGrid: color)
    }

    /// Fill the three exposed zones independently. The exact 1×3 order is
    /// scroll wheel, logo, thumb grid; it is not a twelve-key matrix.
    public static func customFrame(
        scrollWheel: RGBColor,
        logo: RGBColor,
        thumbGrid: RGBColor
    ) -> [UInt8] {
        var report = blank(
            dataSize: 0x0E,
            commandID: RazerNagaVendorProtocol.customFrameCommandID
        )
        report[10] = 0x00 // row
        report[11] = 0x00 // first column
        report[12] = 0x02 // last column, inclusive
        for (offset, color) in zip(
            stride(from: 13, through: 19, by: 3),
            [scrollWheel, logo, thumbGrid]
        ) {
            report[offset] = color.red
            report[offset + 1] = color.green
            report[offset + 2] = color.blue
        }
        finish(&report)
        return report
    }

    public static func checksum(of report: [UInt8]) -> UInt8 {
        guard report.count == RazerNagaVendorProtocol.reportLength else { return 0 }
        return report[2..<88].reduce(0, ^)
    }

    private static func effectBase(
        dataSize: UInt8,
        zone: UInt8,
        effect: UInt8
    ) -> [UInt8] {
        var report = blank(
            dataSize: dataSize,
            commandID: RazerNagaVendorProtocol.effectCommandID
        )
        report[8] = RazerNagaVendorProtocol.noStore
        report[9] = zone
        report[10] = effect
        return report
    }

    private static func blank(dataSize: UInt8, commandID: UInt8) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: RazerNagaVendorProtocol.reportLength)
        report[0] = RazerVendorResponseStatus.newCommand.rawValue
        report[1] = RazerNagaVendorProtocol.transactionID
        report[5] = dataSize
        report[6] = RazerNagaVendorProtocol.commandClass
        report[7] = commandID
        return report
    }

    private static func finish(_ report: inout [UInt8]) {
        report[88] = checksum(of: report)
        report[89] = 0
    }
}

public enum RazerVendorError: Error, Equatable, CustomStringConvertible {
    case deviceNotFound
    case multipleDevices
    case openFailed(String)
    case exchangeFailed(String)
    case malformedResponse(String)
    case commandFailed(RazerVendorResponseStatus)

    public var description: String {
        switch self {
        case .deviceNotFound:
            return "exact Razer Naga 1532:008d was not found"
        case .multipleDevices:
            return "more than one exact Razer Naga 1532:008d was found"
        case .openFailed(let status):
            return "could not open exact Razer Naga USB device (\(status))"
        case .exchangeFailed(let status):
            return "Razer vendor report exchange failed (\(status))"
        case .malformedResponse(let detail):
            return "invalid Razer vendor response: \(detail)"
        case .commandFailed(let status):
            return "Razer rejected vendor lighting command with status \(status)"
        }
    }
}
