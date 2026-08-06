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
    "toggleKey": 12,
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
3. Leave everything else untouched: the 2,750 DPI on every stage, the wheel
   press (Play/Pause), and the **DPI Toggle button, which stays disabled**. None
   of them are part of the grid and none are ever intercepted.
4. Switch to the copy when you want multi-tap; switch back to the original
   otherwise.

### What this costs you while the fallback profile is active

The normal side-button actions are gone, because they have been replaced by raw
button outputs. Specifically you lose, until you switch profiles back:

| Button | Normal action |
|---|---|
| 4 | **VoiceInk++ speech-to-text** |
| 5 | Forward |
| 6 | Next Track |
| 7 | horizontal scroll left (repeating) |
| 8 | Back |
| 9 | Previous Track |
| 10 | horizontal scroll right (repeating) |

And, if VS Code is frontmost, the Better Git overrides on 7 (next change),
8 (previous change) and 10 (stage current file) go with them, because the
fallback profile is not the VS Code-linked one.

Losing speech-to-text on button 4 is the part that stings, and it is precisely
why this is the fallback. The primary route keeps every one of these and
suspends them only while the mode is actually active.

### Reverting

Switch back to the original profile in iCUE. Nothing else is required — the
helper wrote nothing to iCUE. Delete the duplicate profile if you want.

## Keystroke bindings

If mouse buttons collide with something, use keystrokes instead. Do not reuse
F13 (`0x69`), F17 (`0x40`), or F18 (`0x4F`): the VS Code profile already uses
those for Better Git next/previous/stage. F14 (`0x6B`), F15 (`0x71`), F16
(`0x6A`), and F19 (`0x50`) are currently unclaimed; use distinct modifier
combinations as well if you need twelve bindings, and verify them against your
other app shortcuts. For example, F14 is:

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
