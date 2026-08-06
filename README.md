# Agentic Mouse

**Two mice. One muscle-memory map. Local macOS automation with no mystery
profiles.**

Agentic Mouse is an open, local-first control layer for a Corsair Scimitar
Elite Wireless SE and a left-handed Razer Naga. It keeps the useful parts of a
gaming mouse — reachable buttons, hardware profiles and lighting — while
making them useful for writing, browsing, coding and talking to an agent.

It started as Ethan's setup. The point of publishing it is not that everyone
should copy Ethan's exact choices: it is that you should be able to see every
choice, adopt the pieces you like, and keep both of your mice coherent.

> **Current status:** the bundled macOS helper is production-designed for the
> Corsair Scimitar's iCUE SDK route. The Razer Naga Left-Handed Edition is
> supported today as a documented Karabiner-Elements profile workflow; its
> event map still needs one physical capture before we generate its final
> profile. Nothing in this repository silently edits either vendor profile.

## Ethan's map

The core idea is physical reach, not a long menu of actions. The Scimitar's
easy middle keys do common navigation; the hard-to-reach keys get rarer jobs.
These are the currently authoritative Corsair assignments:

| Control | Normal behaviour | VS Code behaviour |
|---|---|---|
| Wheel press | Play / Pause | Play / Pause |
| DPI button | Disabled | Disabled |
| Button 4 | VoiceInk++ speech-to-text | VoiceInk++ speech-to-text |
| Button 5 | Forward | Forward |
| Button 6 | Next Track | Next Track |
| Button 7 | Horizontal scroll left | Better Git: Next Change |
| Button 8 | Back | Better Git: Previous Change |
| Button 9 | Previous Track | Previous Track |
| Button 10 | Horizontal scroll right | Better Git: Stage Current File |
| Button 12 | Multi-tap entry / exit | Multi-tap entry / exit |
| DPI stages, including Sniper | 2,750 DPI | 2,750 DPI |

Buttons 1–3 and 11 are deliberately left open while the layout settles. That
is a feature: an empty button is better than a shortcut you constantly trigger
by accident.

See [the two-mouse setup guide](docs/MICE.md) for the matching Razer approach,
how to capture its real button events, and the safety boundaries around vendor
software.

## What the included helper does

The macOS menu-bar app adds two *optional* Corsair-only behaviours:

- **Multi-tap typing.** Button 12 turns the twelve-key thumb grid into a
  classic phone keypad. It uses buffered, focus-anchored text delivery: if the
  target app or text field changes, it drops the pending character rather than
  risking typing into the wrong place.
- **Read-only Hue mirroring.** Two groups of Philips Hue lights can colour the
  Scimitar's two LED zones. The implementation only reads the bridge; it cannot
  modify a light.

The helper never writes an iCUE profile, changes DPI, changes a Hue light or
replaces a normal button assignment. When it quits, iCUE takes the mouse back.

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
swift run agentic-mouse-doctor mapping
```

It reports configuration and simulated behaviour. It does not rewrite iCUE,
Hue, macOS permissions or vendor firmware.

## The two supported routes

| Mouse | Practical macOS route | Why |
|---|---|---|
| Corsair Scimitar Elite Wireless SE | iCUE for its device profile; Agentic Mouse for optional SDK-only features | iCUE exposes the Scimitar's macro keys and two LED zones. |
| Razer Naga Left-Handed Edition (RZ01-0341) | Karabiner-Elements, with its real events captured in Karabiner-EventViewer | Current Razer Synapse for Mac does not list this model, and Razer documents a Synapse/Karabiner conflict. |

The Razer recommendation is deliberately conservative: do not install Synapse
for this model just to chase a profile editor. Capture the Naga's events in
Karabiner-EventViewer, map only the buttons you want, and keep the same shared
actions as the Corsair where physical reach makes sense. The full procedure is
in [docs/MICE.md](docs/MICE.md).

## Multi-tap, without the unsafe bit

The Scimitar's 4 × 3 grid becomes a phone keypad when the mode is active:

```text
physical pad (front → back)       phone keypad

1  4  7  10                        1 2 3
2  5  8  11                        4 5 6
3  6  9  12                        7 8 9
                                  * 0 #
```

Tap 2–9 for letters, hold for digits, use 10 for Backspace/case, 11 for
Space/Return, and 12 to enter or leave the mode. While multi-tap is on, all
twelve side keys are held by the helper; button 4 will not accidentally start
dictation while you are trying to type a `g`.

## Safety model

- **No hidden profile edits.** Configure iCUE or Karabiner visibly; the helper
  never writes vendor databases or private profile files.
- **No secret repository.** Bridge keys, light IDs, device IDs and serials stay
  out of Git. The supplied configuration is placeholders only.
- **No light control.** Hue traffic is read-only by type, not just by policy.
- **Fail closed typing.** Password fields, unknown focus and missing
  Accessibility permission produce no text.
- **No device assumption.** The iCUE path refuses to guess when several
  Scimitars match.

## Project layout

```text
Sources/
  CICUEBridge/              Runtime bridge to the proprietary iCUE SDK
  ScimitarKit/              Injectable Corsair, Hue, input and multi-tap core
  ScimitarUI/               Non-activating HUD and menu-bar UI
  AgenticMouseApp/          The Agentic Mouse app entry point
  ScimitarDoctor/           Read-only diagnostics and simulator
Config/config.example.json  Safe placeholders only
docs/                       Setup, safety notes and the public project page
```

The internal Swift module names retain `Scimitar` where they describe the
specific Corsair adapter. The public product, application, command names,
configuration path and documentation are **Agentic Mouse**.

## Documentation

| Guide | What it is for |
|---|---|
| [Mice](docs/MICE.md) | Two-mouse setup, authoritative map and Razer workflow |
| [Setup](docs/SETUP.md) | Build, iCUE SDK, optional Hue pairing and permissions |
| [Architecture](docs/ARCHITECTURE.md) | Components and invariants |
| [Limitations](docs/LIMITATIONS.md) | What is not claimed to work |
| [Recovery](docs/RECOVERY.md) | Cleanly getting back to normal |
| [iCUE fallback](docs/ICUE-FALLBACK.md) | The less capable fallback input route |
| [Live proof](docs/LIVE-PROOF.md) | Verified versus still-physical checks |

## Contributing your own layout

Fork it, document the physical mouse and macOS version, use an event viewer to
prove the transport before remapping it, and keep the map legible. If a finding
is durable, update the relevant guide in the same change — future you should
not have to rediscover it by pressing buttons.

## License

MIT. See [LICENSE](LICENSE).
