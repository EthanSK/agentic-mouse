# Karabiner semantic actions

This folder is Agentic Mouse's source-and-build home for the shared action
vocabulary used by the Corsair Scimitar and left-handed Razer Naga. It contains
no implicit installer. The checked-in binding layer now contains the approved
Corsair adapter and a separate Razer adapter derived from the verified physical
crosswalk. Both exact-device adapters are now live after separate physical
captures; their downstream semantic acceptance remains a separate gate.

## VS Code review holds

Printed 5 (both mice) begins Previous immediately on button-down; printed 8 begins Next. If the button is still held at 200 ms, Karabiner emits readiness F20 so Better Git restores the exact pre-down view while the hold remains armed. A short release cancels the captured origin; a long release stages it and advances. Hold 8 then press the adjacent Enter cell (Corsair 7 / Razer 9), or hold 5 then press the Copy cell (Corsair 4 / Razer 6), to cancel the current hold. The adjacent chord consumes the later release. Better Git 1.2.82 interprets its bare F16 as hold cancellation only while that hold is active; otherwise F16 remains exact Undo. The separate Stage + Next button in the VS Code child remains unchanged.

The superseded two-button staging chords and one-second late-stage routes remain behind `agentic_mouse_vscode_legacy_stage_chords_enabled`, default unset/0. For an explicitly requested temporary legacy test, use Karabiner's `--set-variables '{"agentic_mouse_vscode_legacy_stage_chords_enabled":1}'`; return it to 0 afterward. This flag affects the Default overrides, not the child page's own input classifier. The retained action JSONC templates describe that legacy path; the generator emits the default native hold rules ahead of it. Normal configuration does not enable the flag. Double-long-hold undo is deliberately removed, not retained as a hidden timing gesture.

Better Git owns the captured view, staging and undo history. F13/F17 begin a navigation hold, F20 marks it ready after 200 ms, F18/F19 finish and stage, F14 cancels, and F15 clears readiness. Karabiner must not condition F20 on the state variable it changes earlier in the same `to_if_held_down` list because Karabiner evaluates those event conditions before that mutation. The disabled legacy route remains available only for an explicitly requested test.

Better Git 1.2.146 adds atomic Default Eyes entry through **Control-Command-Shift-F13/F17** (Corsair) and **Option-Command-Shift-F13/F17** (Razer). These are separate from the occupied tagged navigation shortcuts and from the entered VS Code page. Agentic Mouse starts with this path disabled: an installed extension version is not proof that its running host supports it. After qualifying every normal Code window and extension host, the existing private user-command socket accepts `agentic_mouse_vscode_eyes_begin_gate` with `enabled: true`, the current `code_pid` and all qualified `host_pids`. `enabled: false` explicitly revokes admission. Do not set the underlying Karabiner expiry variable manually.

The one-session gate uses the existing short absolute-expiry lease. Companion restart, lock/sleep, process exit/exec/fork, or a failed writer revokes it; a new window/host requires fresh qualification. While inactive, the original begin and unmarked Eyes bootstrap remain unchanged. A hold that selected the new begin sends its redundant bootstrap with `initial=1`, which Better Git146 ignores even if it arrives late. Gate expiry during that hold cannot alter its already-selected release lifecycle. Explicit mode toggles remain on their existing URI transport; cross-hold ordering of those independent URIs is a separate limitation.

In the Default layer, Karabiner handles holds before Agentic Mouse's UI queue and checks original short-click duration through `to_if_alone` before release output. The VS Code child measures press/release timestamps captured on the dedicated socket receive queue and schedules readiness from that ingress time. Both paths use 200 ms. These are transport-arrival timestamps, not raw HID timestamps; physical acceptance under load remains distinct from deterministic queue-lag tests.

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
    agentic-mouse.json     Development base export; do not install alone
    agentic-mouse-runtime.json  Complete runtime-mode replacement
```

For a first installation, follow [SETUP.md](../docs/SETUP.md#6-initialize-the-complete-karabiner-rules). The installer supports an explicit `--initialize` dry run and preserves the selected profile's unrelated rules. Only the complete runtime artifact is suitable for installation.

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
rules or expiry gates. The live installer accepts only the complete runtime
artifact and rejects the five-rule base export because installing it would
leave mode entry available without the active-mode routing and Exit rule.

`action-catalog.json` proves which action definitions were discovered and is
useful for review or future UI work. It is not installed into Karabiner. The
base complex-modification file currently contains 66 manipulators across the
locked-session sink, the two base rules, and the two VS Code overrides. The
runtime artifact adds one 58-manipulator Modes layer for 124 total. Colour Proof
is no longer generated as a live rule. The two artifacts are alternatives, not
files to enable together. Physical cells 5 and 8 have app-specific duplicates;
matching base exclusions preserve Forward/Back outside VS Code. Cell 6 always
holds the source-specific YouTube scrub wheel chord outside runtime modes; Agentic
Mouse then asks the VoiceInk bridge to seek backward without focusing Chrome.

## Persistent default-map reference

The top-level VS Code navigation/staging overrides depend on Better Git's
captured-origin commands. Navigation uses Control-Option-Command-F13/F17 for
Corsair and adds Shift for Razer; the corresponding late-stage press uses
F18/F19 with the same modifiers. Ordinary held Stage + Next/Previous remains
unmodified F18/F19. Install this complete rule artifact only after the compatible
Better Git extension is loaded, or navigation will have no receiver. Each binding
declares `outputModifiers`; shared action templates substitute
`$binding_output_modifiers` so both device adapters keep one navigation behavior.

Both exact-device bases give canonical physical cell 10
(Corsair printed 10 / Razer printed 12) a lazy Command modifier while held and one
source-specific `agentic_mouse_default_map_toggle` command when tapped alone.
Canonical cell 11 owns
the native hold-open Switch App action outside modes. Cell 10 becomes universal
Exit while its mode lease is active. This persistent HUD takes no mode lease and
does not alter lighting. Each mouse owns an independent legend, so one mouse's
press never retargets or closes the other mouse's panel. Physical cell 12
remains suppressed in the ordinary base because the runtime rule opens Utility
immediately; universal physical cell 10 owns active exit while that mouse's mode
lease is active. Physical
cell 3 sends a source-specific screenshot-toggle command outside modes.

## Expiring Modes system

Physical cell 12 opens the shared Modes lease immediately:
Corsair printed 12 or Razer printed 10. While active, all twelve exact-device transports send ordered
press/release `agentic_mouse_mode_picker` payloads, independent of frontmost-app
base conditions. Keys cell 6 selects Keypad; top-level cell 2 opens the current
frontmost app's mode, while Utility cell 11 opens the manual configured-app
selector. Cell 10 exits from every page; app children also use their matching
entry cell 2 as Exit, while the parent selector keeps cell 2 for Terminal. App
children keep cell 12 available for a real app action. VS Code, Terminal, and iTerm use it for one app-targeted
Ctrl-C interrupt, while Utility uses it to open Extra Utilities. Top-level cell 9 and Utility cell 9 open Keys. Utility
uses held wheel chords on cell 1 for Brightness and cell 2 for Zoom. Top-level
cell 4 owns Copy / Paste directly, while top-level cell 1 owns Horizontal Scroll. Utility cell 3 holds Spaces + Wheel, cell 4
holds Mission Control / Show Desktop + Wheel, cell 5 holds App Exposé + Wheel,
and cell 6 holds Magnet + Wheel. Utility cell 8 opens Intelligence on Demand
with one hardware-shaped Option-Space lifecycle. Wheel up means decrease / zoom in / Paste /
Mission Control / Magnet Left / Space right; wheel down means
increase / zoom out / Copy / Show Desktop / App Exposé / Magnet Right /
Space left. Cell 7 types the optional
device-local Keychain password.
Agentic Mouse lets only the first accepted Space ratchet in each physical hold
choose this Mac's exact Control-Fn-Left/Right shortcut after the wheel callback
returns; later ratchets stay consumed until release. A temporary,
rate-limited legend footer exposes the raw wheel fields, routing verdict,
keyboard post, and observed Space-change notification during diagnosis.
Keys uses cell 3 for Undo as Command-Z, cell 6 for Keypad, cell 9 for the held Next/Previous Track wheel chord,
cell 8 for Space, and cell 11 for Backspace; cells 2 and 12 are spare. Its four arrows
use cells 5/4/7/1 on Corsair, with horizontal meanings mirrored on the
left-handed Razer. Active-mode legends remain visible until cell 10 exits;
Keypad cell 1 cycles punctuation, cell 3 is the familiar DEF key, cell 11 sends
Space, and cell 12 taps Backspace or holds Return.
Every Default and runtime-mode card omits explanatory subtitles and retains
only the action title plus the source-mouse button label.
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
rules on a Mac. The Corsair top DPI transport `F19` and lower Razer top button
`F22` toggle VoiceInk++ on physical release. Upper Razer `F21` is consumed with
`vk_none` and has no press, hold or release action. Preserve this Razer-specific
resting-finger choice; deliberate VoiceInk double/triple gestures stay available
through the lower button.

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
