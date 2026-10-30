# Codex sidebar navigation

Chats Selection + Wheel uses Codex's `previousThread` and `nextThread`
commands through dedicated Hyper-F13 and Hyper-F14 bindings. Hyper means
Command, Control, Option and Shift together. The regular Command-Option-arrow
shortcuts also match tab navigation, which can select side chats first.

Merge the entries in `keybindings.json` into `~/.codex/keybindings.json`.
Preserve all existing entries. If either command already has custom bindings,
retain those and put its dedicated Hyper shortcut first; do not restore
defaults that the user deliberately removed. Reject a Hyper shortcut already
assigned to another command.

The fragment includes the macOS defaults because Codex replaces a command's
default bindings once any custom binding exists for that command. It does not
change `nextTab`, `previousTab`, recent-chat navigation or other mouse actions.

Order matters: Codex 26.901.31953 registers only the first two bindings for
each thread command in its native menu. Put Hyper first, then preserve the
existing shortcuts in their original order. Appending Hyper third caused
Chats Selection to stop responding. After saving, switch to another app and
return to Codex; its window-focus handler rebuilds the menu from the file.
No Codex restart is required.

Verify with multiple side chats open and a side-chat composer focused: each
wheel detent must select the adjacent main-sidebar task, leaving side-tab
selection unchanged. The transport is shared by Corsair 6 and Razer 4.
