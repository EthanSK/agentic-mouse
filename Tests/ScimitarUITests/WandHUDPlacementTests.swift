import AppKit
@testable import ScimitarUI
import XCTest

final class WandHUDPlacementTests:XCTestCase {
    let screen=NSRect(x:-1728,y:612,width:1728,height:1090)
    let size=NSSize(width:500,height:300)

    func testIdleHUDUsesBottomCentre() {
        let r=WandHUDPlacement.frame(size:size,visible:screen,recorderFrames:[])
        XCTAssertEqual(r.midX,screen.midX)
        XCTAssertEqual(r.minY,screen.minY+12)
    }
    func testHUDClearsActualRecorderGeometry() {
        let recorder=NSRect(x:screen.midX-200,y:screen.minY+30,width:400,height:130)
        let r=WandHUDPlacement.frame(size:size,visible:screen,recorderFrames:[recorder])
        XCTAssertEqual(r.minY,recorder.maxY+12)
        XCTAssertFalse(r.intersects(recorder))
        XCTAssertEqual(r.midX,screen.midX)
    }
    func testOtherScreenAndNonoverlappingPanelsDoNotMoveHUD() {
        let unrelated=[NSRect(x:0,y:0,width:400,height:150),
            NSRect(x:screen.minX,y:screen.minY,width:100,height:100)]
        let r=WandHUDPlacement.frame(size:size,visible:screen,recorderFrames:unrelated)
        XCTAssertEqual(r.minY,screen.minY+12)
    }
    func testHighestOverlappingPanelWinsAndTopIsClamped() {
        let panels=[NSRect(x:screen.midX-100,y:screen.minY,width:200,height:60),
            NSRect(x:screen.midX-100,y:screen.minY+30,width:200,height:180)]
        let r=WandHUDPlacement.frame(size:size,visible:screen,recorderFrames:panels)
        XCTAssertEqual(r.minY,panels[1].maxY+12)
        let tall=WandHUDPlacement.frame(size:NSSize(width:500,height:1000),visible:screen,recorderFrames:panels)
        XCTAssertEqual(tall.maxY,screen.maxY)
    }
    func testVisibleSessionDoesNotFollowRecorderStartupWindowChanges() {
        var frames: [NSRect] = []
        var reads = 0
        let anchor = WandHUDPlacement.Anchor {
            reads += 1
            return frames
        }
        let initial = anchor.frame(size:size,visible:screen)
        // Agent Flow's transparent host appears, then its compact state changes.
        frames = [NSRect(x:screen.midX-270,y:screen.minY+24,width:540,height:430)]
        XCTAssertEqual(anchor.frame(size:size,visible:screen),initial)
        frames = [NSRect(x:screen.midX-200,y:screen.minY+24,width:400,height:97)]
        XCTAssertEqual(anchor.frame(size:size,visible:screen),initial)
        XCTAssertEqual(reads,1)
        let reopened = WandHUDPlacement.Anchor { frames }
        XCTAssertEqual(reopened.frame(size:size,visible:screen).minY,frames[0].maxY+12)
    }

    func testAnchoredClearanceSurvivesTemporaryRecorderDisappearance() {
        var frames = [NSRect(x:screen.midX-200,y:screen.minY+24,width:400,height:97)]
        let anchor = WandHUDPlacement.Anchor { frames }
        let initial = anchor.frame(size:size,visible:screen)
        frames = []
        XCTAssertEqual(anchor.frame(size:size,visible:screen),initial)
        XCTAssertEqual(WandHUDPlacement.Anchor { frames }.frame(size:size,visible:screen).minY,screen.minY+12)
    }

}
