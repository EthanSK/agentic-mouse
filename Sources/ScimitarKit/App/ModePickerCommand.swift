import Foundation

/// Exact-device Karabiner ingress for the shared top-level mode picker.
public struct ModePickerCommand: Equatable, Codable, Sendable {
    public enum Action: String, Codable, Sendable {
        case open
        case openAppSpecific
        case openKeys
        case select
        case selectNative
        case close
    }

    public enum Phase: String, Codable, Sendable {
        case press
        case release
    }

    public static let commandName = "agentic_mouse_mode_picker"

    public let command: String
    public let action: Action
    public let source: MouseSource
    public let physicalCell: PhysicalCell
    public let phase: Phase

    public init(
        action: Action,
        source: MouseSource,
        physicalCell: PhysicalCell,
        phase: Phase = .press
    ) {
        command = Self.commandName
        self.action = action
        self.source = source
        self.physicalCell = physicalCell
        self.phase = phase
    }

    private enum CodingKeys: String, CodingKey {
        case command, action, source
        case physicalCell = "physical_cell"
        case phase
    }

    public static func decode(_ data: Data) throws -> ModePickerCommand {
        let decoded = try JSONDecoder().decode(ModePickerCommand.self, from: data)
        guard decoded.command == commandName else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "unexpected user-command namespace")
            )
        }
        return decoded
    }
}
