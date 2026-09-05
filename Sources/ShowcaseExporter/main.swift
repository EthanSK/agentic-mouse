import Foundation
import ScimitarKit

// This executable builds public data using the real coordinator with inert outputs. It never loads app configuration, discovers hardware, or sends a command to the Mac. (Codex task: 01a06ee5-4aa0-7a61-a029-704e5c44a8f2)
struct SiteControl: Encodable {
    let cell: Int
    let printed: Int
    let title: String
    let color: String
    let destinationColor: String?
    let reportedBroken: Bool
    var next: String?
    var followsApp: Bool?
    var effect: String?
    var wheel: SiteWheel?
    var keypad: SiteKeypad?
    var doublePress: String?
}

struct SiteWheel: Encodable {
    let id: String
    let up: String?
    let down: String?
    let oncePerHold: Bool
}

struct SiteKeypad: Encodable {
    let cycle: [String]
    let digit: String?
    let tap: KeyAction?
    let hold: KeyAction?
}

struct SiteMode: Encodable {
    let title: String
    let color: String
    let controls: [SiteControl]
}

struct SiteSource: Encodable {
    let rows: [[Int]]
    let modes: [String: SiteMode]
    let defaults: [String: SiteMode]
}

struct SiteApp: Encodable {
    let id: String
    let title: String
}

struct SiteMap: Encodable {
    let schemaVersion = 1
    let sources: [String: SiteSource]
    let apps: [SiteApp]
    let keypadTimeout: Double
    let holdThreshold: Double
    let initialShift: String
}

/// Satisfies the coordinator's lease boundary without a Karabiner connection.
final class SiteLease: ColorProofLeaseControlling {
    func activate() throws {}
    func renew() throws {}
    func deactivate() {}
}

/// Replays a native route with recording presenters and inert output adapters.
final class SiteProbe {
    let source: MouseSource
    let hud = RecordingModeHUDPresenter()
    let coordinator: ModePickerCoordinator
    var effect: String?

    init(source: MouseSource, commands: [ModePickerCommand], app: AppSpecificTarget?) {
        self.source = source
        coordinator = ModePickerCoordinator(
            lease: SiteLease(), hud: hud, scheduler: ManualTickScheduler(),
            reservedHUDScheduler: ManualTickScheduler(),
            log: Log(category: "site-export", sink: StandardErrorLogSink(minimumLevel: .error))
        )
        coordinator.resolveFrontmostApp = { context(for: app) }
        coordinator.onKeypadModeRequested = { _ in true }
        coordinator.onUtilityAction = { [unowned self] _, action in
            effect = action.actionTitle
            return .performed
        }
        coordinator.onKeysInput = { [unowned self] _, action in
            effect = String(describing: action)
            return true
        }
        coordinator.onAppSpecificInput = { [unowned self] _, target, cell, phase in
            guard phase == .press else { return true }
            effect = target.definition.legend.first { $0.cell == cell }?.actionTitle
            return effect != "Spare"
        }
        coordinator.onChromeWebsiteInput = { [unowned self] _, action in
            effect = action.title
            return true
        }
        for command in commands { coordinator.handle(command) }
        effect = nil
    }

    var modeID: String {
        guard coordinator.isActive else { return "default" }
        switch coordinator.page {
        case .modes: return "utility"
        case .keys: return "keys"
        case .appSelector: return "apps"
        case .appSpecific: return coordinator.appSpecificTarget?.rawValue ?? "unsupported"
        case .keypad: return "keypad"
        case .extraUtilities: return "extra"
        case .chromeWebsites: return "websites"
        }
    }
}

/// Exports the native mode graph by pressing each cell from a fresh route.
func exportSource(_ source: MouseSource) -> SiteSource {
    typealias Route = (commands: [ModePickerCommand], app: AppSpecificTarget?)
    var routes: [Route] = [
        ([.init(action: .open, source: source, physicalCell: .modePickerEntry)], nil),
        ([.init(action: .openKeys, source: source, physicalCell: .keysModeEntry)], nil),
        ([.init(action: .openAppSpecific, source: source, physicalCell: .frontmostAppModeSelector)], nil),
    ]
    routes += AppSpecificTarget.allCases.map { target in
        ([.init(action: .openAppSpecific, source: source, physicalCell: .frontmostAppModeSelector)], target)
    }
    var modes: [String: SiteMode] = [:]
    var index = 0
    while index < routes.count {
        let route = routes[index]
        index += 1
        let probe = SiteProbe(source: source, commands: route.commands, app: route.app)
        let modeID = probe.modeID
        guard modeID != "default", modes[modeID] == nil else { continue }
        if modeID == "keypad" {
            modes[modeID] = keypadMode(source)
            continue
        }
        let snapshot = probe.hud.snapshots.last!
        let controls = snapshot.legend.map { item -> SiteControl in
            var control = exportControl(item, source: source)
            let press = ModePickerCommand(action: .select, source: source, physicalCell: item.cell, phase: .press)
            let cellProbe = SiteProbe(source: source, commands: route.commands, app: route.app)
            cellProbe.coordinator.handle(press)
            if cellProbe.modeID != modeID {
                control.next = cellProbe.modeID
                if cellProbe.coordinator.followsFrontmostApp != probe.coordinator.followsFrontmostApp {
                    control.followsApp = cellProbe.coordinator.followsFrontmostApp
                } // A Chrome submenu preserves automatic/manual targeting; do not bake the first traversal's context into every visit.
                if cellProbe.modeID != "default" {
                    routes.append((route.commands + [press], route.app))
                }
            } else {
                control.effect = cellProbe.effect
            }
            if let wheel = cellProbe.coordinator.activeWheelControl { control.wheel = exportWheel(wheel) }
            if probe.coordinator.appSpecificTarget == .vsCode,
               let command = VSCodeModeAction.action(for: item.cell)?.doublePressCommand {
                control.doublePress = String(describing: command)
            }
            return control
        }
        modes[modeID] = SiteMode(title: snapshot.modeTitle, color: hex(snapshot.accent), controls: controls)
    }
    modes["default"] = defaultMode(source, app: nil)
    return SiteSource(
        rows: PhysicalCell.displayRowsTopToBottom(for: source).map { $0.map(\.rawValue) },
        modes: modes,
        defaults: Dictionary(uniqueKeysWithValues: AppSpecificTarget.allCases.map { ($0.rawValue, defaultMode(source, app: $0)) })
    )
}

/// Projects the default HUD and routes its named entry cells into the native coordinator.
func defaultMode(_ source: MouseSource, app: AppSpecificTarget?) -> SiteMode {
    let snapshot = DefaultMapLegend.snapshot(source: source, frontmostAppContext: context(for: app))
    let controls = snapshot.legend.map { item -> SiteControl in
        var control = exportControl(item, source: source)
        let entry: ModePickerCommand.Action?
        switch item.cell {
        case .modePickerEntry: entry = .open
        case .keysModeEntry: entry = .openKeys
        case .frontmostAppModeSelector: entry = .openAppSpecific
        default: entry = nil
        }
        if let entry {
            let probe = SiteProbe(source: source, commands: [.init(action: entry, source: source, physicalCell: item.cell)], app: app)
            control.next = probe.modeID
            control.followsApp = probe.coordinator.followsFrontmostApp
        } else if item.cell == .defaultMapToggle {
            control.effect = "toggleLegend"
        } else {
            control.effect = item.actionTitle
        }
        if let wheel = WheelChordControl.topLevelControl(for: item.cell) { control.wheel = exportWheel(wheel) }
        return control
    }
    return SiteMode(title: snapshot.modeTitle, color: hex(snapshot.accent), controls: controls)
}

/// Exports the actual keypad groups and commands without a second letter map.
func keypadMode(_ source: MouseSource) -> SiteMode {
    let accent = ModePickerCoordinator.keypadAccent
    let controls = PhysicalCell.all.map { cell -> SiteControl in
        let spec = MultiTapKeymap.modesKeypad[MultiTapKey(rawValue: cell.rawValue)!]!
        var control = exportControl(.init(cell: cell, actionTitle: spec.caption, accent: accent), source: source)
        control.keypad = SiteKeypad(cycle: spec.cycle.map(String.init), digit: spec.numericCharacter.map(String.init), tap: spec.tapAction, hold: spec.holdAction)
        if spec.tapAction == .exitMode { control.next = "default" }
        return control
    }
    return SiteMode(title: "Keypad mode", color: hex(accent), controls: controls)
}

func exportControl(_ item: ModeHUDLegendItem, source: MouseSource) -> SiteControl {
    SiteControl(cell: item.cell.rawValue, printed: item.cell.printedSide(on: source)!, title: item.actionTitle,
                color: hex(item.accent), destinationColor: item.destinationModeAccent.map(hex),
                reportedBroken: item.controlStatus == .reportedBroken)
}

/// Direction labels come from the native wheel resolver, including its accepted per-family physical inversions.
func exportWheel(_ control: WheelChordControl) -> SiteWheel {
    let physicalUp: WheelChordDirection
    switch control {
    case .youtubeScrub, .codexReasoningEffort, .vsCodeCursorHistory: physicalUp = .down // These families normalize the physical ratchet to the opposite Quartz enum sign; keep that exception local as the runtime does.
    case .horizontalScroll, .youtubeVolume, .brightness, .zoom, .clipboard, .systemOverview,
         .applicationWindows, .magnetWindow, .spaces, .mediaTracks, .chromeTabs, .spotifyVolume, .codexChatHistory:
        physicalUp = .up
    }
    return SiteWheel(id: control.rawValue, up: control.feedbackActionTitle(for: physicalUp),
                     down: control.feedbackActionTitle(for: physicalUp == .up ? .down : .up),
                     oncePerHold: control.dispatchPolicy == .oncePerHold)
}

func context(for app: AppSpecificTarget?) -> FrontmostAppModeContext {
    FrontmostAppModeContext(target: app, displayName: app?.displayName ?? "Current app", bundleIdentifier: app?.bundleIdentifier)
}

func hex(_ color: RGBColor) -> String {
    String(format: "#%02x%02x%02x", color.red, color.green, color.blue)
}

let map = SiteMap(
    sources: Dictionary(uniqueKeysWithValues: MouseSource.allCases.map { ($0.rawValue, exportSource($0)) }),
    apps: AppSpecificTarget.allCases.map { SiteApp(id: $0.rawValue, title: $0.displayName) },
    keypadTimeout: MultiTapConfiguration.default.multiTapTimeout * 1000,
    holdThreshold: MultiTapConfiguration.default.holdThreshold * 1000,
    initialShift: MultiTapConfiguration.default.initialShiftState.rawValue
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
FileHandle.standardOutput.write(try encoder.encode(map))
FileHandle.standardOutput.write(Data("\n".utf8))
