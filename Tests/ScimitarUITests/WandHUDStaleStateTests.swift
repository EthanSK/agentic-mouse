import AppKit
import ScimitarKit
@testable import ScimitarUI
import XCTest

final class WandHUDStaleStateTests: XCTestCase {
    func testHideForgetsTheOutlineSoTheNextOpenIsAFullFreshApply() {
        let model = ModeHUDViewModel(source: .wand, appIconProvider: NoStaleIconProvider())
        let keys = snapshot(title: "Keys mode", focus: ModeHUDPointerFocus(cell: .modeExit, pullX: 0.4))
        XCTAssertFalse(model.apply(keys))
        XCTAssertTrue(model.apply(snapshot(title: "Keys mode", focus: ModeHUDPointerFocus(cell: .modeExit, pullX: 0.6))),
                      "an outline-only change stays on the cheap focus path")

        model.resetAfterHide()
        XCTAssertNil(model.pointerFocus, "no stale Exit Keys outline survives a hide")
        XCTAssertFalse(model.isActive)
        XCTAssertNil(model.feedback)

        let home = snapshot(title: "Default mode", focus: ModeHUDPointerFocus(cell: .frontmostAppModeSelector))
        XCTAssertFalse(model.apply(home), "the next open re-applies everything")
        XCTAssertEqual(model.modeTitle, "Default mode")
        XCTAssertEqual(model.pointerFocus, ModeHUDPointerFocus(cell: .frontmostAppModeSelector))
    }

    func testPageChangeAndOutlineArriveInOneApply() {
        let model = ModeHUDViewModel(source: .wand, appIconProvider: NoStaleIconProvider())
        model.apply(snapshot(title: "Default mode", focus: ModeHUDPointerFocus(cell: PhysicalCell(rawValue: 9)!)))
        let focusOnly = model.apply(snapshot(title: "Keys mode", focus: ModeHUDPointerFocus(cell: .modeExit)))
        XCTAssertFalse(focusOnly, "a page change is a full cut, not an outline animation")
        XCTAssertEqual(model.modeTitle, "Keys mode")
        XCTAssertEqual(model.pointerFocus?.cell, .modeExit)
    }

    func testHiddenWandPresenterNeverResurrectsForFeedback() {
        let presenter = AppKitModeHUDPresenter(source: .wand)
        presenter.hide()
        presenter.flashFeedback(ModeHUDFeedback(message: "Back", tone: .informational))
        XCTAssertFalse(presenter.isVisible)
    }

    private func snapshot(title: String, focus: ModeHUDPointerFocus?) -> ModeHUDSnapshot {
        ModeHUDSnapshot(
            isActive: true,
            modeTitle: title,
            source: .wand,
            selection: nil,
            legend: ModePickerCoordinator.keysLegend(for: .wand),
            accent: ModePickerCoordinator.keysAccent,
            footerTitle: title,
            presentationStyle: .boldOpaque,
            showsOnAllDisplays: true,
            pointerFocus: focus
        )
    }
}

private final class NoStaleIconProvider: ModeHUDAppIconProviding {
    func icon(for backdrop: ModeHUDAppBackdrop) -> NSImage? { nil }
}
