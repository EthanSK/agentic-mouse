import AppKit
import SwiftUI
@testable import ScimitarUI
import XCTest

/// Ethan's create-chat status (double-clicking the speech button) reuses the review reminder's slot.
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
            // Narrow-screen fallback: the clamped width still keeps one line each.
            WandReviewIndicatorView(content: .review("files"), maximumWidth: 420)
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
        XCTAssertGreaterThan(review.height, status.height, "the subtitle line gets just enough room")
        let slot = try indicator()
        slot.update(mode: "changes")
        slot.update(mode: "files")
        XCTAssertEqual(slot.currentContent, .review("files"), "toggling swaps content in the same slot")
    }

    /// Ethan, 2026-10-30: "This shouldn't be double line ... The subtext can be
    /// smaller, and the whole pill can be wider ... single line for title and
    /// then single line for the subtitle text ... separated by a dot ...
    /// vertically centered". Then: "Hold to stage selection", not commit, and
    /// "double click for stage files mode".
    func testReviewReminderIsOneTitleLineThenOneDotSeparatedSubtitleLine() {
        let changes = WandIndicatorContent.review("changes"), files = WandIndicatorContent.review("files")
        XCTAssertEqual(changes.title, "Review changes")
        XCTAssertEqual(changes.hints, ["Hold to stage selection", "Double-click for Stage files mode"])
        XCTAssertEqual(files.title, "Stage files")
        XCTAssertEqual(files.hints, ["Hold to stage selection", "Double-click for Review changes mode"])
        XCTAssertEqual(WandIndicatorContent.creatingChat.hints, [])
        XCTAssertEqual(WandIndicatorContent.repeatKeysHint.hints, [])
        for content in [changes, files, .creatingChat, .repeatKeysHint] as [WandIndicatorContent] {
            for text in [content.title] + content.hints {
                XCTAssertFalse(text.contains("("), "no bracketed hint: \(text)")
                XCTAssertFalse(text.lowercased().contains("commit"), "staging is never called commit: \(text)")
                XCTAssertFalse(text.lowercased().contains("whether"), text)
            }
        }
    }

    func testEveryLineFitsItsPillAtFullSizeWithTheSmallerSubtitle() {
        typealias V = WandReviewIndicatorView
        // Lounging distance: large title; the subtitle is smaller but readable.
        XCTAssertGreaterThanOrEqual(V.titleSize, 20)
        XCTAssertLessThan(V.detailSize, V.titleSize)
        XCTAssertGreaterThanOrEqual(V.detailSize, 14)
        for content in [.review("changes"), .review("files"), .creatingChat, .repeatKeysHint] as [WandIndicatorContent] {
            let size = V.size(for: content)
            let titleWidth = V.titleLineWidth(content.title)
            let hintWidth = V.hintLineWidth(content.hints)
            // Each line's ends stay clear of the capsule's curve at its row.
            let room = size.width - 2 * V.contentInset(height: size.height, lines: content.hints.isEmpty ? 1 : 2)
            XCTAssertLessThanOrEqual(titleWidth, room, content.title)
            XCTAssertLessThanOrEqual(hintWidth, room, content.hints.joined(separator: " · "))
            XCTAssertLessThanOrEqual(size.width, 640, "wider, not a banner")
        }
        XCTAssertGreaterThan(V.size(for: .review("files")).width, 340, "the review pill grew instead of wrapping")
        XCTAssertGreaterThan(V.hintLineWidth(["A", "B"]), V.hintLineWidth(["A"]) + V.hintLineWidth(["B"]), "the dot and its gaps take room")
    }

    func testSeparatorDotSitsOnTheSubtitleTextCentre() {
        typealias V = WandReviewIndicatorView
        let font = V.detailFont
        // Centre of the lowercase-and-capital body (half way up between the
        // x-height and cap-height centres), measured from the baseline.
        let textCentre = (font.xHeight + font.capHeight) / 4
        // SwiftUI centres the dot on the line box; `dotLift` moves it there.
        let boxCentre = (font.ascender + font.descender) / 2
        XCTAssertEqual(boxCentre + V.dotLift, textCentre, accuracy: 0.25)
        XCTAssertGreaterThan(V.dotDiameter, 3)
        XCTAssertLessThan(V.dotDiameter, font.xHeight / 1.5, "a dot, not a bullet")
    }

    /// The pill's width never exceeds the visible screen; placement still centres it.
    func testPillFrameStaysOnANarrowScreen() {
        let size = WandReviewIndicatorView.size(for: .review("files"), maximumWidth: 300)
        XCTAssertEqual(size.width, 300)
        let natural = WandReviewIndicatorView.lineScales(for: .review("files"), maximumWidth: nil)
        XCTAssertEqual(natural.title, 1); XCTAssertEqual(natural.hints, 1)
        let narrow = WandReviewIndicatorView.lineScales(for: .review("files"), maximumWidth: 420)
        XCTAssertLessThan(narrow.hints, 1, "a narrow screen shrinks the whole subtitle line evenly")
        let clamped = WandReviewIndicatorView.size(for: .review("files"), maximumWidth: 420)
        let room = clamped.width - 2 * WandReviewIndicatorView.contentInset(height: clamped.height, lines: 2)
        XCTAssertLessThanOrEqual(WandReviewIndicatorView.hintLineWidth(WandIndicatorContent.review("files").hints, scale: narrow.hints), room,
                                 "measured at its shrunken size, the whole subtitle still fits")
        let frame = WandHUDPlacement.frame(size: size, visible: NSRect(x: 0, y: 0, width: 324, height: 600), recorderFrames: [])
        XCTAssertGreaterThanOrEqual(frame.minX, 0)
        XCTAssertLessThanOrEqual(frame.maxX, 324)
    }
}
