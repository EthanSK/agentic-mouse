import AppKit
import ScimitarKit

/// The menu bar presence.
///
/// Deliberately minimal: status, the things that commonly go wrong, and a way
/// out. It never mutates iCUE, Hue or system settings — the only action that
/// leaves the app is opening the Accessibility pane, and that is a direct
/// response to the user clicking it.
public final class StatusItemController {
    public struct Status {
        public var isModeActive: Bool
        public var multiTapEnabled: Bool
        public var accessibilityGranted: Bool
        public var icueState: String
        public var deviceDescription: String?
        public var hueStatus: String
        public var warnings: [String]

        public init(
            isModeActive: Bool = false,
            multiTapEnabled: Bool = true,
            accessibilityGranted: Bool = false,
            icueState: String = "unknown",
            deviceDescription: String? = nil,
            hueStatus: String = "idle",
            warnings: [String] = []
        ) {
            self.isModeActive = isModeActive
            self.multiTapEnabled = multiTapEnabled
            self.accessibilityGranted = accessibilityGranted
            self.icueState = icueState
            self.deviceDescription = deviceDescription
            self.hueStatus = hueStatus
            self.warnings = warnings
        }
    }

    private let statusItem: NSStatusItem
    private var status = Status()

    public var onToggleMode: (() -> Void)?
    public var onQuit: (() -> Void)?
    public var onReloadConfiguration: (() -> Void)?

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
            accessibilityDescription: status.isModeActive ? "Multi-tap mode active" : "Agentic Mouse"
        )
        button.image?.isTemplate = !status.isModeActive
        button.toolTip = status.isModeActive
            ? "Multi-tap mode is ON — press side button 12 to exit"
            : "Agentic Mouse"
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(
            title: !status.multiTapEnabled
                ? "Multi-tap mode: disabled"
                : (status.isModeActive ? "Multi-tap mode: ON" : "Multi-tap mode: off"),
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)

        if status.multiTapEnabled {
            let toggle = NSMenuItem(
                title: status.isModeActive ? "Exit multi-tap mode" : "Enter multi-tap mode",
                action: #selector(toggleMode),
                keyEquivalent: ""
            )
            toggle.target = self
            menu.addItem(toggle)
        }

        menu.addItem(.separator())

        addInfo(to: menu, "Mouse", status.deviceDescription ?? "not detected")
        addInfo(to: menu, "iCUE", status.icueState)
        addInfo(to: menu, "Hue", status.hueStatus)
        if status.multiTapEnabled {
            addInfo(
                to: menu,
                "Accessibility",
                status.accessibilityGranted ? "granted" : "NOT granted — multi-tap disabled"
            )
        }

        if status.multiTapEnabled, !status.accessibilityGranted {
            let item = NSMenuItem(
                title: "Open Accessibility settings…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
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
    @objc private func quit() { onQuit?() }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: AccessibilityPermission.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }
}
