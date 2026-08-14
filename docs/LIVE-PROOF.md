# Verification boundary

Agentic Mouse deliberately separates **implemented**, **automatically tested**
and **physically proven** behaviour. A green Swift test suite does not prove a
vendor SDK, an Accessibility grant or a wireless receiver.

## What is covered without hardware

Run this on any supported Mac:

```bash
make check
make simulate
```

The hardware-free suite covers the state machines and their safety boundaries:

| Area | Examples |
|---|---|
| Multi-tap | cycling, timeout, digits, punctuation, case and Exit |
| Focus safety | app change or text-field change drops pending text |
| iCUE key lifecycle | claim, rollback, session loss, device loss and cleanup |
| Lighting lifecycle | multi-tap mode indicator; normal iCUE lighting returns on release |
| Device selection | no match or several matches fails closed |
| Privacy | device identifiers are redacted |
| Reference map | wheel Play/Pause, top DPI VoiceInk++, 1/4 horizontal scroll, 2 Switch App, 3 Screenshot/cancel, 5/8 Forward/Back outside VS Code and Previous/Next Change inside it, 6 silent app wildcard or VS Code Stage + Next, 7 Enter, 9 Keys mode with Copy on 6, Paste on 3 and Next Track on 9, 10 Legend toggle or active-mode Exit, 11 app-specific mode and 12 Utility modes |

## What needs a real Corsair mouse

Use a dedicated iCUE profile, and work through these visibly. Do not edit an
iCUE database or profile file behind the app's back.

1. Connect the Scimitar and open iCUE.
2. In Karabiner-EventViewer, prove side 1–9 emit `keypad_1`–`keypad_9`, side 10
   emits `keypad_0`, side 11 emits `keypad_hyphen`, and side 12 emits
   `keypad_plus`, all from vendor `6940`, product `65535`. Record clean down/up,
   a two-second hold and rapid presses; reject any pointing-button leakage.
3. Install the generated Corsair rules only after that capture, then prove that
   a physical keyboard or numpad cannot trigger them. Test the global behavior
   in both an ordinary app and VS Code, including App Switcher release and held
   horizontal scrolling. Also prove each mouse's default wheel click is
   captured only from its exact pointing device and emits Play/Pause. The
   Corsair wheel passed Ethan's physical Play/Pause acceptance on 9 August
   2026; the Razer wheel remains unaccepted until reconnected and tested.
4. Confirm the semantic map with `swift run agentic-mouse-doctor mapping`.
5. Run `swift run agentic-mouse-doctor icue` to inspect the SDK connection,
   selected mouse, macro keys and LED LUIDs. This is read-only.
6. Enter Utility with physical cell 12, select Keypad with cell 7, and prove
   every side transport is intercepted only while that mouse's mode is active.
   Cell 1 must expose its full punctuation cycle, cell 3 must cycle `DEF`, cell
   11 must advance `abc → Abc → ABC → 123 → abc`, cell 12 must type Space (hold
   Return), and universal physical cell 10 must exit on both Corsair and Razer
   without a separate in-mode legend toggle. Confirm Utility cards have no
   explanatory subtitle beneath their action title.
7. Enter Keys with physical cell 9 and prove Copy on physical cell 6, Paste on
   cell 3, Space on cell 8, Next Track on cell 9, and one Backspace on cell 11,
   with no repeat or raw transport leakage. Prove Corsair cells 5/4/7/1 are
   Up/Down/Right/Left while the Razer mirrors the horizontal gestures, then use
   physical cell 10 to exit and restore the ordinary map.
8. Put the caret into two separate text fields in one app; start a pending
   character, change fields, and prove that no text is delivered.
9. With explicit consent, use
   `swift run agentic-mouse-doctor icue -- --probe-lighting --i-mean-it` to
   briefly write then release the shared lighting layer.

The helper must never leave a device in exclusive input control after Exit,
disconnect, sleep, iCUE loss or quit.

## Evidence to include in a contribution

- macOS version and hardware model;
- the relevant iCUE or Karabiner screen, with serials and credentials hidden;
- the exact command run and its redacted output;
- what was observed physically; and
- what was *not* tested.

That makes the public map trustworthy without exposing a home network or a
personal device profile.
