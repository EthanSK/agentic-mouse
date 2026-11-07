import Foundation
import IOKit

/// Presence of the mouse's physical transport, independent of optional lighting access.
/// Reading registry properties never opens or seizes an input interface.
enum CorsairDevicePresence {
    static func matches(vendorID: Int?, productID: Int? = nil, productName: String?) -> Bool {
        guard vendorID == 0x1B1C, let productName else { return false }
        if productName.localizedCaseInsensitiveContains("scimitar") { return true }
        // Ethan's wireless Corsair 10 arrives through the accepted receiver
        // transport (also bound in Karabiner), whose HID name omits Scimitar.
        // Do not accept iCUE's persistent virtual keyboard as physical presence.
        return productID == 0x2B00
            && productName.caseInsensitiveCompare("CORSAIR SLIPSTREAM WIRELESS USB Receiver") == .orderedSame
    }

    static func isPresent() -> Bool {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator)
                == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            let vendor = IORegistryEntryCreateCFProperty(service, "VendorID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
            let product = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            let productID = IORegistryEntryCreateCFProperty(service, "ProductID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
            IOObjectRelease(service)
            if matches(vendorID: vendor?.intValue, productID: productID?.intValue, productName: product) { return true }
        }
        return false
    }
}
