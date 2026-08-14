# Recovery

## The one-line answer

**Quit Agentic Mouse.** Everything this helper does is process-lifetime
scoped. Quitting, killing, or crashing it all end the same way: iCUE observes
the SDK client disappear, restores the device to shared access, discards the
shared lighting layer, and your normal iCUE profile takes over. There is no
persisted state and nothing to undo by hand.

```bash
killall AgenticMouse
```

Nothing needs repairing after that.

### Custom buttons do nothing after unlocking

This is the intentional fail-closed session boundary until Agentic Mouse has
re-established its short unlocked lease. Wait up to three seconds and confirm
the menu-bar app is running. Do not remove the locked-session sink: without it,
the mice's neutral keypad/digit/function-key transports could leak into the
lock screen when ordinary rules are inactive.

Unlock starts a new idle runtime. A mode, legend, pending Keypad character, or
queued action that existed before lock is deliberately discarded and must be
opened again.

---

## Symptoms

### The side buttons are doing letters instead of their normal jobs

You are in Keypad mode. Press universal exit physical cell **10** — Corsair
printed 10 or Razer printed 12 — to leave the mode.

If that does not work, any of these also exit:

- Menu bar → **Exit multi-tap mode**.
- Quit the app.
- Let the short Karabiner mode lease expire after an app failure.

The mode also exits by itself if the mouse disconnects, iCUE drops, or
Accessibility permission is revoked.

### Physical cell 12 does nothing

Modes is driven by the installed exact-device Karabiner rules and Agentic
Mouse's user-command socket. It does not depend on iCUE SDK key interception.

1. Confirm Agentic Mouse is running and owns Karabiner's documented
   `user_command_receiver.sock`.
2. Confirm the selected Karabiner profile still contains both exact-device
   Agentic Mouse base rules and the Modes rule.
3. In EventViewer, bypass modifications temporarily and check the source:
   Corsair printed 12 must emit `keypad_plus` from `6940:65535`; Razer printed
   10 must emit main-row `0` from `5426:141`.
4. If every Corsair side transport is absent together, recover iCUE's virtual
   HID producer or replug the Slipstream receiver before changing rules.

Entry that fails changes no lighting, HUD, or ordinary mapping.

### The mouse is stuck on a strange colour

Quit the app. If the colour persists, it is iCUE's own lighting, not this
helper's.

To confirm the helper is not involved:

```bash
killall AgenticMouse
```

The helper writes only to a *shared* layer at priority 130 and clears it with
alpha 0 on exit. It never requests exclusive lighting control, so it cannot
prevent iCUE from painting the mouse.

The saved iCUE software fallback is deliberately dim amber. It means iCUE is
visible because Agentic Mouse's runtime layer is absent or has not recovered;
it is not a mode colour. The app's two-second exact-device recovery monitor
normally restores idle white after a Slipstream receiver replug. If it does not,
quit and relaunch Agentic Mouse, then use the preserved official `.cueprofile`
export rather than editing iCUE's private files.

### Corsair buttons work but Agentic Mouse cannot connect to the iCUE SDK

These are separate paths. iCUE's VirtualHIDKeyboard can keep the side-grid and
DPI transports working while the SDK's local server is unavailable.

Inspect the newest iCUE log for
`QLocalServer::listen: Address in use` and inspect the exact temporary
`iCUESDKv4` Unix socket with `lsof`. If an owner exists, do not move or delete
it. If no process owns the socket, send the native heads-up, cleanly stop iCUE
and Agentic Mouse, re-check that it remains unowned, and move only that exact
socket to a timestamped quarantine path. Start iCUE first, then Agentic Mouse.

Recovery requires all of these, in order:

- iCUE logs `Starting listening` without the address-in-use failure;
- Agentic Mouse completes the SDK handshake and subscription;
- the SDK enumerates the exact Scimitar before any runtime-lighting claim.

A successful handshake without device enumeration repairs the SDK transport,
but it does not prove the receiver/mouse is paired or available to runtime
lighting.

### Typing produces nothing

The reference card explains it:

- *"Accessibility permission is not granted"* — grant it, relaunch.
- *"The focused field is a secure/password field"* — by design.
- *"The focused element does not accept text"* — click into a real text field.
- *"Could not determine what has keyboard focus"* — the app exposes no usable
  Accessibility element.

### A letter vanished mid-word

*"Focus moved — pending letter discarded."* Something changed focus — an app
switch, a notification, or tabbing to another field. The pending letter is
cancelled rather than risk typing it somewhere unintended. Retype it.

### Wrong letters appear

Check the case indicator on the card. In `123` mode every key types its digit.
Hold button 10 to cycle back to `abc`.

### The HUD stole focus / moved my cursor

It should be structurally impossible: the panel is a non-activating borderless
`NSPanel` that returns `false` from `canBecomeKey` and `canBecomeMain`, ignores
all mouse events, and is only ever ordered front with `orderFrontRegardless()`.
The process is an `LSUIElement` accessory and cannot become active.

If you see otherwise, that is a bug worth reporting — with the app name it
happened over.

---

## Full reset

```bash
killall AgenticMouse                            # stop the helper
rm -rf ~/.config/agentic-mouse                  # forget the configuration
```

Then remove the app bundle. To also revoke the permission: System Settings →
Privacy & Security → Accessibility → remove Agentic Mouse.

Uninstalling changes nothing about iCUE, your profiles, your DPI stages, the
Logitech setup, or the VoiceInk++ macro on the top DPI control. The helper never
modified any of them.

---

## Verifying the helper is not the problem

Run the whole system against fakes, with no hardware involved:

```bash
make simulate
```

If that behaves correctly, the state machine, interception lifecycle and text
pipeline are sound and the problem is at the hardware or permission boundary.
