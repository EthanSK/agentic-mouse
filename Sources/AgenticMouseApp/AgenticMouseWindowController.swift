import AppKit
import Carbon
import ScimitarKit
import ScimitarUI
import SwiftUI

/// The normal app window is intentionally separate from the nonactivating HUD
/// panels. A Dock tile must not turn a mouse legend into a focus-stealing window.
@MainActor
final class AgenticMouseWindowController: NSWindowController, NSWindowDelegate {
    var onRefresh: () -> Void = {}
    var onQuit: () -> Void = {}
    private var refreshTimer: Timer?

    init(state: AgenticMouseControlState) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Agentic Mouse"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 540)
        window.maxSize = NSSize(width: 720, height: 1400)
        window.collectionBehavior = [.fullScreenNone]
        window.tabbingMode = .disallowed
        window.contentView = NSHostingView(rootView: AgenticMouseControlView(state: state))
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("AgenticMouseMainWindow") { window.center() }
        window.setFrameAutosaveName("AgenticMouseMainWindow")
    }

    required init?(coder: NSCoder) { return nil }

    @objc func openWindow() {
        onRefresh()
        NSApp.unhideWithoutActivation()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if refreshTimer == nil {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.onRefresh() }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        // Restore the previous app so mouse text/navigation cannot target this
        // settings window just because the user closed it with Command-W.
        if NSApp.isActive { NSApp.deactivate() }
    }

    func restoreLegendsAfterHide() {
        window?.close()
        NSApp.unhideWithoutActivation()
    }

    @objc private func quitFromMenu() { onQuit() }

    func installApplicationMenu() {
        let main = NSMenu()
        let app = NSMenu(title: "Agentic Mouse")
        let root = NSMenuItem(); root.submenu = app; main.addItem(root)
        app.addItem(withTitle: "About Agentic Mouse", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openWindow), keyEquivalent: ",")
        settings.target = self; app.addItem(settings)
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services; app.addItem(servicesItem); NSApp.servicesMenu = services
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]; app.addItem(hideOthers)
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Agentic Mouse", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self; app.addItem(quit)

        let edit = NSMenu(title: "Edit")
        let editRoot = NSMenuItem(); editRoot.submenu = edit; main.addItem(editRoot)
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                     ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let windows = NSMenu(title: "Window")
        let windowsRoot = NSMenuItem(); windowsRoot.submenu = windows; main.addItem(windowsRoot)
        windows.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windows.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windows.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windows
        NSApp.mainMenu = main
    }
}

enum AgenticMouseTerminationPolicy {
    @MainActor
    static var isHandlingSystemQuit: Bool {
        let event: NSAppleEventDescriptor? = NSAppleEventManager.shared().currentAppleEvent
        let reason = event?.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason))
        return isSystemQuit(reason: reason?.enumCodeValue)
    }
    /// Logout/restart must keep the login helper registered for the next login;
    /// every ordinary Quit must finish its asynchronous supervisor disarm first.
    static func isSystemQuit(reason: UInt32?) -> Bool {
        guard let reason else { return false }
        return [UInt32(kAEQuitAll), UInt32(kAEShutDown), UInt32(kAERestart), UInt32(kAEReallyLogOut)].contains(reason)
    }
}
