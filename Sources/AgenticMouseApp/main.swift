import AppKit
import Darwin

// Exercise the actual packaged executable and dyld before publishing it. Exit
// before the instance lock, AppKit lifecycle, hardware, or recovery helper starts.
if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--check-packaged-launch" {
    guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
          let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
          let data = try? JSONSerialization.data(withJSONObject: ["packagedLaunch": "ok", "version": version, "build": build], options: [.sortedKeys]) else {
        exit(EX_DATAERR)
    }
    FileHandle.standardOutput.write(data)
    exit(0)
}

// A plain `main.swift` rather than `@main` so the activation policy is set
// before any window can be created — the HUD must never be able to activate
// this process.
let runtimeInstanceLock: RuntimeInstanceLock
do {
    runtimeInstanceLock = try RuntimeInstanceLock.acquire(at: RuntimeInstanceLock.defaultURL())
} catch RuntimeInstanceLockError.alreadyRunning {
    fputs("Agentic Mouse is already running; duplicate launch exited.\n", stderr)
    exit(0)
} catch {
    fputs("Agentic Mouse could not acquire its runtime lock: \(error)\n", stderr)
    exit(EX_CANTCREAT)
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    withExtendedLifetime(runtimeInstanceLock) {
        application.run()
    }
}
