import AppKit
import ScimitarKit
@testable import ScimitarUI
import SwiftUI
import XCTest

final class WandAdjustRingTests: XCTestCase {
    private let card = PhysicalCell(rawValue: 4)!

    func testAdjustingRingIsVisiblyDistinctFromNavigationAndArming() {
        XCTAssertNotEqual(WandAdjustRingStyle.dash, ModeHUDPointerFocusMetrics.armedDash,
                          "a ratchet, not the armed dashes")
        XCTAssertFalse(WandAdjustRingStyle.dash.isEmpty, "never the solid navigation outline")
        XCTAssertGreaterThan(WandAdjustRingStyle.lineWidth, ModeHUDPointerFocusMetrics.lineWidth)
        XCTAssertEqual(WandAdjustRingStyle.dash.reduce(0, +), WandAdjustRingStyle.dashPeriod)
    }

    func testEachSentDetentMovesTheRatchetExactlyOneNotchInItsDirection() {
        XCTAssertEqual(WandAdjustRingStyle.dashPhase(netSteps: 0), 0)
        XCTAssertEqual(WandAdjustRingStyle.dashPhase(netSteps: 1), WandAdjustRingStyle.dashPeriod)
        XCTAssertEqual(WandAdjustRingStyle.dashPhase(netSteps: -2), -2 * WandAdjustRingStyle.dashPeriod)
        XCTAssertLessThan(WandAdjustRingStyle.rippleOffset(lastStepWasUp: true), 0, "up pulses toward the top")
        XCTAssertGreaterThan(WandAdjustRingStyle.rippleOffset(lastStepWasUp: false), 0)
        XCTAssertEqual(WandAdjustRingStyle.rippleOffset(lastStepWasUp: nil), 0)
    }

    func testReduceMotionKeepsTheInformationButRemovesEveryMotion() {
        let stepped = ModeHUDWheelAdjustment(pull: -0.4, netSteps: 2, sentSteps: 2, lastStepWasUp: true)
        XCTAssertNil(WandAdjustRingStyle.notchAnimation(reduceMotion: true))
        XCTAssertNil(WandAdjustRingStyle.stretchAnimation(reduceMotion: true))
        XCTAssertNil(WandAdjustRingStyle.rippleAnimation(reduceMotion: true))
        XCTAssertFalse(WandAdjustRingStyle.showsRipple(stepped, reduceMotion: true))
        XCTAssertNotNil(WandAdjustRingStyle.notchAnimation(reduceMotion: false))
        XCTAssertTrue(WandAdjustRingStyle.showsRipple(stepped, reduceMotion: false))
        XCTAssertFalse(WandAdjustRingStyle.showsRipple(ModeHUDWheelAdjustment(), reduceMotion: false),
                       "no pulse before anything is sent")
    }

    func testAdjustmentNeverCarriesNavigationPull() {
        let focus = ModeHUDPointerFocus(cell: card, pullX: 0.8, pullY: -0.6,
                                        adjustment: ModeHUDWheelAdjustment(pull: 0.3))
        XCTAssertEqual(focus.pullX, 0)
        XCTAssertEqual(focus.pullY, 0)
        XCTAssertTrue(focus.isArmed)
        XCTAssertEqual(ModeHUDWheelAdjustment(pull: 4, netSteps: 5_000, sentSteps: -3).pull, 1)
        XCTAssertNil(ModeHUDWheelAdjustment(sentSteps: 0, lastStepWasUp: true).lastStepWasUp)
    }

    func testAdjustmentUpdatesStayOnTheFocusOnlyPathSoThePanelNeverReflows() {
        let model = ModeHUDViewModel(source: .wand, appIconProvider: NoAdjustIconProvider())
        XCTAssertFalse(model.apply(snapshot(focus: ModeHUDPointerFocus(cell: card, isArmed: true))))
        for adjustment in [
            ModeHUDWheelAdjustment(),
            ModeHUDWheelAdjustment(pull: -0.5),
            ModeHUDWheelAdjustment(pull: 0.3, netSteps: 1, sentSteps: 1, lastStepWasUp: true),
            ModeHUDWheelAdjustment(pull: 0.1, netSteps: -1, sentSteps: 3, lastStepWasUp: false),
        ] {
            XCTAssertTrue(model.apply(snapshot(focus: ModeHUDPointerFocus(cell: card, adjustment: adjustment))),
                          "adjustment feedback must not remeasure or reposition the HUD")
            XCTAssertEqual(model.pointerFocus?.adjustment, adjustment)
        }
        XCTAssertTrue(model.apply(snapshot(focus: nil)), "release clears it on the same cheap path")
        XCTAssertNil(model.pointerFocus)
    }

    @MainActor
    func testEveryOutlineStateRendersInTheSameFrame() throws {
        let states: [ModeHUDPointerFocus?] = [
            nil,
            ModeHUDPointerFocus(cell: card, pullX: 0.6),
            ModeHUDPointerFocus(cell: card, isArmed: true),
            ModeHUDPointerFocus(cell: card, adjustment: ModeHUDWheelAdjustment(pull: -0.9)),
            ModeHUDPointerFocus(cell: card, adjustment: ModeHUDWheelAdjustment(pull: 0.4, netSteps: 3, sentSteps: 3, lastStepWasUp: true)),
        ]
        var sizes: [CGSize] = []
        var images: [NSImage] = []
        for focus in states {
            let model = ModeHUDViewModel(source: .wand, appIconProvider: NoAdjustIconProvider())
            model.apply(snapshot(focus: focus))
            let renderer = ImageRenderer(content: ModeHUDView(model: model))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage)
            sizes.append(image.size)
            images.append(image)
        }
        XCTAssertEqual(Set(sizes.map { "\($0.width)x\($0.height)" }).count, 1,
                       "no outline state may change HUD geometry: \(sizes)")
        if let destination = ProcessInfo.processInfo.environment["WAND_WHEEL_VISUAL_OUTPUT"],
           let cardSize = sizes.first {
            let gap: CGFloat = 20
            let preview = NSImage(size: CGSize(width: cardSize.width * 3 + gap * 4,
                                               height: cardSize.height * 2 + gap * 3))
            preview.lockFocus()
            NSColor.black.setFill()
            NSRect(origin: .zero, size: preview.size).fill()
            for (index, image) in images.enumerated() {
                let x = gap + CGFloat(index % 3) * (cardSize.width + gap)
                let y = preview.size.height - gap - CGFloat(index / 3 + 1) * cardSize.height - CGFloat(index / 3) * gap
                image.draw(in: NSRect(origin: CGPoint(x: x, y: y), size: cardSize))
            }
            preview.unlockFocus()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(preview.tiffRepresentation)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: destination))
        }
    }

    private func snapshot(focus: ModeHUDPointerFocus?) -> ModeHUDSnapshot {
        ModeHUDSnapshot(
            isActive: true,
            modeTitle: "Codex mode",
            source: .wand,
            selection: nil,
            legend: AppSpecificTarget.codex.definition.legend,
            accent: CodexMode.accent,
            footerTitle: "Codex mode",
            presentationStyle: .boldOpaque,
            showsOnAllDisplays: true,
            pointerFocus: focus
        )
    }
}

private final class NoAdjustIconProvider: ModeHUDAppIconProviding {
    func icon(for backdrop: ModeHUDAppBackdrop) -> NSImage? { nil }
}
