import CoreGraphics
import Foundation

/// One complete hardware-shaped keyboard lifecycle posted from a reusable HID
/// event source. Modifier transitions use `flagsChanged`, action keys retain
/// their normal down/up types, and small monotonic offsets reproduce physical
/// modifier settling and key dwell without suppressing Ethan's real input.
final class SyntheticKeyboardChordPoster: @unchecked Sendable {
    struct Event: Equatable {
        let type: CGEventType
        let keyCode: CGKeyCode
        let flags: CGEventFlags
        let timestampOffset: TimeInterval

        static func modifier(
            keyCode: CGKeyCode,
            flags: CGEventFlags,
            at timestampOffset: TimeInterval
        ) -> Event {
            Event(
                type: .flagsChanged,
                keyCode: keyCode,
                flags: flags,
                timestampOffset: timestampOffset
            )
        }

        static func key(
            keyCode: CGKeyCode,
            flags: CGEventFlags,
            isDown: Bool,
            at timestampOffset: TimeInterval
        ) -> Event {
            Event(
                type: isDown ? .keyDown : .keyUp,
                keyCode: keyCode,
                flags: flags,
                timestampOffset: timestampOffset
            )
        }
    }

    typealias Sleeper = (TimeInterval) -> Void

    static let shared = SyntheticKeyboardChordPoster()

    private let source: CGEventSource?
    private let sleeper: Sleeper

    init(
        source: CGEventSource? = SyntheticKeyboardChordPoster.makeEventSource(),
        sleeper: @escaping Sleeper = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.source = source
        self.sleeper = sleeper
    }

    func post(_ descriptions: [Event]) -> Bool {
        post(descriptions) { event in
            event.post(tap: .cghidEventTap)
        }
    }

    func post(_ descriptions: [Event], to processIdentifier: pid_t) -> Bool {
        post(descriptions) { event in
            event.postToPid(processIdentifier)
        }
    }

    private func post(
        _ descriptions: [Event],
        deliver: (CGEvent) -> Void
    ) -> Bool {
        guard let source, !descriptions.isEmpty else { return false }

        var previousOffset: TimeInterval = -1
        var created: [(CGEvent, TimeInterval)] = []
        created.reserveCapacity(descriptions.count)
        let startTimestamp = DispatchTime.now().uptimeNanoseconds

        for description in descriptions {
            guard description.timestampOffset.isFinite,
                  description.timestampOffset >= 0,
                  description.timestampOffset > previousOffset,
                  let event = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: description.keyCode,
                    keyDown: description.type != .keyUp
                  )
            else { return false }

            event.type = description.type
            event.flags = description.flags
            event.timestamp = startTimestamp + UInt64(
                description.timestampOffset * 1_000_000_000
            )
            created.append((event, description.timestampOffset))
            previousOffset = description.timestampOffset
        }

        // Every event already exists before the first modifier transition is
        // posted, so allocation failure can never strand a modifier globally.
        var postedOffset: TimeInterval = 0
        for (event, offset) in created {
            let wait = offset - postedOffset
            if wait > 0 { sleeper(wait) }
            deliver(event)
            postedOffset = offset
        }
        return true
    }

    private static func makeEventSource() -> CGEventSource? {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return nil
        }
        source.localEventsSuppressionInterval = 0
        let permitAll = CGEventFilterMask(rawValue: 0x7)
        source.setLocalEventsFilterDuringSuppressionState(
            permitAll,
            state: .eventSuppressionStateSuppressionInterval
        )
        source.setLocalEventsFilterDuringSuppressionState(
            permitAll,
            state: .eventSuppressionStateRemoteMouseDrag
        )
        return source
    }
}
