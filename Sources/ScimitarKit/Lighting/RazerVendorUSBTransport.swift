#if os(macOS)
import CRazerUSBTransport
import Foundation

public protocol RazerVendorTransport: AnyObject {
    func open() throws
    func exchange(_ request: [UInt8]) throws -> [UInt8]
    func close()
}

/// Legacy IOKit USB-device transport used by established macOS Razer tools.
/// It opens only the exact VID/PID, never detaches or seizes an input interface,
/// and exposes only one acknowledged 90-byte HID control exchange.
public final class RazerVendorUSBTransport: RazerVendorTransport {
    private var handle: AMRazerUSBHandle?

    public init() {}

    /// Read-only presence probe for reconnect recovery. It enumerates the
    /// exact USB device without opening it or disturbing the live controller.
    public static func exactDeviceIsPresent() -> Bool {
        var count: UInt32 = 0
        let status = am_razer_usb_count_exact(
            RazerNagaVendorProtocol.vendorID,
            RazerNagaVendorProtocol.productID,
            &count
        )
        return status == 0 && count == 1
    }

    deinit { close() }

    public func open() throws {
        if handle != nil { return }
        var opened: AMRazerUSBHandle?
        let status = am_razer_usb_open_exact(
            RazerNagaVendorProtocol.vendorID,
            RazerNagaVendorProtocol.productID,
            &opened
        )
        switch status {
        case 0:
            guard let opened else {
                throw RazerVendorError.openFailed("transport returned no handle")
            }
            handle = opened
        case -2:
            throw RazerVendorError.multipleDevices
        case Int32(truncatingIfNeeded: kIOReturnNotFound):
            throw RazerVendorError.deviceNotFound
        default:
            throw RazerVendorError.openFailed(Self.status(status))
        }
    }

    public func exchange(_ request: [UInt8]) throws -> [UInt8] {
        guard let handle else { throw RazerVendorError.deviceNotFound }
        guard request.count == RazerNagaVendorProtocol.reportLength else {
            throw RazerVendorError.exchangeFailed("request was \(request.count) bytes")
        }

        var response = [UInt8](repeating: 0, count: RazerNagaVendorProtocol.reportLength)
        let status = request.withUnsafeBufferPointer { requestBuffer in
            response.withUnsafeMutableBufferPointer { responseBuffer in
                am_razer_usb_exchange(
                    handle,
                    requestBuffer.baseAddress,
                    requestBuffer.count,
                    responseBuffer.baseAddress,
                    responseBuffer.count,
                    RazerNagaVendorProtocol.exchangeDelayMicroseconds
                )
            }
        }
        guard status == 0 else {
            throw RazerVendorError.exchangeFailed(Self.status(status))
        }
        return response
    }

    public func close() {
        if let handle {
            am_razer_usb_close(handle)
        }
        handle = nil
    }

    private static func status(_ status: Int32) -> String {
        String(format: "0x%08X", UInt32(bitPattern: status))
    }
}
#endif
