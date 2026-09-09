# Set up Agentic Mouse

Start with the [browser walkthrough](https://ethansk.github.io/agentic-mouse/). The native app needs manual setup for your own Mac, mice, keyboard layout and installed apps. There is no signed, notarized app download yet.

Using a coding agent? Give it [AGENT-SETUP.md](AGENT-SETUP.md) before letting it change your machine.

## 1. Build without changing your Mac

You need **Xcode 26 or later with the macOS 26 SDK**, its bundled Swift toolchain, **Node.js 22 or later**, and **Python 3**. The native glass HUD cannot compile against an older SDK, even though the app's deployment target is macOS 13. The package manifest's Swift 5.10 tools version is not the complete build requirement.

Use a Mac supported by your Xcode version: Xcode 26 requires macOS 15.6 or later, and newer versions may require a newer host. Check [Apple's Xcode requirements](https://developer.apple.com/xcode/system-requirements). Apple Silicon and Intel are build targets; each still needs its own hardware acceptance.

Select the full Xcode installation under **Xcode → Settings → Locations → Command Line Tools**, or set `DEVELOPER_DIR` to that installation's `Contents/Developer` directory for your shell. Confirm `xcodebuild -version`, `xcrun --show-sdk-version` (26 or later), `swift --version`, `node --version`, and `python3 --version` before building. CI selects Xcode 26.3 explicitly rather than relying on the runner's older default.

```sh
git clone https://github.com/EthanSK/agentic-mouse.git
cd agentic-mouse
npm ci --ignore-scripts --prefix Integrations/VSCode
make check
make app
```

The npm step installs the locked local VS Code packaging tool; it does not install an editor extension. Tests use fake hardware. `make app` writes an **ad-hoc development bundle** to `build/AgenticMouse.app`; it does not install or launch it. Do not use it to replace an app with Accessibility permission.

Read-only diagnostics:

```sh
swift run agentic-mouse-doctor config
swift run agentic-mouse-doctor mapping
swift run agentic-mouse-doctor icue
swift run agentic-mouse-doctor razer
make simulate
```

Do not add hardware-write flags for an initial inspection. Launching the GUI app is separate: it starts input handling and registers its runtime supervisor.

## 2. Check which features you can use

| Feature | Dependency | Included here? |
|---|---|---|
| Exact-device button routing | [Karabiner-Elements](https://karabiner-elements.pqrs.org/) and verified device adapters | Rules and installer; Karabiner itself is separate |
| Modes, HUD, Keypad, clipboard and basic keys | Agentic Mouse with Accessibility permission | Yes |
| Corsair neutral transports and temporary RGB | [iCUE 5](https://www.corsair.com/uk/en/s/downloads); audited SDK for RGB | iCUE and SDK are separate |
| Razer input and mode lighting | Supported Naga Left-Handed `1532:008d` and its onboard transports | Adapter and lighting code; verify your exact unit |
| Speech mode | [VoiceInk++](https://github.com/EthanSK/VoiceInkPlusPlus) | Separate app; ordinary VoiceInk is not a verified substitute |
| YouTube pause/resume, seek, volume, 2× speed; Chrome tab history and website opening | VoiceInk YouTube Bridge Chrome extension and macOS helper | **No; bridge source is currently private.** [Setup and checks](YOUTUBE-BRIDGE.md) |
| VS Code cursor history and terminal toggle | Agentic Mouse VS Code Bridge | Yes; package below |
| VS Code review navigation and staging | Compatible Better Git extension and its captured-origin commands | **No.** The included bridge does not provide these commands |
| Window placement and saved layout | Magnet / Stay, matching shortcuts and your own saved layout | No |
| App-specific shortcuts | Matching apps, keyboard layout and shortcut settings | Definitions only; configure for your Mac |

Missing external receivers leave their controls without a working destination. They do not prevent building or using independent controls. Review or replace those actions in source before relying on them. The [generated map](https://ethansk.github.io/agentic-mouse/mouse-map.html) shows the layout and reported repairs; it does not test your installed apps.

## 3. Prepare your hardware

Back up your vendor profile and `~/.config/karabiner/karabiner.json`. Keep an ordinary keyboard available. Verify exact vendor/product IDs and press/release events in Karabiner-EventViewer before enabling an adapter. Never broaden it to all keyboards or mice to make a button work.

For the supported Corsair, use one iCUE software profile with modifier-free Keyboard Remaps:

| Printed side button | Neutral transport |
|---|---|
| 1–9 | Keypad 1–9 |
| 10 | Keypad 0 |
| 11 | Keypad hyphen |
| 12 | Keypad plus |

Keep **Retain Original Key Output** off. Keep **Imitate Holding Key** off unless EventViewer proves your device needs it for one clean down/up lifecycle. Reopen each saved assignment to confirm its target. The top DPI control uses F19; wheel click stays ordinary middle click. Ethan uses 2,750 DPI in every stage; choose your own sensitivity without assigning semantic actions to DPI changes.

The supported Razer onboard grid emits main-row `1–9`, `0`, `hyphen`, and `equal_sign`. Its printed numbers differ from Corsair's; [PhysicalCell.swift](../Sources/ScimitarKit/App/PhysicalCell.swift) owns the crosswalk, with adapter details in [Karabiner/README.md](../Karabiner/README.md). Verify top-button transports separately. Other Naga or Scimitar models may expose different interfaces.

Use vendor settings visibly. Do not edit iCUE's private database or reset unrelated devices. With one supported mouse, the other exact-device adapter has no matching device; it needs no broad fallback.

## 4. Prepare Corsair lighting, if used

Only **iCUE SDK 4.0.84** is accepted. Download `iCUESDK_4.0.84.dmg` from [Corsair's official release](https://github.com/CorsairOfficial/cue-sdk/releases/tag/v4.0.84), mount it, and locate `iCUESDK.framework`. The framework is not committed here. Check its version:

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  /Volumes/iCUESDK/iCUESDK.framework/Versions/A/Resources/Info.plist
```

The result must be `4.0.84`. Substitute the actual mount path if different. Unknown versions and raw dylibs are rejected before loading. Enable SDK / third-party lighting access in iCUE, then use `agentic-mouse-doctor icue` to verify connection and exact-device enumeration. Connection alone does not prove colours or restoration on exit.

The packager can embed your local framework. Alternatively, `lighting.sdkSearchPaths` accepts the binary path inside a versioned framework. Karabiner mode input does **not** require iCUE SDK macro interception; the older exclusive-key diagnostics are separate.

## 5. Make a stable installation candidate

Use a Developer ID Application certificate that belongs to you:

```sh
security find-identity -v -p codesigning
CODE_SIGN_IDENTITY='Developer ID Application: YOUR NAME (YOUR TEAM)' \
ICUE_SDK_FRAMEWORK='/path/to/iCUESDK.framework' make install-candidate
```

For Razer only, or a deliberate build without Corsair lighting:

```sh
CODE_SIGN_IDENTITY='Developer ID Application: YOUR NAME (YOUR TEAM)' \
REQUIRE_ICUE_SDK=0 ICUE_SDK_FRAMEWORK='/nonexistent/agentic-mouse-sdk' \
make install-candidate
```

`REQUIRE_ICUE_SDK=0` allows the SDK to be absent; it does not remove a framework found at the supplied path. With no certificate, stop at build/tests and the browser demo. Do not bypass the installation guard with an ad-hoc signature.

A successful candidate advances the patch version and build number in `Resources/Info.plist` once. Failed candidates consume no version. To choose a higher release version, also pass `RELEASE_VERSION=1.2.0` (or another version above the recorded one). Review that source change before committing.

This packages but does not install. At a safe time, preserve any existing `/Applications/AgenticMouse.app` as a rollback, then copy the signed candidate to **that exact path**. Keep the same signing identity, bundle ID and installation path on updates. Do not launch a second copy from `build/`.

## 6. Initialize the complete Karabiner rules

Open Karabiner once so a selected profile exists. Compare [bindings.json](../Karabiner/bindings/bindings.json) with your captured devices, then check [the agent setup guide](AGENT-SETUP.md) for keyboard-layout dependencies.

```sh
make karabiner
make test-karabiner
```

Install **only** `agentic-mouse-runtime.json`. It includes the locked-session sink, exact-device bases, app overrides, mode routing and Exit. The smaller `agentic-mouse.json` is a development export, unsafe as a complete installation.

For a first installation, run this in one shell:

```sh
AM_LIVE="$HOME/.config/karabiner/karabiner.json"
AM_HASH="$(shasum -a 256 "$AM_LIVE" | awk '{print $1}')"
AM_BACKUP="$HOME/.config/karabiner/karabiner.before-agentic-$(date +%Y%m%d-%H%M%S).json"
python3 Scripts/install-live-karabiner.py \
  --live "$AM_LIVE" \
  --generated Karabiner/generated/agentic-mouse-runtime.json \
  --expected-live-sha256 "$AM_HASH" --backup "$AM_BACKUP" --initialize
```

This is a dry run. Read the result, then repeat the Python command with **`--apply`** appended. It refuses a changed live hash or existing backup path, inserts a contiguous Agentic block before existing rules, and preserves other rules, profile settings and profiles. Retain the backup privately. Custom buttons stay consumed until the app establishes its unlocked-session lease.

For updates, omit `--initialize`, use a fresh hash and unused backup path, and keep the current app running so the installer can close both mode coordinators before reload. Scattered Agentic rules cause a refusal; review that arrangement instead of replacing the whole profile.

## 7. Launch and grant permissions

Optionally copy [config.example.json](../Config/config.example.json) to `~/.config/agentic-mouse/config.json` **only if no config exists**. Keep it private with `chmod 600`. Missing settings use defaults. Validate with `swift run agentic-mouse-doctor config`. Keep personal identifiers and credentials out of Git.

Launch `/Applications/AgenticMouse.app`. It is a menu-bar app with no Dock icon. Add that exact app under **System Settings → Privacy & Security → Accessibility**, then use **Quit Agentic Mouse** and relaunch. Follow Karabiner's separate permission and background-service prompts. Do not reset all Accessibility permissions or edit TCC databases.

Every GUI launch attempts to register the signed nested **Agentic Mouse Runtime Supervisor** through `SMAppService.loginItem`. It starts at login and recovers unexpected exits. If approval is required, enable it under **System Settings → General → Login Items & Extensions**. The app's own Quit unregisters it; reopening enables it. This also applies to a GUI bundle opened outside `/Applications`, which is why the development bundle should stay unlaunched.

Optional VS Code bridge:

```sh
make vscode-bridge
code --install-extension build/agentic-mouse-vscode-bridge-0.1.1.vsix --force
```

The same VSIX is included at `Contents/Resources/AgenticMouseVSCodeBridge.vsix`. Reload your editor at a safe time if needed. It accepts only its narrow commands in a focused VS Code window, adds no user keybindings, and does not replace Better Git.

## 8. Verify before relying on it

Start in a disposable text field. Confirm ordinary pointer/scroll/left/right click, each installed mouse's twelve transports, top button and wheel click. Open and exit modes independently on each hand. Test Keys → Keypad, focus changes before a pending character commits, and restoration of the normal map.

Then verify wheel polarity, sleep/wake, session lock/unlock, intentional Quit, restart and physical lighting restoration. Test external actions only after their receiver and shortcuts are configured. Avoid testing interruption, screenshots, staging, clipboard or window actions over valuable work.

Keep automated tests, installed-byte checks and physical acceptance separate. See [release readiness](RELEASE.md) for public-release gates and [recovery](RECOVERY.md) for rollback and removal.
