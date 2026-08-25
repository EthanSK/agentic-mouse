# Agentic Mouse VS Code Bridge

This private local companion accepts only three URI paths for the exact
`ethansk.agentic-mouse-vscode-bridge` authority: a no-op health probe and the
two built-in VS Code Cursor History commands. It never accepts an arbitrary
command id. Cursor commands also require the receiving VS Code window to be
focused.

Package it from the repository root with `make vscode-bridge`, then install the
resulting VSIX through VS Code's normal extension installer.
