import Combine
import ScimitarKit
import SwiftUI

/// Observable mirror of `HUDSnapshot`.
final class HUDViewModel: ObservableObject {
    @Published var isActive = false
    @Published var source: MouseSource = .corsair
    @Published var rows: [[HUDLayout.Cell]] = []
    @Published var pendingDescription = "Ready"
    @Published var statusLine = "abc"
    @Published var progress: Double?
    @Published var problem: String?

    init(source: MouseSource) {
        self.source = source
    }

    func apply(_ snapshot: HUDSnapshot) {
        isActive = snapshot.isActive
        source = snapshot.source
        rows = HUDLayout.grid(for: snapshot, toggleKey: snapshot.toggleKey)
        pendingDescription = HUDLayout.pendingDescription(for: snapshot)
        statusLine = HUDLayout.statusLine(for: snapshot)
        progress = HUDLayout.pendingProgress(for: snapshot)
        problem = snapshot.problem
    }
}

/// The reference card.
///
/// Laid out as the source mouse's real 4×3 thumb pad rather than as a phone
/// keypad, because the user is feeling for a button, not reading a phone. The
/// large label is the number printed on that exact mouse; letter groups retain
/// the familiar phone mapping.
struct HUDView: View {
    @ObservedObject var model: HUDViewModel
    let showsTapProgressRing: Bool

    private let modeColor = Color(red: 1.0, green: 0.0, blue: 0.66)

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
        .background(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .strokeBorder(modeColor.opacity(model.isActive ? 0.55 : 0.15), lineWidth: 2.25)
                )
        )
    }

    // MARK: - Sections

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

    private var grid: some View {
        VStack(spacing: 9) {
            ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 9) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        cellView(cell)
                    }
                }
            }
        }
    }

    private func cellView(_ cell: HUDLayout.Cell) -> some View {
        VStack(spacing: 4) {
            Text(cell.legend)
                .font(.system(size: 22.5, weight: .bold, design: .rounded))

            if cell.cycle.isEmpty {
                Text(cell.caption)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(cell.isModeToggle ? modeColor : .secondary)
            } else {
                cyclePreview(cell)
            }

            if let hold = cell.holdCaption {
                Text(hold)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Text(sourceMouseLabel(for: cell.key))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, ModeHUDLayoutMetrics.cardHorizontalContentInset)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10.5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(background(for: cell))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            cell.isPending ? modeColor : Color.primary.opacity(0.08),
                            lineWidth: cell.isPending ? 2.25 : 1.5
                        )
                )
        )
    }

    /// Letter keys fit on one line. The thirteen-character punctuation cycle
    /// needs a compact two-row grid so every tap target remains visible.
    @ViewBuilder
    private func cyclePreview(_ cell: HUDLayout.Cell) -> some View {
        if cell.cycle.count > 6 {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 12), spacing: 1),
                    count: 7
                ),
                spacing: 2
            ) {
                ForEach(Array(cell.cycle.enumerated()), id: \.offset) { index, character in
                    cycleCharacter(character, index: index, activeIndex: cell.activeCycleIndex, dense: true)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 2) {
                ForEach(Array(cell.cycle.enumerated()), id: \.offset) { index, character in
                    cycleCharacter(character, index: index, activeIndex: cell.activeCycleIndex, dense: false)
                }
            }
        }
    }

    private func cycleCharacter(
        _ character: String,
        index: Int,
        activeIndex: Int?,
        dense: Bool
    ) -> some View {
        Text(character)
            .font(.system(
                size: dense ? 11 : 16.5,
                weight: .semibold,
                design: .monospaced
            ))
            .foregroundStyle(index == activeIndex ? Color.white : Color.secondary)
            .padding(.horizontal, dense ? 2 : 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: dense ? 4 : 6)
                    .fill(index == activeIndex ? modeColor : .clear)
            )
    }

    private func sourceMouseLabel(for key: MultiTapKey) -> String {
        let cell = PhysicalCell(rawValue: key.rawValue)!
        return cell.displayLabel(on: model.source).uppercased()
    }

    private func background(for cell: HUDLayout.Cell) -> Color {
        if cell.isHeld { return modeColor.opacity(0.28) }
        if cell.isPending { return modeColor.opacity(0.16) }
        if cell.isModeToggle { return modeColor.opacity(0.07) }
        return Color.primary.opacity(0.04)
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Text("KEYPAD MODE")
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundStyle(modeColor)

            Text(model.statusLine)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Text(model.pendingDescription)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(model.progress == nil ? .secondary : .primary)

            if showsTapProgressRing, let progress = model.progress {
                // Drains as the commit deadline approaches, so the user can see
                // how long they have to keep cycling.
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 111, height: 6)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(modeColor)
                            .frame(width: 111 * progress, height: 6)
                    }
            }
        }
    }
}
