import Foundation

/// Where committed text goes. Injectable so the engine can be exercised with no
/// Accessibility permission and no foreground app.
public protocol TextOutput: AnyObject {
    /// Applies the commands in order, **to the given target only**.
    ///
    /// Implementations must deliver to `target.processIdentifier` specifically
    /// rather than posting a global HID event, so that a race between the user
    /// switching apps and the commit landing cannot type into the wrong window.
    func apply(_ commands: [TextCommand], to target: TextTarget) throws
}

public enum TextOutputError: Error, Equatable {
    case accessibilityPermissionMissing
    case eventSourceUnavailable
    case targetChanged
}

/// Records commands instead of typing them. Used by tests and by `--dry-run`.
public final class RecordingTextOutput: TextOutput {
    public struct Delivery: Equatable {
        public let commands: [TextCommand]
        public let target: TextTarget
    }

    public private(set) var deliveries: [Delivery] = []
    public var errorToThrow: TextOutputError?

    public init() {}

    public var commands: [TextCommand] { deliveries.flatMap(\.commands) }

    /// The text each target would have ended up holding. Lets a test assert
    /// "typing 2-2-8 gave `bt`, and the other app received nothing" in one line.
    public private(set) var buffers: [TextTarget: String] = [:]

    /// Convenience for single-target tests.
    public var buffer: String { buffers.values.first ?? "" }

    public func apply(_ commands: [TextCommand], to target: TextTarget) throws {
        if let errorToThrow { throw errorToThrow }
        deliveries.append(Delivery(commands: commands, target: target))

        var text = buffers[target] ?? ""
        for command in commands {
            switch command {
            case .insert(let value):
                text.append(value)
            case .deleteBackward(let count):
                for _ in 0..<count where !text.isEmpty { text.removeLast() }
            case .deleteWordBackward:
                while let last = text.last, last == " " { text.removeLast() }
                while let last = text.last, last != " " { text.removeLast() }
            case .newline:
                text.append("\n")
            }
        }
        buffers[target] = text
    }

    public func buffer(for target: TextTarget) -> String { buffers[target] ?? "" }

    public func reset() {
        deliveries.removeAll()
        buffers.removeAll()
    }
}
