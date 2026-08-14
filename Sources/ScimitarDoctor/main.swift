import Foundation
import ScimitarKit

/// `agentic-mouse-doctor` — read-only diagnostics and a hardware-free simulator.
///
/// Everything here is safe to run: it reads, it prints, it simulates. It never
/// changes an iCUE profile, never modifies system settings, and never prints a
/// device id or serial number.
///
/// The write exceptions are the explicitly gated iCUE and Razer lighting tests;
/// both require `--i-mean-it` and release their temporary control before exit.

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
case "razer":
    runRazer()
case "razer-vendor":
    runRazerVendor()
case "keymap":
    runKeymap()
case "mapping":
    runMapping()
case "simulate":
    runSimulate()
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
      razer       Validate the exact Razer HID LampArray read-only. The optional
                  solid-red test requires separate approval and two flags.
      razer-vendor
                  Run only the separately approved exact-device vendor test.
      keymap      Print the multi-tap keymap and the physical grid layout.
      mapping     Print the normal / VS Code iCUE assignments this helper
                  assumes, so they can be checked against iCUE itself.
      simulate    Run the whole coordinator against fakes — no hardware needed.
    FLAGS
      --verbose            Debug logging to stderr.
      --probe-lighting     (icue) Briefly write to the shared lighting layer and
                           release it again. Requires --i-mean-it.
      --solid-red-test     (razer) Set all three zones red for three seconds,
                           then restore autonomous lighting. Requires --i-mean-it.
      --deep-thought-test  (razer) Run a distinctive three-zone violet/cyan/RGB
                           pattern for five minutes, then restore autonomous
                           lighting. Requires --i-mean-it.
      --red-strobe-test    (razer) Alternate solid red and fully off every half
                           second for five minutes, then restore autonomous
                           lighting. Requires --i-mean-it.
      --green-restore-test (razer-vendor) Send acknowledged transient green to
                           all three exact zones for three seconds, then send
                           acknowledged Spectrum Cycling and close. Requires
                           --i-mean-it.
      --red-green-until-stopped
                           (razer-vendor) Alternate acknowledged solid red and
                           green once per second until interrupted, then restore
                           Spectrum Cycling and close. Requires --i-mean-it.
      --i-mean-it          Confirms an action that touches the device.

    Nothing this tool does can change an iCUE profile or system setting.
    """)
}

// MARK: - Razer acknowledged vendor protocol

func runRazerVendor() {
    heading("Razer vendor lighting — guarded exact-device test")
    let wantsGreenRestore = flags.contains("--green-restore-test")
    let wantsRedGreen = flags.contains("--red-green-until-stopped")
    guard (wantsGreenRestore != wantsRedGreen), flags.contains("--i-mean-it") else {
        output("  refused: select exactly one vendor test and add --i-mean-it")
        output("  no USB device was opened and no vendor report was sent")
        exit(1)
    }

    output("  target:   exact USB 1532:008d only")
    output("  storage:  NOSTORE (transient; no onboard-profile write)")
    output("  action:   acknowledged \(wantsRedGreen ? "red/green alternation" : "solid green") on scroll, logo and thumb grid")
    output("  restore:  acknowledged Spectrum Cycling on the same three zones")

    let controller = RazerVendorLightingController(
        transport: RazerVendorUSBTransport(),
        log: log
    )
    controller.onProblem = { output("  restore warning: \($0)") }
    defer { controller.release() }

    if wantsRedGreen {
        runRedGreenVendorLoop(controller: controller)
        return
    }

    guard controller.setColor(RGBColor(red: 0, green: 255, blue: 0)) else {
        output("  failed: the device did not acknowledge all three transient green commands")
        output("  Spectrum restore was attempted and the USB device was closed; stop here")
        exit(1)
    }
    output("  accepted: all three green commands were acknowledged")
    Thread.sleep(forTimeInterval: 3)
    controller.release()
    output("  complete: Spectrum restore was acknowledged where available; USB closed")
    output("  confirm: ordinary pointer/buttons still work and the rainbow returned")
}

func runRedGreenVendorLoop(controller: RazerVendorLightingController) {
    let stop = DispatchSemaphore(value: 0)
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
    interruptSource.setEventHandler { stop.signal() }
    terminateSource.setEventHandler { stop.signal() }
    interruptSource.resume()
    terminateSource.resume()

    output("  running:  solid red / solid green, one second per colour")
    output("  stop:     interrupt this process to restore Spectrum Cycling")
    var showRed = true
    while stop.wait(timeout: .now()) == .timedOut {
        let color = showRed
            ? RGBColor(red: 255, green: 0, blue: 0)
            : RGBColor(red: 0, green: 255, blue: 0)
        guard controller.setColor(color) else {
            output("  failed: a colour was rejected; Spectrum restore was attempted")
            exit(1)
        }
        output("  acknowledged: \(showRed ? "RED" : "GREEN")")
        showRed.toggle()
        if stop.wait(timeout: .now() + 1.0) == .success { break }
    }

    controller.release()
    output("  stopped: Spectrum restore acknowledged where available; USB closed")
}

// MARK: - Razer LampArray

func runRazer() {
    heading("Razer HID LampArray")
    let transport = RazerLampArrayIOHIDTransport()
    let controller = RazerLampArrayController(
        transport: transport,
        log: log
    )
    defer { controller.release() }

    do {
        let attributes = try controller.probe()
        output("  exact interface: 1532:008d / usage page 0x59 / usage 0x01")
        output("  lamps:           \(attributes.lampCount)")
        output("  kind:            \(attributes.kind == RazerNagaLampArray.mouseKind ? "mouse" : String(attributes.kind))")
        output("  minimum update:  \(attributes.minimumUpdateIntervalMicroseconds) µs")
        output("  descriptor:      exact audited match")

        do {
            let report = try transport.readFeatureReport(
                id: 6,
                maximumLength: RazerNagaLampArray.maximumFeatureReportLength
            )
            let prefix = report.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")
            output("  report 6 read:   \(report.count) bytes [\(prefix)] (read-only)")
        } catch {
            output("  report 6 read:   unavailable read-only (\(error))")
        }

        do {
            for attempt in 1...3 {
                let lamp = try controller.readCurrentLampAttributes()
                output("  lamp report 3.\(attempt): id \(lamp.lampID), programmable \(lamp.isProgrammable ? "yes" : "NO")")
                output("                   RGB levels \(lamp.redLevelCount)/\(lamp.greenLevelCount)/\(lamp.blueLevelCount), latency \(lamp.updateLatencyMicroseconds) µs")
            }
        } catch {
            output("  lamp report 3:   unavailable read-only (\(error))")
        }

        do {
            let report = try transport.readFeatureReport(id: 6, maximumLength: 2)
            let bytes = report.map { String(format: "%02x", $0) }.joined(separator: " ")
            output("  report 6 after 3: \(report.count) bytes [\(bytes)] (read-only, two-byte buffer)")
        } catch {
            output("  report 6 after 3: unavailable read-only (\(error))")
        }

        let wantsSolidRed = flags.contains("--solid-red-test")
        let wantsDeepThought = flags.contains("--deep-thought-test")
        let wantsRedStrobe = flags.contains("--red-strobe-test")
        guard wantsSolidRed || wantsDeepThought || wantsRedStrobe else {
            output("  state:           read-only; no feature report was written")
            return
        }
        guard flags.contains("--i-mean-it") else {
            output("  refused: a Razer lighting test also requires --i-mean-it")
            exit(1)
        }

        if wantsDeepThought {
            runDeepThoughtPattern(controller: controller)
            return
        }
        if wantsRedStrobe {
            runRedStrobe(controller: controller)
            return
        }

        heading("Guarded solid-red test")
        output("  disabling autonomous lighting and setting all three lamps red…")
        guard controller.setColor(RGBColor(red: 255, green: 0, blue: 0)) else {
            output("  failed before the solid colour was accepted; autonomous restore was attempted")
            exit(1)
        }
        Thread.sleep(forTimeInterval: 3)
        controller.release()
        output("  autonomous lighting restore requested; confirm the rainbow returned")
    } catch {
        output("  unavailable: \(error)")
        exit(1)
    }
}

func runDeepThoughtPattern(controller: RazerLampArrayController) {
    heading("Guarded five-minute deep-thought pattern")
    output("  violet/cyan thought waves, RGB chases, and white sparks are starting…")

    let black = RGBColor(red: 0, green: 0, blue: 0)
    let indigo = RGBColor(red: 18, green: 0, blue: 72)
    let violet = RGBColor(red: 112, green: 0, blue: 255)
    let cyan = RGBColor(red: 0, green: 225, blue: 255)
    let white = RGBColor(red: 255, green: 255, blue: 255)
    let red = RGBColor(red: 255, green: 0, blue: 0)
    let green = RGBColor(red: 0, green: 255, blue: 0)
    let blue = RGBColor(red: 0, green: 0, blue: 255)

    let frames: [[RGBColor]] = [
        [indigo, black, black],
        [violet, indigo, black],
        [cyan, violet, indigo],
        [white, cyan, violet],
        [cyan, white, cyan],
        [violet, cyan, white],
        [indigo, violet, cyan],
        [black, indigo, violet],
        [red, green, blue],
        [blue, red, green],
        [green, blue, red],
        [indigo, indigo, indigo],
        [cyan, cyan, cyan],
        [white, white, white],
        [cyan, cyan, cyan],
        [violet, violet, violet],
    ]

    let deadline = ProcessInfo.processInfo.systemUptime + 300
    var frameIndex = 0
    while ProcessInfo.processInfo.systemUptime < deadline {
        guard controller.setFrame(frames[frameIndex % frames.count]) else {
            output("  failed during the pattern; autonomous restore was attempted")
            exit(1)
        }
        frameIndex += 1
        Thread.sleep(forTimeInterval: 0.35)
    }

    controller.release()
    output("  five-minute pattern complete; autonomous rainbow restore requested")
}

func runRedStrobe(controller: RazerLampArrayController) {
    heading("Guarded five-minute red strobe")
    output("  all three zones are alternating solid red and fully off every 0.5 seconds…")

    let red = RGBColor(red: 255, green: 0, blue: 0)
    let off = RGBColor(red: 0, green: 0, blue: 0)
    let deadline = ProcessInfo.processInfo.systemUptime + 300
    var showRed = true

    while ProcessInfo.processInfo.systemUptime < deadline {
        guard controller.setColor(showRed ? red : off) else {
            output("  failed during the red strobe; autonomous restore was attempted")
            exit(1)
        }
        showRed.toggle()
        Thread.sleep(forTimeInterval: 0.5)
    }

    controller.release()
    output("  five-minute red strobe complete; autonomous rainbow restore requested")
}

// MARK: - config

func runConfig() {
    heading("Configuration")
    let (configuration, warnings) = ConfigurationLoader.load(log: log)
    output(ConfigurationLoader.describe(configuration))

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
            output("  • 0x\(String(led.luid, radix: 16))  \(name)")
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

    heading("While Keypad mode is active")
    output("""
      All twelve side buttons are intercepted, so none of the actions above
      fire. The separate top DPI VoiceInk++ control stays outside the grid.
      Exiting releases the interception and the global base resumes.
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
