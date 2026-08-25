# The fallback input route

**Read this only if the primary route does not work.** The production design is
raw iCUE macro-key events (`docs/ARCHITECTURE.md`). This document describes the
opt-in alternative and is honest about why it is worse.

## When you would need it

- iCUE's key-interception setting is unavailable or refuses
  (`keyControlRefused(code: 7)`), and cannot be enabled.
- The SDK cannot be installed.
- Physical testing shows `CorsairConfigureKeyEvent` does not actually suppress
  the profile action on this firmware.

## Why it is second choice

| | macro keys | event tap |
|---|---|---|
| Knows which device sent the event | **yes** | no |
| Sees the button regardless of assignment | **yes** | no |
| Can suppress the normal action | **yes**, via the SDK | only by consuming the CGEvent |
| Needs Accessibility permission | to type only | to work at all |
| Survives iCUE being closed | no | yes |

The first row is the important one. A CGEvent carries no device identity. If
the Logitech emits button 4, this transport cannot tell it from the Scimitar
emitting button 4. Anything it sees, it treats as the Scimitar.

The second row is nearly as important: a side button assigned to "Next Track"
arrives as a media event, not a mouse button, so the tap simply cannot see it.
Which is why the fallback requires reconfiguring iCUE.

## Enabling it

```json
{
  "input": {
    "transport": "cgEventTap",
    "toggleKey": 10,
    "fallbackBindings": {
      "k1":  { "kind": "mouseButton", "button": 3 },
      "k2":  { "kind": "mouseButton", "button": 4 },
      "k3":  { "kind": "mouseButton", "button": 5 },
      "k4":  { "kind": "mouseButton", "button": 6 },
      "k5":  { "kind": "mouseButton", "button": 7 },
      "k6":  { "kind": "mouseButton", "button": 8 },
      "k7":  { "kind": "mouseButton", "button": 9 },
      "k8":  { "kind": "mouseButton", "button": 10 },
      "k9":  { "kind": "mouseButton", "button": 11 },
      "k10": { "kind": "mouseButton", "button": 12 },
      "k11": { "kind": "mouseButton", "button": 13 },
      "k12": { "kind": "mouseButton", "button": 14 }
    }
  }
}
```

`button` is the CoreGraphics `mouseEventButtonNumber`, which is **one less**
than iCUE's "Mouse Button N". iCUE's "Mouse Button 4" is `3` here.
Only `2...31` are observable through this fallback; left/right (`0`/`1`) use
different event types. Raw `icueMacroKey` bindings are also rejected because
they do not exist in CoreGraphics. Keystroke key codes must be in `0...127`.

`agentic-mouse-doctor config` warns whenever this transport is selected.

## The reversible iCUE configuration

This is the part that changes live settings. Do it in the iCUE app, visibly,
and never by editing iCUE's database or profile files.

**Use a separate profile.** Do not modify the working one.

1. In iCUE, duplicate the current Scimitar profile. Name it
   `Agentic Mouse Fallback`.
2. In the *copy only*, reassign the twelve side buttons to distinct
   `Mouse Button` outputs — 4 through 15 — matching the JSON above.
3. Leave everything else untouched: the 2,750 DPI on every stage, the wheel's
   default middle-click source (mapped to Play/Pause by exact-device Karabiner),
   and the **DPI Toggle button, which keeps its neutral F19 transport without
   changing DPI**. The exact-device Karabiner rule turns that release into the
   VoiceInk++ shortcut. None of them are part of the grid and none are ever
   intercepted by this fallback.
4. Switch to the copy when you want multi-tap; switch back to the original
   otherwise.

### What this costs you while the fallback profile is active

The normal side-button actions are gone, because they have been replaced by raw
button outputs. Specifically you lose, until you switch profiles back:

| Button | Normal action |
|---|---|
| 1 | Horizontal Scroll + Wheel chord |
| 2 | Current frontmost-app mode |
| 4 | Copy / Paste + Wheel chord |
| 5 | Forward |
| 6 | YouTube Scrub + Wheel through the VoiceInk bridge |
| 7 | Enter |
| 8 | Back |
| 9 | Keys mode |

VS Code additionally overrides physical cell 5 to Better Git Previous Change
and cell 8 to Next Change; those app-scoped actions are also unavailable while
the fallback profile replaces the neutral transports.

The separate DPI VoiceInk++ control remains available. The primary route keeps
every normal grid action and suspends them only while the mode is actually
active.

### Reverting

Switch back to the original profile in iCUE. Nothing else is required — the
helper wrote nothing to iCUE. Delete the duplicate profile if you want.

## Keystroke bindings

If mouse buttons collide with something, use keystrokes instead. Do not reuse
F13, F17, F18, or F19: the preserved G502 VS Code workflow owns those four
transports. Prefer the same twelve modifier-free keypad transports as the
primary Corsair adapter, and verify that an ordinary physical numpad is excluded
by exact-device Karabiner conditions. A plain F14 fallback would be:

```json
"k1": { "kind": "keyCode", "keyCode": 107, "modifiers": "" }
```

Same caveats: no device attribution, and the tap must consume the event so it
does not also reach the foreground app.

## Behaviour differences

- **Interception is coarse.** The tap consumes *every* observed binding while
  the mode is active — there is no per-key transaction, because CGEvent taps
  have no such concept. `beginInterception()` therefore cannot fail partway, but
  it also cannot prove it claimed anything.
- **The toggle is always consumed.** The companion derives its exact fallback
  binding from `toggleKey` and swallows that signal even while the mode is off,
  so the press that enters the mode cannot leak into the foreground app.
- **The tap can be disabled by the system** under load. It is re-enabled
  automatically and the coordinator is told, which exits the mode rather than
  going quietly deaf.
- **Everything else is identical.** The same state machine, the same anchoring,
  the same HUD, the same lighting.
