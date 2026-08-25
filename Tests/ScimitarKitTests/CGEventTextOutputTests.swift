#if canImport(AppKit) && canImport(CoreGraphics)
import AppKit
import CoreGraphics
import XCTest
@testable import ScimitarKit

final class CGEventTextOutputTests: XCTestCase {
    func testUnicodeInsertionPostsDirectlyToCapturedProcess() throws {
        let fixture = Fixture(target: applicationTarget)

        try fixture.output.apply([.insert("u£—")], to: applicationTarget)

        XCTAssertEqual(fixture.postedEvents.count, 2)
        XCTAssertTrue(fixture.postedEvents.allSatisfy {
            $0.pid == applicationTarget.processIdentifier
        })
        XCTAssertEqual(fixture.unicodeStrings, ["u£—", "u£—"])
    }

    func testUnicodeInsertionDoesNotTouchPasteboard() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("agentic-mouse-direct-text-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        let initialChangeCount = pasteboard.changeCount
        let fixture = Fixture(target: applicationTarget)

        try fixture.output.apply([.insert("u")], to: applicationTarget)

        XCTAssertEqual(pasteboard.string(forType: .string), "keep me")
        XCTAssertEqual(pasteboard.changeCount, initialChangeCount)
    }

    func testApplicationAnchorAcceptsNewExactElementInSameProcess() throws {
        let fixture = Fixture(target: applicationTarget)
        fixture.resolver.resolution = .ready(
            TextTarget(
                processIdentifier: applicationTarget.processIdentifier,
                elementIdentity: "ax:4321:new",
                redactedApplication: applicationTarget.redactedApplication
            )
        )

        try fixture.output.apply([.insert("u")], to: applicationTarget)

        XCTAssertEqual(fixture.unicodeStrings, ["u", "u"])
    }

    func testApplicationAnchorRejectsAppSwitch() {
        let fixture = Fixture(target: applicationTarget)
        fixture.resolver.moveToApplication(pid: 9999)

        XCTAssertThrowsError(try fixture.output.apply([.insert("u")], to: applicationTarget)) {
            XCTAssertEqual($0 as? TextOutputError, .targetChanged)
        }
        XCTAssertTrue(fixture.postedEvents.isEmpty)
    }

    func testExactElementAnchorRejectsSameAppFieldMove() {
        let exactTarget = TextTarget(
            processIdentifier: 4321,
            elementIdentity: "ax:4321:first",
            redactedApplication: "app:test"
        )
        let fixture = Fixture(target: exactTarget)
        fixture.resolver.moveToElement("ax:4321:second")

        XCTAssertThrowsError(try fixture.output.apply([.insert("u")], to: exactTarget)) {
            XCTAssertEqual($0 as? TextOutputError, .targetChanged)
        }
        XCTAssertTrue(fixture.postedEvents.isEmpty)
    }

    func testBackspaceAndReturnRemainNativeProcessTargetedKeys() throws {
        let fixture = Fixture(target: applicationTarget)

        try fixture.output.apply([.deleteBackward(1), .newline], to: applicationTarget)

        XCTAssertEqual(fixture.keyCodes, [0x33, 0x33, 0x24, 0x24])
        XCTAssertTrue(fixture.postedEvents.allSatisfy {
            $0.pid == applicationTarget.processIdentifier
        })
    }

    private var applicationTarget: TextTarget {
        TextTarget(
            processIdentifier: 4321,
            elementIdentity: "frontmost:4321",
            redactedApplication: "app:test",
            anchor: .frontmostApplication
        )
    }

    private final class Fixture {
        struct PostedEvent {
            let event: CGEvent
            let pid: pid_t
        }

        private final class EventBox {
            var values: [PostedEvent] = []
        }

        let resolver: StubTextTargetResolver
        let output: CGEventTextOutput
        private let eventBox: EventBox

        var postedEvents: [PostedEvent] { eventBox.values }
        var keyCodes: [Int64] {
            postedEvents.map { $0.event.getIntegerValueField(.keyboardEventKeycode) }
        }
        var unicodeStrings: [String] {
            postedEvents.map { posted in
                var length = 0
                posted.event.keyboardGetUnicodeString(
                    maxStringLength: 0,
                    actualStringLength: &length,
                    unicodeString: nil
                )
                guard length > 0 else { return "" }
                var units = [UniChar](repeating: 0, count: length)
                posted.event.keyboardGetUnicodeString(
                    maxStringLength: length,
                    actualStringLength: &length,
                    unicodeString: &units
                )
                return String(utf16CodeUnits: units, count: length)
            }
        }

        init(target: TextTarget) {
            resolver = StubTextTargetResolver(resolution: .ready(target))
            let eventBox = EventBox()
            self.eventBox = eventBox
            output = CGEventTextOutput(
                permission: StubAccessibilityPermission(isTrusted: true),
                targetResolver: resolver,
                log: Log(category: "test", sink: NullLogSink()),
                postEvent: { event, pid in
                    eventBox.values.append(PostedEvent(event: event, pid: pid))
                }
            )
        }
    }
}
#endif
