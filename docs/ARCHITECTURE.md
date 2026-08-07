# Architecture

## Shape

```
                    ┌──────────────────────────┐
  Hue bridge ──SSE──▶│  HueRoomObserver (actor) │──frame──┐
   (read-only)       └──────────────────────────┘         │
                                                          ▼
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

The state machines, Hue/lighting pipeline, transports, and coordinator logic in
`ScimitarKit` are injectable. Its macOS target-discovery adapters use AppKit's
`NSWorkspace`/`NSRunningApplication`; `ScimitarUI` contains the drawing and
non-activating panel implementation. The pure multi-tap engine is AppKit-free.

## Shared Karabiner source/build layer

`Karabiner/actions/` contains one JSONC source file per named semantic action.
`Karabiner/bindings/bindings.json` is the separate physical adapter layer: it
connects an observed source transport and exact device identity to an action
name. `Scripts/generate-karabiner.py` validates both layers and deterministically
produces the action catalog and installable complex-modification JSON under
`Karabiner/generated/`.

This split keeps physical numbering and vendor transports out of the action
definitions. iCUE still owns Corsair hardware settings and neutral transports;
Karabiner owns approved device-scoped live semantics; Agentic Mouse owns the
reviewable sources and build. An empty binding layer intentionally generates
zero live rules.

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

- `0x40001` `MouseLogoLed` ← desk lusters
- `0x40002` `MouseSideLed` ← candle + sofa

They are named constants because they are a property of the device, but every
write goes through `LightingFrame.resolve(availableLuids:)`, which emits only
the two audited LUIDs when the device actually reports them. A firmware change
that renumbers or adds zones fails closed: unknown LEDs stay under iCUE rather
than inheriting an unrelated zone colour.

Cluster mixing is done in linear light (`gammaDecode` → weighted mean →
`gammaEncode`) and weighted by each lamp's effective brightness. Gamma-space
averaging would turn red + green into dark olive; linear averaging gives the
yellow a real room shows.

### Injectable boundaries

| Boundary | Protocol | Fake |
|---|---|---|
| iCUE key control | `ICUEKeyControlling` | `FakeICUEKeyControl` |
| Input events | `InputTransport` | `SimulatedInputTransport` |
| Hue network | `HueReadOnlyTransport` | `StubHueTransport` |
| Text output | `TextOutput` | `RecordingTextOutput` |
| Focus target | `TextTargetResolving` | `StubTextTargetResolver` |
| Accessibility | `AccessibilityPermissionChecking` | `StubAccessibilityPermission` |
| Lighting | `LightingController` | `RecordingLightingController` |
| HUD | `HUDPresenting` | `RecordingHUDPresenter` |
| Time | `MonotonicClock` | `ManualClock` |
| Timers | `TickScheduler` | `ManualTickScheduler` |
| Logging | `LogSink` | `RecordingLogSink` |
| Secrets | `SecretResolving` | `StaticSecretResolver` |

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

`Redaction` turns device ids, hosts and secrets into stable 8-hex tags before
they reach a log, the menu bar or the doctor output. AX element titles and
values are never read for target identity. Tests assert
that raw identifiers never appear in log output, and that the redacted config
dump contains neither the bridge address, the application key, nor a light id.

## Threading

- Input callbacks, the tick scheduler and all AppKit work are on the main queue.
- `ICUESession` marshals its C callbacks onto the main queue.
- `HueRoomObserver` is an actor; its frame handler hops back to the main queue
  before touching the lighting coordinator.
- `MultiTapEngine` has no concurrency at all — it is only ever touched from the
  main queue.
