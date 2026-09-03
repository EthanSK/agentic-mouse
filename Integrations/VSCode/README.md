# Agentic Mouse VS Code Bridge

This private local companion accepts only five URI paths for the exact
`ethansk.agentic-mouse-vscode-bridge` authority: a no-op health probe, the two
built-in VS Code Cursor History commands, the Hide-first Terminal alternator,
and Codex's Add to Chat command. It never accepts an arbitrary command id.
Cursor History and Terminal require the receiving VS Code window to be focused.
Add to Chat deliberately uses the editor selection retained in the background
while Codex is frontmost.

Package it from the repository root with `make vscode-bridge`, then install the
resulting VSIX through VS Code's normal extension installer.
