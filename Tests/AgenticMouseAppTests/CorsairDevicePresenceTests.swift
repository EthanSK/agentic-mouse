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
}
