import Foundation

/// One exact-device top-level screenshot toggle from physical cell 3.
/// Agentic Mouse starts a native interactive selection on the first press and
/// cancels that still-running selection on the next press.
public struct SelectedAreaScreenshotCommand: Equatable, Codable, Sendable {
    public static let commandName = "agentic_mouse_selected_area_screenshot_toggle"
    public static let triggerCell = PhysicalCell.screenshotToggle

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

    public static func decode(_ data: Data) throws -> SelectedAreaScreenshotCommand {
        let decoded = try JSONDecoder().decode(SelectedAreaScreenshotCommand.self, from: data)
        guard decoded.command == commandName, decoded.physicalCell == triggerCell else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "unexpected selected-area screenshot command")
            )
        }
        return decoded
    }
}


/// Receiver-only start for Ethan's Bottom triple-click. Retries never toggle
/// an existing native selection off. The ordinary mouse toggle is unchanged.
public struct WandScreenshotStartCommand: Decodable, Equatable, Sendable {
    public static let commandName = "agentic_mouse_wand_screenshot_start"
    public let command:String
    public let version:Int
    public let id:String

    public static func decode(_ data:Data) throws -> Self {
        guard data.count <= 256,
              let fields=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              Set(fields.keys) == ["command","version","id"] else {
            throw DecodingError.dataCorrupted(.init(codingPath:[],debugDescription:"invalid wand screenshot request"))
        }
        let value=try JSONDecoder().decode(Self.self,from:data)
        guard value.command == commandName,value.version == 1,UUID(uuidString:value.id) != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath:[],debugDescription:"invalid wand screenshot request"))
        }
        return value
    }
}
