import AppKit

// A plain `main.swift` rather than `@main` so the activation policy is set
// before any window can be created — the HUD must never be able to activate
// this process.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
