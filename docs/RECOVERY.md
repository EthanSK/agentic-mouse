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

---

## Symptoms

### The side buttons are doing letters instead of their normal jobs

You are in multi-tap mode. Press side button **12**.

If that does not work, any of these also exit:

- Wait for the idle timeout (default 3 minutes).
- Menu bar → **Exit multi-tap mode**.
- Quit the app.
- Quit iCUE — losing the session forces an exit.

The mode also exits by itself if the mouse disconnects, iCUE drops, or
Accessibility permission is revoked.

### Button 12 does nothing

Entry is failing a precondition, and the reference card should say which for a
few seconds. Check:

```bash
swift run agentic-mouse-doctor icue
```

That doctor command checks the read-only prerequisites. Key-control codes `7`
and `2` appear only after an actual button-12 entry attempt in the helper.

| Reason | Fix |
|---|---|
| Accessibility not granted | System Settings → Privacy & Security → Accessibility, then **relaunch** |
| iCUE not connected | Start iCUE; enable SDK / third-party control |
| key control refused, code 7 | Key interception is disabled in iCUE settings |
| key control refused, code 2 | Another SDK client holds exclusive control — close it |
| fewer than 12 macro keys | The mouse is asleep or on a profile that hides them |
| no Scimitar selected | Check `lighting.device.modelContains` |

Entry that fails changes nothing at all — no HUD, no colour, no interception.

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

### The mouse went dark

Expected if all four Living room lights are off and `hue.offPolicy` is
`blackout` — the mouse mirrors the room going dark. To have it fall back to
iCUE's own lighting instead:

```json
"hue": { "offPolicy": "releaseLayer" }
```

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

### Hue mirroring is not following the lights

```bash
swift run agentic-mouse-doctor config
```

| Menu shows | Meaning |
|---|---|
| `not configured` | Bridge host or light ids are still `REPLACE_ME` |
| `missing application key` | The Keychain item is absent or unreadable |
| `failed(...)` | Bridge unreachable, or key rejected |
| `streaming` | Working |

Both zones clear (alpha 0) when Hue is unavailable, so the mouse falls back to
iCUE lighting rather than freezing on a stale colour.

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
security delete-generic-password \
  -s com.ethan.agentic-mouse \
  -a hue-application-key                       # forget the Hue key
```

Then remove the app bundle. To also revoke the permission: System Settings →
Privacy & Security → Accessibility → remove Agentic Mouse.

Uninstalling changes nothing about iCUE, your profiles, your DPI stages, your
Hue lights, the Logitech setup, or the VoiceInk++ macro on side button 4. The
helper never modified any of them.

---

## Verifying the helper is not the problem

Run the whole system against fakes, with no hardware involved:

```bash
make simulate
```

If that behaves correctly, the state machine, interception lifecycle and text
pipeline are sound and the problem is at the hardware or permission boundary.
