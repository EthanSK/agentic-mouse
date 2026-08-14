import Foundation

/// One exact-device cell-10 press forwarded by Karabiner. It toggles the
/// persistent ordinary button-map reference without entering a mode.
public struct DefaultMapHintCommand: Equatable, Codable, Sendable {
    public static let commandName = "agentic_mouse_default_map_toggle"
    public static let triggerCell = PhysicalCell.defaultMapToggle

    public let command: String
    public let source: MouseSource
    public let physicalCell: PhysicalCell

    public init(source: MouseSource, physicalCell: PhysicalCell = triggerCell) {
        self.command = Self.commandName
        self.source = source
        self.physicalCell = physicalCell
    }

    private enum CodingKeys: String, CodingKey {
        case command, source
        case physicalCell = "physical_cell"
    }

    public static func decode(_ data: Data) throws -> DefaultMapHintCommand {
        let decoded = try JSONDecoder().decode(DefaultMapHintCommand.self, from: data)
        guard decoded.command == commandName, decoded.physicalCell == triggerCell else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "unexpected default-map hint command")
            )
        }
        return decoded
    }
}
