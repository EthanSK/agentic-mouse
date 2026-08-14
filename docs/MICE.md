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
| Button 3 | Start / cancel selected-area Screenshot outside modes; mode-specific action inside modes |
| Button 1 | Horizontal scroll left in every app |
| Button 2 | Open the current frontmost app mode |
| Button 4 | Horizontal scroll right in every app |
| Button 5 | Forward; VS Code overrides it to Previous Change through F17 |
| Button 7 | Enter; selects Keypad inside Modes |
| Button 8 | Back; VS Code overrides it to Next Change through F13 |
| Button 6 | Open Keys mode |
| Button 9 | App-specific wildcard; silent by default, VS Code single Stage + Next through F18 and rapid-double exact undo through F16 |
| Button 10 | Blank outside modes; universal Exit inside modes |
| Button 11 | Hold-open Switch App |
| Button 12 | Single press: Utility; rapid double press: persistent Default legend |
| Every DPI stage | 2,750 DPI |

Ethan physically accepted the Corsair wheel's Karabiner-owned Play/Pause
behavior on 9 August 2026 after **Modify events** was enabled for its exact
physical pointing interface. The equivalent Razer wheel remains separately
unaccepted until that mouse is reconnected and tested.

Button 9 is the fail-closed app-specific wildcard, while button 6 opens shared Keys mode.
Inside Keys, cell 6 copies, cell 3 pastes, and cell 9 owns Next Track.
Normal behavior
stays normal unless a mode is deliberately entered or the three approved VS Code
overrides apply to physical cells 5, 8, and 9.

Switch App uses Karabiner's native output lifecycle. The action sends one
self-contained Command-Tab first, then places a repeat-enabled bare left Command
last so its key-up follows the physical source release. Ethan physically
accepted this hold-open behavior on the exact Corsair and Razer rules on
10 August 2026. It needs no Agentic Mouse command receiver or Accessibility
permission.

In VS Code only, physical cell 5 emits non-repeating F17 for Better Git Previous
Change, physical cell 9 uses a bounded F18 single press for Stage + Next and F16
rapid double press for its exact undo, and physical cell 8 emits non-repeating
F13 for Next Change. Matching base
exclusions preserve Forward, Back, and a silent wildcard everywhere else; every
untouched control continues to inherit the exact-device base.

Physical cell 3 starts or cancels the selected-area Screenshot interaction:
Corsair printed 3 and mirrored Razer printed 1. Runtime pages own it only while
active: Space Left in Utility, Paste in Keys, DEF in Keypad, or Spare when
the current app page has no assignment. A rapid double press of shared physical
cell 12 (Corsair printed 12 / Razer printed 10) toggles the Default legend outside
modes, while a single press opens Utility. Canonical physical cell 11 owns Switch
App outside modes. Cell 10 remains the universal Exit inside modes (Corsair
printed 10 / Razer printed 12) and is blank outside modes.

### Musixmatch Pro continuous playback

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
The Razer's lower DPI transport `F22` additionally maps to the existing
VoiceInk++ action, while `F21` remains unchanged.

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
