# Verification boundary

Agentic Mouse deliberately separates **implemented**, **automatically tested**
and **physically proven** behaviour. A green Swift test suite does not prove a
vendor SDK, an Accessibility grant, a wireless receiver or someone else's Hue
bridge.

## What is covered without hardware

Run this on any supported Mac:

```bash
make check
make simulate
```

The hardware-free suite covers the state machines and their safety boundaries:

| Area | Examples |
|---|---|
| Multi-tap | cycling, timeout, digits, punctuation, case and Exit |
| Focus safety | app change or text-field change drops pending text |
| iCUE key lifecycle | claim, rollback, session loss, device loss and cleanup |
| Hue colour handling | CIE xy/mirek conversion, light mixing, SSE delta merging and deduplication |
| Lighting precedence | multi-tap overrides Hue; normal iCUE lighting returns on release |
| Device selection | no match or several matches fails closed |
| Privacy | identifiers, bridge hosts and secrets are redacted |
| Reference map | button 4 speech-to-text, 5/8 navigation, 6/9 media, 7/10 horizontal scroll and the VS Code overrides |

## What needs a real Corsair mouse

Use a dedicated iCUE profile, and work through these visibly. Do not edit an
iCUE database or profile file behind the app's back.

1. Connect the Scimitar and open iCUE.
2. Confirm the normal map with `swift run agentic-mouse-doctor mapping`.
3. Run `swift run agentic-mouse-doctor icue` to inspect the SDK connection,
   selected mouse, macro keys and LED LUIDs. This is read-only.
4. Enable multi-tap with button 12 and prove that every side button is
   intercepted only while the mode is active.
5. Put the caret into two separate text fields in one app; start a pending
   character, change fields, and prove that no text is delivered.
6. With explicit consent, use
   `swift run agentic-mouse-doctor icue -- --probe-lighting --i-mean-it` to
   briefly write then release the shared lighting layer.

The helper must never leave a device in exclusive input control after Exit,
disconnect, sleep, iCUE loss or quit.

## What needs a real Hue bridge

Hue mirroring is optional. Keep its configuration in
`~/.config/agentic-mouse/config.json`, with a Keychain-backed application key.
Before trusting it, verify:

1. The bridge snapshot succeeds with the configured resource IDs.
2. The local SSE endpoint produces a state update after a colour and brightness
   change.
3. Each LED zone reflects only its intended light group.
4. Turning every light in a group off follows the configured `offPolicy`.
5. Cutting bridge connectivity releases the lighting layer instead of leaving a
   stale colour on the mouse.

The project deliberately has no code path that writes to the Hue bridge.

## What needs a real Razer Naga

The Naga Left-Handed Edition route is Karabiner-first. Before publishing a
specific rule, open Karabiner-EventViewer and capture each physical grid button
with the exact device attached. Verify the generated rule only affects that
device, and test its Back/Forward/shortcut actions with the Corsair still
connected. See [MICE.md](MICE.md).

## Evidence to include in a contribution

- macOS version and hardware model;
- the relevant iCUE or Karabiner screen, with serials and credentials hidden;
- the exact command run and its redacted output;
- what was observed physically; and
- what was *not* tested.

That makes the public map trustworthy without exposing a home network or a
personal device profile.
