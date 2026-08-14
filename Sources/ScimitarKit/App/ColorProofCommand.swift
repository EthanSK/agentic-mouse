import Foundation

public struct ColorProofCommand: Equatable, Codable, Sendable {
    public enum Action: String, Codable, Sendable {
        case enter
        case select
        case exit
    }

    public static let commandName = "agentic_mouse_color_proof"

    public let command: String
    public let action: Action
    public let source: MouseSource
    public let physicalCell: PhysicalCell

    public init(action: Action, source: MouseSource, physicalCell: PhysicalCell) {
        self.command = Self.commandName
        self.action = action
        self.source = source
        self.physicalCell = physicalCell
    }

    private enum CodingKeys: String, CodingKey {
        case command, action, source
        case physicalCell = "physical_cell"
    }

    public static func decode(_ data: Data) throws -> ColorProofCommand {
        let decoded = try JSONDecoder().decode(ColorProofCommand.self, from: data)
        guard decoded.command == commandName else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "unexpected user-command namespace")
            )
        }
        return decoded
    }
}
