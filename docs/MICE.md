# Two mice, one vocabulary

Agentic Mouse keeps **meaning** consistent between mice without pretending that
their shapes are identical. Map actions to the buttons your thumb can reach
reliably; do not force a twelve-key grid onto a mouse that does not have one.

## Corsair Scimitar Elite Wireless SE

Use iCUE for the actual device profile. This project reads the map and may use
the iCUE SDK for the optional multi-tap and lighting features, but it does not
write iCUE settings.

| Control | Assignment |
|---|---|
| Wheel press | Play / Pause |
| Top DPI button | Disabled |
| Button 4 | VoiceInk++ speech-to-text |
| Button 5 | Forward |
| Button 6 | Next Track |
| Button 7 | Horizontal scroll left; Better Git Next Change in VS Code |
| Button 8 | Back; Better Git Previous Change in VS Code |
| Button 9 | Previous Track |
| Button 10 | Horizontal scroll right; Better Git Stage Current File in VS Code |
| Button 12 | Multi-tap toggle, with no normal iCUE action |
| Every DPI stage | 2,750 DPI |

Buttons 1–3 and 11 remain unassigned for now. The layout is intentionally
single-layer: normal behaviour stays normal unless multi-tap is deliberately
entered.

## Razer Naga Left-Handed Edition (RZ01-0341)

The Naga can be used alongside the Scimitar. On this Mac it is visible as USB
vendor/product `1532:008d`. Do **not** assume its grid labels equal the event
numbers macOS sees.

### Why Karabiner, not Synapse

Razer's current Mac-compatible device list does not include the Naga
Left-Handed Edition. Razer also documents that Synapse for Mac can conflict
with Karabiner-Elements. The safe route is therefore Karabiner-first:

1. Leave Synapse uninstalled for this mouse.
2. Open **Karabiner-EventViewer** and press every physical Naga button once.
3. Record each observed event and its device identity in a Karabiner
   `device_if` condition. Do not map a device based on a guessed model name.
4. Start with universal actions: Back, Forward, media, and accessibility-safe
   keyboard shortcuts. Add app-specific rules only when their normal app
   shortcut has been verified.
5. Preserve direct normal Back/Forward, and do not reuse the VoiceInk trigger
   or VS Code signals without checking the existing rules.

The first capture is intentionally left as a physical step because different
firmware and prior onboard profiles can change what the grid emits. Once it is
captured, this repository can carry a named, reviewable Karabiner complex
modification instead of an opaque vendor profile.

## Cross-mouse update rule

Before changing either mouse:

1. Inspect the existing Corsair iCUE profile and Razer/Karabiner rule.
2. Decide whether the action is **shared**, **device-specific** or
   **app-specific**.
3. Update the other mouse's map when it is a shared action and physical reach
   allows it; otherwise document why it differs.
4. Verify the changed mouse physically and confirm that the other one still
   sends its expected event.

This keeps one ergonomic vocabulary without making either device worse.
