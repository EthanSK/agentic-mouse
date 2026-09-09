# Karabiner setup and source files

Start with the [reproduction guide](../docs/REPRODUCE.md) and [installation steps](../docs/SETUP.md#6-initialize-the-complete-karabiner-rules). This directory contains the complete public rules and their sources, not a copy of Ethan's live Karabiner profile.

## Included files

| File | Purpose |
|---|---|
| `actions/**/*.jsonc` | Shared semantic actions; each filename is its action ID. |
| `bindings/bindings.json` | Exact mouse interfaces, input keys and action bindings. |
| `generated/action-catalog.json` | Readable action inventory; not installed. |
| `generated/agentic-mouse.json` | Partial development base; do not install alone. |
| `generated/agentic-mouse-runtime.json` | Complete runtime rules, including the session gate, bases, app overrides, modes and Exit. |

The native app is also required: Karabiner routes events, while Agentic Mouse owns modes, the HUD, output commands and lighting. Without the app's unlocked-session lease, custom transports stay consumed; this is not a standalone remapping profile.

## Build and validate

```sh
make karabiner
make test-karabiner
make test-install
```

The generator uses the committed actions and bindings. `make test-karabiner` checks that the generated files match their sources, runs generator tests, and runs Karabiner's structural lint when its CLI is installed. `make test-install` exercises first installation, updates, backup preservation and refusal cases using temporary profiles.

Only install `generated/agentic-mouse-runtime.json`, using [the guarded installer](../Scripts/install-live-karabiner.py) and its documented dry-run sequence. Do not enable both rule artifacts, import a whole private profile or paste runtime rules into another profile without checking the selected profile and existing Agentic block.

## Adapt the supported devices

These are public model/interface identifiers, not private device serials. Re-capture them on the owner's Mac before enabling an adapter.

| Interface | Vendor ID | Product ID | Role |
|---|---:|---:|---|
| Corsair iCUE virtual keyboard | 6940 | 65535 | Side-grid and top-button keys |
| Corsair pointing interface | 6940 | 11008 | Wheel click |
| Razer keyboard interface | 5426 | 141 | Side-grid and top-button keys |
| Razer pointing interface | 5426 | 141 | Wheel click |

For different hardware, update the source adapter after verifying every input. Preserve exact `device_if` filters, mirrored physical-cell meanings and independent per-hand state. Never broaden a keyboard filter to make an unidentified device work.

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
rules on a Mac. The Corsair top DPI transport `F19` and both separately captured
Razer DPI transports (`F21` up and `F22` down) toggle VoiceInk++ on physical
release. Both Razer routes emit the same primary shortcut. VoiceInk++ discards
only a second complete Primary chord arriving within 90 ms, before its gesture
classifier, so a paired release becomes one activation without suppressing
deliberate double or triple gestures.

The two wheel bindings consume ordinary `pointing_button: button3` from each
mouse's exact pointing interface and inline the same `play-pause-current-media`
action. Corsair uses `6940:11008`; Razer uses `5426:141`. Vendor software keeps
the wheel at its default middle-click source instead of owning Play/Pause.

Base actions are app-agnostic except for their explicit app overrides; exact-device and session filters always remain in place. A future app-specific override should be
added only for the selected transport: give the override a
`frontmost_application_if` condition and exclude that same app from the base
binding with `frontmost_application_unless`. Do not clone all twelve bindings.

## App shortcuts and runtime behavior

The [current map](https://ethansk.github.io/agentic-mouse/mouse-map.html) is generated from the native mode definitions. Read those definitions and the action sources for current buttons and wheel directions instead of maintaining a second handwritten mode map here.

VS Code navigation/staging uses Better Git's captured-origin commands. The side-5/8 adapters supply their own `outputModifiers`; the shared action templates substitute `$binding_output_modifiers`. Configure the corresponding Better Git receiver before testing those actions. The [included VS Code bridge](../Integrations/VSCode/README.md) handles cursor history and terminal commands separately.

The [agent guide](../docs/AGENT-SETUP.md) covers Ethan's Dvorak keyboard-layout assumptions. The [YouTube/Chrome bridge guide](../docs/YOUTUBE-BRIDGE.md) covers external media and browser receivers. A successful Karabiner import does not configure those apps.

## Verify and recover

- iCUE owns Corsair profiles, DPI and neutral input assignments; the Razer onboard profile owns its source keys.
- Karabiner owns the selected profile's exact-device rules; Agentic Mouse owns the runtime and transient lighting.
- Verify all source keys, both hands independently, ordinary input, mode entry/exit, lock/unlock and sleep/wake using the [physical checklist](../docs/AGENT-SETUP.md#verify-the-owners-real-case).
- Keep backups private and follow [recovery](../docs/RECOVERY.md) for an update or removal; never overwrite newer unrelated Karabiner settings with an old whole-file backup.

Generated JSON, tests and browser demos do not establish physical acceptance on another Mac.
