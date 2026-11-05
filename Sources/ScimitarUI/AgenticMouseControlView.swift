import AppKit
import ScimitarKit
import SwiftUI

/// Opus's paired thumb plates make this a mouse control surface rather than a
/// generic settings dashboard. The plates use the same physical-cell crosswalk
/// as the HUD; they never create a second editable mapping source.
@MainActor
public struct AgenticMouseControlView: View {
    @ObservedObject private var state: AgenticMouseControlState
    @ObservedObject private var scale: HUDScaleStore
    @State private var warningsExpanded = false

    public init(state: AgenticMouseControlState, scale: HUDScaleStore = .shared) {
        self.state = state
        self.scale = scale
    }

    private var snapshot: AgenticMouseControlSnapshot { state.snapshot }
    private var healthColor: Color {
        switch snapshot.health {
        case .working: return .green
        case .attention: return .orange
        case .unavailable: return .red
        case .paused: return .secondary
        }
    }
    private var healthSymbol: String {
        switch snapshot.health {
        case .working: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .unavailable: return "xmark.octagon.fill"
        case .paused: return "pause.circle.fill"
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 22) {
                plate(source: .razer, connected: snapshot.razerConnected,
                      mode: snapshot.razerMode, accent: snapshot.razerAccent)
                VStack(spacing: 7) {
                    Image(systemName: healthSymbol).font(.system(size: 30))
                        .foregroundStyle(healthColor).accessibilityHidden(true)
                    Text(snapshot.headline).font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(snapshot.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity).padding(.top, 8)
                plate(source: .corsair, connected: snapshot.corsairConnected,
                      mode: snapshot.corsairMode, accent: snapshot.corsairAccent)
            }.padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 14)

            Form {
                if snapshot.health == .unavailable {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snapshot.issue ?? "Mouse commands unavailable").fontWeight(.semibold)
                                Text(snapshot.accessibilityGranted
                                     ? "Retrying automatically. Reload configuration if the problem continues."
                                     : "Wheel actions, typing and shortcuts need Accessibility permission.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button(snapshot.accessibilityGranted ? "Reload" : "Open Settings") {
                                if snapshot.accessibilityGranted { state.onReload() }
                                else { state.onAccessibility() }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                hudSection
                passwordSection
                systemSection
                configurationSection
                Text(snapshot.version).font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit().frame(maxWidth: .infinity).textSelection(.enabled)
            }.formStyle(.grouped)
        }
        .frame(minWidth: 560, minHeight: 540)
    }

    private var hudSection: some View {
        Section("HUD") {
            legendRow(source: .corsair, shown: snapshot.corsairLegend, mode: snapshot.corsairMode)
            legendRow(source: .razer, shown: snapshot.razerLegend, mode: snapshot.razerMode)
            HStack(spacing: 12) {
                Text("Size").frame(width: 95, alignment: .leading)
                Slider(value: Binding(get: { scale.scale }, set: { scale.setScale($0) }),
                       in: HUDScaleStore.minimumScale...HUDScaleStore.maximumScale, step: 0.05)
                    .accessibilityLabel("HUD size")
                Text("\(Int((scale.scale * 100).rounded()))%")
                    .monospacedDigit().frame(width: 38, alignment: .trailing)
                Button("Reset") { scale.resetScale() }
                    .disabled(scale.scale == HUDScaleStore.defaultScale)
            }
        }
    }

    private var passwordSection: some View {
        Section("Utility Password") {
            HStack {
                Label(snapshot.passwordConfigured ? "Saved in Keychain" : "Not set", systemImage: "key")
                Spacer()
                Button(snapshot.passwordConfigured ? "Replace…" : "Set…", action: state.onSetPassword)
                if snapshot.passwordConfigured { Button("Clear…", action: state.onClearPassword) }
            }.disabled(!snapshot.sessionReady)
            Text("Utility Corsair \(PhysicalCell.storedPassword.printedSide(on: .corsair)!) / Razer \(PhysicalCell.storedPassword.printedSide(on: .razer)!) types it directly, without the clipboard.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var systemSection: some View {
        Section("System") {
            statusRow("Accessibility", value: snapshot.accessibilityGranted ? "On" : "Off",
                      ready: snapshot.accessibilityGranted) {
                if !snapshot.accessibilityGranted { Button("Open Settings", action: state.onAccessibility) }
            }
            statusRow("Mouse commands", value: snapshot.commandsReady ? "Ready" : "Unavailable", ready: snapshot.commandsReady)
            statusRow("Wheel actions", value: snapshot.wheelReady ? "Ready" : "Unavailable", ready: snapshot.wheelReady)
            statusRow("iCUE", value: snapshot.icue, ready: snapshot.corsairConnected)
            statusRow("Keep running", value: snapshot.recovery, ready: snapshot.recovery == "enabled") {
                if snapshot.recovery == "requires approval" {
                    Button("Open Login Items", action: state.onLoginItems)
                } else if snapshot.recovery != "enabled" {
                    Button("Retry", action: state.onRetryRecovery)
                }
            }
            Text("Keep running starts at login and recovers unexpected exits.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var configurationSection: some View {
        Section("Configuration") {
            HStack {
                Label("config.json", systemImage: "doc.text")
                Spacer()
                Button("Show in Finder", action: state.onRevealConfiguration)
                Button("Reload", action: state.onReload)
            }
            if !snapshot.warnings.isEmpty {
                DisclosureGroup("\(snapshot.warnings.count) \(snapshot.warnings.count == 1 ? "warning" : "warnings")",
                                isExpanded: $warningsExpanded) {
                    ForEach(Array(snapshot.warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func legendRow(source: MouseSource, shown: Bool, mode: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(source.displayName) legend")
                Text(mode.map { "\($0) open" } ?? "Tap \(source.displayName) \(PhysicalCell.defaultMapToggle(for: source).printedSide(on: source)!)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if mode != nil {
                Button("Exit mode") { state.onExitMode(source) }
            } else {
                Toggle("\(source.displayName) legend", isOn: Binding(
                    get: { shown }, set: { _ in state.onLegend(source) }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }.disabled(!snapshot.sessionReady)
    }

    private func statusRow(_ title: String, value: String, ready: Bool) -> some View {
        statusRow(title, value: value, ready: ready) { EmptyView() }
    }

    private func statusRow<Actions: View>(_ title: String, value: String, ready: Bool,
                                         @ViewBuilder actions: () -> Actions) -> some View {
        HStack {
            Text(title).frame(width: 112, alignment: .leading)
            Circle().fill(ready ? Color.green : Color.orange).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(value).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 8)
            actions()
        }
    }

    private func plate(source: MouseSource, connected: Bool, mode: String?, accent: ScimitarKit.RGBColor?) -> some View {
        VStack(spacing: 7) {
            VStack(spacing: 6) {
                ForEach(Array(PhysicalCell.displayRowsTopToBottom(for: source).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(row, id: \.rawValue) { cell in
                            Text("\(cell.printedSide(on: source)!)")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded)).monospacedDigit()
                                .frame(width: 22, height: 22)
                                .foregroundStyle(connected ? (accent == nil ? Color.black.opacity(0.7) : .white) : .white.opacity(0.45))
                                .background(plateFill(connected: connected, accent: accent), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }.padding(12).background(Color(red: 0.114, green: 0.106, blue: 0.145), in: RoundedRectangle(cornerRadius: 20))
            Text(source.displayName).font(.system(size: 13, weight: .semibold))
            Text(mode ?? (connected ? "Connected" : "Not connected"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(source.displayName)
            .accessibilityValue(mode ?? (connected ? "Connected" : "Not connected"))
    }

    private func plateFill(connected: Bool, accent: ScimitarKit.RGBColor?) -> Color {
        guard connected else { return Color.white.opacity(0.15) }
        guard let accent else { return Color(red: 0.969, green: 0.965, blue: 0.984) }
        return Color(red: Double(accent.red) / 255, green: Double(accent.green) / 255, blue: Double(accent.blue) / 255)
    }
}
