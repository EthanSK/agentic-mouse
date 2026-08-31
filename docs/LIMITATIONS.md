# Limitations

An honest list. Where something is unverified, it says so rather than implying
otherwise.

## Hardware-gated: not fully proven by this codebase

Current ordinary and mode input uses exact-device Karabiner transports, not the
older iCUE exclusive-key interception experiment. The remaining gates are:

1. **DPI release timing on the current saved transports.** Corsair F19 and both
   Razer transports, F21 and F22, are installed as release actions. The latest
   configuration still needs one physical down/up capture and one VoiceInk
   activation from each control, plus one simultaneous two-button release to
   prove VoiceInk++ coalesces it into a single activation.

2. **Typing into real applications.** `postToPid` + `keyboardSetUnicodeString`
   is the standard layout-independent approach, but individual apps vary. Known
   awkward cases: terminal emulators in some modes, remote-desktop clients,
   games with raw input, and anything that ignores synthetic events.

3. **Final physical lock-screen acceptance.** Automated tests prove the
   documented session lifecycle, three-second fail-closed lease, complete
   exact-device transport sink, output-time guards, and destructive mode/HUD
   teardown. Ethan still needs to lock the real Mac once and physically confirm
   that both mice retain ordinary pointer/click behavior while every custom
   side-grid, DPI, wheel-command, and active-mode action remains inert.

## Known behavioural limits

**Locked-session protection depends on Agentic Mouse and the installed generated
Karabiner rules agreeing on the same lease variable.** A process crash or stale
lease fails closed within three seconds. Replacing only one side of that pair is
not a supported installation. Unlock never resumes the previously active mode.

**Colour Proof is retired from the live map.** Its accepted input, HUD, Corsair,
and Razer lighting paths remain only as regression infrastructure. It has no
generated rule or selectable mouse slot.

**Razer macOS RGB through standard HID LampArray is physically rejected.**
Read-only inspection proved that exact device `1532:008d` exposes a standard
three-lamp LampArray and reports each lamp programmable. However, solid red, a
distinctive three-zone pattern, and a five-minute red/off strobe all returned
successful HID writes while the mouse visibly stayed on its autonomous rainbow.
Report 6 (`AutonomousMode`) reads back the previous valid feature response
instead of its declared state, proving that the advertised control is not
implemented correctly enough for this route. Do not ship or install this source
adapter as a working lighting target.

`agentic-mouse-doctor razer` remains a read-only exact-interface diagnostic.
Its write flags preserve the failed acceptance probes for reproducibility, but
must not be repeated without a new reason, a macOS heads-up, and Ethan's exact
approval. Windows has now supplied the reference result: Dynamic Lighting with
Synapse stopped changed only its own UI and had no physical effect, while
Synapse 4 Quick Effects -> Static physically changed the same mouse to green
and red. A Windows-configured effect is still separate from live per-mode macOS
colour and is not assumed to persist onboard.

**The exact Razer vendor route is live and physically accepted.** Agentic Mouse
uses the acknowledged `NOSTORE` custom-frame path for PID `008d`, returns to
the explicitly calibrated cool idle-white output `(124,129,130)` outside modes,
and keeps mode/alert
colours independent. The remaining gate is only Ethan's final side-by-side hue
and brightness judgment against the Corsair.

**The accepted live Modes entry is physical cell 12.** That is Corsair printed
12 and Razer printed 10. Universal physical cell 10 (Corsair printed 10 /
Razer printed 12) exits the menu and every child mode; outside modes one press
toggles that source mouse's own Default legend. Shared physical cell 11 owns
Switch App. Physical cell 12 opens Utility immediately.
Physical cell 3 starts or cancels Screenshot and rapid-double-pastes its copied image
outside modes; active-mode legends remain visible until cell 10 exits the mode.
There is no idle or absolute timeout while Agentic Mouse is healthy; the short
Karabiner lease fails closed after process failure. Exact-device mode ingress
consumes the neutral transport, so no keypad digit leaks into applications.

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
Exact AX editors stay field-anchored. An editor that hides its AX focus uses the
unchanged frontmost app as the strongest available anchor, so a field change
inside that one app cannot be distinguished; an app switch still cancels. If
the final `TextOutput` recheck catches a detectable move after delivery has
begun, the coordinator exits instead: ending the transaction is safer than
continuing after a possibly partial command batch.

**Some apps expose no usable AX element.** Canvas-based editors, some Electron
builds and some Java apps report focus that fails the editable test. The mode
fails closed: the HUD says the target will not accept text, and nothing is
typed. It is a refusal, not a silent failure.

**Secure editable fields accept direct key input.** Keypad treats them like
other editable fields while never reading their value or touching the
pasteboard. Unknown or non-editable focus still fails closed.

**The event-tap fallback cannot identify the device.** If you opt into
`cgEventTap`, a matching button on any mouse looks the same. Documented in
[`ICUE-FALLBACK.md`](ICUE-FALLBACK.md).

**One mouse only.** Two matching Scimitars means the selector refuses to guess.
Pin one with `lighting.device.deviceTag`.

**Multi-tap is slow.** It is multi-tap. `s` costs four presses. It is for
"type a URL without reaching for the keyboard", not for prose.

**No T9.** Deliberately. No dictionary, no prediction, no surprises.

## iCUE limits

**iCUE must be running for Corsair RGB and the neutral Corsair transports must
remain configured.** Keypad and Modes input now arrive through exact-device
Karabiner rules, so they do not depend on Scimitar SDK macro callbacks. iCUE's
absence does not suppress the universal HUD or Razer runtime path. The menu bar
reports the Corsair/iCUE boundary separately.

**The public SDK does not document macOS support.** Corsair's current public
iCUE SDK reference lists Windows requirements. iCUE for macOS contains an SDK
library and approval UI, and this project can load its audited ABI, but that is
not enough to call the integration a supported public macOS API. Treat runtime
mode colours as experimental until Corsair documents macOS support and a
guarded physical write/release test is explicitly approved.

**Shared layer only.** iCUE renders at 127, other shared clients at 128, this
helper at 130. Another SDK client at a higher priority would win, and this
project will not escalate to exclusive lighting to fight it.

**Exclusive lighting is never requested.** Levels 1 and 3 are rejected inside
the C bridge before the SDK is called.

**Wireless sleep.** A sleeping Scimitar reports `CE_DeviceNotFound`; the
controller forgets it and re-selects on reconnect. If the mouse sleeps *during*
multi-tap mode, the mode exits.

## Scope

**Nothing is installed by the build.** `make app` writes to `build/` and stops.
When the packaged app is launched from its installed location, it registers
its signed nested runtime supervisor through `SMAppService.loginItem`. The
helper starts at login and relaunches an unexpectedly absent main process with
bounded backoff. It does not install a LaunchAgent, and menu-bar Quit unregisters
it before the app terminates.

**iCUE profiles are never edited.** The helper reads device properties and
writes shared-layer colours. It does not modify a profile, and it never touches
iCUE's database files.

**Normal-mode assignments are not managed by this helper.** iCUE owns the
Corsair neutral keypad transports, while one exact-device Karabiner base maps
them globally: hold 1 + ratcheted wheel = horizontal scroll, 2 = current
frontmost-app mode, 3 = Screenshot / rapid-double Paste, hold 4 + ratcheted wheel = Copy / Paste,
5 = Forward, 6 = YouTube Scrub + Wheel through the VoiceInk bridge, 7 = Enter, 8 = Back,
9 = Keys mode, 10 = Default legend outside modes / universal Exit,
11 = Switch App and 12 = Utility.
Physical cell 3 starts a native selected-area Screenshot outside modes, retains
the uniquely identified saved path without changing the clipboard, and on a
rapid double press uses a short restoring pasteboard lease to paste that exact
file into the current app. A newer clipboard write always wins over restoration.
A plain click without a drag is cancellation; only a dragged selection waits for
the saved file, with the existing 60-second bound preserved for slow destinations.
Closing the native overlay also recreates only still-active HUD panels on the
current display Spaces; an explicitly hidden legend remains hidden.
Physical cell 10 exits the active mode;
there is no separate in-mode legend toggle. Wheel
click also stays a
neutral middle-click source and becomes Play/Pause in Karabiner. Every visible
DPI stage is 2,750. The separate DPI Toggle control emits iCUE's named F19
neutral transport and exact-device Karabiner triggers VoiceInk++ on release.
The helper prints this table (`agentic-mouse-doctor mapping`) so it can be
checked, but it never writes either live configuration.

**Wheel chords require Agentic Mouse and Accessibility trust.** Karabiner can
arm a chord from an exact mouse button, but it cannot use wheel movement as a
basic manipulator input. Agentic Mouse therefore captures phase-free Quartz
wheel events only while one exact-device chord is held; Karabiner VirtualHID
may mark an ordinary ratchet as continuous, so the phase fields—not that marker
alone—separate a ratchet from a gesture. Quartz does not attach
a device identity to that event: if one mouse's chord is held and a different
ratcheted mouse is scrolled, the held chord still owns the step. Phased trackpad
scrolling is excluded, two simultaneous chords fail closed, and every
chord is cleared on lock, sleep, device loss, lease failure, or app shutdown.

**App overrides are Karabiner's business, not the helper's.** The helper suspends
all twelve buttons while multi-tap is active and releases them on exit. In VS
Code, Karabiner maps physical cell 5 to non-repeating F17 Previous Change and
cell 8 to non-repeating F13 Next Change. Top-level cell 6 remains the global
source-specific YouTube scrub action. Matching exclusions preserve Forward/Back
everywhere else without duplicating other controls. Top-level cell 2 opens the
frontmost app's mode and top-level cell 9 opens Keys. In Keys, cell 3 emits
Undo as Command-Z, cell 6 enters Keypad, and cell 9 emits Next Track; the Razer swaps the horizontal-arrow
meanings of physical cells 1 and 7 for its left-handed layout.
