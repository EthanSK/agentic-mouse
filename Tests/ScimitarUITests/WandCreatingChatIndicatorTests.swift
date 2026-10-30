import AppKit
import SwiftUI
@testable import ScimitarUI
import XCTest

/// Ethan's double-Top create-chat status reuses the review reminder's slot.
@MainActor
final class WandCreatingChatIndicatorTests: XCTestCase {
    func testRenderStatusCapsulesForVisualInspection() throws {
        guard let path = ProcessInfo.processInfo.environment["AGENTIC_MOUSE_WAND_STATUS_RENDER"] else {
            throw XCTSkip("opt-in visual artifact")
        }
        let view = VStack(spacing: 18) {
            WandReviewIndicatorView(content: .review("changes"))
            WandReviewIndicatorView(content: .review("files"))
            WandReviewIndicatorView(content: .creatingChat)
            WandReviewIndicatorView(content: .repeatKeysHint)
        }.padding(24).background(Color(white: 0.14))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let representation = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: path))
    }

    private func indicator() throws -> WandReviewIndicator {
        guard NSScreen.main != nil else { throw XCTSkip("no screen") }
        return WandReviewIndicator(screenProvider:{NSScreen.main},present:{_ in})
    }

    func testCreatingChatShowsAloneAndHidesWithNoReview() throws {
        let slot = try indicator()
        slot.setCreatingChat(true)
        XCTAssertEqual(slot.currentContent, .creatingChat)
        XCTAssertTrue(slot.isVisible)
        slot.setCreatingChat(false)
        XCTAssertNil(slot.currentContent)
        XCTAssertFalse(slot.isVisible)
    }

    func testCreatingChatCoversThenRestoresTheLatestReviewSelection() throws {
        let slot = try indicator()
        slot.update(mode: "changes")
        XCTAssertEqual(slot.currentContent, .review("changes"))
        slot.setCreatingChat(true)
        XCTAssertEqual(slot.currentContent, .creatingChat)
        slot.update(mode: "files")
        XCTAssertEqual(slot.currentContent, .creatingChat, "review changes wait underneath")
        slot.setCreatingChat(false)
        XCTAssertEqual(slot.currentContent, .review("files"))
        slot.update(mode: nil)
        XCTAssertFalse(slot.isVisible)
    }

    func testClearedReviewDuringCreatingChatHidesAfterward() throws {
        let slot = try indicator()
        slot.update(mode: "changes"); slot.setCreatingChat(true); slot.update(mode: nil)
        XCTAssertEqual(slot.currentContent, .creatingChat)
        slot.setCreatingChat(false)
        XCTAssertFalse(slot.isVisible)
        XCTAssertEqual(WandReviewIndicatorView(mode: "files").mode, "files", "existing review initializer still works")
    }

    func testRepeatHintSitsBetweenCreatingChatAndReview() throws {
        let slot = try indicator()
        slot.update(mode: "changes")
        slot.setRepeatKeysHint(true)
        XCTAssertEqual(slot.currentContent, .repeatKeysHint)
        slot.setCreatingChat(true)
        XCTAssertEqual(slot.currentContent, .creatingChat, "Creating chat… wins")
        slot.setCreatingChat(false)
        XCTAssertEqual(slot.currentContent, .repeatKeysHint)
        slot.setRepeatKeysHint(false)
        XCTAssertEqual(slot.currentContent, .review("changes"), "the review selection returns")
        slot.update(mode: nil)
        XCTAssertFalse(slot.isVisible)
    }

    func testRepeatHintAloneShowsAndHides() throws {
        let slot = try indicator()
        slot.setRepeatKeysHint(true)
        XCTAssertEqual(slot.currentContent, .repeatKeysHint)
        XCTAssertTrue(slot.isVisible)
        slot.setRepeatKeysHint(false)
        XCTAssertNil(slot.currentContent)
        XCTAssertFalse(slot.isVisible)
    }

    func testReviewReminderNamesItsDoubleClickDestinationAndOnlyItGrows() throws {
        XCTAssertEqual(WandReviewIndicatorView.toggleDestination(for: "changes"), "Stage files")
        XCTAssertEqual(WandReviewIndicatorView.toggleDestination(for: "files"), "Review changes")
        let review = WandReviewIndicatorView.size(for: .review("changes"))
        let status = WandReviewIndicatorView.size(for: .creatingChat)
        XCTAssertEqual(WandReviewIndicatorView.size(for: .repeatKeysHint), status)
        XCTAssertGreaterThan(review.height, status.height, "the third line gets just enough room")
        // Ethan reads the reminder from a lounging distance: large type, and
        // every line fits its capsule at full size (no shrink-to-fit).
        XCTAssertGreaterThanOrEqual(WandReviewIndicatorView.titleSize, 20)
        XCTAssertGreaterThanOrEqual(WandReviewIndicatorView.detailSize, 16)
        func width(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight) -> CGFloat {
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
            return (text as NSString).size(withAttributes: [.font: font]).width
        }
        let icon = WandReviewIndicatorView.iconSize + 8, padding: CGFloat = 40
        for text in ["Creating chat…", "Double-click to exit"] {
            XCTAssertLessThanOrEqual(icon + width(text, WandReviewIndicatorView.titleSize, .semibold) + padding, status.width, text)
        }
        // The capsule's round ends narrow its top and bottom rows.
        let endInset = review.height / 2 - sqrt(pow(review.height / 2, 2) - pow(review.height / 2 - 14, 2))
        for text in ["(Hold to commit selection)", "Double-click for Review changes", "Double-click for Stage files"] {
            XCTAssertLessThanOrEqual(width(text, WandReviewIndicatorView.detailSize, .medium) + padding + endInset * 2, review.width, text)
        }
        let slot = try indicator()
        slot.update(mode: "changes")
        slot.update(mode: "files")
        XCTAssertEqual(slot.currentContent, .review("files"), "toggling swaps content in the same slot")
    }
}
