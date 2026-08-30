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
> apply globally, with approved VS Code base overrides on physical cells 5 and
> 8 only. The public site was last audited against Ethan's installed, locally
> signed Agentic Mouse 1.0.110 (116) on 23 August 2026. This repository does not
> currently publish a signed or notarized binary release. The 1.0.110 map is a
> snapshot of Ethan's installed personal build; some corresponding implementation
> work is still in an active local worktree and has not yet landed on public
> `main`, so a fresh clone is not presently identical to that installed build.

## Ethan's map

The core idea is physical reach, not a long menu of actions. The Scimitar's
easy middle keys do common navigation; the hard-to-reach keys get rarer jobs.
These are the currently authoritative Corsair assignments:

| Control | Normal behaviour | VS Code behaviour |
|---|---|---|
| Wheel press | Play / Pause through Karabiner | Same global action |
| DPI button | VoiceInk++ speech-to-text; DPI remains fixed | Same global action |
| Button 1 | Hold + wheel for horizontal scrolling | Same global action |
| Button 2 | Open the current frontmost app mode | Same global action |
| Button 3 | Screenshot; rapid double-press pastes the copied result | Same global action |
| Button 4 | Hold + wheel for Copy / Paste | Same global action |
| Button 5 | Forward | Previous Change through F17 |
| Button 6 | Click to rewind YouTube 5 sec; hold + wheel to scrub ±5 sec per ratchet through the VoiceInk bridge | Same global action |
| Button 7 | Enter | Enter |
| Button 8 | Back | Next Change through F13 |
| Button 9 | Open Keys mode | Same global action |
| Button 10 | Toggle this mouse's Default legend; universal Exit in modes | Same global action |
| Button 11 | Hold-open Switch App | Same global action |
| Button 12 | Open Utility immediately | Same global action |
| DPI stages, including Sniper | 2,750 DPI | 2,750 DPI |

Hold physical cell 1 and ratchet the wheel for native horizontal scrolling. Utility cell 3
moves at most one macOS Space per hold; the first accepted wheel sign chooses
right or left, and release re-arms the next move. Hold cell 4 for per-ratchet
Copy / Paste. Each accepted cell-1 horizontal detent emits four horizontal
line units by default; set
`input.horizontalScrollLinesPerRatchet` from 1 through 12 to tune the travel
without weakening the fixed duplicate-ratchet filter. Click button 6 without moving the wheel to rewind the selected
YouTube target five seconds. Hold it and ratchet up to move forward five seconds or down to move backward five seconds without focusing Chrome; button 2 opens the current
frontmost app mode, and button 9 opens shared Keys mode. On the left-handed Razer, YouTube Scrub + Wheel is printed 4, Keys is printed
7, and Enter is printed 9. Switch App uses shared physical cell 11. Cell 10 toggles that
source mouse's independent Default legend outside modes and exits any active
mode. Cell 12 opens Utility immediately.

While a top-level wheel chord is active, an already-visible source legend may
show bounded action feedback. The trace never opens a hidden legend or changes
the persistent legend toggle.

VS Code has two exact-device overrides: physical cell 5 emits non-repeating F17
for Better Git Previous Change, cell 8 emits non-repeating F13 for Next Change,
while top-level cell 6 remains the global YouTube scrub action. Inside the
explicitly entered VS Code child, cell 9 uses one 300 ms gesture: a single sends
Stage + Next and a rapid double sends exact Undo Stage. Hold cell 6 and ratchet
down for Back or up for Forward through the bundled, allow-listed VS Code
command bridge. The bridge invokes VS Code's built-in navigation commands
directly and does not rewrite Ethan's keyboard shortcuts. Matching
exclusions keep Forward/Back base semantics everywhere else; every untouched
control continues to inherit the base.

F16 is only the neutral transport. Better Git v1.2.53+ records the latest exact
Git-index transition, so Undo also covers staging performed through VS Code's
keyboard or Source Control UI, another mouse control, or `git add`. It restores
only the recorded index state and refuses after an unexpected index or `HEAD`
change; Agentic Mouse never guesses which staged files to remove.

On the Razer, both proven DPI transports—upper `F21` and lower `F22`—toggle
VoiceInk++ on physical release through exact-device Karabiner rules. Both emit
the same primary shortcut. VoiceInk++ discards only a second complete Primary
chord arriving within 90 ms, before its gesture classifier, so a
near-simultaneous two-button release becomes one activation without removing
deliberate double or triple gestures. These extra controls
do not alter the mirrored twelve-cell grid.

See [the mouse map guide](docs/MICE.md) for the exact ownership boundaries and
the safety rules around iCUE, Agentic Mouse and optional downstream automation.

## Locked-session security

Custom mouse commands fail closed whenever the macOS user session is inactive
or locked. The menu-bar app renews a three-second absolute-expiry unlocked
lease once per second from documented AppKit session and application-activation
notifications. Loginwindow activation clears it immediately; launch, display
wake, and leaving loginwindow require positive global input while a normal app
is frontmost before the lease can return. Every
generated Karabiner command checks that lease at match time and again when an
output actually fires; while the lease is inactive, an exact-device sink
consumes the Corsair and Razer side-grid, DPI, and custom wheel transports so
their neutral keys cannot reach the lock screen.

Lock, fast-user-switch, screen sleep, app failure, or lease-write failure exits
all modes, hides every legend, and cancels pending text and delayed commands.
Unlock restores only the idle runtime baseline. It never restores a previous
mode or HUD. Ordinary pointer motion, scrolling, and primary/secondary clicks
remain standard macOS input.

## Self-recovery

The installed app registers a signed, nested macOS login-item supervisor. If
Agentic Mouse unexpectedly disappears during an unlocked login session, the
helper relaunches the exact containing app in the background with bounded
backoff and crash-loop protection. A per-user instance lock prevents duplicate
runtimes. While the app remains alive, it also repairs a lost Karabiner command
socket, retries an unavailable wheel tap or transient session lease, and runs
the same device/lighting recovery after display wake and system wake.

The supervisor defers recovery while loginwindow or the screensaver owns the
session. A recovered process begins fail closed and waits for positive unlocked
input, so self-recovery never restores a pre-lock command lease, mode, or HUD.

This uses `SMAppService.loginItem` and `NSWorkspace`; it does not install a
LaunchAgent or write private service state. Menu-bar **Quit Agentic Mouse**
unregisters the supervisor before terminating, so an intentional Quit remains
intentional. Opening the app again re-enables recovery.

## What the included helper does

The macOS menu-bar app adds several optional runtime behaviours:

- **Persistent Default mode legend.** Press physical cell 10
  (Corsair 10 or Razer 12) to toggle the actual current twelve-button map on every
  connected display. It takes no runtime mode lease and does not alter the
  normal mappings or lighting.
  The same canonical cells render with Corsair numbers after a Corsair press
  and Razer numbers after a Razer press, so the HUD matches the mouse in hand.
  A second press from that same mouse hides only its copies. The other mouse
  owns an independent legend, so left and right HUDs can coexist.
  All map and mode HUDs draw the physical top row first and the desk-side
  `1/4/7/10` row last, matching the mouse instead of flipping it vertically.

- **Modes and app-specific controls.** Press physical cell 12 (Corsair 12 or
  Razer 10) to open the all-display Utility mode HUD immediately; physical cell 10
  (Corsair 10 / Razer 12) exits Utility or any child mode. Hold Utility cell 1
  and ratchet the wheel for Brightness or cell 2 for Zoom. Hold top-level cell 4
  for Copy / Paste, or Utility cell 3 for Spaces: wheel up means decrease / zoom
  in / Paste / Space right and wheel down means increase / zoom out / Copy /
  Space left. Utility and other wheel families act once per accepted ratchet;
  Spaces acts only on the first sign of each cell-3 hold and consumes later
  ratchets until release. Ordinary scrolling and
  phase-bearing trackpad gestures pass through. Space steps use this Mac's
  configured Control-Fn-Left/Right shortcuts. In Utility, hold cell 4 and ratchet
  up for Mission Control or down for Show Desktop; hold cell 5 and ratchet down
  once for native App Exposé (Application Windows; wheel-up is ignored);
  hold cell 6 and ratchet up for Magnet Left or down for Magnet Right. Each Magnet detent sends the
  complete physical Control-Option-Arrow shortcut lifecycle, including the
  native arrow-key flags, so Magnet remains the placement and display owner. Cell
  7 types the optional device-local Keychain password. Cell 8 opens Codex's
  Intelligence on Demand window with one hardware-shaped Option-Space cycle.
  Utility cell 9 opens Keys,
  and Utility cell 12 opens the nested Extra Utilities page. Extra Utilities
  cell 1 manually restores Stay's saved `Agentic Mouse Layout v1` through its
  reserved Control-Option-Shift-Command-A hotkey; it never runs automatically.
  Extra Utilities cell 9 sends one ordinary Command-Q lifecycle to the current
  frontmost external app, excluding both Agentic Mouse processes, and latches
  until the page is exited so one physical press cannot quit twice. Universal cell 10 exits
  Extra Utilities directly back to the ordinary top-level map.
  Top-level cell 2 opens the current frontmost app's mode and refreshes it as
  focus changes. Utility cell 11 opens the separate manual selector for Codex,
  Terminal, Claude, Chrome, iTerm, Spotify, VS Code, Notion, OBS, Telegram, and
  Safari and locks the chosen target. Automatic mode also recognizes Firefox,
  Opera, Restream Chat++, Preview, Mail, iCUE, Karabiner-Elements, System
  Settings, Finder, Karabiner-EventViewer, and iPhone Mirroring. iPhone
  Mirroring cell 1 (Corsair 1 / Razer 3) opens macOS Notification Center with
  Apple's Fn-N shortcut, which is where mirrored iPhone alerts appear; the app
  does not expose an iPhone-style notification pull-down. App children keep cell 12
  available for a real app action and use either their matching entry cell 2
  or universal cell 10 to exit. The parent Choose App selector still uses cell
  2 for Terminal and exits only through cell 10. VS Code,
  Terminal, and iTerm use that cell for one layout-aware, app-targeted Ctrl-C interrupt. Top-level
  cell 9 and Utility cell 9 open Keys. Codex mode currently provides
  Steer Queued Message via Codex's built-in Command-Return on cell 1
  (Corsair 1 / Razer 3), duplicate app Exit on shared cell 2, Pin/Unpin on
  shared cell 3 (Corsair 3 / Razer 1), Reasoning Effort + Wheel on cell 4,
  Mute/Unmute Voice
  Mic on cell 6 (Corsair 6 / Razer 4), and Enter on shared cell 7
  (Corsair 7 / Razer 9). Open in Side Chat is cell 9 (Corsair 9 / Razer 7), New
  Chat is cell 5, and Edit Queued Message is cell 8. Cell 11 owns Chats Selection +
  Wheel (up next, down previous); cell 12 owns Voice Mode. Reasoning Effort
  ratchets up to increase and down to decrease. Voice Mode and Edit Queued Message retain red repair
  markers because their latest physical reports are still failed; their
  presence in the map is not a success claim. The redundant broken New Voice Chat card is
  retired. ChatGPT's global `realtimeVoice` shortcut remains Ethan's unchanged
  Control-Shift-V. The earlier PID-targeted Hyper-F17 synthetic route never fired
  from real mouse input, so the exact-device Karabiner rule now emits the chord
  natively; Agentic Mouse separately receives `selectNative` only for HUD feedback.
  On `DVORAK - QWERTY CMD`, semantic V sits at the ANSI period position, so the
  generated rule emits `key_code: period` with Control and Shift. The route requires
  the exact mouse, an unlocked session, an active Codex page, and either manual
  Codex selection or frontmost ChatGPT. Physical acceptance remains pending. Open in
  Side Chat uses Codex's built-in
  Command-Option-S app accelerator for the current task through macOS System
  Events. That foreground-only control fails
  closed for a background Codex instead of sending a global chord to
  another app. Other keyboard-backed actions send Codex's
  own configured shortcuts directly to its running process without bringing it
  to the front. Steer uses Codex's built-in Command-Return shortcut; Edit alone
  presses the exact action on Codex's real queued-message row because no
  keyboard shortcut edits an already queued item. The row is validated through
  its exact visible Steer, Delete, and Actions
  control cluster because Chromium omits its wrapper groups from the macOS
  Accessibility hierarchy. Voice confirmation is based only on an observed
  exact Codex voice-control state transition across two complete, identically
  bounded scans of its visible windows; a partial scan is never called inactive. Edit
  is confirmed only when the exact newly exposed `Edit message` control is
  pressed; ambiguous or stale candidates fail closed. Chrome cell 1 sends Command-W directly to the running Chrome
  process to close its current tab, while cell 8 sends Shift-Command-W to close its current window. Chrome cell 3 sends Chrome's native Command-Option-I shortcut to
  open DevTools. Holding Chrome cell 7 sets the bridge-selected, currently playing
  YouTube video to 2× and release restores that video's exact prior rate; a short renewed browser lease
  restores it automatically if release is lost. Chrome cell 4 controls tabs with the wheel without
  focusing Chrome. Chrome cells 5 and 8 open a new tab, and cell 6 reloads the current tab. Chrome mode
  does not duplicate the Default map's Forward/Back controls. VS Code cell 1 closes the current editor
  tab, cell 7 opens the Command Palette, cell 4 toggles its integrated terminal,
  cell 11 goes to the selected symbol's definition with F12, and cell 12
  interrupts it. Better Git gestures use cells 5, 8, and 9; cell 6 owns Cursor
  History + Wheel through VS Code's direct command API. Those child-page
  controls reuse the same 300 ms single/double gestures as the ordinary VS Code
  layer rather than a second immediate-only shortcut map. Spotify and Notion
  have full starter grids for playback/library navigation and page/tab/search
  work respectively. OBS, Telegram, Safari, Firefox, Opera, Restream Chat++,
  Preview, Mail, Finder, Terminal, and iTerm likewise expose a useful starter
  grid sourced from their installed menus or official shortcuts. Claude has a
  dedicated shared definition for automatic and manually chosen journeys:
  Settings, Search, Voice Mode, New Chat, Mute/Unmute Voice Mic, Enter, Reload,
  Sidebar, Previous Tab, and Next Tab. Its menu accelerators are sent directly
  to Claude, while its UI-only controls use a bounded exact-label Accessibility
  search in Claude's own focused window and fail closed on missing or ambiguous
  controls. Small
  maintenance apps remain deliberately sparse where they expose only a few
  safe commands. Every genuinely unassigned app card stays Spare. Newly
  populated starter grids remain reviewable defaults rather than physically
  accepted personal preferences until Ethan tests them. The Chrome 2× transport
  and fail-safe lease are proven, but physical speed/restore acceptance on a
  playing video remains open.
  Safari uses Chrome's cells for their shared actions: Close Tab, Open DevTools,
  New Tab on both cells 5 and 8, Reload, Reopen Tab, and Find Page. Its separate
  tab-direction and Forward controls remain available; Downloads is retired from
  Safari mode only.
  Every mode has its own bold, saturated colour. If the Default mode legend was already open, it is restored
  after exit; otherwise the mode HUD closes.
  Active-mode legends stay visible until physical cell 10 exits the mode; no
  separate in-mode Show/Hide control consumes an action cell. Related controls
  share one calmer opaque internal fill colour (Brightness, Zoom, and the four
  arrow keys). Ordinary cards keep the current mode's full-strength border;
  cards that open another mode use that destination mode's fully saturated
  fill and thicker border. Default mode uses neutral white borders for ordinary
  actions.
  Utility cards deliberately show only the action title and the small printed
  button label for the source mouse; explanatory subtitles are omitted.
  A slot that names a concrete app uses that real installed app icon as its
  own lightly blurred edge-to-edge background. The top-level current-app slot prefers
  the running app's exact bundle path; each named `Choose app` slot resolves
  its configured bundle identifier. Agentic Mouse samples that same icon once
  to choose a strong representative mode colour for the HUD perimeter and
  mouse lighting, then caches the icon and colour in memory by resolved app
  path. The rest of the panel and every child page remain unchanged.

  Keys mode sends native non-repeating arrows from physical cells 1/4/5/7,
  with the Razer's left/right meanings mirrored for its left-handed layout.
  Cell 3 sends Undo as Command-Z, cell 6 enters Keypad, cell 9 sends Next Track, cell 8 sends Space,
  cell 11 sends Backspace, and cell 12 sends Enter through the active exact-device Karabiner layer.
  Cell 2 is spare. Utility cell 7 reads the optional device-local,
  When-Unlocked Keychain item only after the unlocked-session and Accessibility
  gates pass, then types directly without using the clipboard or plaintext
  configuration.

- **Save, copy and paste selected-area Screenshot.** Outside modes, one press
  of physical cell 3 (Corsair 3 / Razer 1) starts the native macOS selection
  crosshair after a short double-press window. A press while that crosshair is
  active cancels it. Completing the selection still follows exact
  Shift-Command-4, so macOS owns the configured save destination, capture sound
  and floating thumbnail. Agentic Mouse then finds only that new saved image in
  the configured Screenshot folder and copies it to the clipboard. Rapidly
  double-press the same mouse's button to send Paste while that screenshot is
  still the current clipboard item; changing the clipboard disables the stale
  paste rather than silently restoring it. The HUD shows capture, cancellation,
  copy progress and the double-paste affordance truthfully.

- **Runtime lighting and reusable mode HUD.** The accepted colour-validation
  mode is retired from the live mouse menu, so it consumes no button slot.
  Its proven transient Corsair and Razer lighting controllers remain the
  internal foundation for real modes: both mice use the accepted white idle
  baseline, future mode colours remain non-persistent, and the large reusable
  legend can show each mode's actual twelve-button map on every display. Every
  ordinary card uses the current mode colour for its border and a deliberately
  calmer opaque version of its action-family colour as the fill. Mode-entry
  cards use the destination mode's exact saturated colour for both fill and
  stronger border, so modes remain the strongest controls in the hierarchy.
  Only cards that name a concrete app add a dynamic blurred installed-app icon
  behind their white label. The app mode's identity colour comes from a small,
  cached representative-colour sample of that icon rather than a muddy raw
  average. It never replaces semantic action-family colours. Icons and derived
  colours are memory-only: they are not embedded in the repository or persisted,
  and they never alter the whole panel or accepted child-page action cards.

- **Keypad typing.** Open Keys with cell 9, then select Keypad with cell 6.
  Cell 1 cycles punctuation, cells 2–9 use the classic ABC-through-WXYZ phone
  letters with digit holds, including DEF on cell 3. Cell 10 exits; cell 11
  inserts Space; cell 12 taps Backspace and holds Return. The large HUD labels
  are the real 1–12 numbers printed on the source mouse, with Razer 1 at its
  physical top-right position rather than a fictional `* / 0 / #` row.
  The HUD wraps cell 1's complete punctuation cycle so every symbol remains
  visible. Committed characters are inserted directly as process-targeted
  UTF-16 Core Graphics events. Keypad never reads a field value, never touches
  the pasteboard and never synthesizes Command-V. Exact editable AX fields stay
  field-anchored; editors that hide their AX focus fall back to the unchanged
  frontmost app. Backspace and Return remain process-targeted native key events;
  an app switch drops pending text rather than risking delivery elsewhere.

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

The Scimitar's 4 × 3 grid keeps its physical 1–12 identity while the first nine
buttons use familiar phone letter groups:

```text
physical pad (front → back)       letter groups

1  4  7  10                        1 2 3
2  5  8  11                        4 5 6
3  6  9  12                        7 8 9
```

Tap 1 for punctuation, tap 2–9 for letters, hold 1–9 for digits, use cell 10
to exit, tap 11 for Space, and tap 12 for Backspace or hold 12 for Return.
While Keypad is on, all
twelve side keys are held by the helper; the normal scroll, navigation and media
actions stay suspended until you leave the mode.

Outside a runtime mode, physical cell 3 starts or cancels selected-area Screenshot,
then rapid-double-pastes its copied result: Corsair printed 3 / Razer printed 1.
Shared physical cell 10 (Corsair 10 /
Razer 12) toggles that mouse's persistent Default legend and exits an active
mode. Shared physical cell 11 owns Switch App. Cell 12 (Corsair 12 / Razer 10)
opens Utility immediately.

## Safety model

- **No hidden profile edits.** Configure iCUE visibly; the helper never writes
  vendor databases or private profile files.
- **No private device data.** Device IDs and serials stay out of Git. The
  supplied configuration contains safe defaults only.
- **Bounded typing.** Keypad never reads a field value or the pasteboard.
  Unknown focus, a changed target, and missing Accessibility permission produce
  no text; secure fields accept the same direct process-targeted key events as
  other editable fields.
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
