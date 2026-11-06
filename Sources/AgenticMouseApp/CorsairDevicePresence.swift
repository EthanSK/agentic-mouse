import Foundation
import IOKit

/// Presence of the actual mouse, independent of optional iCUE lighting access.
/// Reading registry properties never opens or seizes an input interface.
enum CorsairDevicePresence {
    static func matches(vendorID: Int?, productName: String?) -> Bool {
        vendorID == 0x1B1C && productName?.localizedCaseInsensitiveContains("scimitar") == true
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
            IOObjectRelease(service)
            if matches(vendorID: vendor?.intValue, productName: product) { return true }
        }
        return false
    }
}
