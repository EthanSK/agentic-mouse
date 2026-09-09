# Reproduce Agentic Mouse with your agent

The public repository includes the Karabiner sources, complete generated rules, installer, app source, example configuration and tests. Use the whole repository: copying a JSON rule alone does not install the app or its external receivers.

**You can build and test the public core without either mouse. Reproducing every action in Ethan's setup still needs separate integrations, including the currently private YouTube/Chrome bridge.** Check the [dependency table](SETUP.md#2-check-which-features-you-can-use) before choosing which controls to use.

## Give your agent this prompt

```text
Set up Agentic Mouse from https://github.com/EthanSK/agentic-mouse on my Mac.
Read docs/REPRODUCE.md, docs/AGENT-SETUP.md and docs/SETUP.md first.
Record the source commit and check my mouse models, keyboard layout and apps.
Use the committed sources and complete runtime rules, not Ethan's live profile.
Run the hardware-free build and tests before proposing changes to my Mac.
List unavailable integrations and ask which controls I want to adapt or omit.
Do not assume I have Ethan's signing certificate, shortcuts or permissions.
Back up my configuration and preserve my unrelated rules and settings.
Show the Karabiner installer dry run before applying my approved setup.
Verify the physical buttons with me and report anything not tested.
Leave me the source commit, changed files, setup notes and recovery instructions.
```

## Start from a Git checkout

```sh
git clone https://github.com/EthanSK/agentic-mouse.git
cd agentic-mouse
git rev-parse HEAD
npm ci --ignore-scripts --prefix Integrations/VSCode
make check
```

Record the printed commit so another agent can use the same version. Follow the [toolchain requirements](SETUP.md#1-build-without-changing-your-mac) first. Use a Git clone rather than an extracted source ZIP: the website exporter reads Git's revision for its generated map. `make check` uses simulated hardware and temporary installer profiles; it does not install rules or launch the native app.

## Files already included

| Need | Included source or file |
|---|---|
| Complete Karabiner installation | [`agentic-mouse-runtime.json`](../Karabiner/generated/agentic-mouse-runtime.json) — the only rule artifact to install |
| Exact device filters and source keys | [`bindings.json`](../Karabiner/bindings/bindings.json) |
| Shared actions and output shortcuts | [`Karabiner/actions/`](../Karabiner/actions/) |
| Regenerate and check the rules | [`generate-karabiner.py`](../Scripts/generate-karabiner.py), `make karabiner`, `make test-karabiner` |
| Preserve existing Karabiner settings | [`install-live-karabiner.py`](../Scripts/install-live-karabiner.py), `make test-install` |
| Mouse models, transports and printed-number crosswalk | [Karabiner setup reference](../Karabiner/README.md) and [`PhysicalCell.swift`](../Sources/ScimitarKit/App/PhysicalCell.swift) |
| Native modes, HUD and command receiver | [`Sources/`](../Sources/) and [`Tests/`](../Tests/) |
| Optional app configuration | [`config.example.json`](../Config/config.example.json) |
| App packaging and stable signing | [`package-app.sh`](../Scripts/package-app.sh) and [candidate setup](SETUP.md#5-make-a-stable-installation-candidate) |
| Included VS Code command bridge | [`Integrations/VSCode/`](../Integrations/VSCode/) — separate from Better Git |
| Recovery and removal | [`RECOVERY.md`](RECOVERY.md) |

The generated rules are committed so an agent can inspect them immediately. Regeneration must match those files before adapting them. Do not install `agentic-mouse.json` or `action-catalog.json`: they are development/reference exports, not the complete runtime.

## Configure your own hardware and shortcuts

Follow [hardware preparation](SETUP.md#3-prepare-your-hardware), then the [Karabiner installation steps](SETUP.md#6-initialize-the-complete-karabiner-rules). iCUE assignments and the Razer onboard keys are documented explicitly instead of shipping Ethan's private vendor profile or replacing yours.

Capture each mouse's keyboard **and** pointing interface in Karabiner-EventViewer. Match every transport before enabling the rules; a different model needs an audited adapter, not a filter widened to every keyboard. The two mice share physical actions, but their printed numbers differ.

The top-button action currently sends **Control–Option–Shift** to VoiceInk++ on release. Configure that receiver or adapt its [semantic action](../Karabiner/actions/productivity/toggle-voiceink-speech-to-text.jsonc); installing the JSON does not configure VoiceInk++. The vendor wheel click stays `button3`, which the runtime maps to macOS Play/Pause. Other mouse buttons and ordinary scrolling must remain unaffected.

Ethan uses **DVORAK - QWERTY CMD**. Check every chosen app's shortcuts on your own layout, especially Codex voice, VS Code/Better Git review commands and window controls. Use the source contracts and [generated map](https://ethansk.github.io/agentic-mouse/mouse-map.html); do not copy a private editor settings directory or assume installing the included VS Code bridge supplies Better Git.

## What is deliberately not bundled

- Your live Karabiner profile, vendor profile exports, app settings, device serials, Keychain entries and signing keys.
- Karabiner-Elements, iCUE and Corsair's proprietary SDK; the setup guide links their official sources and the accepted SDK version.
- A Developer ID certificate for your Mac's stable installation; the development build is not a substitute for the documented signed installation.
- VoiceInk++, Better Git and other external apps; configure them separately.
- The private YouTube/Chrome bridge; [its guide](YOUTUBE-BRIDGE.md) explains the missing components and conditional setup.

Finish with the [physical acceptance checklist](AGENT-SETUP.md#verify-the-owners-real-case). Record each feature as working, unavailable or not tested; a successful build does not prove button events, permissions, lighting or another person's physical setup.
