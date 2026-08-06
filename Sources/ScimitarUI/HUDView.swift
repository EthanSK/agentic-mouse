import Combine
import ScimitarKit
import SwiftUI

/// Observable mirror of `HUDSnapshot`.
final class HUDViewModel: ObservableObject {
    @Published var isActive = false
    @Published var rows: [[HUDLayout.Cell]] = []
    @Published var pendingDescription = "Ready"
    @Published var statusLine = "abc"
    @Published var progress: Double?
    @Published var problem: String?

    func apply(_ snapshot: HUDSnapshot) {
        isActive = snapshot.isActive
        rows = HUDLayout.grid(for: snapshot)
        pendingDescription = HUDLayout.pendingDescription(for: snapshot)
        statusLine = HUDLayout.statusLine(for: snapshot)
        progress = HUDLayout.pendingProgress(for: snapshot)
        problem = snapshot.problem
    }
}

/// The reference card.
///
/// Laid out as the mouse's real 4×3 thumb pad rather than as a phone keypad,
/// because the user is feeling for a button, not reading a phone. Each cell
/// still prints the phone digit and its letters, so `2 = ABC` stays obvious.
struct HUDView: View {
    @ObservedObject var model: HUDViewModel
    let showsTapProgressRing: Bool

    private let modeColor = Color(red: 1.0, green: 0.0, blue: 0.66)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let problem = model.problem, !problem.isEmpty {
                problemBanner(problem)
            }

            grid
            footer
        }
        .padding(18)
        .frame(width: 470)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(modeColor.opacity(model.isActive ? 0.55 : 0.15), lineWidth: 1.5)
                )
        )
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.isActive ? modeColor : Color.secondary.opacity(0.4))
                .frame(width: 9, height: 9)

            Text(model.isActive ? "MULTI-TAP" : "MULTI-TAP OFF")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .kerning(1.4)
                .foregroundStyle(model.isActive ? modeColor : .secondary)

            Spacer()

            Text(model.statusLine)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func problemBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            )
    }

    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        cellView(cell)
                    }
                }
            }
        }
    }

    private func cellView(_ cell: HUDLayout.Cell) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(cell.legend)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("·\(cell.key.rawValue)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if cell.cycle.isEmpty {
                Text(cell.caption)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(cell.isModeToggle ? modeColor : .secondary)
            } else {
                // Each character is shown separately so the *position* of the
                // pending letter in the cycle can be highlighted — this is the
                // "how many times do I press it" answer.
                HStack(spacing: 1) {
                    ForEach(Array(cell.cycle.enumerated()), id: \.offset) { index, character in
                        Text(character)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(index == cell.activeCycleIndex ? Color.white : Color.secondary)
                            .padding(.horizontal, 2.5)
                            .padding(.vertical, 0.5)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(index == cell.activeCycleIndex ? modeColor : .clear)
                            )
                    }
                }
            }

            if let hold = cell.holdCaption {
                Text(hold)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(background(for: cell))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            cell.isPending ? modeColor : Color.primary.opacity(0.08),
                            lineWidth: cell.isPending ? 1.5 : 1
                        )
                )
        )
    }

    private func background(for cell: HUDLayout.Cell) -> Color {
        if cell.isHeld { return modeColor.opacity(0.28) }
        if cell.isPending { return modeColor.opacity(0.16) }
        if cell.isModeToggle { return modeColor.opacity(0.07) }
        return Color.primary.opacity(0.04)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(model.pendingDescription)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(model.progress == nil ? .secondary : .primary)

            Spacer()

            if showsTapProgressRing, let progress = model.progress {
                // Drains as the commit deadline approaches, so the user can see
                // how long they have to keep cycling.
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 74, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(modeColor)
                            .frame(width: 74 * progress, height: 4)
                    }
            }
        }
    }
}
