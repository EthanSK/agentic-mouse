# Karabiner semantic actions

This folder is Agentic Mouse's source-and-build home for the shared action
vocabulary used by the Corsair Scimitar and left-handed Razer Naga. It contains
no implicit installer. The checked-in binding layer now contains the approved
Corsair adapter and a separate Razer adapter derived from the verified physical
crosswalk. Both exact-device adapters are now live after separate physical
captures; their downstream semantic acceptance remains a separate gate.

## Structure

```text
Karabiner/
  actions/                 One commented JSONC file per semantic action
    app-switching/
    media/
    navigation/
    productivity/
    vscode/
  bindings/bindings.json   Exact-device physical adapter layer
  generated/
    action-catalog.json    Combined, browsable action vocabulary
    agentic-mouse.json     Importable Karabiner complex modifications
    agentic-mouse-runtime.json  Complete runtime-mode replacement
```

The generator recursively discovers action files, so future modes and submenus
can live in new named subfolders without turning one source file into a large
catch-all. Every action filename equals its stable action ID, and the first line
describes its behavior.

## Build and validate

```bash
make karabiner
make test-karabiner
```

`Scripts/generate-karabiner.py` combines the separate actions because
Karabiner cannot reference action fragments across files. The checked-in
`generated/agentic-mouse.json` is valid Karabiner complex-modification JSON.
Runtime modes are deliberately generated into a separate, complete replacement
file so ordinary base-map work cannot accidentally install partial mode-entry
rules or expiry gates.

`action-catalog.json` proves which action definitions were discovered and is
useful for review or future UI work. It is not installed into Karabiner. The
base complex-modification file currently contains 67 manipulators across the
locked-session sink, the two base rules, and the two VS Code overrides. The
runtime artifact adds one 70-manipulator Modes layer for 137 total. Colour Proof
is no longer generated as a live rule. The two artifacts are alternatives, not
files to enable together. Physical cells 5, 6, and 8 have app-specific
duplicates; matching base exclusions preserve Forward/Back plus the silent
cell-6 wildcard outside VS Code.

## Persistent default-map reference

Each base adapter sends one non-repeating `agentic_mouse_default_map_toggle`
command from canonical physical cell 10: Corsair `keypad_0` / printed 10 and
Razer `equal_sign` / printed 12. This persistent HUD takes no mode lease and
does not alter lighting. Each mouse owns an independent legend, so one mouse's
press never retargets or closes the other mouse's panel. Physical cell 12
remains suppressed in the ordinary base because the expiring Modes rule owns
its inactive Utility entry; universal physical cell 10 owns active exit instead
of the base legend command while that mouse's mode lease is active. Physical
cell 3 sends a source-specific screenshot-toggle command outside modes.

## Expiring Modes system

Physical cell 12 opens the shared Modes lease: Corsair printed 12 or Razer
printed 10. While active, all twelve exact-device transports send ordered
press/release `agentic_mouse_mode_picker` payloads, independent of frontmost-app
base conditions. Cell 7 selects Keypad; top-level cell 11 opens the current
frontmost app's mode, while Utility cell 11 opens the manual configured-app
selector. Cell 10 exits from every page; app children keep cell 12 available
for a real app action. Utility cell 9 opens Keys and Keys cell 12 returns to
Utility. Utility uses cells 1/2 for brightness down/up, 3/6 for Space left/right,
and 4/5 for zoom out/in. Keys uses cell 6 for Copy, cell 3 for Paste, cell 9
for Next Track, cell 8 for Space, and cell 11 for Backspace. Its four arrows
use cells 5/4/7/1 on Corsair, with horizontal meanings mirrored on the
left-handed Razer. Active-mode legends remain visible until cell 10 exits;
Keypad cell 1 cycles punctuation, cell 3 is the familiar DEF key, cell 11 cycles
`abc → Abc → ABC → 123 → abc`, and cell 12 sends Space or hold-for-Return.
Utility cards omit explanatory subtitles and retain only the action title plus
the source-mouse button label.
The ordinary base excludes the Modes lease on
all twelve cells. Colour Proof is not generated or selectable. Each entry receives only a
1.2-second bootstrap lease, so a missing receiver cannot leave a hidden latch
and an app crash restores ordinary mappings after the last short renewal.

Karabiner routes cells but does not control lighting or render the HUD. The
running Agentic Mouse app owns those outputs and uses only transient runtime
lighting. Generation and linting do not themselves install or enable the rules.
Do not enable the ordinary base artifact alongside the runtime artifact: it
already contains gated replacements for both base rules.

## Corsair neutral transports

iCUE supplies the Scimitar side grid as twelve modifier-free keypad transports:

| Corsair side | Transport |
|---:|---|
| 1–9 | `keypad_1` through `keypad_9` |
| 10 | `keypad_0` |
| 11 | `keypad_hyphen` |
| 12 | `keypad_plus` |

Every binding supplies:

- a stable binding ID and human description;
- one action ID from `actions/`;
- the exact observed `from` event;
- an exact `device_if` condition;
- an optional rule name for grouping.

The Razer onboard profile supplies main-row `1`–`9`, `0`, `hyphen`, and
`equal_sign` from exact device `1532:008d`. Its adapter matches physical cells,
not printed numbers: `C3↔R1`, `C2↔R2`, `C1↔R3`; `C6↔R4`, `C5↔R5`, `C4↔R6`;
`C9↔R7`, `C8↔R8`, `C7↔R9`; `C12↔R10`, `C11↔R11`, `C10↔R12`. Keep private
serials out of Git and recapture the exact device before installing the Razer
rules on a Mac. The Corsair top DPI transport `F19` and the separately captured
Razer lower DPI transport `F22` both toggle VoiceInk++ on physical release;
Razer `F21` remains unchanged.

The two wheel bindings consume ordinary `pointing_button: button3` from each
mouse's exact pointing interface and inline the same `play-pause-current-media`
action. Corsair uses `6940:11008`; Razer uses `5426:141`. Vendor software keeps
the wheel at its default middle-click source instead of owning Play/Pause.

The base is intentionally unfiltered. A future app-specific override should be
added only for the selected transport: give the override a
`frontmost_application_if` condition and exclude that same app from the base
binding with `frontmost_application_unless`. Do not clone all twelve bindings.

## Ownership and verification

- iCUE owns Corsair DPI, profiles, lighting and neutral source transports.
- The Naga onboard profile owns its hardware transports.
- Karabiner owns enabled, exact-device live mappings.
- Agentic Mouse owns these semantic sources, the generator, and its separately
  approved runtime modes.

Static generation and Karabiner lint do not prove a mouse. The generated
Corsair rules were installed only after EventViewer proved all twelve source
events from vendor `6940`, product `65535`; downstream semantic acceptance is
still in progress. The Razer rules were installed after the returned Naga was
listed as exact keyboard device `5426:141` and Ethan physically produced
F21/F22 plus its ordered `1–9,0,-,=` side-grid sequence. Acceptance additionally
requires physical global behavior, rollback, and both-mice coexistence tests.
