# Musixmatch Pro Chrome extension plan

This is the preferred design for a Corsair control that toggles whole-song
playback in Musixmatch Pro without making a mouse button send `Tab` across all
of Chrome. The repository contains a deliberately inert extension scaffold at
`extensions/musixmatch-playback`; it is not a claim that the extension or live
mouse assignment is already installed.

## Scope and permissions

- Use a small unpacked Manifest V3 extension.
- Match only `https://pro.musixmatch.com/*`.
- Request no other host pattern and no broad Chrome permission.
- Load no content script, listener, or shortcut handler on any other origin.
- Keep the dedicated Chrome web-app route only as a fallback if this boundary
  cannot be proven in the personal Chrome session.

## Input route

1. Audit every relevant iCUE profile and confirm one side button has no normal,
   VS Code, multi-tap, or other application responsibility.
2. Treat button 2 as a proposal only. Do not assign it merely because one iCUE
   screen looked empty.
3. Record a unique candidate key or chord in iCUE, verify the saved assignment
   visibly, and prove its exact Corsair-device event in Karabiner-EventViewer.
4. Reject any transport that collides with an existing keyboard, Karabiner,
   Codex, VS Code, media, browser, or accessibility action.
5. Leave the extension disabled until that proven transport is recorded in its
   configuration and tested from the physical mouse.

## Page behaviour

The content script must listen for the exact proven transport and require a
trusted, non-repeating key press. On a match it must locate one unambiguous,
visible, enabled whole-song Play/Pause control by a live-verified semantic
identifier such as its accessible role/name or a stable application-owned test
identifier, then activate that real control directly.

Do not dispatch a synthetic `Tab` keyboard event. Do not select a control by
screen coordinates, hashed CSS class, or generic text that could also mean
Play Current Line. If the control is absent, hidden, disabled, or ambiguous,
do nothing and surface a diagnostic that contains no lyric or account data.

## Proof before installation

1. Inspect the logged-in Musixmatch page and record the real whole-song
   Play/Pause semantic target. Do not guess it from the documented `Tab`
   shortcut.
2. Unit-test exact-origin matching, transport matching, trusted-event gating,
   ambiguous-target refusal, and direct activation of one valid target.
3. Confirm the manifest contains only the Musixmatch Pro match pattern.
4. Load the unpacked extension visibly in Ethan's personal Chrome only after
   the target and transport are proven.
5. Start whole-song playback, cross at least one lyric-line boundary, press the
   physical mouse control to pause and resume, and confirm playback continues
   beyond the line where `Enter` preview would stop.
6. Open an unrelated Chrome tab, press the same mouse button, and prove that it
   neither inserts a tab nor triggers any page or browser action.

## Current boundary

The Musixmatch session has been verified as an ordinary personal-Chrome tab,
not a dedicated app. The checked-in extension is disabled with no transport or
target. Button 2 is not yet proven free, no transport is yet EventViewer-proven,
and the live semantic control has not yet been inspected. Therefore no
extension, iCUE assignment, or hardware setting should be made live yet.
