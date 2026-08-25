import Foundation

/// Legacy exact-device top-level YouTube rewind from physical cell 6.
///
/// Generated live mappings now use the held-wheel `youtubeScrub` lifecycle;
/// keep this decoder temporarily so an already-running old Karabiner rule can
/// release safely while a new app and generated map are installed.
///
/// Karabiner sends this only after physical release. Agentic Mouse then asks
/// the existing VoiceInk bridge to select and rewind the correct YouTube
/// target without activating Chrome.
public struct YouTubeRewindCommand: Equatable, Codable, Sendable {
    public static let commandName = "agentic_mouse_youtube_rewind_five_seconds"
    public static let triggerCell = PhysicalCell.youtubeBackFiveSeconds

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

    public static func decode(_ data: Data) throws -> YouTubeRewindCommand {
        let decoded = try JSONDecoder().decode(YouTubeRewindCommand.self, from: data)
        guard decoded.command == commandName, decoded.physicalCell == triggerCell else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "unexpected YouTube rewind command")
            )
        }
        return decoded
    }
}
