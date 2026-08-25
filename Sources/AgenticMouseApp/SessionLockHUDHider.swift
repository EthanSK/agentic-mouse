import ScimitarKit

/// Final UI fail-closed sweep for a locked or inactive macOS session.
///
/// Coordinators still tear down their own state first. This separate presenter
/// boundary also removes transient feedback panels or a panel whose coordinator
/// state was already inactive, so no Agentic Mouse legend remains visible over
/// the lock screen.
enum SessionLockHUDHider {
    static func hideAll<ModeHUDs: Sequence, KeypadHUDs: Sequence>(
        modeHUDs: ModeHUDs,
        keypadHUDs: KeypadHUDs
    ) where ModeHUDs.Element: ModeHUDPresenting,
            KeypadHUDs.Element: HUDPresenting {
        modeHUDs.forEach { $0.hide() }
        keypadHUDs.forEach { $0.hide() }
    }
}
