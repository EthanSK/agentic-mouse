#if canImport(AppKit) && canImport(CoreGraphics)
import AppKit
import CoreGraphics
import XCTest
@testable import ScimitarKit

final class ClipboardPreservingTextOutputTests: XCTestCase {
    private let target = TextTarget(
        processIdentifier: 4321,
        elementIdentity: "frontmost:4321",
        redactedApplication: "app:test",
        anchor: .frontmostApplication
    )

    func testPastePostsOneCommandVAndRestoresEveryOriginalPasteboardType() throws {
        let pasteboard = makePasteboard()
        let customType = NSPasteboard.PasteboardType("com.ethansk.agentic-mouse.tests.custom")
        let original = NSPasteboardItem()
        original.setString("original clipboard", forType: .string)
        original.setData(Data([0x01, 0x02, 0x03]), forType: customType)
        XCTAssertTrue(pasteboard.writeObjects([original]))

        let fixture = makeOutput(pasteboard: pasteboard)
        try fixture.output.apply([.insert("a")], to: target)

        XCTAssertEqual(pasteboard.string(forType: .string), "a")
        XCTAssertEqual(fixture.postedEvents.count, 4)
        XCTAssertTrue(fixture.postedEvents.allSatisfy { $0.pid == nil })
        XCTAssertEqual(fixture.keyCodes, [0x37, 0x09, 0x09, 0x37])
        XCTAssertEqual(fixture.scheduledRestorations.count, 1)

        fixture.scheduledRestorations[0]()
        XCTAssertEqual(pasteboard.string(forType: .string), "original clipboard")
        XCTAssertEqual(pasteboard.data(forType: customType), Data([0x01, 0x02, 0x03]))
    }

    func testConsecutiveCharactersRestoreTheClipboardFromBeforeTheFirstCharacter() throws {
        let pasteboard = makePasteboard(initialText: "before keypad")
        let fixture = makeOutput(pasteboard: pasteboard)

        try fixture.output.apply([.insert("a")], to: target)
        try fixture.output.apply([.insert("b")], to: target)
        XCTAssertEqual(pasteboard.string(forType: .string), "b")
        XCTAssertEqual(fixture.scheduledRestorations.count, 2)

        fixture.scheduledRestorations[0]()
        XCTAssertEqual(pasteboard.string(forType: .string), "b", "an older lease must not overwrite a newer Keypad payload")
        fixture.scheduledRestorations[1]()
        XCTAssertEqual(pasteboard.string(forType: .string), "before keypad")
    }

    func testAUserClipboardChangeWinsOverTheScheduledRestore() throws {
        let pasteboard = makePasteboard(initialText: "before keypad")
        let fixture = makeOutput(pasteboard: pasteboard)

        try fixture.output.apply([.insert("a")], to: target)
        pasteboard.clearContents()
        pasteboard.setString("new user copy", forType: .string)
        fixture.scheduledRestorations[0]()

        XCTAssertEqual(pasteboard.string(forType: .string), "new user copy")
    }

    func testTargetChangeRefusesBeforeMutatingThePasteboard() {
        let pasteboard = makePasteboard(initialText: "untouched")
        let fixture = makeOutput(pasteboard: pasteboard)
        fixture.resolver.moveToApplication(pid: 9999)

        XCTAssertThrowsError(try fixture.output.apply([.insert("a")], to: target)) { error in
            XCTAssertEqual(error as? TextOutputError, .targetChanged)
        }
        XCTAssertEqual(pasteboard.string(forType: .string), "untouched")
        XCTAssertTrue(fixture.postedEvents.isEmpty)
        XCTAssertTrue(fixture.scheduledRestorations.isEmpty)
    }

    func testFrontmostApplicationAnchorAcceptsANewlyExposedElementInTheSameApp() throws {
        let pasteboard = makePasteboard(initialText: "before keypad")
        let fixture = makeOutput(pasteboard: pasteboard)
        fixture.resolver.resolution = .ready(
            TextTarget(
                processIdentifier: target.processIdentifier,
                elementIdentity: "ax:4321:1",
                redactedApplication: target.redactedApplication
            )
        )

        try fixture.output.apply([.insert("a")], to: target)

        XCTAssertEqual(fixture.keyCodes, [0x37, 0x09, 0x09, 0x37])
        fixture.scheduledRestorations[0]()
        XCTAssertEqual(pasteboard.string(forType: .string), "before keypad")
    }

    func testBackspaceAndReturnRemainProcessTargetedNativeKeys() throws {
        let pasteboard = makePasteboard(initialText: "untouched")
        let fixture = makeOutput(pasteboard: pasteboard)

        try fixture.output.apply([.deleteBackward(1), .newline], to: target)

        XCTAssertEqual(fixture.keyCodes, [0x33, 0x33, 0x24, 0x24])
        XCTAssertTrue(fixture.postedEvents.allSatisfy { $0.pid == target.processIdentifier })
        XCTAssertEqual(pasteboard.string(forType: .string), "untouched")
    }

    private func makePasteboard(initialText: String? = nil) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("agentic-mouse-tests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        if let initialText { pasteboard.setString(initialText, forType: .string) }
        return pasteboard
    }

    private func makeOutput(pasteboard: NSPasteboard) -> Fixture {
        Fixture(target: target, pasteboard: pasteboard)
    }

    private final class Fixture {
        struct PostedEvent {
            let event: CGEvent
            let pid: pid_t?
        }

        private final class EventBox {
            var values: [PostedEvent] = []
        }

        private final class RestorationBox {
            var values: [() -> Void] = []
        }

        let resolver: StubTextTargetResolver
        let output: ClipboardPreservingTextOutput
        private let eventBox: EventBox
        private let restorationBox: RestorationBox

        var postedEvents: [PostedEvent] { eventBox.values }
        var scheduledRestorations: [() -> Void] { restorationBox.values }

        var keyCodes: [Int64] {
            postedEvents.map { $0.event.getIntegerValueField(.keyboardEventKeycode) }
        }

        init(target: TextTarget, pasteboard: NSPasteboard) {
            resolver = StubTextTargetResolver(resolution: .ready(target))
            let eventBox = EventBox()
            let restorationBox = RestorationBox()
            self.eventBox = eventBox
            self.restorationBox = restorationBox
            output = ClipboardPreservingTextOutput(
                permission: StubAccessibilityPermission(isTrusted: true),
                targetResolver: resolver,
                pasteboard: pasteboard,
                postEvent: { event, pid in eventBox.values.append(PostedEvent(event: event, pid: pid)) },
                scheduleRestore: { _, action in restorationBox.values.append(action) },
                log: Log(category: "test", sink: NullLogSink())
            )
        }
    }
}
#endif
