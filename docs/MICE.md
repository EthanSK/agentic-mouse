# Scimitar mapping and ownership

Agentic Mouse adds optional runtime features without becoming a second device
profile editor. Keep each capability with the layer that can actually own it.

## Corsair Scimitar Elite Wireless SE

Use iCUE for hardware settings, lighting, profiles and the neutral source
transport on each side cell. Karabiner owns the exact-device semantic actions;
the Agentic Mouse app separately owns the accepted runtime modes, legends and
temporary lighting, but it does not write iCUE settings.

| Control | Assignment |
|---|---|
| Wheel press | Default middle-click source → exact-device Karabiner Play / Pause |
| Top DPI button | iCUE F19 neutral transport → exact-device Karabiner VoiceInk++ on release; all DPI stages remain 2,750 |
| Button 3 | Screenshot outside modes; rapid double-press pastes its last saved result; mode-specific action inside modes |
| Button 1 | Hold + wheel for at most one macOS Space; first sign wins until release |
| Button 2 | Open the current frontmost app mode |
| Button 4 | Hold + wheel for Copy / Paste; VS Code uses it for Stage + Previous while button 5 is held or for one second after release |
| Button 5 | Forward; VS Code overrides it to Previous Change through F17 and arms button 4's Stage + Previous gesture |
| Button 7 | Enter |
| Button 8 | Back; VS Code overrides it to Next Change through F13 |
| Button 6 | Click for YouTube −5 sec; hold 350 ms for temporary 2× speed; hold + wheel for up +5 sec, down −5 sec |
| Button 9 | Open Keys mode |
| Button 10 | Toggle this mouse's Default legend; universal Exit inside modes |
| Button 11 | Hold-open Switch App |
| Button 12 | Open Utility immediately |
| Every DPI stage | 2,750 DPI |

Ethan physically accepted the Corsair wheel's Karabiner-owned Play/Pause
behavior on 9 August 2026 after **Modify events** was enabled for its exact
physical pointing interface. The equivalent Razer wheel remains separately
unaccepted until that mouse is reconnected and tested.

Button 6 rewinds the selected YouTube target by five seconds on a short click without focusing Chrome. Holding for 350 ms requests 2× speed; release restores the exact prior speed without seeking. Any wheel input cancels the speed boost and keeps the existing scrub gesture. Holding button 5 inhibits speed so the volume wheel retains priority. Long holds never add a rewind on release. Button 2 opens the current
frontmost app's mode, and button 9 opens shared Keys mode.
Inside Keys, cell 3 sends Undo, cell 6 enters Keypad, and holding cell 9 maps wheel up/down to Next/Previous Track.
Normal behavior
stays normal unless a mode is deliberately entered or the two approved VS Code
overrides apply to physical cells 5 and 8.

Inside Chrome mode, cell 8 opens a website submenu for YouTube, X, Facebook, Ethan's GitHub, LinkedIn, Gemini, and Grok; the chosen site opens directly beside the active Chrome tab.

Switch App uses Karabiner's native output lifecycle. The action sends one
self-contained Command-Tab first, then places a repeat-enabled bare left Command
last so its key-up follows the physical source release. Ethan physically
accepted this hold-open behavior on the exact Corsair and Razer rules on
10 August 2026. It needs no Agentic Mouse command receiver or Accessibility
permission.

In VS Code only, top-level physical cell 5 emits source-tagged F17 for Better Git
Previous Change on release, and physical cell 8 emits source-tagged F13 Next Change on release.
While same-source cell 5 is held, pressing physical cell 4 emits F19 Stage + Previous
instead of arming Copy / Paste and suppresses the pending Previous action. For one second after cell 5
releases, one same-source cell-4 press stages the file captured before Previous instead of Copy / Paste.
While same-source cell 8 is held, pressing physical cell 7 emits F18 Stage + Next
instead of Enter and suppresses the pending Next action. For one second after cell 8
releases, one same-source cell-7 press stages the file captured before Next instead of Enter. Top-level navigation has
no double-click delay. Physical cell 6 remains YouTube Scrub + Wheel. Inside the VS Code child page, cell 9 sends
F18 Stage + Next on a single press or F16 exact Undo on a rapid double. Hold
cell 6 and ratchet down for cursor-history Back or up for Forward; delivery uses
the current VS Code keybindings without changing them. Cells 5 and 8 retain
their 300 ms navigation gestures only inside that explicitly entered child. Cell 1 closes
the current editor tab with Command-W, cell 7 opens the Command Palette with
Command-Shift-P, and cell 11 sends F12 for Go to Definition. The child does not duplicate the
Default Back/Forward pair. Matching base
exclusions preserve Forward and Back everywhere else, while Copy / Paste remains available whenever its Stage + Previous window is inactive; every
untouched control continues to inherit the exact-device base.

The captured-origin routes use Control-Option-Command with F13/F17 navigation
and F18/F19 late staging for Corsair, plus Shift for Razer. Better Git remembers
the source file before moving and stages it directly. If navigation already
opened another file, it leaves that destination selected; otherwise it retains
normal Stage + Next/Previous. Held chords keep ordinary F18/F19 and never arm
another late stage on release. Load the matching Better Git release before
installing these generated rules; old Better Git versions do not handle them.

Agentic Mouse and Karabiner emit only the neutral F16 transport. Better Git
v1.2.53+ resolves it against the latest exact observed Git-index transition, so
the same Undo works after staging through Better Git, VS Code's keyboard or
Source Control UI, another mouse binding, or `git add`. Better Git requires the
saved `HEAD` and after-index tree to match before restoring the before-index
tree; the working tree is never changed.

Physical cell 3 starts or cancels the native selected-area Screenshot interaction,
remembers its exact saved path without changing the clipboard, and rapid-double-pastes
that saved image through a short restoring pasteboard lease:
Corsair printed 3 and mirrored Razer printed 1. A plain click without a drag
cancels the crosshair; a real dragged selection keeps the existing bounded wait
for its saved file. Runtime pages own it only while active: Spaces in Utility,
DEF in Keypad, or Spare when
the current app page has no assignment. One press of shared physical cell 10
(Corsair printed 10 / Razer printed 12) toggles the Default legend outside modes
and exits an active mode. Canonical physical cell 11 owns Switch App outside
modes. Cell 12 (Corsair printed 12 / Razer printed 10) opens Utility immediately.

### Proposed only — Musixmatch Pro continuous playback is not implemented

Musixmatch Pro 3.9.0 uses `Tab` for whole-song Play/Pause; `Enter` previews only
the current line and therefore stops at its boundary. On the currently inspected
Mac, Musixmatch Pro is an ordinary tab in Google Chrome rather than a dedicated
macOS app. iCUE must not link a `Tab` assignment to Google Chrome, because that
would affect unrelated Chrome pages.

The preferred route is a tiny local Chrome extension whose only page match is
`https://pro.musixmatch.com/*`. A genuinely free Corsair button will emit a
unique transport key or chord that is first proven in Karabiner-EventViewer.
The extension will accept only that trusted press and directly activate the
real whole-song Play/Pause control on Musixmatch Pro; it will not synthesize
`Tab` and it will not run on unrelated Chrome pages.

Any currently unassigned button is only a proposal. Although a control may look unassigned
in the inspected iCUE view, it is not considered free until every relevant
profile and its real EventViewer output have been checked. No Musixmatch mouse
assignment is live until the free button, transport, exact semantic control,
across-line playback, and unrelated-tab no-op have all been physically proven.
A dedicated Chrome web app remains the fallback only if the extension cannot
prove this exact-origin, fail-closed behaviour. See
[the Musixmatch extension plan](MUSIXMATCH-EXTENSION.md).

## Shared semantic source

The named action definitions now live under [`Karabiner/actions`](../Karabiner/actions),
one commented file per behavior. The generator combines them with the separate
physical adapter file because Karabiner cannot import action fragments. The
approved Corsair adapter maps side 1–9 to `keypad_1`–`keypad_9`, side 10 to
`keypad_0`, side 11 to `keypad_hyphen`, and side 12 to `keypad_plus`, all scoped
to the exact iCUE VirtualHIDKeyboard identity. The generated Razer adapter uses
the onboard main-row `1–9`, `0`, `hyphen`, and `equal_sign` transports from
exact device `1532:008d`, with meanings matched by physical cell rather than
printed number. Generated source is never installed automatically. The Corsair
adapter is live after raw EventViewer proof but still needs full semantic
acceptance. The Razer adapter is also live after the exact device was present
and the returned mouse physically produced F21/F22 plus its ordered main-row
side-grid namespace; its global semantics still need acceptance.
Both Razer DPI transports map to the existing VoiceInk++ action on release:
upper `F21` and lower `F22`. Their output is identical. VoiceInk++ discards only
a second complete Primary chord arriving within 90 ms, before its gesture
classifier; deliberate double and triple gestures remain available.

## Ownership rule

1. **iCUE owns the Scimitar hardware layer:** DPI, software profiles, device
   memory, supported lighting and neutral source transports.
2. **The Naga onboard profile owns its hardware transports.**
3. **Karabiner owns enabled exact-device semantic mappings.** It cannot
   configure either sensor, firmware profile or lighting layer.
4. **Agentic Mouse owns the semantic source/build tree and its accepted runtime
   features:** currently Modes, Keypad, App-specific Codex controls, reference
   legends and temporary runtime lighting. It never
   silently installs the generated Karabiner output or writes a vendor profile.

Before changing the Scimitar, inspect the saved iCUE assignment and any
downstream rule separately. Verify the physical button and state plainly which
layer owns the behavior.
