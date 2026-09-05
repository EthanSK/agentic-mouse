# Recovery

## The one-line answer

**Use the menu-bar app's Quit command for an intentional stop.** It first
unregisters the signed runtime supervisor, then terminates Agentic Mouse. An
unexpected process exit is different: the supervisor relaunches the exact
containing app in the background with bounded backoff, while a single-instance
lock prevents duplicate runtime ownership.

The supervisor pauses for five minutes after five relaunch attempts inside two
minutes, so a broken build cannot spin forever. A runtime that remains healthy
for one minute resets that history. Agentic Mouse also repairs recoverable
in-process failures without a process restart: it rebinds a missing or replaced
Karabiner command socket, retries an unavailable wheel event tap, retries a
transient unlocked-session lease write, and refreshes the device/lighting path
after either system or display wake.

Recovery is deliberately dormant while loginwindow or the screensaver owns the
session. A relaunched or waking runtime remains locked until macOS delivers
positive user input while a normal app is frontmost. It never restores the
pre-lock command lease, mode, HUD, pending text, or queued synthetic action.

Everything that controls the mice remains process-lifetime scoped. While the
runtime is absent, iCUE restores shared device access and the saved fallback
lighting. No mode, HUD, pending text, or synthetic input survives a restart.

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

Use the menu-bar Quit command. If the colour persists after Agentic Mouse and
its supervisor have stopped, it is iCUE's own lighting, not this helper's.

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
- Secure/password fields accept the same direct process-targeted keyboard input
  as other editable fields. Keypad never reads their value or touches the
  pasteboard.
- *"The focused element does not accept text"* — click into a real text field.
- *"Could not determine what has keyboard focus"* — the app exposes no usable
  Accessibility element.

### A letter vanished mid-word

*"Focus moved — pending letter discarded."* Something changed focus — an app
switch, a notification, or tabbing to another field. The pending letter is
cancelled rather than risk typing it somewhere unintended. Retype it.

### Wrong letters appear

Keypad starts with one initial capital and then returns to lowercase. Hold
buttons 1–9 for their digits. Cell 11 is Space; cell 12 is Backspace or hold
Return. If another result appears, exit with cell 10 and re-enter Keypad.

### The HUD stole focus / moved my cursor

It should be structurally impossible: the panel is a non-activating borderless
`NSPanel` that returns `false` from `canBecomeKey` and `canBecomeMain`, ignores
all mouse events, and is only ever ordered front with `orderFrontRegardless()`.
The process is an `LSUIElement` accessory and cannot become active.

If you see otherwise, that is a bug worth reporting — with the app name it
happened over.

---

## Roll back or uninstall

Keep an ordinary keyboard available. Back up the current Karabiner file before changing it, even when you already have an older installation backup.

For an app rollback, use **Quit Agentic Mouse**, restore the preserved signed bundle to `/Applications/AgenticMouse.app`, and relaunch that exact path. Restore its matching Agentic rule block if the new source changed the command contract. Never restore an old whole Karabiner file over unrelated changes made since the backup; merge only the Agentic block, preserving other rules and profiles.

For complete removal:

1. Choose **Quit Agentic Mouse** from its menu bar item. This disarms its supervisor. If the menu is unavailable, disable **Agentic Mouse Runtime Supervisor** under **System Settings → General → Login Items & Extensions** before stopping the exact process. Repeated process killing leaves an enabled supervisor trying to recover it.
2. In Karabiner's selected profile, remove only the rules whose descriptions start with `Agentic Mouse — `. This includes the locked-session sink, bases, app overrides and runtime Modes rule. Keep every unrelated rule and profile. The complete installer block must come out together: leaving the sink while deleting the app would keep custom buttons consumed.
3. Restore the mouse's desired ordinary assignments through its vendor/onboard settings, using the saved profile export where appropriate. Without the Agentic rules, neutral digit/keypad/function-key transports can reach ordinary apps. Do not reset other devices or profiles.
4. Remove `/Applications/AgenticMouse.app` and its row under **Privacy & Security → Accessibility**. Verify its supervisor is no longer enabled.
5. Keep the private config and backups until rollback is no longer needed. Optionally archive or remove only `~/.config/agentic-mouse` afterward. Removing the app alone does not delete that directory or a separately installed VS Code extension.

Uninstalling the app does not revert vendor profiles or configure external apps. Check pointer, scrolling, primary/secondary clicks, side buttons and an ordinary keyboard before considering removal complete.

---

## Verifying the helper is not the problem

Run the whole system against fakes, with no hardware involved:

```bash
make simulate
```

This checks the simulated coordinator paths. A pass helps narrow the problem;
it does not rule out native integration, permissions, timing or hardware faults.
