# Agentic Mouse

**Give two twelve-button mice one readable action vocabulary.**

Agentic Mouse is an open, local-first control layer for a Corsair Scimitar
Elite Wireless SE and a left-handed Razer Naga. It keeps hardware configuration
with each vendor route, while giving both mice one readable set of named macOS
actions for writing, browsing, coding and talking to an agent.

It started as Ethan's setup. The point of publishing it is not that everyone
should copy Ethan's exact choices: it is that you should be able to see every
choice and adopt the pieces you like.

**[Explore the interactive Agentic Mouse site](https://ethansk.github.io/agentic-mouse/)**
or open the [full signal-path map](https://ethansk.github.io/agentic-mouse/mouse-map.html).

> **Current status:** the bundled macOS helper supplies explicit Scimitar
> runtime features. iCUE now stores a distinct modifier-free keypad transport
> for every Corsair side cell, and the generated exact-device Karabiner adapter
> is installed after a physical EventViewer sweep proved all twelve raw
> transports; downstream semantic acceptance is still in progress. Wheel click
> is now sourced as ordinary middle click and translated by exact-device
> Karabiner rules into the shared Play/Pause consumer action. A separate
> exact-Razer adapter is now installed after the returned mouse physically
> produced F21/F22 and its ordered main-row side-grid namespace on macOS;
> downstream semantic acceptance is still in progress. Exact-device base maps
> apply globally, with approved VS Code overrides on physical cells 5/6/8.

## Ethan's map

The core idea is physical reach, not a long menu of actions. The Scimitar's
easy middle keys do common navigation; the hard-to-reach keys get rarer jobs.
These are the currently authoritative Corsair assignments:

| Control | Normal behaviour | VS Code behaviour |
|---|---|---|
| Wheel press | Play / Pause through Karabiner | Same global action |
| DPI button | VoiceInk++ speech-to-text; DPI remains fixed | Same global action |
| Button 1 | Horizontal scroll left | Same global action |
| Button 2 | Open Keys mode | Same global action |
| Button 3 | Start / cancel selected-area Screenshot | Same global action |
| Button 4 | Horizontal scroll right | Same global action |
| Button 5 | Forward | Previous Change through F17 |
| Button 6 | Open the current frontmost app mode | Same global action |
| Button 7 | Enter | Enter; inside Modes, selects Keypad |
| Button 8 | Back | Next Change through F13 |
| Button 9 | App shortcut; silent when unconfigured | One-press Stage + Next through F18 |
| Button 10 | Blank outside modes; universal Exit in modes | Same global action |
| Button 11 | Hold-open Switch App | Same global action |
| Button 12 | Single: Utility; rapid double: Default legend | Same global action |
| DPI stages, including Sniper | 2,750 DPI | 2,750 DPI |

Button 9 is the fail-closed app-specific wildcard and button 2 opens the shared Keys mode. Switch App uses shared physical cell 11; cell 10 is blank outside modes and exits any active mode. On cell 12, one press opens Utility after the bounded click window and a rapid double press toggles that source mouse's independent Default legend. The native Switch App hold lifecycle is proven; the final relocated positions still need one final two-mouse acceptance press.

VS Code has three exact-device overrides: physical cell 5 emits non-repeating F17
for Better Git Previous Change, cell 8 emits non-repeating F13 for Next Change,
and cell 9 emits non-repeating F18 for one-press Stage + Next. Matching exclusions
keep Forward/Back and the silent wildcard base semantics everywhere else; every
untouched control continues to inherit the base.

On the Razer, the lower DPI button's proven `F22` transport now toggles
VoiceInk++ through an exact-device Karabiner rule; the upper `F21` transport is
unchanged. This extra control does not alter the mirrored twelve-cell grid.

See [the mouse map guide](docs/MICE.md) for the exact ownership boundaries and
the safety rules around iCUE, Agentic Mouse and optional downstream automation.

## Locked-session security

Custom mouse commands fail closed whenever the macOS user session is inactive
or locked. The menu-bar app renews a three-second absolute-expiry unlocked
lease once per second from documented AppKit session notifications. Every
generated Karabiner command checks that lease at match time and again when an
output actually fires; while the lease is inactive, an exact-device sink
consumes the Corsair and Razer side-grid, DPI, and custom wheel transports so
their neutral keys cannot reach the lock screen.

Lock, fast-user-switch, screen sleep, app failure, or lease-write failure exits
all modes, hides every legend, and cancels pending text and delayed commands.
Unlock restores only the idle runtime baseline. It never restores a previous
mode or HUD. Ordinary pointer motion, scrolling, and primary/secondary clicks
remain standard macOS input.

## What the included helper does

The macOS menu-bar app adds four optional runtime behaviours:

- **Persistent Default mode legend.** Rapidly double-press physical cell 12
  (Corsair 12 or Razer 10) to toggle the actual current twelve-button map on every
  connected display. It takes no runtime mode lease and does not alter the
  normal mappings or lighting.
  The same canonical cells render with Corsair numbers after a Corsair press
  and Razer numbers after a Razer press, so the HUD matches the mouse in hand.
  A second rapid double press from that same mouse hides only its copies. The other mouse
  owns an independent legend, so left and right HUDs can coexist.
  All map and mode HUDs draw the physical top row first and the desk-side
  `1/4/7/10` row last, matching the mouse instead of flipping it vertically.

- **Modes and app-specific controls.** Press physical cell 12 (Corsair 12 or
  Razer 10) once to open the all-display Utility mode HUD after the bounded
  double-press window; physical cell 10
  (Corsair 10 / Razer 12) exits Utility or any child mode. In the menu, cell 1 raises display brightness, cell 2
  zooms in, cells 3/6 move one Space left/right, and cell 8 rewinds
  the selected YouTube target by five seconds through the VoiceInk YouTube
  Bridge without focusing Chrome. Cell 4 lowers display brightness and cell 5
  zooms out; cell 7 selects Keypad, and cell 9 opens Keys.
  Top-level cell 6 opens the current frontmost app's mode and refreshes it as
  focus changes. Utility cell 11 opens the separate manual selector for Codex,
  Chrome, and VS Code and locks the chosen target. App children keep cell 12
  available for a real app action and use universal cell 10 to exit. Codex mode currently provides
  New Task, Pin/Unpin, Mute/Unmute voice microphone, Start Voice Mode, Steer
  Queued Message, Enter, Start New Voice Chat, and Reasoning Effort Up/Down by sending Codex's own
  configured shortcuts directly to the running Codex process without bringing
  it to the front. Chrome cell 1 sends Command-W directly to the running Chrome
  process to close its current window. VS Code cell 4 toggles its integrated
  terminal; its Better Git actions remain on cells 5, 8, and 9. Every genuinely
  unassigned app card stays Spare.
  Every mode has its own bold, saturated colour. If the Default mode legend was already open, it is restored
  after exit; otherwise the mode HUD closes.
  Active-mode legends stay visible until physical cell 10 exits the mode; no
  separate in-mode Show/Hide control consumes an action cell. Related controls
  share one internal fill colour (Brightness, Zoom, Spaces, and the four arrow
  keys). Ordinary cards keep the current mode's border; cards that open another
  mode use a thicker border in that destination mode's colour. Default mode
  uses neutral white borders for ordinary actions.
  Utility cards deliberately show only the action title and the small printed
  button label for the source mouse; explanatory subtitles are omitted.

  Keys mode sends native non-repeating arrows from physical cells 1/4/5/7,
  with the Razer's left/right meanings mirrored for its left-handed layout.
  Cell 6 copies, cell 3 pastes, cell 9 sends Next Track, cell 8 sends Space,
  cell 11 sends Backspace, and cell 12 sends Escape through the active exact-device Karabiner layer.
  Enter stays on the top-level cell 7 instead of being duplicated here. Its optional cell-2 password action reads a device-local,
  When-Unlocked Keychain item only after the unlocked-session and Accessibility
  gates pass, then types directly without using the clipboard or plaintext
  configuration.

- **Cancellable selected-area Screenshot.** Outside modes, physical cell 3
  (Corsair 3 / Razer 1) starts the native macOS selection crosshair. Press the
  same physical cell again while that interaction is still active to cancel
  it. Completing the capture or pressing Escape ends that exact session, so a
  later press always starts a fresh screenshot. Agentic Mouse passes an explicit
  collision-safe path in the configured macOS Screenshots folder, so a completed
  capture must exist as a non-empty PNG instead of silently ending up only on the clipboard.

- **Runtime lighting and reusable mode HUD.** The accepted colour-validation
  mode is retired from the live mouse menu, so it consumes no button slot.
  Its proven transient Corsair and Razer lighting controllers remain the
  internal foundation for real modes: both mice use the accepted white idle
  baseline, future mode colours remain non-persistent, and the large reusable
  legend can show each mode's actual twelve-button map on every display. Every
  ordinary card uses the current mode colour for its border and keeps its action
  colour as the fill. Mode-entry cards use a stronger destination-coloured
  border, so navigation is obvious without erasing individual action identity.

- **Keypad typing.** Open Utility with cell 12, then select Keypad with cell 7.
  Cell 1 cycles punctuation, cells 2–9 use the classic ABC-through-WXYZ phone
  letters with digit holds, including DEF on cell 3. Cell 10 exits; cell 11
  cycles `abc → Abc → ABC → 123 → abc`; cell 12 is Space with hold-for-Return.
  The HUD wraps cell 1's complete punctuation cycle so every symbol remains visible. It uses
  buffered, focus-anchored text delivery: if the
  target app or text field changes, it drops the pending character rather than
  risking typing into the wrong place.

The helper never writes an iCUE profile, changes DPI or replaces a normal
button assignment. Corsair runtime lighting is a process-lifetime shared layer;
when the app quits, iCUE takes the Corsair back. iCUE's recoverable software
fallback is a dim amber Solid layer, while the running app owns idle white.
The live Razer route permits transient `NOSTORE` commands only and restores
Spectrum Cycling on true teardown. Generated Karabiner output is installed only
after linting, complete-config backup, and preservation comparison.

## Quick start

```bash
git clone https://github.com/EthanSK/agentic-mouse.git
cd agentic-mouse
make check      # clean build and hardware-free tests
make mapping    # print the intended Corsair map
make simulate   # exercise the coordinator without any mouse connected
make app        # package build/AgenticMouse.app; installs nothing
```

Then follow [the setup guide](docs/SETUP.md). Configuration is intentionally
outside the repository at `~/.config/agentic-mouse/config.json`; the committed
example contains placeholders only.

The command-line companion is deliberately diagnostic-first:

```bash
swift run agentic-mouse-doctor config
swift run agentic-mouse-doctor icue
swift run agentic-mouse-doctor razer   # exact-interface read-only validation
swift run agentic-mouse-doctor mapping
```

It reports configuration and simulated behaviour. It does not rewrite iCUE,
macOS permissions or vendor firmware.

## Configuration ownership

| Layer | Owner | Why |
|---|---|---|
| Corsair hardware, DPI, profiles and neutral transports | iCUE | These are device-profile and hardware capabilities. |
| Razer hardware transports | Naga onboard profile | The commissioned profile survives without a supported Mac editor. |
| Enabled exact-device mappings | Karabiner | It owns the live semantic mapping after each source event is proven. |
| Semantic action sources, generator and optional runtime modes | Agentic Mouse | The repository makes the shared behavior readable and reproducible without silently installing it. |

## Multi-tap, without the unsafe bit

The Scimitar's 4 × 3 grid becomes a phone keypad when the mode is active:

```text
physical pad (front → back)       phone keypad

1  4  7  10                        1 2 3
2  5  8  11                        4 5 6
3  6  9  12                        7 8 9
                                  * 0 #
```

Tap 1 for punctuation, tap 2–9 for letters, hold 1–9 for digits, use cell 10
to exit, tap 11 to cycle case/number state, and use 12 for Space or hold 12 for
Return. While Keypad is on, all
twelve side keys are held by the helper; the normal scroll, navigation and media
actions stay suspended until you leave the mode.

Outside a runtime mode, physical cell 3 starts or cancels selected-area Screenshot:
Corsair printed 3 / Razer printed 1. The persistent Default legend uses shared
physical cell 12 (Corsair 12 / Razer 10) as a rapid double press; a single press
opens Utility. Shared physical cell 11 owns Switch App. Cell 10 (Corsair 10 /
Razer 12) is blank outside modes and exits an active mode; its legend remains
visible until exit.

## Safety model

- **No hidden profile edits.** Configure iCUE visibly; the helper never writes
  vendor databases or private profile files.
- **No private device data.** Device IDs and serials stay out of Git. The
  supplied configuration contains safe defaults only.
- **Fail closed typing.** Password fields, unknown focus and missing
  Accessibility permission produce no text.
- **No device assumption.** The iCUE path refuses to guess when several
  Scimitars match.

## Project layout

```text
Sources/
  CICUEBridge/              Runtime bridge to the proprietary iCUE SDK
  ScimitarKit/              Injectable Corsair, input and multi-tap core
  ScimitarUI/               Non-activating HUD and menu-bar UI
  AgenticMouseApp/          The Agentic Mouse app entry point
  ScimitarDoctor/           Read-only diagnostics and simulator
Karabiner/                  Shared actions, exact-device adapters and generated output
Config/config.example.json  Safe placeholders only
docs/                       Setup, safety notes and the public project page
```

The internal Swift module names retain `Scimitar` where they describe the
specific Corsair adapter. The public product, application, command names,
configuration path and documentation are **Agentic Mouse**.

## Documentation

| Guide | What it is for |
|---|---|
| [Mouse map](docs/MICE.md) | Scimitar mapping and configuration ownership |
| [Karabiner actions](Karabiner/README.md) | Shared semantic sources, generated Corsair adapter and verification boundary |
| [Musixmatch extension](docs/MUSIXMATCH-EXTENSION.md) | Exact-origin plan for whole-song Play/Pause from a free Corsair control |
| [Setup](docs/SETUP.md) | Build, iCUE SDK and permissions |
| [Architecture](docs/ARCHITECTURE.md) | Components and invariants |
| [Limitations](docs/LIMITATIONS.md) | What is not claimed to work |
| [Recovery](docs/RECOVERY.md) | Cleanly getting back to normal |
| [iCUE fallback](docs/ICUE-FALLBACK.md) | The less capable fallback input route |
| [Live proof](docs/LIVE-PROOF.md) | Verified versus still-physical checks |

## Contributing your own layout

Fork it, document the physical mouse and macOS version, prove every transport
before adding downstream automation, and keep the map legible. If a finding is
durable, update the relevant guide in the same change — future you should not
have to rediscover it by pressing buttons.

## License

MIT. See [LICENSE](LICENSE).
