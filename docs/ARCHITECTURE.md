# Architecture

## Shape

```
                                              ┌────────────────────────┐
                                              │  LightingCoordinator   │
                                              │  ├ LightingArbiter     │
                                              │  └ Throttle + dedupe   │
                                              └───────────┬────────────┘
                                                          │ shared layer
                                                          ▼
  Scimitar ──CorsairKeyEvent──▶┌──────────────────────┐   ICUELightingController
                               │ ICUEMacroKeyTransport│        (exact device)
                               └──────────┬───────────┘
                                          │ PhysicalInputEvent
                                          ▼
                             ┌────────────────────────┐
                             │  MultiTapCoordinator   │───▶ HUDPresenting
                             │  (mode transaction)    │
                             └───────────┬────────────┘
                                         │
                    ┌────────────────────┼────────────────────┐
                    ▼                    ▼                    ▼
            MultiTapEngine      TextTargetResolving      TextOutput
            (pure)              (AX: pid + element)      (postToPid)
```

The state machines, lighting pipeline, transports, and coordinator logic in
`ScimitarKit` are injectable. Its macOS target-discovery adapters use AppKit's
`NSWorkspace`/`NSRunningApplication`; `ScimitarUI` contains the drawing and
non-activating panel implementation. The pure multi-tap engine is AppKit-free.

The shared Karabiner source/build path is deliberately independent of the app
runtime:

```text
Karabiner/actions/**/*.jsonc ─┐
                              ├─▶ Scripts/generate-karabiner.py
Karabiner/bindings/*.json ────┘        ├─▶ action-catalog.json
                                       └─▶ agentic-mouse.json
```

Action definitions contain output semantics but no `from` event. Bindings add
the exact-device source event only after a physical position is approved. The
current Corsair adapter generates twelve side-cell manipulators plus one wheel
binding from iCUE's keypad and physical-pointing namespaces. The separate Razer
adapter generates the same base shape from its onboard main-row and
physical-pointing namespaces, plus its lower-DPI VoiceInk binding. Physical
cells 5, 8, and 9 also generate exact-device VS Code overrides with matching base
exclusions; every other control inherits its ordinary action. Cell 9's ordinary
action is deliberately a silent sink until another app override is configured. Generation never installs or
enables rules as a side effect, and linted output is not physical proof. The
Razer output was installed only after the returned exact device and ordered
transport sequence were physically captured; downstream semantic behavior is
still a separate physical acceptance gate.

The physical-cell crosswalk is the semantic contract. Naming a printed Corsair
or Razer button identifies its canonical physical cell; it does not create a
device-specific action. A rapid double press of canonical cell 12 toggles that
source mouse's Default legend, while canonical cell 11 holds open Switch App.
Cell 10 is blank outside modes and remains the universal active-mode Exit. Only explicit hardware or handedness behavior,
such as the Razer Keys-mode horizontal gesture reversal, may diverge.

### Locked-session security boundary

`SessionSecurityController` starts fail closed during
`applicationWillFinishLaunching`, observes AppKit's documented workspace-session
and sleep notifications, and renews
`agentic_mouse_session_unlocked_expires_at` for three seconds once per second
only while the session is active. A failed write locks the runtime instead of
assuming that the previous value remains trustworthy.

The generator applies two independent controls:

1. every ordinary or runtime manipulator requires the unlocked lease when its
   source event matches, and every native/delayed/release output checks it again
   at emission time;
2. a highest-priority exact-device rule consumes every neutral Corsair and
   Razer side-grid, DPI, and custom wheel transport with `vk_none` whenever the
   lease is inactive.

The second control prevents a disabled command rule from exposing raw keypad,
digit, or function-key transports to the lock screen. Ordinary movement,
scrolling, and primary/secondary clicks are outside this custom transport set.
On lock or session resign, the app exits every mode, clears its per-mouse mode
variables, hides every HUD, cancels pending Keypad state, and refuses socket
commands. Unlock starts a fresh idle session; no ephemeral state is restored.

## Design decisions, and why

### The input route is raw macro keys, not synthesised mouse buttons

The audited Scimitar reports `CDPI_MacroKeyArray` = `CMKI_1 … CMKI_12`. Every
side button therefore arrives as a `CorsairKeyEvent` carrying the originating
device id.

This beats watching CGEvents on three counts:

- **Attribution.** The event names the device. A second mouse, or the Logitech,
  cannot be mistaken for the Scimitar. A CGEvent carries no device identity at
  all.
- **Independence.** The macro key fires regardless of what the iCUE profile has
  assigned to that button. A tap route can only see buttons whose assignment
  happens to produce an observable CGEvent — a button mapped to "Next Track"
  arrives as a media event and is effectively invisible.
- **Suppression.** `CorsairConfigureKeyEvent` under
  `CAL_ExclusiveKeyEventsListening` stops the normal assignment firing while
  the mode is active. That is what makes the mode *modal* rather than merely
  additive.

### Access level 2 is input-only

The SDK defines four levels:

| Level | Meaning | Used here |
|-------|---------|-----------|
| 0 `CAL_Shared` | default | yes, always, for lighting |
| 1 `CAL_ExclusiveLightingControl` | exclusive lighting | **never** |
| 2 `CAL_ExclusiveKeyEventsListening` | *exclusive key events, shared lighting* | while the mode is active |
| 3 both | exclusive everything | **never** |

Level 2 does not touch lighting — the SDK documents it as "exclusive key
events, but shared lightings". The prohibition in this project is specifically
on exclusive *lighting* control, and levels 1 and 3 are unreachable: the C
bridge rejects those raw values before the SDK is called
(`SC_ICUE_ACCESS_LEVEL_FORBIDDEN`), and the Swift enum has no case for them.

### Mode entry is a transaction

`MultiTapCoordinator.enter()` and `ICUEMacroKeyTransport.beginInterception()`
form one all-or-nothing operation:

```
preflight:  multi-tap enabled?  Accessibility granted?  iCUE connected?
            exactly one Scimitar?  all 12 macro keys reported?
            event subscription healthy?
commit:     requestControl(level 2)
            configureKeyEvent(intercepted) × 12   ← tracked individually
            engine.reset() ; hud.show() ; lighting mode colour ; tick timer
```

A failure on the *k*-th key un-configures keys 1…*k−1* in reverse order,
releases control, and throws. `configuredKeys` is the ledger that makes the
rollback exact rather than approximate.

Nothing user-visible happens before the commit point. A refused entry leaves
the mouse byte-for-byte as it was: no HUD, no colour change, no interception.

### One teardown path

`forceExit(reason:)` is the only way the mode ends, and every ending routes
through it: button 12, idle timeout, focus policy, transport failure, iCUE
session loss, device disconnect, permission revoked, quit, and `deinit`. It is
idempotent and non-throwing.

Layered underneath, so a bug in the above cannot strand anything:

- `ICUEMacroKeyTransport.deinit` rolls back interception.
- `LightingCoordinator.deinit` releases the shared layer.
- `SIGINT`/`SIGTERM` handlers run the full teardown.
- If the process is `SIGKILL`ed, iCUE observes the client vanish and restores
  shared access by itself. There is no persisted state anywhere.

**A reconnect never re-enters the mode.** When iCUE comes back the transport is
rebuilt and the lighting repainted, but the mode stays off. Being put back into
a modal state by a background event you did not initiate is exactly the kind of
surprise that makes a helper untrustworthy.

iCUE's connection callback remains the fast path, but a two-second
`ICUEDeviceRecoveryMonitor` also probes exact device presence. It emits only
real missing/recovered/replaced/lighting-availability transitions. Stable polls
do not repaint. This covers Slipstream re-plugs for which iCUE omits a callback,
without using a busy loop or treating enumeration as permission to restore a
mode.

### Buffered commit with dual anchoring

The state machine is pure: `(key, timestamp, TextTargetResolution)` in, text
edits out. It holds a `Pending` with an `anchor: TextTarget` captured at
creation.

`reconcileTarget` runs at the top of every `press`, `release` and `tick`. It is
the single choke point for the safety rule, and it emits **no** text commands in
any branch — so a cancellation can never type or delete anywhere.

Two identities are compared, because a pid alone is not enough:

- `processIdentifier` catches switching apps.
- `elementIdentity` catches moving between fields *inside* one app.

`elementIdentity` is a resolver-local monotonic token associated with the
actual focused `AXUIElement`. Repeated resolutions use `CFEqual` to recognise
that same element; a different element receives a different token even when it
has the same role or title. The resolver does not read `AXValue`, titles,
placeholders, help text, frames, or window titles to construct identity.

Commit is one `insert`. There is no rewrite loop in the default policy, so the
class of bug where a stray backspace eats a character in the wrong document
cannot occur.

### Two zones, exact LUIDs

The device exposes two controllable LEDs, and the LUIDs follow the documented
`(group << 16) | index` encoding with `CLG_Mouse == 4`:

- `0x40001` `MouseLogoLed`
- `0x40002` `MouseSideLed`

They are named constants because they are a property of the device, but every
write goes through `LightingFrame.resolve(availableLuids:)`, which emits only
the two audited LUIDs when the device actually reports them. A firmware change
that renumbers or adds zones fails closed: unknown LEDs stay under iCUE rather
than inheriting an unrelated zone colour.

### Independent runtime lighting outputs

The universal mode HUD is authoritative. Hardware lighting fans out to the
accepted Corsair and Razer adapters:

```text
mode colour ─┬─▶ LightingCoordinator ─▶ iCUE shared layer (Corsair)
             ├─▶ RazerVendorLightingController ─▶ exact USB 1532:008d
             └─▶ ModeHUDLegendItem[] ─▶ non-activating HUD
```

A missing iCUE session never suppresses the HUD. A Razer open or write failure
likewise never suppresses Corsair. `ModeLightingTargets` records which adapters accepted
the current colour so the HUD can say exactly what is live.

The old standard-HID adapter is retained only as negative diagnostic evidence:
macOS and Windows both expose a plausible LampArray, but physical tests proved
that its colour reports do not control the LEDs. The live vendor adapter is
not a second button-mapping owner. Its C shim opens only the whole exact USB
device `1532:008d`, does not open/detach/seize an input interface, and exchanges
only acknowledged 90-byte feature reports on interface zero. Swift owns the
clean packet encoding, exact transaction and command IDs, three audited zones,
`NOSTORE` invariant, response validation and Spectrum Cycling rollback.

`ModeHUDLegendItem` separates the visible button action from the original
colour-validation implementation. That internal proof supplies `Solid Red`,
`Solid Orange`, and so on; real modes can
provide navigation, editing, or submenu labels without forking the panel or
making RGB the only state signal. The shared view uses the accepted 705-point
layout — 75% of the earlier 940-point experiment — so it remains a readable
on-demand reference without wasting display space.

One `ModePickerCoordinator` per exact `MouseSource` is the authoritative layer
above individual modes. A single press of physical cell 12 (Corsair 12 / Razer 10)
opens that mouse's Utility page and expiring exact-device lease after the bounded
double-press window; a rapid double press toggles the independent Default legend. While it is alive,
all twelve transports feed one ordered press/release stream, independent of
ordinary frontmost-app conditions. Universal physical cell 10 exits any active
mode and is blank outside modes. Cell 7 selects Keypad. Top-level
cell 2 opens a live frontmost-app child that refreshes on workspace activation;
Utility cell 11 opens the separate configured-app selector and locks the chosen
target without activation. App children keep cell 12 available for real app
actions and use universal cell 10 to exit. Top-level cell 6 and Utility cell 9
open Keys mode. Within Keys, Corsair physical cells 5/4/7/1
emit Up/Down/Right/Left; the left-handed Razer swaps the horizontal meanings
of cells 1 and 7. Cell 6 emits Copy, cell 3 emits Paste, cell 9 emits Next Track,
cell 8 emits Space, cell 11 emits Backspace, and cell 12 emits Escape through non-repeating exact-device
Karabiner output. Enter remains available on top-level cell 7 and is not duplicated in Keys.
Within Keypad, cell 1 owns the complete punctuation cycle, cells 2–9 use the
classic phone letter groups with digit holds, cell 11 cycles the shift state,
and cell 12 sends Space or hold-for-Return. The HUD wraps long cycles rather
than clipping the punctuation preview.
The coordinator keeps a cycle-free navigation path per mouse, reusing an
existing ancestor rather than stacking duplicate pages. Utility assigns cell 3
to Space Left, Keypad restores its familiar DEF key, and pages without a real
cell-3 action render it as Spare. Active-mode legends remain visible until
universal cell 10 exits. The Corsair and Razer use distinct variables,
presenters, and lighting callbacks, so their HUDs and modes may coexist. Colour Proof is neither generated nor selectable;
its lighting source remains only as internal regression infrastructure.

The same `ModeHUDSnapshot` and non-activating presenter supports the persistent
ordinary Default mode legend. A rapid double press of shared physical cell 12
toggles each source's respective copy with one exact-device command and no lease or lighting
change. Each source owns an independent legend; hiding
one never retargets or closes the other. Mode entry suspends only that source's panel; exit restores it only
if it was already visible. Outside modes, cell 3 starts or cancels one native
selected-area screenshot interaction; it is not a universal in-mode legend
control. Mode HUDs and Keypad panels appear on all connected
displays, use a distinct accent per mode, keep the actual function prominent,
and show only the initiating mouse's small printed button label under each function.
Every ordinary card border repeats the current mode accent, while related action
pairs or groups share one internal fill colour. A card that enters another mode
uses a thicker border in the destination mode's own accent; selection remains
stronger still. Default mode uses white borders for ordinary actions as the
neutral baseline.

The colour-proof coordinator defaults both its idle and absolute timeouts to
zero, so the mode and HUD remain active until the entry cell explicitly exits.
The short Karabiner routing lease is still renewed every heartbeat and expires
if the helper disappears; sleep, active-device loss, lease failure, and app
shutdown still use the common teardown path.

### Injectable boundaries

| Boundary | Protocol | Fake |
|---|---|---|
| iCUE key control | `ICUEKeyControlling` | `FakeICUEKeyControl` |
| Input events | `InputTransport` | `SimulatedInputTransport` |
| Text output | `TextOutput` | `RecordingTextOutput` |
| Focus target | `TextTargetResolving` | `StubTextTargetResolver` |
| Accessibility | `AccessibilityPermissionChecking` | `StubAccessibilityPermission` |
| Lighting | `LightingController` | `RecordingLightingController` |
| HUD | `HUDPresenting` | `RecordingHUDPresenter` |
| Time | `MonotonicClock` | `ManualClock` |
| Timers | `TickScheduler` | `ManualTickScheduler` |
| Logging | `LogSink` | `RecordingLogSink` |

The fakes live in the library rather than the test bundle, so
`agentic-mouse-doctor simulate` can drive the real coordinator end to end on a
machine with no hardware at all.

### The SDK is loaded, not linked

`Sources/CICUEBridge` re-declares the small slice of the iCUE C ABI this project
uses and resolves it with `dlopen`/`dlsym`. No Corsair headers or binaries are
vendored.

Consequences, all deliberate:

- The project builds and its tests run with no SDK present.
- A missing or incompatible SDK degrades to "lighting unavailable" rather than a
  link error or a crash.
- Struct layouts are pinned by `SC_STATIC_ASSERT`s in `CICUEBridge.c`, which
  catch drift in this repository's declarations. Because no vendor header is
  compiled, those asserts cannot detect a changed vendor binary. Before
  `dlopen`, `ICUESession` therefore accepts only audited iCUE SDK framework
  versions; unknown versions and raw unversioned dylibs fail closed without
  calling the ABI.

### Redaction

`Redaction` turns device ids into stable 8-hex tags before they reach a log, the
menu bar or the doctor output. AX element titles and values are never read for
target identity. Tests assert that raw identifiers never appear in log output.

## Threading

- Input callbacks, the tick scheduler and all AppKit work are on the main queue.
- `ICUESession` marshals its C callbacks onto the main queue.
- `MultiTapEngine` has no concurrency at all — it is only ever touched from the
  main queue.
