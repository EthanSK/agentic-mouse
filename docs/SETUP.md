# Setup

Nothing here is done for you. Every step is a deliberate action, and none of
the build tooling installs anything, registers a LaunchAgent, or changes a
system setting.

## 0. Prerequisites

- macOS 13 or later, Apple Silicon or Intel
- Xcode command line tools (Swift 5.10+)
- iCUE 5.x installed and running

## 1. Build and verify

```bash
make check      # clean build + full test suite, no hardware needed
make keymap     # sanity-check the mapping
make simulate   # drive the whole coordinator against fakes
```

## 2. Install the iCUE SDK

The Corsair iCUE SDK is proprietary and is **not** bundled with this project.
Download it from Corsair. The companion currently accepts the audited framework
release **4.0.84** only; unknown versions and raw dylibs fail closed before
`dlopen` so an ABI change cannot corrupt memory. Then either:

**Option A — embed it in the app bundle** (simplest):

```bash
ICUE_SDK_FRAMEWORK=/path/to/iCUESDK.framework make app
```

**Option B — install it once, system-wide:**

```bash
sudo mkdir -p /usr/local/lib
sudo cp -R /path/to/iCUESDK.framework /usr/local/lib/
```

**Option C — point at it from your config:**

```json
"lighting": { "sdkSearchPaths": ["/somewhere/iCUESDK.framework/Versions/A/iCUESDK"] }
```

Verify:

```bash
swift run agentic-mouse-doctor icue
```

You should see the library load, the session connect, your Scimitar listed with
a redacted id, `macro keys: CMKI_1…CMKI_12 (12)`, and two LED zones.

## 3. Enable SDK access in iCUE

In iCUE: **Settings → (your Scimitar or the global settings) → enable SDK /
third-party control**. Under **Settings → SDK**, keep **iCUE SDK** enabled and
enable **Allow Exclusive Control for iCUE Actions**. Despite its broad label,
that is the iCUE gate used by `CAL_ExclusiveKeyEventsListening`; without it,
`CorsairRequestControl` / `CorsairConfigureKeyEvent` return `CE_NotAllowed` and
multi-tap correctly refuses to enter.

If `agentic-mouse-doctor icue` reports *"iCUE refused the connection"*, this is what
is missing. The doctor stays read-only and does not request key control; code
`7` is surfaced only when the running helper actually tries to enter multi-tap.

Do this in the iCUE app, visibly. Never edit iCUE's database or profile files
directly.

## 4. Configure neutral side-grid transports

In iCUE, create one Keyboard Remap for every side cell. Use modifier-free
NumKeyboard keys so the source is easy to diagnose and cannot strand a
modifier:

| Side | iCUE transport |
|---:|---|
| 1–9 | keypad 1 through keypad 9 |
| 10 | keypad 0 |
| 11 | keypad hyphen |
| 12 | keypad plus |

Keep `Retain Original Key Output` off. Keep `Imitate Holding Key` off when a
physical two-second hold already produces one clean down and one clean up; turn
it on only if EventViewer proves that it is required. Reopen each assignment
after saving it. The selected NumKeyboard target must still be present before
you generate or install a downstream rule.

Button 12 remains the Agentic Mouse Utility / Default-legend classifier through
the exact-device Karabiner user-command route: single press opens Utility after
the bounded click window; rapid double press toggles the source mouse's legend.
Karabiner consumes its neutral keypad transport so
the key does not leak into the frontmost application while the runtime owner
handles it. The older SDK raw macro-key route remains source-only diagnostics.

## 4a. Check the rest of the mapping matches

```bash
make mapping
```

This prints the intended semantic layout. Compare it with the generated
Karabiner adapter and the actual iCUE neutral transports. It changes nothing;
saved iCUE state, generated source, installed Karabiner state and physical proof
remain separate evidence classes.

The things worth confirming:

- side buttons **1** and **4** are the horizontal-scroll pair, left then right;
- the **DPI Toggle button** emits the named iCUE F19 transport, and Karabiner
  triggers VoiceInk++ on release without changing DPI;
- **5** = Forward, **8** = Back;
- **2** opens Keys, **3** starts/cancels Screenshot,
  **6** opens the current frontmost app mode, and **7** = Enter;
- **9** is the app-specific wildcard (silent by default; VS Code single press
  Stage + Next and rapid double press exact undo), **10** is blank outside
  modes, **11** holds open Switch App, and **12** opens Utility on a single
  press or toggles the persistent Default legend on a rapid double press;
- while any runtime mode is active, **10** exits it;
- inside Keys, **6** = Copy, **3** = Paste, **9** = Next Track, **8** = Space,
  **11** = Backspace, and **12** = Escape;
- every visible DPI stage, Sniper included, reads **2,750**;
- the generated Karabiner map gives **5**, **8**, and **9** matching base exclusions
  plus exact-device VS Code overrides: F17 Previous Change, F13 Next Change,
  and the bounded F18 single / F16 rapid-double Stage + Next / exact-undo pair;
- every other physical cell inherits the same base action in VS Code;
- the wheel click on each mouse arrives as ordinary `pointing_button: button3`
  from its exact pointing interface and becomes `play_or_pause` in Karabiner;
- every binding contains the exact Corsair `device_if` and optional-any
  modifier handling, and an ordinary physical numpad does not trigger it.

## 5. Package the app

```bash
make app
```

This writes `build/AgenticMouse.app`. It installs nothing. Move it
wherever you want it.

Launch it once. It appears in the menu bar and has **no Dock icon**.

## 6. Grant Accessibility permission

macOS will prompt on first use, or:

**System Settings → Privacy & Security → Accessibility → add
AgenticMouse.app**

Then **quit and relaunch** — macOS only re-reads the grant at launch.

The permission is used for two things: typing the characters you tap out, and
reading which text field has focus so field changes are detected before each
delivery step. A narrow same-application last-check-to-delivery race remains;
see [`LIMITATIONS.md`](LIMITATIONS.md).

The app never prompts behind your back — it uses the non-prompting
`AXIsProcessTrusted()` and explains what is missing in the menu.

The portable package defaults to an ad-hoc signature. For a personal install
that should retain Accessibility approval across rebuilds, package with one
stable signing identity and keep the bundle id and installation path stable:

```bash
make install-candidate
```

Every successfully signed local install candidate advances both version
identifiers exactly once after the package and signature checks pass. By
default it increments the patch component of `CFBundleShortVersionString` and
increments `CFBundleVersion`, for example `v1.0.0 (6)` becomes `v1.0.1 (7)`.
The legend footer shows both values. A failed candidate and ordinary `make app`
development build consume neither value. For a named major or minor release,
set a higher version on the same guarded path:

```bash
RELEASE_VERSION=1.1.0 make install-candidate
```

Grant Accessibility once to that signed `/Applications/AgenticMouse.app`.
Do not reset TCC or use an ad-hoc build for later replacements, because its
designated requirement is a changing code hash.

If the Accessibility row appears enabled but the app still reports that the
grant is unavailable, the row may still be bound to an older ad-hoc build's
exact code hash. Quit Agentic Mouse, remove that row completely with the minus
button, add the literal `/Applications/AgenticMouse.app`, then launch that exact
path again. Do not toggle the stale row, reset all TCC grants, edit the TCC
database, or use `sfltool` as a substitute for this supported repair.

Plain `make app` intentionally produces a development-only ad-hoc bundle and
prints a warning not to install it. The install-candidate target fails closed
if the stable Developer-ID identity or audited iCUE SDK is unavailable.

## 7. Configure

```bash
mkdir -p ~/.config/agentic-mouse
cp Config/config.example.json ~/.config/agentic-mouse/config.json
chmod 600 ~/.config/agentic-mouse/config.json
$EDITOR ~/.config/agentic-mouse/config.json
```

Every setting is documented inline. Missing keys fall back to defaults, so a
three-line config that changes one timeout is perfectly valid.

```bash
swift run agentic-mouse-doctor config
```

prints the resolved configuration, fully redacted, with warnings.

## 8. Use it

1. Click into a text field.
2. Press side button **12**. The mouse turns magenta and pulses; the reference
   card appears.
3. Type. Watch the card for which tap you are on.
4. Press **12** again.

If entry is refused, the card says why for a few seconds and the mouse does not
change colour at all.

## Running at login

The installed menu-bar app registers itself with macOS using `SMAppService`.
It does not install a separate LaunchAgent. If macOS reports that approval is
required, enable **Agentic Mouse** under **System Settings → General → Login
Items**; the menu-bar status reports that state.
