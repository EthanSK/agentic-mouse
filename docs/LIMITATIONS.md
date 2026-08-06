# Limitations

An honest list. Where something is unverified, it says so rather than implying
otherwise.

## Hardware-gated: not proven by this codebase

These need the physical mouse and a live iCUE, and are covered in
[`LIVE-PROOF.md`](LIVE-PROOF.md).

1. **Whether a *disabled* button 12 still emits a shared raw macro-key event.**
   The mouse is known to report `CMKI_1…CMKI_12`. Whether clearing M12's
   assignment in iCUE suppresses the SDK event as well as the action is a
   firmware/iCUE behaviour that only a physical test can settle. If it does
   suppress it, button 12 needs a harmless assignment instead of an empty one.

2. **Whether `CorsairConfigureKeyEvent` actually stops the normal assignment
   reaching macOS.** The SDK documents interception as routing the event to the
   exclusive client instead of other SDK clients. Whether iCUE *also* suppresses
   its own profile action for an intercepted key is the behaviour multi-tap mode
   depends on. If it does not, pressing `4` in the mode would type a letter *and*
   scroll — visible immediately, and the fallback is to clear the twelve
   assignments in a dedicated iCUE profile.

3. **Whether iCUE grants `CAL_ExclusiveKeyEventsListening` on this setup.**
   Code `7` means it is switched off in iCUE's settings. Handled and explained,
   but the happy path is unproven here.

4. **Real LED appearance.** The two LUIDs and the colour maths are implemented
   and unit-tested, but nobody has looked at the actual mouse.

5. **Typing into real applications.** `postToPid` + `keyboardSetUnicodeString`
   is the standard layout-independent approach, but individual apps vary. Known
   awkward cases: terminal emulators in some modes, remote-desktop clients,
   games with raw input, and anything that ignores synthetic events.

## Known behavioural limits

**Entering the mode can leak one button press.** Interception starts *after*
entry succeeds, so the press of button 12 that enters the mode is still seen by
iCUE. Clearing button 12's assignment avoids it. The same is true in reverse:
the press that exits happens while interception is still active, so it does not
leak.

**Focus detection is per-element, not per-caret.** Moving the caret within one
text field is not a target change, so a pending character still commits there.
That is intended.

**The final CoreGraphics delivery is process-targeted, not AX-element-targeted.**
The helper re-resolves the exact focused AX element before every output command
and Unicode chunk, and `postToPid` prevents cross-application redirection. macOS
still delivers the event to whichever field is focused inside that captured
application. A focus move in the tiny interval after the last check but before
OS delivery can therefore reach another field in the same app. CoreGraphics
does not expose an atomic check-and-post operation; avoid changing fields while
a commit is landing.

**A target change detected during final delivery ends the mode.** The configured
`cancelPending` policy normally keeps multi-tap active after a field change.
If the final `TextOutput` recheck catches that move after delivery has begun,
the coordinator exits instead: ending the transaction is safer than continuing
after a possibly partial command batch.

**Some apps expose no usable AX element.** Canvas-based editors, some Electron
builds and some Java apps report focus that fails the editable test. The mode
fails closed: the HUD says the target will not accept text, and nothing is
typed. It is a refusal, not a silent failure.

**Secure fields are never typed into.** By design, with no override.

**The event-tap fallback cannot identify the device.** If you opt into
`cgEventTap`, a matching button on any mouse looks the same. Documented in
[`ICUE-FALLBACK.md`](ICUE-FALLBACK.md).

**One mouse only.** Two matching Scimitars means the selector refuses to guess.
Pin one with `lighting.device.deviceTag`.

**Multi-tap is slow.** It is multi-tap. `s` costs four presses. It is for
"type a URL without reaching for the keyboard", not for prose.

**No T9.** Deliberately. No dictionary, no prediction, no surprises.

## Hue limits

**Local network only.** No cloud API, no remote access. The bridge must be
reachable directly.

**Bridge TLS uses a host-scoped trust exception, not certificate pinning.** Hue bridges present a
certificate signed by Philips' private root with the bridge id as the common
name, which system trust rejects. The delegate accepts it for the exact
configured request host and refuses every other host. It does not verify a
certificate fingerprint or public key, so a LAN attacker able to impersonate
that host is not excluded. Pair and operate only on a trusted local network.

**Only lights, not groups or scenes.** Four light resource ids, two clusters.
Scenes are not read.

**A light missing from the bridge is treated as absent.** Its zone renders
black rather than guessing.

**Colour is approximate.** Two small LEDs cannot reproduce a room. Brightness
has a floor so a lamp at 1% does not look broken, and saturation is boosted
slightly because small LEDs read washed out.

## iCUE limits

**iCUE must be running.** No iCUE means no lighting and no multi-tap. The menu
bar says so.

**Shared layer only.** iCUE renders at 127, other shared clients at 128, this
helper at 130. Another SDK client at a higher priority would win, and this
project will not escalate to exclusive lighting to fight it.

**Exclusive lighting is never requested.** Levels 1 and 3 are rejected inside
the C bridge before the SDK is called.

**Wireless sleep.** A sleeping Scimitar reports `CE_DeviceNotFound`; the
controller forgets it and re-selects on reconnect. If the mouse sleeps *during*
multi-tap mode, the mode exits.

## Scope

**Nothing is installed.** No LaunchAgent, no login item, no system settings
touched. `make app` writes to `build/` and stops.

**iCUE profiles are never edited.** The helper reads device properties and
writes shared-layer colours. It does not modify a profile, and it never touches
iCUE's database files.

**Normal-mode assignments are not managed by this helper.** The mapping lives in
iCUE: 4 = VoiceInk++ speech-to-text, 5 = Forward, 6 = Next Track, 7 = horizontal
scroll left, 8 = Back, 9 = Previous Track, 10 = horizontal scroll right, with a
VS Code-linked profile overriding only 7/8/10 for Better Git. Every visible DPI
stage is 2,750 and the DPI Toggle button is disabled. The helper prints this
table (`agentic-mouse-doctor mapping`) so it can be checked, but it never writes it —
if iCUE and the table disagree, iCUE wins.

**Profile switching is iCUE's business, not the helper's.** The helper suspends
all twelve buttons while multi-tap is active and releases them on exit. Which
profile iCUE then resumes — Normal or the VS Code-linked one — is decided by
iCUE from the frontmost app. The helper does not read, switch or influence that,
so if profile switching itself is flaky, this cannot compensate for it.
