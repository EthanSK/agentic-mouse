# Setup

Nothing here is done for you. Every step is a deliberate action, and none of
the build tooling installs anything, registers a LaunchAgent, or changes a
system setting.

## 0. Prerequisites

- macOS 13 or later, Apple Silicon or Intel
- Xcode command line tools (Swift 5.10+)
- iCUE 5.x installed and running
- A Philips Hue bridge on your LAN (optional — multi-tap works without it)

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

## 4. Free up side button 12

Button 12 is the mode toggle. In iCUE, make sure it has no assignment (or an
assignment you do not mind losing while the mode is active).

The helper will still work if button 12 has an assignment — the macro key event
fires regardless — but the assignment will also fire when you press it to
*enter* the mode, because interception is not active until after entry
succeeds. Clearing it avoids that one-shot leak.

> **Open hardware question.** Whether a *disabled* M12 still emits shared raw
> macro-key events is the one thing that could not be settled without physical
> testing. See [`docs/LIVE-PROOF.md`](LIVE-PROOF.md) for the exact test and the
> fallback if the answer turns out to be "no".

## 4a. Check the rest of the mapping matches

```bash
make mapping
```

This prints what the helper believes is in iCUE. Compare it against the actual
profiles. It changes nothing — if the two disagree, iCUE is right and the table
in `Sources/ScimitarKit/App/NormalMapping.swift` is what needs updating.

The things worth confirming by eye:

- side button **4** runs the VoiceInk++ macro, and the **DPI Toggle button is
  disabled** and does *not*;
- **5** = Forward, **8** = Back;
- **7** and **10** are the horizontal-scroll pair;
- **6** = Next Track, **9** = Previous Track;
- every visible DPI stage, Sniper included, reads **2,750**;
- the **VS Code** profile is linked to `/Applications/Visual Studio Code.app`
  and overrides only **7** (F13), **8** (F17) and **10** (F18), with the
  matching Better Git keybindings on the VS Code side.

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
delivery step. Hue mirroring does not need it. A narrow same-application
last-check-to-delivery race remains; see [`LIMITATIONS.md`](LIMITATIONS.md).

The app never prompts behind your back — it uses the non-prompting
`AXIsProcessTrusted()` and explains what is missing in the menu.

> The local package is only ad-hoc signed. Keep the bundle at one stable path
> and keep the bundle id `com.ethan.agentic-mouse`, but do not rely on that
> to preserve TCC approval: macOS can invalidate Accessibility permission after
> a rebuild. Re-check the app in this pane and remove/re-add it if necessary.

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

### Multi-tap only

If you do not want Hue mirroring, set `"hue": { "enabled": false }` and you are
done.

## 8. Hue (optional)

### 8a. Find the bridge

The Hue app shows it under **Settings → My Hue System**. Or:

```bash
curl -s https://discovery.meethue.com/
```

### 8b. Create an application key

This is the one setup step that writes to the bridge — it creates a credential
for this app. It does not touch any light.

Press the physical **link button** on the bridge, then within 30 seconds:

```bash
curl -sk -X POST https://<BRIDGE-IP>/api \
  -H 'Content-Type: application/json' \
  -d '{"devicetype":"agentic-mouse#mac","generateclientkey":true}'
```

The response contains `"username": "<long string>"`. That is your
`hue-application-key`.

### 8c. Store it in the Keychain

```bash
security add-generic-password \
  -s com.ethan.agentic-mouse \
  -a hue-application-key \
  -w '<THE KEY>' \
  -U
```

The helper only ever *reads* this item. It never creates or updates one.

### 8d. Find your four light ids

```bash
KEY=$(security find-generic-password -s com.ethan.agentic-mouse -a hue-application-key -w)
curl -sk -H "hue-application-key: $KEY" https://<BRIDGE-IP>/clip/v2/resource/light \
  | python3 -c 'import json,sys; [print(l["id"], l.get("metadata",{}).get("name")) for l in json.load(sys.stdin)["data"]]'
```

Put the ids into `hue.lights`, assigning each to `candleAndSofa` or
`deskLusters`.

> None of these values — bridge address, application key, light ids — may be
> committed to this repository. They belong in `~/.config` and the Keychain.

### 8e. Check it

```bash
swift run agentic-mouse-doctor colors    # how readings convert to mouse colours
swift run agentic-mouse-doctor config    # confirms the key resolves, without printing it
```

## 9. Use it

1. Click into a text field.
2. Press side button **12**. The mouse turns magenta and pulses; the reference
   card appears.
3. Type. Watch the card for which tap you are on.
4. Press **12** again.

If entry is refused, the card says why for a few seconds and the mouse does not
change colour at all.

## Running at login (optional, manual)

This project deliberately does not install a LaunchAgent. If you want one, add
the app under **System Settings → General → Login Items**.
