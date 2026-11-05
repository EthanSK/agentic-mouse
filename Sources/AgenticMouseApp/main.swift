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

// Establish the normal Dock application before creating windows. HUDPanel's
// nonactivating style and key-window refusal keep legends from stealing focus.
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
    application.setActivationPolicy(.regular)
    withExtendedLifetime(runtimeInstanceLock) {
        application.run()
    }
}
