# Agentic Mouse

**The setup for the agentic future.**

Twelve thumb controls, mirrored on both mice. I lean back, talk to agents, and keep the rest under my thumb.

My personal macOS setup, made public so you can explore it and build your own. — **Ethan S K**

[**Try the interactive walkthrough →**](https://ethansk.github.io/agentic-mouse/) · [Every button and mode](https://ethansk.github.io/agentic-mouse/mouse-map.html) · [Setup guide](docs/SETUP.md)

![An AI recreation of Ethan S K reclining at his studio desk, using one of two mice on the desktop](docs/assets/ethan-lounging.webp)

*My setup, reimagined with AI from my portrait and studio photos.*

## Take it for a spin

The website is a working browser demo of the mouse controls:

1. **Rotate either mouse.** Drag the models, then switch hands to try each thumb grid.
2. **Press a mode button.** The native-style HUD opens beside the mouse with Utility, Keys, or the current app’s controls. Press Exit to return.
3. **Try the gestures.** Hold a wheel control and use Wheel up / Wheel down. Open Keys → Keypad to type a local example.

The HUD’s labels, card colours, printed-button crosswalk, repair markers, and mode transitions are generated from the native Swift source. On phones, the HUD appears below the mouse and scrolls into view when you press a key. The 3D hardware is recreated from product photographs. The demo does not control your Mac or access your microphone.

## What I use it for

| Gesture | What it does |
|---|---|
| Top button | Activate speech mode with VoiceInk++. DPI stays at 2,750. |
| Wheel click | Play or pause the current media. |
| Thumb button + wheel | Copy/paste, scroll horizontally, scrub YouTube, or use a mode-specific control. |
| App mode | Bring up controls for the frontmost app, including Codex, Chrome, VS Code, and Spotify. |
| Utility mode | Control windows, Spaces, brightness, zoom, and other utilities. |
| Keys → Keypad | Use arrows and editing keys, or type with classic phone-style multi-tap. |
| Legend toggle / Exit | Show the Default map, or leave an active mode. Each mouse keeps its own state. |

[Open the generated map](https://ethansk.github.io/agentic-mouse/mouse-map.html) for the exact button numbers and every app mode. Some controls carry a **Needs repair** marker from my latest physical report; a browser demo is not proof that the corresponding Mac action works.

## My setup

| Part | What I use |
|---|---|
| Left hand | [Razer Naga Left-Handed Edition](https://www.razer.com/gb-en/gaming-mice/razer-naga-left-handed-edition), black |
| Right hand | [Corsair Scimitar Elite Wireless SE](https://www.corsair.com/uk/en/p/gaming-mouse/ch-9314415-ww/scimitar-elite-wireless-se-mmo-gaming-mouse-black-yellow-ch-9314415-ww), black/yellow (`CH-9314415-WW`) |
| Dictation | VoiceInk++ |
| Chair | [Hbada E3 Pro 2026](https://www.hbada.uk/products/hbada-e3-pro-ergonomic-office-chair?variant=57072259858807), grey with footrest |
| Desk | [FlexiSpot E7 Pro](https://flexispot.co.uk/next-generation-standing-desk-e7-pro), bought in 2025: black frame, 180 × 80 cm bamboo top |

These models and options were checked against my purchase confirmations. FlexiSpot's linked shop page now sells the 2026 revision; my desk is the 2025 model.

The mice share a physical action layout, with their own printed numbers and mirrored presentation. I can switch hands without changing how I work.

## Build the app

**Ready to build and adapt; manual setup required.** There is no signed, notarized app download yet. Speech mode, YouTube control and some VS Code actions depend on external integrations that are not included. Check the [dependency table](docs/SETUP.md#2-check-which-features-you-can-use) before setting up your mice.

Building requires **Xcode 26 or later with the macOS 26 SDK**, its bundled Swift toolchain, **Node.js 20 or later**, and **Python 3**. Use a Mac supported by that Xcode version; the app itself targets macOS 13 or later. Building and running the hardware-free tests does not require either mouse or the proprietary iCUE SDK. See the [toolchain setup](docs/SETUP.md#1-build-without-changing-your-mac).

```sh
git clone https://github.com/EthanSK/agentic-mouse.git
cd agentic-mouse
make check
make app
```

`make app` packages an ad-hoc development bundle at `build/AgenticMouse.app`. It does **not** install or launch it. Follow the signing steps in the setup guide before a real installation; launching the GUI app starts input handling and registers its login supervisor.

For real hardware, follow the [setup guide](docs/SETUP.md): configure the neutral button transports, provide the iCUE SDK for Corsair lighting, review the generated Karabiner runtime rules, and grant the required macOS permissions. This is a personal setup to commission, not a universal plug-and-play installer.

<details>
<summary>Read-only diagnostics</summary>

```sh
swift run agentic-mouse-doctor config
swift run agentic-mouse-doctor mapping
swift run agentic-mouse-doctor icue
swift run agentic-mouse-doctor razer
make simulate
```

These commands inspect or simulate. They do not rewrite iCUE profiles or system settings. The doctor's separate lighting tests require explicit flags.

</details>

## Update the website

```sh
make test-site
python3 -m http.server 8841 --directory .build/site
```

Open [localhost:8841](http://localhost:8841/). The build runs the native mode coordinator with inert outputs and writes a fresh website to `.build/site`.

Every push to `main` automatically rebuilds, tests, and publishes the website through [GitHub Actions](.github/workflows/showcase.yml). Pull requests build and test without publishing. Change the app definitions, push the change, and the public map follows; there is no second website button table to update.

The site reflects the source that was pushed. Local changes and private machine settings are not uploaded automatically. See [website maintenance](docs/SHOWCASE.md) for the generation boundary and visual QA checklist.

## How it fits together

| Layer | Owner |
|---|---|
| Corsair DPI, profiles, and neutral transports | iCUE |
| Razer hardware transports | Naga onboard profile |
| Exact-device input routing | Karabiner-Elements |
| Modes, HUDs, action definitions, and temporary lighting | Agentic Mouse |

Agentic Mouse does not edit vendor profile databases. Its runtime modes restore the normal mapping on exit, and session-lock handling cancels pending actions. Configuration and private device details stay outside Git.

## Go deeper

- [Setup](docs/SETUP.md) — build requirements, SDK, hardware, and permissions.
- [Set up with your agent](docs/AGENT-SETUP.md) — adapt the project to your own Mac and apps.
- [Contribute](CONTRIBUTING.md) · [Release readiness](docs/RELEASE.md) — checks, supported scope and remaining release gates.
- [Architecture](docs/ARCHITECTURE.md) — native components and responsibilities.
- [Karabiner](Karabiner/README.md) — semantic actions and exact-device adapters.
- [Limitations](docs/LIMITATIONS.md) · [Live proof](docs/LIVE-PROOF.md) — what is verified and what still needs physical acceptance.
- [Recovery](docs/RECOVERY.md) — return to normal if something goes wrong.

MIT licensed. [Read the license](LICENSE).
