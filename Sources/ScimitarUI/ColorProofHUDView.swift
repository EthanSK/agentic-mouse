import Combine
import ScimitarKit
import SwiftUI

final class ModeHUDViewModel: ObservableObject {
    @Published var isActive = false
    @Published var modeTitle = "Mouse map"
    @Published var source: MouseSource = .corsair
    @Published var selection: ModeHUDSelection?
    @Published var legend: [ModeHUDLegendItem] = []
    @Published var accent = ScimitarKit.RGBColor(red: 94, green: 210, blue: 255)
    @Published var lightingTargets: ModeLightingTargets = []
    @Published var footerTitle = ""
    @Published var footerHint: String?
    @Published var problem: String?
    @Published var presentationStyle: ModeHUDPresentationStyle = .neutral

    init(source: MouseSource) {
        self.source = source
    }

    func apply(_ snapshot: ModeHUDSnapshot) {
        isActive = snapshot.isActive
        modeTitle = snapshot.modeTitle
        source = snapshot.source
        selection = snapshot.selection
        legend = snapshot.legend
        accent = snapshot.accent
        lightingTargets = snapshot.lightingTargets
        footerTitle = snapshot.footerTitle
        footerHint = snapshot.footerHint
        problem = snapshot.problem
        presentationStyle = snapshot.presentationStyle
    }
}

struct ModeHUDView: View {
    @ObservedObject var model: ModeHUDViewModel

    private var accent: Color { Color(model.accent) }
    private var displayAccent: Color {
        Color(model.presentationStyle.displayAccent(model.accent))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let problem = model.problem, !problem.isEmpty {
                problemBanner(problem)
            }

            grid
            footer
        }
        .padding(27)
        .frame(width: 705)
        .background(panelBackground)
    }

    private var grid: some View {
        VStack(spacing: 9) {
            ForEach(Array(PhysicalCell.displayRowsTopToBottom(for: model.source).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 9) {
                    ForEach(row, id: \.self) { cell in
                        legendCell(for: cell)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func legendCell(for cell: PhysicalCell) -> some View {
        if let item = model.legend.first(where: { $0.cell == cell }) {
            let selected = item.cell == model.selection?.cell
            let cardColors = ModeHUDCardColors(
                modeAccent: model.accent,
                actionAccent: item.accent,
                presentationStyle: model.presentationStyle
            )
            let fillColor = Color(cardColors.fill)
            let borderColor = Color(cardColors.border)
            let foregroundColor = Color(cardColors.foreground)
            VStack(spacing: 4.5) {
                Text(item.actionTitle.uppercased())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(foregroundColor)
                if let detail = item.detail {
                    Text(detail)
                        .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(foregroundColor.opacity(0.72))
                }
                Text(item.cell.displayLabel(on: model.source).uppercased())
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(foregroundColor.opacity(0.58))
            }
            .padding(.horizontal, ModeHUDLayoutMetrics.cardHorizontalContentInset)
            .frame(maxWidth: .infinity, minHeight: 66)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(cardFill(fillColor, selected: selected))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                borderColor.opacity(selected ? 1 : 0.9),
                                lineWidth: selected ? 3.5 : 2.25
                            )
                    )
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Text(model.modeTitle.uppercased())
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(displayAccent)

            Spacer()

            Text(model.source.displayName.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 27, style: .continuous)
        switch model.presentationStyle {
        case .neutral:
            shape
                .fill(.ultraThinMaterial)
                .overlay(
                    shape.strokeBorder(
                        accent.opacity(model.isActive ? 0.92 : 0.28),
                        lineWidth: 2.75
                    )
                )
        case .boldOpaque:
            shape
                .fill(Color(red: 0.035, green: 0.043, blue: 0.075))
                .overlay(
                    LinearGradient(
                        colors: [accent.opacity(0.22), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(shape)
                )
                .overlay(shape.strokeBorder(displayAccent, lineWidth: 3))
        case .pastel:
            shape
                .fill(Color(red: 0.055, green: 0.064, blue: 0.09))
                .overlay(
                    LinearGradient(
                        colors: [displayAccent.opacity(0.38), displayAccent.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(shape)
                )
                .overlay(shape.strokeBorder(displayAccent, lineWidth: 2.5))
        }
    }

    private func cardFill(_ color: Color, selected: Bool) -> Color {
        switch model.presentationStyle {
        case .neutral:
            return color.opacity(selected ? 0.58 : 0.24)
        case .boldOpaque, .pastel:
            return color
        }
    }

    private func problemBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 16.5, weight: .medium))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 10.5)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            )
    }
}

private extension Color {
    init(_ rgb: ScimitarKit.RGBColor) {
        self.init(
            red: Double(rgb.red) / 255.0,
            green: Double(rgb.green) / 255.0,
            blue: Double(rgb.blue) / 255.0,
            opacity: Double(rgb.alpha) / 255.0
        )
    }
}
