@testable import AgenticMouseApp
import XCTest

final class CorsairDevicePresenceTests: XCTestCase {
    func testPhysicalScimitarDoesNotRequireTheLightingSDK() {
        XCTAssertTrue(CorsairDevicePresence.matches(vendorID: 0x1B1C, productName: "CORSAIR SCIMITAR ELITE WIRELESS Gaming Mouse"))
        XCTAssertTrue(CorsairDevicePresence.matches(vendorID: 0x1B1C, productName: "Corsair Scimitar RGB"))
    }

    func testOtherCorsairDevicesAndVirtualKeyboardsAreNotTheMouse() {
        XCTAssertFalse(CorsairDevicePresence.matches(vendorID: 0x1B1C, productName: "Corsair Keyboard"))
        XCTAssertFalse(CorsairDevicePresence.matches(vendorID: 0x1B1C, productName: "iCUE Virtual Keyboard"))
        XCTAssertFalse(CorsairDevicePresence.matches(vendorID: 0x1532, productName: "Scimitar"))
        XCTAssertFalse(CorsairDevicePresence.matches(vendorID: nil, productName: nil))
    }

    func testAcceptedWirelessReceiverDoesNotRequireScimitarInTheHIDName() {
        XCTAssertTrue(CorsairDevicePresence.matches(vendorID: 0x1B1C, productID: 0x2B00,
            productName: "CORSAIR SLIPSTREAM WIRELESS USB Receiver"))
        XCTAssertTrue(CorsairDevicePresence.matches(vendorID: 0x1B1C, productID: 0x2B00,
            productName: "Corsair Slipstream Wireless USB Receiver"))
    }

    func testReceiverNameAloneAndPersistentVirtualDevicesCannotEnableTheHUD() {
        for productID in [nil, 0xFFFF, 0x1234] as [Int?] {
            XCTAssertFalse(CorsairDevicePresence.matches(vendorID: 0x1B1C, productID: productID,
                productName: "CORSAIR SLIPSTREAM WIRELESS USB Receiver"))
        }
        XCTAssertFalse(CorsairDevicePresence.matches(vendorID: 0x1B1C, productID: 0xFFFF,
            productName: "Corsair iCUE VirtualHIDKeyboard 1.8.10"))
        XCTAssertFalse(CorsairDevicePresence.matches(vendorID: 0x1532, productID: 0x2B00,
            productName: "CORSAIR SLIPSTREAM WIRELESS USB Receiver"))
    }
}
