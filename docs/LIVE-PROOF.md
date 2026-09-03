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
| Reference map | wheel Play/Pause, top DPI VoiceInk++, hold 1 + wheel for horizontal scroll, hold 4 + wheel for Copy/Paste, 2 current frontmost-app mode, 3 Screenshot/cancel plus rapid-double Paste, 5/8 Forward/Back outside VS Code and Previous/Next Change inside it, hold 6 + wheel for YouTube ±5 sec per ratchet through the VoiceInk bridge, 7 Enter, 9 Keys mode, 10 Default legend outside modes or active-mode Exit, 11 Switch App and 12 Utility |

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
   horizontal scrolling one native line per ratchet while ordinary wheel and
   trackpad scrolling still pass through. Also prove each mouse's default wheel click is
   captured only from its exact pointing device and emits Play/Pause. The
   Corsair wheel passed Ethan's physical Play/Pause acceptance on 9 August
   2026; the Razer wheel remains unaccepted until reconnected and tested.
4. Confirm the semantic map with `swift run agentic-mouse-doctor mapping`.
5. Run `swift run agentic-mouse-doctor icue` to inspect the SDK connection,
   selected mouse, macro keys and LED LUIDs. This is read-only.
6. Hold top-level physical cell 1 and ratchet the wheel once each way to prove
   Space left/right without entering a mode. Enter Utility with cell 12, then
   hold cells 1/2 and ratchet once each way to prove Brightness up/down and Zoom
   in/out. Hold cell 3 and verify one wheel-up ratchet copies while one
   wheel-down ratchet pastes. Hold cell 6 and verify one wheel-up ratchet sends
   Magnet Left while one wheel-down ratchet sends Magnet Right. Hold cell 4 and
   verify one wheel-up ratchet enters Mission Control while one wheel-down
   ratchet shows the desktop. Hold cell 5 and verify wheel-up is consumed with
   no action, then one wheel-down ratchet opens native App Exposé. Extra
   ratchets during that hold must not close it; release before another action.
   Verify cell 7 types the
   configured device-local Keychain password without using the clipboard,
   and every wheel action stays one step per ratchet. Press Utility cell 12 to
   open Extra Utilities, confirm its source-aware label is Corsair 12 / Razer
   10, then press Extra Utilities cell 1 (Corsair 1 / Razer 3) and confirm Stay
   performs exactly one manual `Agentic Mouse Layout v1` restore through the
   reserved Control-Option-Shift-Command-A shortcut.
   With a harmless disposable app frontmost, press Extra Utilities cell 9 and
   confirm one ordinary save-aware Quit request. Keep holding or repeat the raw
   press before leaving the page and confirm no second request occurs. Confirm
   Agentic Mouse and its supervisor are never targets.
   Confirm no window restore occurs merely by entering the page, then use cell
   10 to exit directly to the ordinary top-level map. With a harmless command
   running, enter the frontmost VS Code,
   Terminal, and iTerm app-specific page in turn and press child cell 12;
   confirm exactly one Ctrl-C interrupt stops the running command. Under
   `DVORAK - QWERTY CMD`, require an actual interrupt/`^C`, not the blank new
   prompt caused by the superseded physical-QWERTY-C / Control-J route.
   Then enter Keys with cell 9, select Keypad with cell 6, and prove
   every side transport is intercepted only while that mouse's mode is active.
   Cell 1 must expose its full punctuation cycle, cell 3 must cycle `DEF`, cell
   11 must type Space, cell 12 must tap Backspace and hold Return, and universal
   physical cell 10 must exit on both Corsair and Razer
   without a separate in-mode legend toggle. Confirm Utility cards have no
   explanatory subtitle beneath any action title.
7. Enter Keys with physical cell 9 and prove Keypad entry on physical cell 6,
   Undo on cell 3, Space on cell 8, hold cell 9 and prove one Next Track per wheel-up ratchet plus one Previous Track per wheel-down ratchet, one Backspace on cell 11, and
   no action or key leakage from spare cells 2 and 12,
   with no repeat or raw transport leakage. Prove Corsair cells 5/4/7/1 are
   Up/Down/Right/Left while the Razer mirrors the horizontal gestures, then use
   physical cell 10 to exit and restore the ordinary map.
8. Put the caret into two separate text fields in one app; start a pending
   character, change fields, and prove that no text is delivered.
9. With explicit consent, use
   `swift run agentic-mouse-doctor icue -- --probe-lighting --i-mean-it` to
   briefly write then release the shared lighting layer.
10. Open the Default legend with a known frontmost app. Confirm only that app's
    mode card shows its real installed icon enlarged and lightly blurred to fill
    the slot while remaining recognisable. Enter the app mode and confirm the
    panel perimeter and physical mouse use a strong representative colour from
    that icon without changing the semantic action-family fills. Repeat with a
    strongly different app icon and one neutral icon. The outer panel artwork
    and every other card must remain unchanged. Enter
    Utility → Choose app and confirm each named app slot shows its own icon,
    while selector spares and the selected child app page use no app artwork.
11. Open automatic app mode with Spotify, Notion, OBS, Claude, and one ordinary
    browser frontmost. Confirm each shows its named starter grid and exercise
    one harmless command per app (for example Spotify Search, Notion New Tab,
    OBS Undo, Claude Search, and browser Find). For Claude, also verify its
    dedicated Settings, Voice Mode, New Chat, Mute/Unmute Voice Mic, Enter,
    Reload, Sidebar, Previous Tab, and Next Tab cards; exact UI controls must
    fail closed rather than press an ambiguous match. Open two of those same targets
    through Utility → Choose app and confirm the card titles and actions are
    byte-for-byte identical to the automatic journey. Verify both matching
    entry cell 2 and universal cell 10 exit each app child, while cell 2 still
    chooses Terminal on the parent selector, and that no action fires while the
    session is locked. In both Spotify journeys, hold physical cell 7 (Corsair
    7 / Razer 9): one wheel-up ratchet must raise Spotify volume and one
    wheel-down ratchet must lower it without bringing Spotify frontmost. Release
    the button and confirm ordinary scrolling resumes; cell 8 must remain Spare.
12. Bring iPhone Mirroring frontmost, enter automatic app mode, and confirm the
    page is named `iPhone Mirroring mode`. Press physical cell 1 once (Corsair
    1 / Razer 3) and confirm macOS Notification Center toggles with mirrored
    iPhone alerts. Confirm physical cells 2 and 10 still exit the child and that
    cell 1 does nothing when iPhone Mirroring is no longer frontmost or the Mac
    is locked.

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
