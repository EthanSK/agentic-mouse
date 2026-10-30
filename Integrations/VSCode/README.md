# Agentic Mouse VS Code Bridge

This private local companion accepts only four URI paths for the exact
`ethansk.agentic-mouse-vscode-bridge` authority: a no-op health probe, the two
built-in VS Code Cursor History commands, and the Hide-first Terminal
alternator. It never accepts an arbitrary command id. Commands also require the
receiving VS Code window to be focused.

Package it from the repository root with `make vscode-bridge`, then install the
resulting VSIX through VS Code's normal extension installer.

## Razer stage readiness

Merge `razer-stage-hold-keybindings.json` into the current VS Code user
keybindings without replacing existing entries. The bindings call Better Git's
source-tagged readiness/clear commands with Razer arguments; they do not stage.
Mouse build 180 uses Command-Shift-F20/F15 for Razer. Corsair keeps
Control-Option-Command-F20/F15. Both Default Karabiner output and the app's VS
Code child must use the same bindings.

Do not restore Hyper for Razer readiness. Karabiner emits intermediate modifier
states, and Control-Shift-Option starts VoiceInk before Command completes Hyper.
Keeping Control and Option out of Razer feedback prevents the collision in any
press/release ordering. Preserve the normal VoiceInk shortcut and its immediate
start behavior.
