import Foundation
import ScimitarKit

/// `agentic-mouse-doctor` — read-only diagnostics and a hardware-free simulator.
///
/// Everything here is safe to run: it reads, it prints, it simulates. It never
/// changes an iCUE profile, never writes to a Hue light, never modifies system
/// settings, and never prints a secret, a bridge address, a device id or a
/// serial number.
///
/// The one exception is `keymap` and `simulate`, which touch nothing at all,
/// and `lighting --probe`, which writes to the *shared* SDK layer and releases
/// it again — and which therefore requires an explicit `--i-mean-it` flag.

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"
let flags = Set(arguments.dropFirst())

let sink = StandardErrorLogSink(minimumLevel: flags.contains("--verbose") ? .debug : .notice)
let log = Log(category: "doctor", sink: sink)

func output(_ text: String = "") { print(text) }

func heading(_ text: String) {
    output()
    output(text)
    output(String(repeating: "─", count: max(8, text.count)))
}

switch command {
case "config":
    runConfig()
case "icue":
    runICUE()
case "keymap":
    runKeymap()
case "mapping":
    runMapping()
case "simulate":
    runSimulate()
case "colors", "colours":
    runColors()
case "help", "--help", "-h":
    runHelp()
default:
    output("Unknown command '\(command)'.")
    runHelp()
    exit(2)
}

// MARK: - help

func runHelp() {
    output("""
    agentic-mouse-doctor — diagnostics for Agentic Mouse

    USAGE
      agentic-mouse-doctor <command> [--verbose]

    COMMANDS
      config      Show the resolved configuration, fully redacted, with warnings.
      icue        Probe the iCUE SDK: session, devices, LEDs, macro keys.
                  Read-only unless --probe-lighting is given.
      keymap      Print the multi-tap keymap and the physical grid layout.
      mapping     Print the normal / VS Code iCUE assignments this helper
                  assumes, so they can be checked against iCUE itself.
      simulate    Run the whole coordinator against fakes — no hardware needed.
      colors      Show how Hue readings convert to mouse colours.

    FLAGS
      --verbose            Debug logging to stderr.
      --probe-lighting     (icue) Briefly write to the shared lighting layer and
                           release it again. Requires --i-mean-it.
      --i-mean-it          Confirms an action that touches the device.

    Nothing this tool does can change an iCUE profile, a Hue light, or any
    system setting.
    """)
}

// MARK: - config

func runConfig() {
    heading("Configuration")
    let (configuration, warnings) = ConfigurationLoader.load(log: log)
    let resolver = KeychainSecretResolver(log: log)
    output(ConfigurationLoader.describe(configuration, resolver: resolver))

    heading("Warnings")
    if warnings.isEmpty {
        output("  none")
    } else {
        warnings.forEach { output("  ⚠︎ \($0)") }
    }

    heading("Accessibility")
    let permission = AccessibilityPermission()
    output("  trusted: \(permission.isTrusted ? "yes" : "NO")")
    if !permission.isTrusted {
        output()
        output(AccessibilityPermission.explanation)
    }
}

// MARK: - icue

func runICUE() {
    heading("iCUE SDK")

    let (configuration, _) = ConfigurationLoader.load(log: log)
    let session = ICUESession.shared
    session.configure(log: log)

    let paths = configuration.lighting.sdkSearchPaths + ICUESession.defaultLibrarySearchPaths()
    switch session.loadLibrary(searchPaths: paths) {
    case .success(let path):
        // The path can reveal a home directory, so only its shape is printed.
        output("  library:  loaded (\(URL(fileURLWithPath: path).lastPathComponent))")
    case .failure(let error):
        output("  library:  NOT FOUND — \(error)")
        output()
        output("  The Corsair iCUE SDK is proprietary and is not bundled with this project.")
        output("  See docs/SETUP.md for where to put it.")
        exit(1)
    }

    session.onStateChange = { state in
        output("  session:  \(state.explanation)")
    }

    guard case .success = session.connect() else {
        output("  session:  CorsairConnect failed")
        exit(1)
    }

    // Session callbacks are intentionally marshalled onto the main queue. The
    // doctor itself also starts on the main thread, so blocking that thread on
    // a semaphore would prevent a healthy callback from ever running. Pump the
    // main run loop for a bounded interval instead.
    let deadline = Date().addingTimeInterval(5)
    while session.state == .closed || session.state == .connecting, Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    if session.state != .connected {
        output("  session:  timed out waiting for iCUE.")
        output("            Is iCUE running, with SDK / third-party control enabled?")
        session.disconnect()
        exit(1)
    }

    if let details = session.sessionDetails() {
        output("  versions: client \(details.client), server \(details.server), iCUE \(details.host)")
    }

    heading("Mice")
    let devices = session.devices()
    if devices.isEmpty {
        output("  none reported")
    }
    for device in devices {
        output("  • \(device.safeModel)")
        output("      id:        \(device.redactedIdentifier)")
        output("      LEDs:      \(device.ledCount)")
        let macroKeys = session.macroKeyIdentifiers(of: device.identifier)
        output("      macro keys: \(macroKeys.isEmpty ? "none" : "CMKI_\(macroKeys.min() ?? 0)…CMKI_\(macroKeys.max() ?? 0) (\(macroKeys.count))")")
        if let battery = session.batteryLevel(of: device.identifier) {
            output("      battery:   \(battery)%")
        }
    }

    heading("Selection")
    let selection = DeviceSelector.select(from: devices, using: configuration.lighting.device)
    output("  \(selection.explanation)")

    if let device = selection.device {
        heading("LED zones")
        let leds = session.leds(of: device.identifier)
        for led in leds {
            let zone = MouseZone(rawValue: led.luid)
            let name = zone?.displayName ?? "unrecognised"
            let cluster = zone.map { " ← \($0.hueCluster.displayName)" } ?? ""
            output("  • 0x\(String(led.luid, radix: 16))  \(name)\(cluster)")
        }
        if leds.isEmpty { output("  none reported") }

        heading("Multi-tap readiness")
        let transport = ICUEMacroKeyTransport(
            session: session,
            deviceIdentifier: device.identifier,
            expectedMacroKeys: configuration.input.gridMacroKeys,
            log: log
        )
        do {
            try transport.start()
            let readiness = transport.preflight()
            if readiness.isReady {
                output("  ✓ all preconditions satisfied")
            } else {
                readiness.reasons.forEach { output("  ✗ \($0)") }
            }
            transport.stop()
        } catch {
            output("  ✗ \(MultiTapCoordinator.describe(error))")
        }

        if flags.contains("--probe-lighting") {
            heading("Lighting probe")
            guard flags.contains("--i-mean-it") else {
                output("  refused: add --i-mean-it to briefly write to the shared lighting layer")
                session.disconnect()
                exit(1)
            }
            probeLighting(session: session, configuration: configuration)
        }
    }

    session.disconnect()
}

func probeLighting(session: ICUESession, configuration: AppConfiguration) {
    let controller = ICUELightingController(
        session: session,
        matcher: configuration.lighting.device,
        layerPriority: configuration.lighting.layerPriority,
        log: log
    )
    _ = controller.refreshDevice()
    output("  zones: \(controller.availableZones.map(\.displayName).joined(separator: ", "))")

    do {
        for (label, frame) in [
            ("logo red / side blue", LightingFrame(
                logo: RGBColor(red: 255, green: 0, blue: 0),
                side: RGBColor(red: 0, green: 0, blue: 255)
            )),
            ("logo blue / side red", LightingFrame(
                logo: RGBColor(red: 0, green: 0, blue: 255),
                side: RGBColor(red: 255, green: 0, blue: 0)
            ))
        ] {
            output("  writing \(label)…")
            try controller.apply(frame)
            Thread.sleep(forTimeInterval: 1.2)
        }
        try controller.release()
        output("  layer released; ordinary iCUE lighting restored")
    } catch {
        output("  probe failed: \(error)")
        try? controller.release()
    }
}

// MARK: - keymap

func runKeymap() {
    let keymap = MultiTapKeymap.classic

    heading("Physical grid (thumb side, front → back)")
    output("""
        ┌────┬────┬────┬────┐
        │  1 │  4 │  7 │ 10 │
        ├────┼────┼────┼────┤
        │  2 │  5 │  8 │ 11 │
        ├────┼────┼────┼────┤
        │  3 │  6 │  9 │ 12 │
        └────┴────┴────┴────┘
    """)

    heading("As a phone keypad (each physical column is one keypad row)")
    output("        1 2 3\n        4 5 6\n        7 8 9\n        * 0 #")

    heading("Assignments")
    for key in MultiTapKey.allCases {
        guard let spec = keymap[key] else { continue }
        let cycle = spec.cycle.isEmpty ? spec.caption : spec.cycle.map(String.init).joined(separator: " ")
        let hold = spec.holdCaption.map { " · \($0)" } ?? ""
        output(String(format: "  %2d  [%@]  %@%@", key.rawValue, key.keypadLegend, cycle, hold))
    }

    heading("Shift states")
    for state in ShiftState.allCases {
        output("  \(state.indicator.padding(toLength: 5, withPad: " ", startingAt: 0)) \(state.rawValue)")
    }
}

// MARK: - mapping

func runMapping() {
    heading("iCUE assignments this helper assumes")
    output("""
      These are owned by iCUE. The helper never writes them — it prints them so
      you can check iCUE matches. If they disagree, iCUE is right and this table
      is what needs correcting.
    """)

    for profile in ScimitarNormalMapping.allProfiles {
        output()
        output(profile.describe())
    }

    heading("Never touched, in any mode")
    for control in ScimitarNormalMapping.untouchedControls {
        output("  • \(control)")
    }
    output()
    output("  Every visible DPI stage, Sniper included: \(ScimitarNormalMapping.unifiedDPI)")

    heading("While multi-tap mode is active")
    output("""
      All twelve side buttons are intercepted, so none of the actions above
      fire — including speech-to-text on button 4. Exiting releases the
      interception and iCUE resumes whichever profile applies.
    """)
}

// MARK: - simulate

func runSimulate() {
    heading("Simulated run (no hardware, no iCUE, no permissions)")

    let clock = ManualClock()
    let scheduler = ManualTickScheduler()
    let keyControl = FakeICUEKeyControl()
    let transport = ICUEMacroKeyTransport(
        session: keyControl,
        deviceIdentifier: keyControl.deviceIdentifier,
        clock: clock,
        log: log
    )
    let output0 = RecordingTextOutput()
    let hud = RecordingHUDPresenter()
    let resolver = StubTextTargetResolver()
    let engine = MultiTapEngine()

    let coordinator = MultiTapCoordinator(
        engine: engine,
        transport: transport,
        textOutput: output0,
        targetResolver: resolver,
        permission: StubAccessibilityPermission(isTrusted: true),
        hud: hud,
        clock: clock,
        scheduler: scheduler,
        log: log
    )
    transport.delegate = coordinator
    try? transport.start()

    func press(_ key: Int) {
        keyControl.emit(macroKeyId: key, isPressed: true)
        clock.advance(by: 0.05)
        keyControl.emit(macroKeyId: key, isPressed: false)
        clock.advance(by: 0.05)
    }

    func settle() {
        clock.advance(by: 1.0)
        scheduler.fire()
    }

    output("  entering mode via button 12…")
    press(12)
    output("  active:   \(coordinator.isActive)")
    output("  HUD shown: \(hud.isVisible)")
    output("  intercepted keys: \(keyControl.interceptedKeys.sorted())")
    output("  access level: \(keyControl.currentAccessLevel)")

    // "hi there" — 4·4 (h is the 2nd letter on 4), 4·3 (i is 3rd on 4), …
    output()
    output("  typing “hi”…")
    press(4); press(4)            // g → h
    settle()
    press(4); press(4); press(4)  // g → h → i
    settle()
    output("  produced: \"\(output0.buffer)\"")

    output()
    output("  space, then “on”…")
    press(11)                      // space
    press(6); press(6); press(6)   // m → n → o
    settle()
    press(6); press(6)             // m → n
    settle()
    output("  produced: \"\(output0.buffer)\"")

    output()
    output("  focus moves mid-character (should discard, not misfire)…")
    press(2)                       // pending 'a'
    resolver.moveToElement("field-b")
    scheduler.fire()
    settle()
    output("  produced: \"\(output0.buffer)\"  (unchanged — pending was cancelled)")
    output("  cancellation: \(String(describing: engine.state.lastCancellation))")

    output()
    output("  exiting via button 12…")
    press(12)
    output("  active:   \(coordinator.isActive)")
    output("  HUD shown: \(hud.isVisible)")
    output("  intercepted keys: \(keyControl.interceptedKeys.sorted())")
    output("  access level: \(keyControl.currentAccessLevel)")
    output("  fully released: \(keyControl.isFullyReleased)")
}

// MARK: - colors

func runColors() {
    heading("Hue → mouse colour")

    let policy = HueMirrorPolicy.default
    let samples: [(String, HueLightState)] = [
        ("warm white 2700K @100%", .init(identifier: "a", isOn: true, brightnessPercent: 100, mirek: 370, mirekValid: true)),
        ("warm white 2700K @10%", .init(identifier: "a", isOn: true, brightnessPercent: 10, mirek: 370, mirekValid: true)),
        ("cool white 6500K @100%", .init(identifier: "a", isOn: true, brightnessPercent: 100, mirek: 153, mirekValid: true)),
        ("red", .init(identifier: "a", isOn: true, brightnessPercent: 100, chromaticity: .init(x: 0.675, y: 0.322))),
        ("green", .init(identifier: "a", isOn: true, brightnessPercent: 100, chromaticity: .init(x: 0.409, y: 0.518))),
        ("blue", .init(identifier: "a", isOn: true, brightnessPercent: 100, chromaticity: .init(x: 0.167, y: 0.04))),
        ("off", .init(identifier: "a", isOn: false))
    ]

    for (label, state) in samples {
        let color = HueColorConverter.contribution(for: state, policy: policy)
        let described = color.map(\.hexString) ?? "— (zone goes dark)"
        output("  \(label.padding(toLength: 26, withPad: " ", startingAt: 0)) \(described)")
    }

    heading("Two-cluster aggregation")
    let assignments = [
        HueLightAssignment(resourceIdentifier: "candle", cluster: .candleAndSofa, label: "Candle"),
        HueLightAssignment(resourceIdentifier: "sofa", cluster: .candleAndSofa, label: "Sofa"),
        HueLightAssignment(resourceIdentifier: "luster-1", cluster: .deskLusters, label: "Luster 1"),
        HueLightAssignment(resourceIdentifier: "luster-2", cluster: .deskLusters, label: "Luster 2")
    ]
    let states: [String: HueLightState] = [
        "candle": .init(identifier: "candle", isOn: true, brightnessPercent: 80, chromaticity: .init(x: 0.675, y: 0.322)),
        "sofa": .init(identifier: "sofa", isOn: true, brightnessPercent: 80, chromaticity: .init(x: 0.409, y: 0.518)),
        "luster-1": .init(identifier: "luster-1", isOn: true, brightnessPercent: 60, mirek: 370, mirekValid: true),
        "luster-2": .init(identifier: "luster-2", isOn: false)
    ]

    if let frame = HueClusterAggregator.frame(assignments: assignments, states: states) {
        for zone in MouseZone.allCases {
            let color = frame[zone]?.hexString ?? "—"
            output("  \(zone.displayName) (0x\(String(zone.luid, radix: 16)))  ← \(zone.hueCluster.displayName)  \(color)")
        }
    }
}
