#if os(macOS)
import Foundation
import IOKit
import IOKit.hid

/// User-space Apple HID transport scoped only to the exact LampArray interface.
/// It never opens the Naga keyboard, pointer, or vendor interfaces.
public final class RazerLampArrayIOHIDTransport: RazerLampArrayTransport {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?

    public init() {}

    deinit {
        close()
    }

    public func open() throws {
        if device != nil { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: RazerNagaLampArray.vendorID,
            kIOHIDProductIDKey as String: RazerNagaLampArray.productID,
            kIOHIDPrimaryUsagePageKey as String: RazerNagaLampArray.usagePage,
            kIOHIDPrimaryUsageKey as String: RazerNagaLampArray.usage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let managerStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerStatus == kIOReturnSuccess else {
            throw RazerLampArrayError.openFailed(Self.status(managerStatus))
        }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw RazerLampArrayError.deviceNotFound
        }
        guard devices.count == 1, let device = devices.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw RazerLampArrayError.multipleDevices(devices.count)
        }

        let deviceStatus = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceStatus == kIOReturnSuccess else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw RazerLampArrayError.openFailed(Self.status(deviceStatus))
        }

        guard Self.intProperty(device, kIOHIDVendorIDKey) == RazerNagaLampArray.vendorID,
              Self.intProperty(device, kIOHIDProductIDKey) == RazerNagaLampArray.productID,
              Self.intProperty(device, kIOHIDPrimaryUsagePageKey) == RazerNagaLampArray.usagePage,
              Self.intProperty(device, kIOHIDPrimaryUsageKey) == RazerNagaLampArray.usage
        else {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw RazerLampArrayError.unsupportedDevice("opened HID interface failed exact identity re-check")
        }

        self.manager = manager
        self.device = device
    }

    public func reportDescriptor() throws -> [UInt8] {
        guard let device else { throw RazerLampArrayError.deviceNotFound }
        guard let data = IOHIDDeviceGetProperty(device, kIOHIDReportDescriptorKey as CFString) as? Data else {
            throw RazerLampArrayError.unsupportedDevice("HID report descriptor is unavailable")
        }
        return [UInt8](data)
    }

    public func readFeatureReport(id: UInt8, maximumLength: Int) throws -> [UInt8] {
        guard let device else { throw RazerLampArrayError.deviceNotFound }
        var bytes = [UInt8](repeating: 0, count: maximumLength)
        bytes[0] = id
        var length = maximumLength
        let status = IOHIDDeviceGetReport(
            device,
            kIOHIDReportTypeFeature,
            CFIndex(id),
            &bytes,
            &length
        )
        guard status == kIOReturnSuccess else {
            throw RazerLampArrayError.readFailed(reportID: id, status: Self.status(status))
        }
        return Array(bytes.prefix(length))
    }

    public func writeFeatureReport(_ report: [UInt8]) throws {
        guard let device else { throw RazerLampArrayError.deviceNotFound }
        guard let reportID = report.first else {
            throw RazerLampArrayError.writeFailed(reportID: 0, status: "empty report")
        }
        let status = report.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeFeature,
                CFIndex(reportID),
                buffer.baseAddress!,
                buffer.count
            )
        }
        guard status == kIOReturnSuccess else {
            throw RazerLampArrayError.writeFailed(reportID: reportID, status: Self.status(status))
        }
    }

    public func close() {
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil
        manager = nil
    }

    private static func status(_ status: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: status))
    }

    private static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue
    }
}
#endif
