import AppKit
import Darwin

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
