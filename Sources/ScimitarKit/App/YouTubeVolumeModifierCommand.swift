import Foundation

/// Exact-device press/release lifecycle for physical cell 5 outside VS Code.
/// Agentic Mouse delays ordinary Forward until release so a same-source 6+5
/// volume ratchet can consume the gesture without navigating the browser.
public struct YouTubeVolumeModifierCommand: Equatable, Codable, Sendable {
    public static let commandName = "agentic_mouse_youtube_volume_modifier"
    public static let triggerCell = PhysicalCell(rawValue: 5)!

    public let command: String
    public let source: MouseSource
    public let phase: ModePickerCommand.Phase

    public init(source: MouseSource, phase: ModePickerCommand.Phase) {
        command = Self.commandName
        self.source = source
        self.phase = phase
    }

    public static func decode(_ data: Data) throws -> YouTubeVolumeModifierCommand {
        let decoded = try JSONDecoder().decode(YouTubeVolumeModifierCommand.self, from: data)
        guard decoded.command == commandName else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "unexpected YouTube volume modifier command")
            )
        }
        return decoded
    }
}
