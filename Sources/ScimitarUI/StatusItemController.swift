import AppKit
import ScimitarKit

/// The menu bar presence.
///
/// Deliberately minimal: status, the things that commonly go wrong, and a way
/// out. It never mutates iCUE or system settings — the only action that
/// leaves the app is opening the Accessibility pane, and that is a direct
/// response to the user clicking it.
public final class StatusItemController {
    public struct Status {
        public var isModeActive: Bool
        public var activeModeName: String?
        public var multiTapEnabled: Bool
        public var accessibilityGranted: Bool
        public var keysPasswordConfigured: Bool
        public var launchAtLoginState: String
        public var icueState: String
        public var deviceDescription: String?
        public var warnings: [String]

        public init(
            isModeActive: Bool = false,
            activeModeName: String? = nil,
            multiTapEnabled: Bool = true,
            accessibilityGranted: Bool = false,
            keysPasswordConfigured: Bool = false,
            launchAtLoginState: String = "unknown",
            icueState: String = "unknown",
            deviceDescription: String? = nil,
            warnings: [String] = []
        ) {
            self.isModeActive = isModeActive
            self.activeModeName = activeModeName
            self.multiTapEnabled = multiTapEnabled
            self.accessibilityGranted = accessibilityGranted
            self.keysPasswordConfigured = keysPasswordConfigured
            self.launchAtLoginState = launchAtLoginState
            self.icueState = icueState
            self.deviceDescription = deviceDescription
            self.warnings = warnings
        }
    }

    private let statusItem: NSStatusItem
    private var status = Status()

    public var onToggleMode: (() -> Void)?
    public var onCheckForUpdates: (() -> Void)?
    public var onToggleAutomaticChecks: (() -> Void)?
    public var onToggleAutomaticDownloads: (() -> Void)?
    private var canCheckForUpdates = false
    private var automaticChecks = false
    private var automaticDownloads = false

    public func updateUpdater(canCheck: Bool, automaticChecks: Bool, automaticDownloads: Bool) {
        canCheckForUpdates = canCheck
        self.automaticChecks = automaticChecks
        self.automaticDownloads = automaticDownloads
        rebuildMenu()
    }

    public var onQuit: (() -> Void)?
    public var onReloadConfiguration: (() -> Void)?
    public var onSetKeysPassword: (() -> Void)?
    public var onClearKeysPassword: (() -> Void)?

    public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        rebuildMenu()
    }

    public func update(_ status: Status) {
        self.status = status
        configureButton()
        rebuildMenu()
    }

    // MARK: - Button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let symbolName = status.isModeActive ? "keyboard.fill" : "computermouse"
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: status.activeModeName.map { "\($0) active" } ?? "Agentic Mouse"
        )
        button.image?.isTemplate = !status.isModeActive
        if let activeModeName = status.activeModeName {
            let exit = PhysicalCell.modeExit
            button.toolTip = "\(activeModeName) is ON — press Corsair \(exit.printedSide(on: .corsair)!) or Razer \(exit.printedSide(on: .razer)!) to exit"
        } else {
            button.toolTip = "Agentic Mouse"
        }
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        let headerTitle: String
        if let activeModeName = status.activeModeName {
            headerTitle = "\(activeModeName): ON"
        } else {
            headerTitle = status.multiTapEnabled ? "Modes: ready" : "Keypad mode: disabled"
        }
        let header = NSMenuItem(
            title: headerTitle,
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        if status.activeModeName != nil || status.multiTapEnabled {
            let toggle = NSMenuItem(
                title: status.activeModeName.map { "Exit \($0.lowercased())" } ?? "Open Modes",
                action: #selector(toggleMode),
                keyEquivalent: ""
            )
            toggle.target = self
            menu.addItem(toggle)
        }

        menu.addItem(.separator())

        addInfo(to: menu, "Mouse", status.deviceDescription ?? "not detected")
        addInfo(to: menu, "iCUE", status.icueState)
        addInfo(
            to: menu,
            "Accessibility",
            status.accessibilityGranted ? "granted" : "NOT granted — multi-tap typing disabled"
        )
        addInfo(to: menu, "Self-recovery", status.launchAtLoginState)

        if !status.accessibilityGranted {
            let item = NSMenuItem(
                title: "Open Accessibility settings…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
        }

        let setPassword = NSMenuItem(
            title: status.keysPasswordConfigured
                ? "Replace Keys Mode password…"
                : "Set Keys Mode password…",
            action: #selector(setKeysPassword),
            keyEquivalent: ""
        )
        setPassword.target = self
        menu.addItem(setPassword)

        if status.keysPasswordConfigured {
            let clearPassword = NSMenuItem(
                title: "Clear Keys Mode password…",
                action: #selector(clearKeysPassword),
                keyEquivalent: ""
            )
            clearPassword.target = self
            menu.addItem(clearPassword)
        }

        if !status.warnings.isEmpty {
            menu.addItem(.separator())
            let title = NSMenuItem(title: "Warnings", action: nil, keyEquivalent: "")
            title.isEnabled = false
            menu.addItem(title)
            for warning in status.warnings.prefix(6) {
                let item = NSMenuItem(title: "  • \(warning)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.toolTip = warning
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let reload = NSMenuItem(title: "Reload configuration", action: #selector(reload), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        check.target = self
        // This menu also contains intentional informational rows. Manage this
        // item's availability explicitly rather than AppKit auto-enabling it.
        check.isEnabled = canCheckForUpdates
        menu.autoenablesItems = false
        menu.addItem(check)
        let checks = NSMenuItem(title: "Check for Updates Automatically", action: #selector(toggleAutomaticChecks), keyEquivalent: "")
        checks.target = self; checks.state = automaticChecks ? .on : .off
        menu.addItem(checks)
        let downloads = NSMenuItem(title: "Download Updates Automatically", action: #selector(toggleAutomaticDownloads), keyEquivalent: "")
        downloads.target = self; downloads.state = automaticDownloads ? .on : .off
        menu.addItem(downloads)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Agentic Mouse", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func addInfo(to menu: NSMenu, _ label: String, _ value: String) {
        let item = NSMenuItem(title: "\(label): \(value)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func toggleMode() { onToggleMode?() }
    @objc private func reload() { onReloadConfiguration?() }
    @objc private func checkForUpdates() { onCheckForUpdates?() }
    @objc private func toggleAutomaticChecks() { onToggleAutomaticChecks?() }
    @objc private func toggleAutomaticDownloads() { onToggleAutomaticDownloads?() }
    @objc private func quit() { onQuit?() }
    @objc private func setKeysPassword() { onSetKeysPassword?() }
    @objc private func clearKeysPassword() { onClearKeysPassword?() }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: AccessibilityPermission.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }
}
