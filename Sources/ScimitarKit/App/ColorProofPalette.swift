import Foundation

public struct ColorProofSwatch: Equatable, Hashable, Sendable {
    public let cell: PhysicalCell
    public let name: String
    public let color: RGBColor

    public init(cell: PhysicalCell, name: String, color: RGBColor) {
        self.cell = cell
        self.name = name
        self.color = color
    }
}

/// One deliberately distinct colour per physical side-grid cell.
public enum ColorProofPalette {
    public static let swatches: [ColorProofSwatch] = [
        swatch(1, "Red", "#FF0000"),
        swatch(2, "Orange", "#FF8000"),
        swatch(3, "Yellow", "#FFFF00"),
        swatch(4, "Lime", "#80FF00"),
        swatch(5, "Green", "#00FF00"),
        swatch(6, "Spring", "#00FF80"),
        swatch(7, "Cyan", "#00FFFF"),
        swatch(8, "Azure", "#0080FF"),
        swatch(9, "Blue", "#0000FF"),
        swatch(10, "Violet", "#8000FF"),
        swatch(11, "Magenta", "#FF00FF"),
        swatch(12, "Rose", "#FF0080"),
    ]

    public static func swatch(for cell: PhysicalCell) -> ColorProofSwatch {
        swatches[cell.rawValue - 1]
    }

    public static let legend: [ModeHUDLegendItem] = swatches.map { swatch in
        ModeHUDLegendItem(
            cell: swatch.cell,
            actionTitle: "Solid \(swatch.name)",
            detail: swatch.color.hexString,
            accent: swatch.color
        )
    }

    private static func swatch(_ rawCell: Int, _ name: String, _ hex: String) -> ColorProofSwatch {
        ColorProofSwatch(
            cell: PhysicalCell(rawValue: rawCell)!,
            name: name,
            color: RGBColor(hex: hex)!
        )
    }
}
