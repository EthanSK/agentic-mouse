@testable import AgenticMouseApp
import CoreGraphics
import ScimitarKit
import XCTest

final class WandHeldKeysTests: XCTestCase {
    func testSwitchAppContextOwnershipRequiresAcceptedPressAndClearsOnRelease() {
        var accepts = false
        let keys = WandHeldKeys { _ in accepts }
        XCTAssertFalse(keys.isSwitchAppHeld)
        keys.handle(page: .modes, home: true, cell: .switchApp, phase: .press)
        XCTAssertFalse(keys.isSwitchAppHeld, "failed native output must not enable receiver loops")
        accepts = true
        keys.handle(page: .modes, home: true, cell: .switchApp, phase: .press)
        XCTAssertTrue(keys.isSwitchAppHeld)
        keys.handle(page: .modes, home: true, cell: .switchApp, phase: .release)
        XCTAssertFalse(keys.isSwitchAppHeld)
        keys.handle(page: .keys, home: false, cell: PhysicalCell(rawValue: 2)!, phase: .press)
        XCTAssertFalse(keys.isSwitchAppHeld, "Shift in Keys is a different key owner")
        keys.handle(page: .modes, home: true, cell: .switchApp, phase: .press)
        XCTAssertTrue(keys.isSwitchAppHeld)
        keys.release()
        XCTAssertFalse(keys.isSwitchAppHeld, "teardown also ends the advertised key ownership")
    }
    func testSwitchAppStepsInBothDirectionsOnlyWhileCommandIsOwned() {
        var batches:[[SyntheticKeyboardChordPoster.Event]]=[]
        let keys=WandHeldKeys {batches.append($0);return true}
        XCTAssertFalse(keys.switchAppStep(.down))
        keys.handle(page:.modes,home:true,cell:.switchApp,phase:.press)
        XCTAssertTrue(keys.switchAppStep(.down))
        XCTAssertEqual(batches.last?.map(\.keyCode),[48,48])
        XCTAssertTrue(batches.last!.allSatisfy{$0.flags == .maskCommand})
        XCTAssertTrue(keys.switchAppStep(.up))
        XCTAssertEqual(batches.last?.map(\.keyCode),[56,48,48,56])
        XCTAssertEqual(batches.last?.last?.flags,.maskCommand)
        keys.release()
        XCTAssertEqual(batches.last?.last?.flags,[])
        XCTAssertFalse(keys.switchAppStep(.down))
    }
    func testSwitchAppRetainsCommandUntilReleaseAndDoesNotRepeat() {
        var batches:[[SyntheticKeyboardChordPoster.Event]]=[]
        let keys=WandHeldKeys { batches.append($0);return true }
        let cell=PhysicalCell.switchApp
        XCTAssertTrue(keys.handle(page:.modes,home:true,cell:cell,phase:.press))
        XCTAssertEqual(batches.count,1)
        XCTAssertEqual(batches[0].map(\.type),[.flagsChanged,.keyDown,.keyUp])
        XCTAssertTrue(batches[0].allSatisfy{$0.flags.contains(.maskCommand)})
        keys.handle(page:.modes,home:true,cell:cell,phase:.press)
        XCTAssertEqual(batches.count,1)
        keys.handle(page:.modes,home:true,cell:cell,phase:.release)
        XCTAssertEqual(batches.count,2)
        XCTAssertEqual(batches[1].first?.keyCode,55)
        XCTAssertEqual(batches[1].first?.flags,[])
        keys.release();XCTAssertEqual(batches.count,2)
    }
    func testShiftKeepsItsRealDownUpLifetime() {
        var batches:[[SyntheticKeyboardChordPoster.Event]]=[]
        let keys=WandHeldKeys {batches.append($0);return true}
        keys.handle(page:.keys,home:false,cell:PhysicalCell(rawValue:2)!,phase:.press)
        XCTAssertEqual(batches.last?.first?.flags,.maskShift)
        keys.release()
        XCTAssertEqual(batches.last?.first?.flags,[])
        XCTAssertFalse(keys.handle(page:.keys,home:false,cell:PhysicalCell(rawValue:7)!,phase:.press))
        XCTAssertFalse(keys.handle(page:.modes,home:true,cell:PhysicalCell(rawValue:1)!,phase:.press))
    }
    /// Wand Enter is plain Enter, exactly as on the mice: no held Command.
    func testWandHomeEnterIsNotAHeldCommandChord() {
        var batches:[[SyntheticKeyboardChordPoster.Event]]=[]
        let keys=WandHeldKeys {batches.append($0);return true}
        XCTAssertFalse(keys.handle(page:.modes,home:true,cell:PhysicalCell(rawValue:7)!,phase:.press))
        XCTAssertFalse(keys.handle(page:.modes,home:true,cell:PhysicalCell(rawValue:7)!,phase:.release))
        XCTAssertTrue(batches.isEmpty,"Enter goes through the ordinary home action, never Command")
    }
}
