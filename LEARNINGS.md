# Learnings

## 2026-08-14 — Project Keys by source and bind only real Codex commands

- Canonical physical cells are the transport vocabulary, but a left-handed mouse can need a source-specific presentation meaning. Keep Corsair cells 1/7 as Left/Right and project the Razer cells 1/7 as Right/Left so the physical horizontal gestures mirror correctly; pin both the generated output and the source-specific HUD labels without renumbering either device.
- Keys is a compact native-action page, not a duplicate of the Default map. Keep Enter on top-level cell 7; use Keys cell 6 for Command-C Copy, cell 3 for Command-V Paste, cell 9 for Next Track, cell 8 for Space, and cell 11 for Backspace. Keep every generated event exact-device, non-repeating, and gated by the unlocked-session lease.
- Inspect the running Codex build's command registry before assigning a Codex card. `openSideChat` opens the current task as a side task, while “open this queued message in side chat” currently exists only as a queued-row menu action and has no registered configurable command. Never bind the former as a false substitute for the latter; keep the requested action outstanding until Codex exposes a command or shortcut.
- Use command truth in visible copy. Codex registers `composer.startVoiceMode`, so the mouse card is `Start voice mode`; do not call it a toggle or imply that the same command stops an active voice session. `Start new voice chat` is a two-step action: create an empty task, wait for its composer to mount, then send that same built-in voice command.
- A CSS mirror used for left-handed device geometry also mirrors descendant text. Keep the Razer shell mirrored, but cancel that transform on the explicitly ordered thumb grid so printed numbers and action labels stay readable; the source-specific `DISPLAY_ORDER` remains the semantic authority.

## 2026-08-14 — Keep app wildcards silent and move rare media into Keys

- A top-level app-specific wildcard must fail closed when the frontmost app has no configured meaning. Keep one exact-device base manipulator that consumes the neutral transport under the matching application exclusion, then add only narrow application overrides. Do not let the Corsair keypad or Razer main-row source key leak as text.
- Physical cell 6 is now the wildcard on both mice: Corsair printed 6 / Razer printed 4. VS Code alone emits one non-repeating F18 Stage + Next action; every other app receives no output until its own explicit override exists.
- Rare Next Track moved to Keys physical cell 9, where the generated exact-device route emits one non-repeating `scan_next_track` consumer event and Agentic Mouse updates only the HUD/lighting state. Screenshot copy deliberately reads `Screenshot` while idle and `Cancel screenshot` only while the owned capture is running.

## 2026-08-14 — Give every HUD card an internal horizontal inset

- A flexible four-column card can still let a long two-line action title touch its coloured perimeter when the content stack has only vertical padding. Outer panel padding, inter-card spacing, and `lineLimit(2)` do not create an internal text inset.
- Apply the shared 12-point horizontal content inset before the card's flexible-width frame in both the reusable mode legend and Keypad HUD. This preserves equal outer card widths while keeping titles, source labels, and punctuation previews clear of the border.
- Keep this spacing independent of border and fill styling. A future panel-material experiment must not remove the card inset or the accepted action colours.

## 2026-08-14 — Reject nested Liquid Glass when it suppresses action colours

- A live signed-candidate preview proved that applying native SwiftUI Liquid Glass to both the reusable panel and its twelve card surfaces suppressed the established action-family fills. The result looked like ungrouped white text floating on grey glass, so Ethan rejected it.
- Restore the accepted `.ultraThinMaterial` panel, coloured fills, saturated mode borders, and neutral white Default borders. Never trade the card colour language for glass styling.
- If the outer panel alone is revisited later, prototype it without changing card rendering and inspect a real signed HUD before installation. Do not preview it interactively on Ethan's active Mac; use the Mac mini or a non-interfering render path.

## 2026-08-13 — Keep Utility terse and preserve the classic phone keypad

- Utility mode is a glanceable control surface, not a tutorial. Show the action title and the small source-mouse button label only; remove redundant explanatory subtitles such as `Open native arrow keys`.
- The familiar phone truth is cell 1 punctuation, cells 2–9 ABC through WXYZ, and a long hold on cells 1–9 for the digit. Runtime Keypad keeps universal cell 10 Exit, uses cell 11 as a tap-to-cycle `abc → Abc → ABC → 123 → abc` control, and keeps cell 12 as Space with hold-for-Return.
- A thirteen-character punctuation cycle cannot share the same single-row treatment as a three-letter key. Wrap long cycles into a compact two-row preview while preserving per-tap highlighting, so the UI never hides valid output.

## 2026-08-13 — Name the persistent control Legend toggle

- The persistent legend's control card can only be seen while that legend is already open, so changing its copy to `Hide legend` adds no useful state information and makes Ethan remember two names for one physical control. Use the stable label `Legend toggle` in the Default map, source mapping, documentation, and future projections.
- This is a narrow exception to next-action copy. Keep Screenshot stateful as `Screenshot` / `Cancel screenshot`, because its card is visible independently of whether an owned capture process is running.

## 2026-08-13 — Group related actions and keep active-mode legends visible

- A separate fill colour for every directional or paired control makes one semantic family look like unrelated actions. Give each related family one explicit fill: Brightness Down/Up, Zoom Out/In, Space Left/Right, and all four arrow keys. Keep Enter, Space, Backspace, password paste, and other unrelated controls individually identifiable. The current mode's saturated accent remains the common card border.
- The Default mode is the neutral baseline, so use white for every Default card perimeter while preserving action-family fills inside. Do not reuse a blue runtime accent for the baseline map.

- An in-mode Show/Hide Legend card spends a scarce action cell on hiding the reference needed to use the mode. Keep active-mode legends visible until universal physical cell 10 exits; restore Keypad cell 3 to `DEF`, and render cell 3 as `Spare` on child pages that have no real action there. The persistent Default legend remains independently toggleable through physical cell 10 outside modes.

## 2026-08-13 — Name known-state toggles by their next action

- A persistent HUD that says `Show legend` while the legend is already visible describes the control's category, not what the next press will do. Replace known-state toggle copy at snapshot time: a visible legend says `Hide legend`; Default mode says `Screenshot` while idle and `Cancel screenshot` only while its owned screenshot process is running.
- Keep the state in the coordinator that owns the lifecycle and refresh every visible per-mouse snapshot when it changes. Do not bake `Show / hide` into static mode definitions or infer Pin, microphone, voice, playback, or other external-application state that Agentic Mouse cannot observe reliably.
- Active-mode legends are no longer independently hidden; universal cell 10 exits the mode and closes its HUD. The known-state naming rule remains applicable to the persistent Default legend and selected-area Screenshot.

**Status:** Superseded for the persistent legend by Ethan's stable `Legend toggle` wording above. Screenshot now uses `Screenshot` while idle and `Cancel screenshot` while active.

## 2026-08-13 — Separate mode identity from action identity in every HUD card

- A grid of independently coloured borders makes a mode legend look like twelve unrelated controls. Repeat the current mode's saturated accent on every card border so the active mode reads as one coherent state, and retain each action's accent only in its card fill.
- Express the selected action through a thicker, more opaque mode-coloured border rather than changing border hue. This preserves both the current-mode signal and each action's identity over macOS materials.
- Keys physical cell 11 is the shared native Backspace position: Corsair printed 11 / `keypad_hyphen` and Razer printed 11 / `hyphen`. Emit one non-repeating `delete_or_backspace` cycle in the exact-device Karabiner layer and use Agentic Mouse only for HUD and lighting state.

## 2026-08-13 — Bind every HUD presenter to one exact mouse source

- A source-aware mode coordinator does not guarantee source-aware presentation. Keypad used a shared HUD corner configuration, so a Corsair failure or Keypad legend could appear at the Razer's bottom-left position even though the ordinary and mode legends correctly put Corsair at bottom-right.
- Construct both the Keypad and mode HUD presenters with a fixed `MouseSource`, initialize their view models from that source, reject snapshots from the other source, and derive placement from one shared mapping: Corsair bottom-right, Razer bottom-left. This also keeps pre-entry failure banners on the invoking mouse's side.
- Test the shared source-to-corner mapping and use it for Default, Utility, Keys, Keypad, app-specific, and failure presentation. Never let mutable snapshot state or a generic configured corner decide which mouse owns a panel.

## 2026-08-13 — Repair stale Accessibility identity and keep password paste device-local

- A visible enabled Accessibility row can remain bound to an older ad-hoc build's exact CDHash even after the installed app has moved to a stable Developer ID signature. In that state TCC reports the row enabled while `AXIsProcessTrusted()` correctly returns false for the running signed app. Quit Agentic Mouse, remove the stale row completely, add the literal `/Applications/AgenticMouse.app`, then launch that exact path. Toggling the stale row, resetting all TCC grants, editing the database, or invoking `sfltool` does not repair the code-requirement mismatch safely.
- Treat every installable package as a signed identity boundary. `make install-candidate` must fail closed unless the stable Developer ID and audited iCUE SDK are available; plain `make app` is an ad-hoc development artifact and must never offer installation guidance or replace the trusted app.
- Store the optional Keys Mode password only as a device-local `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` Keychain item. Cell 2 reads it only after the unlocked-session and Accessibility gates pass, then types it directly as Unicode events. Never put the credential in source, generated Karabiner JSON, config, command arguments, the clipboard, diagnostics, or logs.

## 2026-08-13 — Transition nested mode pages as one cycle-free path

- Keypad preflight must accept its request while the source coordinator is still on Utility; the coordinator can switch to `.keypad` only after the dedicated Keypad stack accepts entry. Requiring `.keypad` before entry creates a self-refusing transition that always flashes “Keypad mode could not start.” If entry fails after Karabiner has selected the Keypad page, deactivate the mode lease instead of leaving app and page-variable state split.
- Model submenu navigation as a per-mouse path. Push a new destination, but trim back to an existing ancestor rather than creating Utility → Keys → Utility cycles. Keep the Karabiner page-variable update immediately before the matching user command so the generated rule and app coordinator change pages atomically.
- Ethan's accepted Utility positions are canonical cells 1/2 Brightness Down/Up, 3/6 Space Left/Right, 4/5 Zoom Out/In, 7 Keypad, 8 YouTube −5 sec, 9 Keys, 11 manual app selector, and 10 universal exit. Keys cell 12 returns to Utility. Utility cell 3 is therefore not a legend toggle.

## 2026-08-13 — Share cell 10 between the Default legend and active-mode exit

- Ethan's final shared-map decision keeps Switch App on physical cell 2, moves selected-area Screenshot to physical cell 3, and moves the persistent Default legend to physical cell 10. The two exact mice still crosswalk by canonical cell: Screenshot is Corsair 3 / Razer 1, while Legend or active Exit is Corsair 10 / Razer 12.
- Context, not click counting, makes cell 10 coherent. With no mode lease it sends the source-specific Default legend toggle; with that mouse's mode lease active, the higher-priority Modes rule consumes the same transport as universal Exit. If a Default legend was visible before mode entry, exit restores it and the next cell-10 press hides it naturally.
- Screenshot needs a real lifecycle to support the same-button cancel request. Start `/usr/sbin/screencapture -i -p` as one owned child process, clear ownership on normal completion or Escape, and terminate only that still-running child on the next screenshot command, lock, sleep, reload, or shutdown. Do not emulate the lifecycle with a timer, synthetic Escape, or a global process kill.

## 2026-08-13 — Separate live frontmost-app mode from manual background targeting

- Ethan needs two app-specific journeys: top-level physical cell 11 follows the current frontmost application and refreshes as focus changes, while Utility cell 11 opens a lower-priority configured-app selector whose chosen target stays locked without activation.
- Use one generic bounded `CGEvent.postToPid` shortcut dispatcher selected by bundle identifier. App-specific code supplies only the shortcut meaning: Chrome cell 1 is Command-W, while Codex uses its own commands. This avoids one executor per app without pretending that all apps interpret the same shortcut identically.
- Preserve every existing Codex keyboard shortcut. Reasoning Effort Up/Down are the narrow exception because Codex exposes configurable commands with no existing binding; add dedicated Hyper-F18/F19 bindings without replacing Pin, New Task, Voice, Submit, or the existing Hyper-F20 microphone route. Block all dispatch while the unlocked-session boundary is absent.
- Treat mode identity as a saturated visual state, not a pastel hint: distinct full-channel RGB mode accents drive temporary mouse lighting, and HUD cards use visibly stronger accent fills and borders. Keep unsupported app pages honest and leave ambiguous or conflicting button ideas in the outstanding ledger instead of assigning them by guess.

## 2026-08-13 — Emit deterministic Utility actions in the exact-device Karabiner layer

- A healthy Utility HUD does not prove the action executor can post system input. Brightness, Zoom, and Space movement all failed together when they depended on the installed app's Accessibility trust, while the exact-device ingress and mode state continued to work.
- Emit deterministic Utility outputs directly from the active exact-device Karabiner rule: brightness consumer keys, Command-Plus / Command-Minus, and Control-Left / Control-Right. Send a separate `selectNative` command so Agentic Mouse updates only the HUD and lighting; never synthesize the same action again in the app.
- Keep every native Utility output non-repeating, exclude the ordinary `select` manipulator for the same page/cell, and re-check the unlocked-session lease at output time. Keep app-side execution only for actions that genuinely require an app bridge, such as the YouTube rewind notification.

## 2026-08-13 — Treat display sleep separately from a resigned macOS user session

- `NSWorkspace.screensDidSleepNotification` is a temporary fail-closed boundary, but an ordinary display wake does not necessarily emit `sessionDidBecomeActiveNotification`. Treating both events as a real session resign can leave the three-second Agentic Mouse security lease permanently absent after wake even though the user is still logged in and the app is healthy.
- Track whether the real user session resigned. Clear the lease and runtime state on either display/system sleep or session resign; on display/system wake, restore only when no actual session-resign event occurred. A locked or switched-out session must still wait for `sessionDidBecomeActiveNotification`, so screen wake alone can never bypass authentication.
- Pin the distinction in tests: active-session screen sleep/wake restores the idle command lease, while session resign plus screen wake remains locked until the explicit active-session notification. Also verify the modern `SMAppService.mainApp` login item separately from runtime health: today macOS launched Agentic Mouse automatically, but the later missing lease made the correctly running process look inert.

## 2026-08-13 — Mouse controls must not replace ordinary Codex shortcuts

- Agentic Mouse originally added Hyper-F13 through Hyper-F16 overrides for Codex New Task, Pin/Unpin, Start Voice Mode, and Submit. That made the Codex menu advertise the mouse transport chord instead of Ethan's normal keyboard shortcut, including replacing Pin/Unpin Command-Option-P with Hyper-F14.
- Restore the pre-edit `~/.codex/keybindings.json` exactly and deliver Codex's built-in shortcuts directly to its running process: Command-N, Command-Option-P, Control-Shift-V, and Return. Keep only the pre-existing Hyper-F20 microphone binding because that command has no accepted built-in route.
- Tests must pin the real built-in key codes and modifiers. Never create a user-level Codex keybinding merely to make an Agentic Mouse card easier to dispatch; the mouse adapts to the application, not the application to the mouse.

## 2026-08-13 — Gate the complete mouse command path on an expiring unlocked-session lease

- App-side command rejection alone is not a lock-screen boundary. Exact-device Karabiner rules can still emit native keys, consumer events, mouse keys, delayed actions, or source-release actions without reaching Agentic Mouse; neutral iCUE/Razer transports can also leak through when an ordinary rule is disabled. Gate every generated manipulator on one short absolute-expiry unlocked-session variable, re-check that variable on each output event, and install a locked-only exact-device sink for every neutral side, DPI, and custom wheel transport.
- Use documented `NSWorkspace.sessionDidResignActiveNotification` / `sessionDidBecomeActiveNotification` plus sleep notifications rather than private CoreGraphics lock keys. Start observing in `applicationWillFinishLaunching`, because AppKit documents that an already-inactive launch receives the resign notification before `applicationDidFinishLaunching`. Start fail closed, renew a three-second lease every second only while active, and clear it immediately on session resign, screen sleep, shutdown, or CLI failure.
- Lockdown is destructive to ephemeral runtime state by design: exit every mode, clear per-mouse leases and page variables, hide every HUD, cancel pending Keypad text, and suppress direct user-command datagrams and delayed Codex events. Unlock may re-establish only the idle security lease and baseline lighting; it must not resurrect a prior mode, HUD, queued action, or release event.

## 2026-08-13 — Finish per-mouse mode ownership at the Keypad boundary

- Per-source `ModePickerCoordinator` and mode HUDs are not enough if Keypad still shares one `MultiTapCoordinator`, input transport, target resolver, and HUD presenter. That hidden singleton refuses a second mouse and lets disconnect/focus handling affect the wrong source. Build the complete Keypad stack per `MouseSource`, route only that source's press/release phases into it, and keep one workspace focus observer that notifies every active coordinator.
- The Keypad legend must use the runtime map, not inherit the classic phone map blindly. Physical cell 3 keeps DEF, physical cell 10 is the universal Exit, cell 11 is unused, and cell 12 is Space with hold-for-Return. Put the runtime exit key in `HUDSnapshot` so the UI highlights what the coordinator actually owns instead of the generic classic-map default.
- A per-source legend coordinator must reject a command for another source. Do not keep a cross-source retarget branch after presenters become independent; the two all-display panels may coexist and neither mouse may mutate or close the other's state.

## 2026-08-13 — Emit mode arrows in Karabiner and target configured apps directly

- Agentic Mouse synthetic arrows can fail with an Accessibility warning even when exact-device mode ingress and the HUD are healthy. Emit Keys-mode arrows directly from the generated Karabiner rule, keep each output non-repeating, and send a separate `selectNative` command only for HUD and lighting state. The installed app must not try to synthesize the same arrow again.
- A runtime page change and its Karabiner page variable must be one transition. Set the per-source page variable before the matching `send_user_command`; otherwise a selector, child, or exit press can fall through to another page or the ordinary base.
- Ethan's accepted journey uses dedicated entries but one universal exit: Utility 12, Keypad 7, App-specific 11, and Keys 9 enter their pages; active physical cell 10 exits every page. Active-mode legends remain visible until exit, app-specific children retain cell 12 for a real app action, and Keypad uses cell 3 for DEF plus cell 12 for Space/hold-Return because cell 10 is reserved for Exit.
- Keep both app-specific journeys distinct. Top-level cell 11 follows the current frontmost process; Utility cell 11 shows an explicit Codex/Chrome/VS Code selector and locks the chosen target without activation. For Codex, use its built-in process-targeted keyboard shortcuts without adding user-level overrides. Unsupported Chrome/VS Code cards remain visibly Spare until they own a tested command.

## 2026-08-13 — Split runtime ownership by mouse and fail closed before synthetic keys

- One shared mode coordinator, HUD presenter, and Karabiner lease made the two exact devices interfere: entering a Corsair mode also gated the Razer base, and a Razer legend press could retarget the Corsair HUD. Give each `MouseSource` its own coordinator, all-display presenter, lighting callback, and expiring variable. A wrong-source command must be ignored rather than changing ownership.
- A visible Accessibility toggle does not prove the running build is trusted. The enabled TCC row can still carry an old rollback build's exact CDHash; `CGEvent.post` then silently discards Arrow, Zoom, Space, and Brightness events. Every native executor must check `AXIsProcessTrusted()` before claiming success, use a `.hidSystemState` event source, and surface failure through the HUD. Install the final Developer-ID build before granting the exact `/Applications/AgenticMouse.app` so a later replacement does not invalidate the grant again.
- Physical cell 3 is Screenshot outside modes, Space Left in Utility, DEF in Keypad, and Spare on child pages without another action. It is not an in-mode legend toggle. The accepted conflicts moved YouTube rewind to cell 8 and Codex microphone mute to cell 8; universal cell 10 exits every mode and closes its HUD.
- Direct cell-9 Keys and cell-11 app-specific entry require the same short Karabiner bootstrap lease as cell-12 Utility entry. Prepend the source-specific `set_variable` before `send_user_command`, then let the app acknowledge and renew it; otherwise a rapid second press can leak through the ordinary map.
- Lighting can be source-specific without pretending each side button is an LED zone. Scimitar exposes logo plus whole thumb grid; Naga exposes wheel, logo, plus whole thumb grid. Use the mode colour on logo/wheel and the last-action accent on the grid, with a proven uniform fallback when a distinct Naga frame is rejected.

## 2026-08-13 — Keep top-level media and Keys mode distinct across every layer

- The accepted shared map uses physical cell 6 for Next Track and physical cell 9 for direct Keys-mode entry. Preserve the exact-device crosswalk: Corsair printed 6/9 and Razer printed 4/7. Do not restore the older cell-9 Next Track assignment from historical records.
- Keys mode owns one orange, all-display legend and only four bounded native arrow actions: cells 5/4/7/1 are Up/Down/Right/Left. Universal cell 10 exits it and immediately restores the ordinary map.
- Utility mode may still use cells 6/9 for Space Left/Right because those bindings are scoped to its active lease. Keep top-level and child-mode semantics explicit in generated tests instead of inferring a conflict from matching physical cells.
- A visible card is not acceptance by itself. Pin the generated exact-device ingress, coordinator route, native key down/up executor, distinct Default-legend accent, installed command receiver, all-display HUD lifecycle and both exit paths separately; reserve physical arrow acceptance for the real mice.

**Status:** Superseded on 14 August 2026. Physical cell 6 is now the fail-closed app wildcard, and Next Track moved to Keys physical cell 9 alongside the expanded Copy/Paste/Space/Backspace page.

## 2026-08-12 — Verify every HUD card against a real action boundary

- A visible mode legend is not proof that its controls work. Pin the generated exact-device ingress, coordinator routing, concrete executor, bounded down/up lifecycle, and failure presentation separately; then keep physical acceptance as its own final gate.
- For Codex 26.803.61601, the installed command registry proves New Task = Command-N, Pin/Unpin = Command-Option-P, and Toggle Voice Mode = Control-Shift-V. Steer remains Command-Return by the product interaction contract; plain Enter remains one unmodified Return cycle.
- Accessibility actions must skip matching static text and press only elements that advertise `AXPress`. Continue searching after an unpressable or failed match, fail visibly when the requested control is absent, and always attempt the matching key-up after a key-down dispatch failure.
- `CGEvent.post` can be silently discarded without Accessibility trust, so every Codex keyboard card must check trust before claiming success. Keep the real breadth-first AX search injectable and tested, not only a fake top-level button callback.

## 2026-08-12 — Keep one iCUE software profile and recover runtime lighting separately

- The official pre-cleanup exports proved that the surviving Default profile already contained all twelve modifier-free keypad transports, the named DPI `F19` transport, six 2,750-DPI stages, the dim-amber disconnected fallback, and the saved Watercolor layer. The two extra profiles contained no Scimitar neutral transports; their meaningful profile-level difference was an old Canvas/Mural selection.
- Empty or partial iCUE profiles are a transport outage risk because automatic profile changes can remove every side-grid and DPI source at once. Keep one canonical iCUE software profile and place app-specific semantics only in exact-device Karabiner rules or Agentic Mouse modes.
- The accepted idle white and mode colours are process-lifetime Agentic Mouse SDK output, not iCUE profile content. If the Scimitar falls back to dim amber after profile cleanup, diagnose the running app and SDK session instead of recreating profiles or replacing the fallback with a deceptive static white.

## 2026-08-12 — Name the complete generated rules as the runtime artifact

- The complete replacement was historically written to `agentic-mouse-color-proof.json` even after Colour Proof was retired. That name made it easy to install the ordinary base-only artifact or to assume the complete artifact still contained a live proof mode.
- Generate the ordinary review/import artifact as `agentic-mouse.json` and the complete Modes plus gated base/override replacement as `agentic-mouse-runtime.json`. The runtime artifact must contain the Modes rule and exactly one gated copy of each Corsair/Razer base and VS Code layer; it must contain no Colour Proof rule.
- Never enable both artifacts together. Back up the complete live profile, replace only the contiguous Agentic Mouse rule block from the runtime artifact, and prove every non-Agentic rule object unchanged.

## 2026-08-12 — Cell 3 owns the source-aware Default legend; cell 11 owns app-specific mode

- At this historical stage, the Default legend trigger was canonical physical cell 3: Corsair printed 3 and Razer printed 1. The earlier shared-panel retarget behavior was superseded: each source owned an independent all-display panel, and a second press from that same source hid only its panel.
- Canonical physical cell 11 directly opens app-specific mode from the ordinary layer. This historical configured-selector-only design is superseded again by the 2026-08-13 dual journey at the top of this file: top-level cell 11 follows the frontmost app, while Utility cell 11 retains manual selection. Universal cell 10 exits, and child cell 12 returns to manual app selection.
- Keep source attribution and presentation separate from the shared semantic cells. Tests must pin same-source hide, cross-source retarget, direct app-specific entry/exit, all-display presentation, and the absence of a live Colour Proof rule.

**Status:** Historical cell-3 contract only. The accepted map now uses cell 3 for Screenshot outside modes and cell 10 for the independent source-specific Default legend toggle or universal active-mode Exit, as recorded in the newer learning above.

## 2026-08-12 — Repackage from the already-audited embedded iCUE SDK path

- `make app` defaults to `/Volumes/iCUESDK/iCUESDK.framework`. On a normal machine state that volume may be absent even while the installed Agentic Mouse contains the exact audited framework, so an otherwise good package can silently omit Corsair runtime support and only print a warning.
- Before replacing the live app, require the candidate to contain `Contents/Frameworks/iCUESDK.framework`, compare its binary SHA-256 with the known-good installed framework, and verify the full app signature. A source/test pass does not prove the proprietary runtime was embedded.
- Do not use `codesign --deep` to sign the assembled app: it rewrites the independently signed vendor framework and changes the audited SDK bytes. Sign Agentic Mouse and its bundled doctor, then sign the outer app without `--deep`; use `codesign --verify --deep --strict` only as the read-only verification step.
- A Developer-ID build without the audited SDK is not a usable install candidate. Fail packaging instead of warning and continuing, and retain the real `codesign` diagnostics on stderr so a missing identity, locked keychain, or invalid nested signature is actionable.
- For an authorized local upgrade, pass the known-good framework explicitly with `ICUE_SDK_FRAMEWORK=/Applications/AgenticMouse.app/Contents/Frameworks/iCUESDK.framework make app`. Preserve the previous app first, install by recoverable move/copy, then re-check the executable hash, SDK hash, signature, process, socket ownership, and one real command/HUD path.

## 2026-08-12 — An unowned iCUE SDK socket can survive every process restart

- iCUE 5.49.34 logged `QLocalServer::listen: Address in use` for `iCUESDKv4` even though no process owned the Unix-domain socket. Restarting iCUE and Agentic Mouse could not repair that filesystem-level collision.
- First distinguish the two Corsair paths: iCUE's VirtualHIDKeyboard can still emit side-grid and DPI transports while the separate iCUE SDK client is offline. Working pointer or Karabiner actions therefore do not prove an SDK handshake.
- After a native heads-up and cleanly stopping both apps, use `lsof` to prove the exact socket has no owner. Move only that exact unowned socket to a timestamped quarantine path, then relaunch iCUE before Agentic Mouse. Never remove or move a socket that still has an owner.
- Accept SDK recovery only when iCUE logs `Starting listening`, then a successful Agentic Mouse handshake and subscription. Device enumeration is a separate gate: a handshake can succeed while the Scimitar remains unpaired or unavailable to the SDK.

## 2026-08-12 — Reset the vendor session, not only Swift flags, after terminal iCUE callbacks

- On a real Slipstream receiver loss, iCUE emitted a terminal/disconnect transition and Agentic Mouse cleared its local `isConnected` / callback state. The SDK's process-wide client nevertheless remained connected or connecting, so every later `CorsairConnect` returned `CE_InvalidOperation` (5) indefinitely, including after ordinary app relaunches.
- Terminal session handling must call the real `CorsairDisconnect` while retiring callback generations. `connect()` also gets one bounded recovery for code 5: disconnect once and retry once, then return the real error to the existing backoff loop. Never turn other SDK errors into reset loops.
- A lit mouse, working pointer, or working Karabiner action does not prove Agentic Mouse's iCUE session is healthy. Check the `com.ethan.agentic-mouse:icue` log and require a connected callback plus device enumeration before accepting Corsair runtime lighting or SDK input behavior.

---
**Date:** 2026-08-12
**Trigger:** Ethan opened the Default mode legend from both mice and found that a Razer press while the Corsair legend was visible changed the displayed source instead of dismissing the legend; the Razer grid also appeared horizontally backwards.
**Symptom:** The shared semantic cells were correct, but the left-handed Naga presentation put Switch App on the wrong side and the cross-device toggle could strand a visible legend that no button seemed to close.
**Root cause:** The presenter reused the right-handed Corsair column order for both devices, and the coordinator treated a different-source press as a request to switch the visible legend rather than as the same global toggle.
**Fix:** Keep canonical physical-cell semantics unchanged, reverse every visual row only for the Razer, and make any valid cell-10 legend press hide all visible panels regardless of source. The next press reopens the legend for the exact mouse that sent it. Apply the same source projection to the Keypad HUD.
**Guard:** Pin both source row orders and the cross-source hide/reopen sequence in tests. Presentation mirroring must never renumber bindings, and a visible global legend must have one unambiguous toggle-off action from either mouse.
**Status:** Superseded again by Ethan's final source-aware contract at the top of this file: cell 10 is the trigger or active-mode Exit, and each mouse owns an independent legend that the other mouse cannot close or retarget.
---

---
**Date:** 2026-08-12
**Trigger:** The Scimitar side grid and DPI transport disappeared together even though its lighting, Agentic Mouse, Karabiner, and the Razer adapter remained available.
**Symptom:** Corsair side buttons stopped producing their iCUE virtual-keyboard transports; relaunching iCUE showed an interprocess-mutex lock while stale helper processes remained alive.
**Root cause:** The main iCUE process had exited, but its old QML renderer and crash-handler process still owned the single-instance mutex. That left lighting and unrelated downstream processes looking healthy while the virtual input producer was gone.
**Fix:** Verify the physical receiver and downstream rules first, then terminate only the stale user-level iCUE helper set and start one clean iCUE instance. Treat `Keyboard initialized` and `Pointing initialized` from the new virtual-device service as service recovery evidence; require a physical side-button press for acceptance.
**Guard:** Do not rewrite Karabiner, profiles, or Agentic Mouse when every Corsair virtual transport disappears at once. Check the main iCUE PID, stale renderer ownership, mutex error, and virtual-device initialization before changing mappings; preserve the official profile export/restore path for any later assignment repair.
---

---
**Date:** 2026-08-12
**Trigger:** Ethan added universal Zoom In and Zoom Out controls to the shared Modes utilities.
**Symptom:** Zoom was still only an outstanding idea, and a mouse action must affect the app Ethan is already using without bringing Agentic Mouse forward.
**Root cause:** Command-Tab is app switching, not zoom. The standard macOS application shortcuts are Command-Plus and Command-Minus, delivered to the current frontmost process.
**Fix:** Bind Modes physical cells 4/5 to one non-repeating CGEvent down/up cycle for Command-Shift-Equals and Command-Minus respectively. Keep the Modes lease and HUD open, do not activate another app, and expose both actions through the same exact-device shared physical-cell map.
**Guard:** Keep universal utility shortcuts bounded and frontmost-app targeted. Pin key codes, modifiers, down/up order, both source-independent physical cells, and failure reporting in hardware-free tests.
---

---
**Date:** 2026-08-12
**Trigger:** Ethan needed the Corsair VoiceInk control restored immediately while the release-only transport investigation continued, and added background YouTube rewind to the shared Modes utilities.
**Symptom:** Razer F22 had previously produced a usable physical-release lifecycle, while the Corsair top-DPI control had no current EventViewer-visible neutral transport after the profile experiments. Separately, a mouse-side YouTube rewind must choose the right video without bringing Chrome forward.
**Root cause:** The Corsair source assignment itself had to be restored and visibly persisted in iCUE before Karabiner could observe any lifecycle. YouTube target selection already belongs to the VoiceInk YouTube Bridge, so duplicating it in Agentic Mouse would create a second targeting policy.
**Fix:** Keep Razer F22 release-only. Through the supported iCUE UI, save the Corsair top DPI control as the named neutral `F19` transport, preserve official before/after profile exports, and route both exact-device inputs through the same Karabiner `to_after_key_up` VoiceInk action. Add Modes cell 3 as `YouTube −5 sec` and post the no-payload distributed notification `com.ethansk.agenticmouse.youtube.seekBackwardFiveSeconds`; the bridge remains responsible for PiP/active/audible/recent target selection and the five-second seek.
**Guard:** Installed configuration is not physical proof. Require one EventViewer down/up capture and one VoiceInk activation from each DPI control before accepting release timing. Keep cross-app target selection in its established bridge; Agentic Mouse emits only the stable IPC request and must not focus Chrome or alter playback state itself.
---

---
**Date:** 2026-08-12
**Trigger:** Ethan consolidated rare utilities under one Modes button, kept the ordinary Button Map as a direct reference, and assigned Enter to the remaining reachable spare.
**Symptom:** The earlier design overloaded cell 12 with double-click classification and direct multi-tap entry, used cell 3 as a separate picker, and inherited ordinary VS Code conditions into active runtime input. That made the interaction hard to remember and could make cells 5/8 disappear inside a mode when VS Code was frontmost.
**Root cause:** Reference visibility, menu entry, child-mode selection, ordinary semantics, and runtime transport attribution were split across overlapping gesture classifiers instead of one hierarchy.
**Fix:** Make cell 3 a persistent one-click Default mode legend toggle; make cell 12 the universal Utility modes entry/exit; select Keypad on cell 7 and frontmost-app mode on cell 11; use cell 7 as ordinary Enter outside modes; preserve all twelve exact-device press/release phases while a mode is active; and strip frontmost-app conditions from the runtime ingress while retaining exact device conditions. Restore a previously open Default mode legend after exit, give every mode a distinct colour, show all HUDs on every display, and put one small printed button label for only the active source mouse under the prominent function text.
**Guard:** Runtime mode generation may inherit hardware identity only, never ordinary app-layer conditions. Every new mode must define a distinct colour, a same-as-entry exit, concrete live actions, an all-display HUD, and tests for source crosswalk plus prior-HUD restoration. Do not re-add Colour Proof as a live rule or slot.

**Status:** Historical hierarchy only. The accepted map now uses cell 3 for Screenshot, cell 10 for the persistent Default legend or universal active-mode Exit, and cell 12 for Utility entry; active modes do not reserve an independent legend-toggle cell.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan confirmed that Colour Proof had completed its job and asked to stop spending a live mouse slot on it.
**Symptom:** Physical cell 6 still entered a validation-only mode from both Mouse Mode pages even though that cell's accepted ordinary action is Next Track.
**Root cause:** The proof remained wired as a product mode after its input, HUD, Corsair, and Razer lighting boundaries had already been accepted.
**Fix:** Remove cell 6 from the mode-picker intercept set and both live legends, restore its ordinary Next Track pass-through on both exact mice, and retain the proven lighting controller and isolated proof rule only as internal regression infrastructure.
**Guard:** Retire validation modes from the user map after acceptance. A hidden diagnostic must not consume a physical cell, appear in a live menu, or suppress its accepted base action without fresh explicit approval.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan authorized dedicated mouse submenus but reaffirmed that the first Mouse Mode screen must remain the real current button map he uses for reference.
**Symptom:** Putting future modes directly on the top-level grid either displaced ordinary mappings or advertised unwired actions as if they were usable.
**Root cause:** The reference map and submenu navigation were treated as one page even though they have different contracts: the first describes current physical behavior; the second may route only implemented modes.
**Fix:** Preserve the source-aware current map as page one and use canonical physical cell 7 (Corsair printed 7 / Razer printed 9) to open a second `Mouse modes` page under the same expiring lease. Cell 3 returns to the map, cell 7 closes the menu, cell 6 enters the implemented Colour Proof mode, and cell 12 keeps the universal HUD gesture; every other cell retains its ordinary base action.
**Guard:** Keep one authoritative picker lease and page state. Never put planned modes into the live menu, never intercept a cell that has no overlay action, and pin the four-cell intercepted set plus back/close/selection lifecycles in generator and coordinator tests.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan asked for one screenshot button and explicitly required every Corsair placement request to receive the mirrored Razer equivalent automatically.
**Symptom:** The earlier selected-area screenshot idea remained parked against a superseded spare button, while the live shared map still suppressed canonical physical cell 10 on both mice.
**Root cause:** A semantic action was not yet separated from its old proposed position. The two mice also print different numbers on the same physical cell, so copying the printed number would place the action incorrectly.
**Fix:** Add one non-repeating `capture-selected-screen-area` action using the native Command-Shift-4 shortcut and bind canonical physical cell 10 through separate exact-device adapters: Corsair printed 10 / `keypad_0`, Razer printed 12 / `equal_sign`. Show Screenshot in the shared HUD and preserve physical cell 12 for the existing multi-tap/reference gesture.
**Guard:** Every future shared side-grid request must resolve through the verified physical crosswalk before either adapter changes. Pin both exact-device sources, the native output chord, and `repeat: false` in generator tests; never copy printed numbers or move the reserved top-left HUD cell to satisfy a geometry request.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan approved the same Better Git navigation pair on physical cells 5/8 for both exact mice while retaining ordinary Forward/Back everywhere outside VS Code.
**Symptom:** A full app-specific copy would duplicate unrelated controls, while adding only a VS Code rule would let the global base binding race the same transport. Reusing Switch App's repeat-enabled held Command would also turn a one-step navigation action into an unintended hold lifecycle.
**Root cause:** An application override needs exclusive ownership of only its matching physical transport. The semantic action can own `frontmost_application_if`, but the corresponding exact-device base binding must own the matching `frontmost_application_unless`; one-shot navigation outputs also need an explicit non-repeating event contract.
**Fix:** Keep Forward on physical cell 5 and Back on cell 8 in the two base rules, exclude only those four exact-device base bindings in VS Code, and add two-rule override layers that emit F17 Previous Change from cell 5 and F13 Next Change from cell 8 with `repeat: false`. Generate the normal and complete runtime artifacts from the same action/binding source. Replace only the contiguous Agentic Mouse block in the newest live JSON so the existing G502 and unrelated rules remain raw-byte identical.
**Guard:** Generator tests must pin both exact device identities, both source transports, both app conditions, F17/F13 direction, explicit `repeat: false`, and global Forward/Back fallback. Before live installation, establish a source-stable hash boundary, back up the complete configuration, re-read it immediately before the write, compare the installed Agentic rules with the complete generated artifact, and prove every non-Agentic rule unchanged. Generated, linted, and live-installed state still requires physical presses on both mice inside and outside VS Code.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan compared the live Corsair and Razer HUDs with the mice and found Horizontal Left/Right drawn on the top row instead of the desk-side bottom row.
**Symptom:** Source-aware labels were correct, but both device views still looked vertically flipped.
**Root cause:** The reusable mode HUD and older multi-tap HUD iterated each three-button column in ascending numeric order. On the physical Scimitar, the first number in each column is at the bottom, so canonical `1/4/7/10` is the bottom display row, not the top.
**Fix:** Define one canonical `displayRowsTopToBottom` geometry as `3/6/9/12`, `2/5/8/11`, `1/4/7/10`; use it in every reusable mode and multi-tap HUD. Keep source-specific printed-label projection separate from this physical geometry.
**Guard:** Pin top-to-bottom row order in domain and HUD tests. Never infer visual row order from ascending button numbers, and never fix a presentation inversion by changing semantic bindings.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan opened the shared map from the Razer and found the displayed button numbers mismatched the mouse in his hand.
**Symptom:** The HUD carried the exact source mouse internally but still rendered generic canonical cell numbers and static `C… · R…` crosswalk text. Because the Naga and Scimitar print opposing numbers within each physical column, the reference appeared flipped and forced Ethan to translate it mentally.
**Root cause:** Physical-cell identity and user-facing printed labels were treated as the same thing. Canonical cells are correct for shared actions and generated rules, but the HUD must project each cell through `printedSide(on:)` for the exact source that opened or last controlled it.
**Fix:** Render every legend cell with a source-aware `Corsair n` or `Razer n` label and make the reference header name that exact mouse. Remove the dual-number detail from default and Mouse Mode legends; keep action details such as Colour Proof hex values. Colour Proof already updates its source on every exact-device selection, and Mouse Mode now updates it when the reserved HUD gesture comes from the other mouse.
**Guard:** Keep canonical physical cells as the internal contract and convert only at the presentation boundary. Pin both directions of the crosswalk in tests, especially physical cell 1 as Corsair 1 / Razer 3 and physical cell 3 as Corsair 3 / Razer 1. Never duplicate or renumber the semantic map to make a HUD label look right.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan opened the new top-level mouse overlay and found a grid of speculative future modes instead of the current button map he needed for reference.
**Symptom:** Most cells were labelled Planned and were intercepted by the mode lease even though they had no implementation. The different Ready/Planned accent treatment made the HUD look partly active and partly empty, and ordinary actions stopped working while the overlay was open.
**Root cause:** The first submenu foundation confused navigation possibilities with the live physical map. A reference surface must describe what each press does now; future mode ideas belong in the outstanding ledger until they have a real trigger and action map.
**Fix:** Make the top-level Mouse Mode HUD show the actual shared mappings. Its Karabiner layer owns only physical cell 3 for close, cell 6 for the accepted Colour Proof submenu, and cell 12 for the reserved map gesture. Every other exact-device cell continues through its ordinary base action while the HUD is visible. Use action-category colours rather than Ready/Planned status colours, and preserve Corsair cell 12's existing single-click multi-tap behavior after the double-click window.
**Guard:** Never put speculative modes into a live input map or intercept an ordinary control merely to advertise possible future work. A mode legend must match the generated routing exactly; test the intercepted-cell set, pass-through base exclusions, concrete labels, no Planned copy, same-mouse reserved gesture, and full ordinary-rule preservation before installation.
---

---
**Date:** 2026-08-11
**Trigger:** The Scimitar recovered pointer input after a Slipstream receiver replug, but Agentic Mouse did not automatically restore its accepted white runtime layer.
**Symptom:** iCUE device callbacks were subscribed and the app process stayed healthy, yet the re-enumerated mouse exposed the underlying software-profile lighting until Agentic Mouse restarted.
**Root cause:** The iCUE device callback is a useful fast path, not a reliable reconnect guarantee for every Slipstream replug. The app had no independent presence transition detector, so no code refreshed the exact device, invalidated the throttled frame cache, rebuilt the macro transport, or reasserted idle white when that callback was omitted.
**Fix:** Add a two-second, read-only `ICUEDeviceRecoveryMonitor` around exact iCUE enumeration. Emit only missing, recovered, replaced, or lighting-availability transitions; stable polls do nothing. On recovery, refresh the exact Scimitar, reassert the current idle/mode frame once, refresh mode lighting availability, and rebuild the input transport without re-entering a modal mode. Replace the animated iCUE Watercolor fallback with an officially exported, recoverable dark-amber Solid layer so a missing runtime layer is visually distinct and never resembles an active mode.
**Guard:** Keep iCUE callbacks as the low-latency path and the poller as bounded recovery. Never repaint on every poll, guess between matching devices, restore a mode after loss, edit iCUE private files, or use device-memory lighting as a reconnect workaround. Pin transition deduplication, same-identifier lighting recovery, and callback synchronization in hardware-free tests; require one real unplug/replug acceptance before calling automatic recovery physically verified.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan asked to turn the working Colour Proof HUD into a real shared submenu system for both twelve-button mice.
**Symptom:** Physical cell 3 entered Colour Proof directly, so every future mode would otherwise need another unrelated trigger, lease, HUD, and device mapping. That would duplicate the physical crosswalk and make modes compete for the same grid.
**Root cause:** The reusable HUD and source-keyed reserved-cell gesture existed, but there was no authoritative top-level mode state or mutually exclusive Karabiner ingress above individual modes.
**Fix:** Add one exact-device Mode Picker on physical cell 3 (Corsair 3 / Razer 1), backed by its own expiring lease and the same canonical twelve-cell crosswalk. The picker closes its lease before starting a selected mode, uses physical cell 12 (Corsair 12 / Razer 10) as the universal HUD toggle, and shows on every connected display. Colour Proof is the first live selection on physical cell 6 (Corsair 6 / Razer 4); Media, Zoom, Spaces, Typing, fast-scroll, Codex, Arrow, VS Code, and future slots remain visibly marked Planned until each behavior is separately wired and accepted.
**Guard:** One runtime routing layer owns the grid at a time. Base mappings must exclude every live mode lease; each mode entry must exclude all other leases; and an app crash must let every short absolute lease expire back to the base map. Never label an unwired submenu action Ready, duplicate vendor-specific semantics, or let the picker start a mode before clearing its own HUD, lighting, and Karabiner variable.

**Status:** Historical first prototype only. Colour Proof is retired from the live map; current entries and universal cell-10 Exit are defined by the newer hierarchy learnings above.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan unplugged and replugged the Scimitar's Slipstream receiver after the mouse retained local lighting but lost all pointer input.
**Symptom:** Before the replug, macOS enumerated only iCUE's virtual HID devices. After `1b1c:2b00` returned, pointer input recovered but the side and logo zones visibly resumed iCUE's out-of-phase Watercolor animation instead of Agentic Mouse's accepted solid-white idle baseline.
**Root cause:** The missing physical receiver, not a Karabiner profile or buffered lighting command, caused the input failure. Removing the receiver also destroyed Agentic Mouse's temporary shared SDK lighting layer. The still-running app did not reassert white when the receiver returned, exposing the underlying iCUE software-profile Watercolor layer; Device Memory Mode was visibly off and no doctor/test process remained.
**Fix:** Replug the receiver and verify physical HID `1b1c:2b00` before changing any mapping. A notified clean Agentic Mouse restart rebuilt its white shared layer without modifying iCUE, Karabiner, mappings, config, or the installed binary. Colour Proof exits during receiver loss or app restart by design; with idle and absolute timeouts both zero, it otherwise remains active until explicit exit.
**Guard:** Keep physical link recovery, iCUE fallback lighting, Agentic Mouse shared-layer recovery, and mode lifetime as separate states. On a future replug, verify receiver enumeration, app PID/socket ownership, and physical white independently. Never delete profiles or blame Karabiner for total pointer loss. Treat missing automatic white reassertion after a receiver replug as a reconnect defect to fix and test, not as justification to persist runtime effects to device memory.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan challenged the visible `PASSIVE REMINDER` label in the Default-map HUD.
**Symptom:** The HUD described its internal state distinction instead of simply saying what it showed, making the interface sound patronising.
**Root cause:** Developer vocabulary from comments and architecture (`passive reminder`) was copied directly into user-facing header and status strings.
**Fix:** Replace both visible labels with concrete `BUTTON MAP` wording and centralize the strings in `ModeHUDCopy` so the reference HUD has one reviewable copy source.
**Guard:** Keep implementation terms in source comments and documentation only. Name user-facing mouse HUDs by their actual content or mode, and pin the shared copy in a focused test so internal jargon cannot leak back into the interface.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan made the map reminder easy to toggle and wanted it substantially larger, then established its top-left double-click as the reserved legend control for every mouse mode.
**Symptom:** The 470-point reference card and 9–12-point labels were unnecessarily small across several displays. Colour Proof also treated the top-left cell only as a colour selection, so the base reminder's useful gesture did not carry into an active mode.
**Root cause:** Layout metrics and double-click classification were tied to the first passive reminder instead of being reusable mode infrastructure. Active mode updates also assumed that a live mode always meant a visible HUD.
**Fix:** Double the reusable HUD's panel, type, spacing, cells, strokes and status metrics. Extract `ReservedModeHUDGesture`, key it by mouse source, and reserve physical cell 12 (Corsair 12 / Razer 10) for single-action-or-double-toggle classification. Colour Proof keeps its single-click Rose action, toggles the legend without changing colour or lease state on double-click, and shows the large legend on every connected display.
**Guard:** Every future `ModeHUDLegend` mode must reuse the same physical cell and source-keyed classifier, preserve its single-click action after the bounded decision window, keep hidden HUD state independent from active mode/lighting state, and cancel pending input on exit. Pin same-source, cross-source, single-click, hidden-update and all-display behavior in tests; never let a double-click select the reserved cell twice or let two mice form one gesture.
**Status:** Historical prototype only. The accepted product contract now uses one-click cell 3 for the Default legend and cell 12 as the universal Utility modes entry/exit; no double-click classifier owns either action.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan noticed that the wireless Corsair turned its LEDs off after inactivity while the wired Razer looked materially brighter, and asked for the actual iCUE state before changing either device.
**Symptom:** The Corsair appeared to stop participating in Agentic Mouse's white baseline after a while, while the Razer's full-channel custom frame was uncomfortably bright beside it.
**Root cause:** The Corsair was behaving exactly as saved in iCUE: device brightness was 91% and Sleep Mode was enabled after 15 minutes. Motion Sense Power Saving and Power Saving Mode were off. Agentic Mouse requested full white for both devices, but the Corsair's device-level brightness still capped its LEDs while the Razer custom matrix received unscaled 255-channel frames and has no battery to protect.
**Fix:** Leave the accepted Corsair device settings unchanged. Add a clamped brightness scale to `RazerVendorLightingController`, apply it to every idle and mode custom frame, and configure the app for 50% Razer output after Ethan physically judged 75% still slightly brighter than the Corsair. Keep the exact `NOSTORE` protocol, mode colour proportions, failure rollback, and true teardown behavior unchanged. Do not add a synthetic Razer inactivity timer merely to imitate a battery-powered mouse.
**Guard:** Diagnose apparent lighting timeouts in the vendor UI before changing runtime code. Keep device-level brightness, app-frame brightness, wireless sleep, and system sleep as separate controls. Pin scaled packet bytes in hardware-free tests, preserve live config and Karabiner during app replacement, and require Ethan's visual comparison before describing 50% as a perceptual match.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan wanted the passive Default-map reminder to behave like an on-demand reference HUD: stay open until explicitly toggled off and appear on every connected display.
**Symptom:** The reminder auto-hid after six seconds and `AppKitModeHUDPresenter` owned only one `HUDPanel`, positioned on the configured pointer or main screen. Looking at another display could therefore lose the reference even while the app and input route were healthy.
**Root cause:** Gesture lifetime and display placement were hard-coded as toast behavior. The reusable snapshot did not express whether a presentation belonged on one target display or all displays, and the presenter had no display-change reconciliation.
**Fix:** Treat a second valid top-left double-click as the explicit hide action and use zero `displayDuration` for persistent presentation. Add `ModeHUDSnapshot.showsOnAllDisplays`; for the Default map, maintain one shared-model, non-activating `HUDPanel` per `NSScreen`, and reconcile panels when macOS reports changed screen parameters. At this stage runtime modes retained their configured target display; Ethan later broadened every reusable mode legend to all displays, as recorded in the newer learning above. The installed build showed three correctly placed panels for three connected displays for more than 40 seconds, then removed all three on the next double-click.
**Guard:** Pin persistent, second-double-click, cross-mouse hide, legacy positive auto-hide, and all-display snapshot behavior in tests. Preserve a separate panel/hosting view per display, keep every panel click-through and non-activating, and remove stale panels after display changes. Only broaden runtime modes when Ethan asks; he later did, so the newer universal mode-HUD rule above is authoritative.
**Status:** Historical gesture contract only. The all-display presenter remains valid, but the current Default toggle is one press on cell 10 and each source owns an independent legend; active modes remain visible until that same cell exits.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan required both mice to be maximum solid white whenever no runtime mode is active, instead of falling back to each vendor's rainbow effect.
**Symptom:** Colour Proof could change both mice, but exit cleared the Corsair shared layer and sent Razer Spectrum Cycling, so the ordinary state became rainbow again.
**Root cause:** The code used one `nil` meaning for two different lifecycle events: clearing a mode and relinquishing hardware ownership. The Razer controller also lived inside Colour Proof startup even though the idle baseline is an app-lifetime responsibility.
**Fix:** Give the Corsair coordinator an explicit full-white idle frame and the Razer vendor controller an explicit full-white `NOSTORE` custom frame. Mode or alert colours override white; clearing them restores white without releasing either controller. Start Razer lighting independently of Colour Proof, reassert both baselines after wake, and reserve Corsair layer release plus Razer Spectrum restore for true sleep or app teardown. Ethan physically accepted instant Razer mode colours and maximum-white idle on both mice; the installed app remains the runtime requirement.
**Guard:** Keep mode clear, device/session recovery, and process teardown as separate states. Tests must prove mode exit writes white with zero release calls, reconnect/wake restores the desired baseline, Razer custom mode activates once per open handle, and true teardown remains idempotent and restores vendor ownership. Never turn idle white into an iCUE profile, Razer onboard write, `VARSTORE` packet, or second button-mapping source of truth.
---

---
**Date:** 2026-08-11
**Trigger:** Ethan wanted the shared physical top-left cell to keep its ordinary single-click behavior but show the default button map on a double-click from either exact mouse.
**Symptom:** Treating both mice as one raw key stream could combine a Corsair click with a Razer click, leak Razer's ordinary `0`, or require routing Corsair side 12 through Karabiner and iCUE at the same time. Entering multi-tap on the first Corsair click also made the second click exit a mode instead of showing a passive reminder.
**Root cause:** The gesture and the device adapters are separate responsibilities. Corsair already exposes exact raw `CMKI_12` events through iCUE, while Razer needs an exact-device Karabiner user command; double-click classification must be keyed by mouse source and must defer the existing single action for one bounded decision window.
**Fix:** Feed both adapters into one source-keyed `DefaultMapHintCoordinator`. Delay only inactive Corsair single-click entry for 340 ms, keep one Razer click inert, show the reusable non-activating `ModeHUDSnapshot` for six seconds on two same-source clicks, and cancel pending or visible hints whenever another runtime mode owns the grid. Keep Colour Proof's active lease ahead of the base Razer rule so cell 12 still selects its mode action.
**Guard:** Pin same-source, cross-source, expired-window, cancellation, auto-hide, inactive-only, exact-device payload and no-key-leak behavior in tests. Never duplicate one physical Corsair press through both raw iCUE and Karabiner, never let two mice complete one gesture, and represent passive reminders with no selected cell or lighting state so they cannot look like a latched mode. Ship the feature flag default-off until the matching app and generated Karabiner replacement are separately authorized; otherwise an unrelated shared-worktree app install can activate the Corsair half early.
**Status:** Historical prototype only. The accepted Default legend is a one-click exact-device Karabiner command on cell 3 and uses no double-click decision window.
---

---
**Date:** 2026-08-11
**Trigger:** The installed colour-proof app received a Razer mode command while the separate red/green doctor held the exact USB device open.
**Symptom:** Instead of reporting that USB was busy, Agentic Mouse crashed on the main thread with `Swift runtime failure: Negative value is not representable` in `RazerVendorUSBTransport.open()`.
**Root cause:** The `switch` converted `kIOReturnNotFound` with `UInt32(kIOReturnNotFound)`. IOKit constants can import as negative signed values, and Swift evaluates that trapping case expression even when the actual status is another error such as exclusive access.
**Fix:** Compare the status with `Int32(truncatingIfNeeded: kIOReturnNotFound)`, which preserves the IOKit bit pattern without a checked signed-to-unsigned conversion. Keep the controller fail-closed so an unavailable lighting transport never prevents the HUD from opening.
**Guard:** Source tests must reject direct `UInt32(kIOReturn...)` conversions in the real transport. Exercise the installed app with the USB device intentionally unavailable and prove the process and HUD survive; optional RGB failure must never terminate the authoritative mode UI.
---

---
**Date:** 2026-08-10
**Trigger:** Windows Dynamic Lighting visibly accepted commands for the exact Naga but did not change its LEDs, while Synapse Static immediately changed the physical mouse to green and red.
**Symptom:** The advertised standard LampArray appeared valid on both macOS and Windows, yet only Razer's own application could control the lighting. Installing a capture driver looked like the next way to discover Synapse's commands.
**Root cause:** This unit's standard LampArray is firmware-inert even though the descriptor and Windows device tile exist. Its working lighting path is Razer's acknowledged vendor protocol. Current OpenRazer source already documents PID `008d` as a three-zone device using 90-byte extended-matrix reports with transaction ID `0x1f`; current `librazermacos` supplies the established macOS USB control-transfer transport but omits this PID from several static-effect switch tables.
**Fix:** Retire LampArray as a runtime target. Reimplement the documented vendor frame cleanly in Swift, keep runtime output `NOSTORE`, validate every SET_REPORT with its matching GET_REPORT status, retry only `busy`, and restore Spectrum Cycling across scroll-wheel, logo, and thumb-grid zones after exit or partial failure. Use the narrow macOS USB-device shim only for exact `1532:008d`; do not detach or seize an input interface.
**Guard:** A descriptor, OS settings tile, or successful host call never proves physical LED acceptance. Prefer exact open-source protocol evidence and hardware-free packet vectors before capture. Do not install USBPcap/Wireshark unless the exact acknowledged command is rejected or physically contradicted; never guess subsequent packets after `not supported`, and require a separately described/approved solid-green-plus-spectrum physical test before wiring the vendor controller into the running app.
---

---
**Date:** 2026-08-10
**Trigger:** Ethan expected the floating mode legend to remain visible until he explicitly exited, but later found it absent.
**Symptom:** The installed helper process was no longer running, so Karabiner still consumed and routed the entry button but no receiver existed to draw the HUD. Even while running, the colour proof also had a 30-second idle exit and five-minute absolute limit that contradicted the requested persistent mode.
**Root cause:** Karabiner can own exact-device input routing and an expiring variable lease, but it cannot render AppKit UI or control iCUE/HID LampArray output. Those outputs require the lightweight Agentic Mouse process. The original demonstration defaults also treated automatic timeout as a safety requirement instead of separating user-visible mode lifetime from crash-safe routing lifetime.
**Fix:** Keep Agentic Mouse running whenever runtime HUD or RGB is wanted, and default both colour-proof timeouts to zero so the mode remains until the entry cell explicitly exits. Continue renewing only a short Karabiner lease so a missing process restores ordinary mappings automatically.
**Guard:** Explain the runtime split plainly: Karabiner routes buttons; Agentic Mouse receives commands, draws the HUD, and drives lighting. Preserve teardown on explicit exit, sleep, active-device loss, lease failure, and app shutdown. Test that a full day of simulated time does not hide a zero-timeout HUD, and never mistake a generated Karabiner rule for a self-contained HUD/RGB runtime.
---

---
**Date:** 2026-08-10
**Trigger:** The exact Razer Naga stayed on its autonomous rainbow while both mice successfully drove Agentic Mouse's HUD and the Corsair colour layer.
**Symptom:** Exact-device Karabiner input and shared mode state worked, but solid red, a deliberately distinctive three-zone pattern, and a five-minute red/off strobe all left the Razer on its ordinary smooth rainbow even though every macOS `IOHIDDeviceSetReport` call returned success.
**Root cause:** Input transport and lighting transport are separate interfaces, and successful HID delivery is not physical LED acceptance. The exact `1532:008d` composite advertises an Apple-owned standard LampArray whose report 3 correctly cycles lamp IDs `1, 2, 0` and marks all three programmable, but report 6 (`AutonomousMode`) is not implemented: an initial read returns report-1 data, and a two-byte read after report 3 returns `[03 00]`, echoing the last valid response. Without a working autonomous-mode control, the firmware rainbow continues to own the LEDs and report-5 colour frames never become visible.
**Fix:** Withdraw the standard macOS LampArray adapter as an available runtime target and keep the universal twelve-cell HUD authoritative. Preserve the exact-interface code only as a fail-closed diagnostic until a reference Windows test distinguishes firmware-level LampArray failure from a Mac-specific sequencing issue. Test Windows Dynamic Lighting with Synapse stopped, then Razer Synapse/Chroma Studio with a static colour; only a physically visible result can select the next architecture.
**Guard:** Never promote `kIOReturnSuccess`, a matching descriptor, programmable lamp attributes, generated reports, or hardware-free tests to physical lighting acceptance. Do not install or enable the Razer adapter by default, send more guessed feature reports, or move to the vendor protocol without a separately reviewed exact-device protocol, recovery plan, macOS heads-up, and Ethan's approval. Corsair/Razer result status stays independent, and the HUD remains the reliable mode reference when either RGB path is unavailable.
---

---
**Date:** 2026-08-10
**Trigger:** Ethan physically rejected two increasingly complex Switch App rules, then challenged the assumption that Karabiner could not express the ordinary press-hold-release lifecycle itself.
**Symptom:** Sticky Command failed, and the replacement `left_command` plus delayed Tab produced `Command down/up`, `Tab down/up`, then another `Command down/up`. A proposed Agentic Mouse CGEvent state machine added Accessibility, IPC, watchdog and login-item complexity for a common native remapping behavior.
**Root cause:** Karabiner releases non-final ordinary `to` events immediately, but preserves the final repeat-enabled event until the physical source releases. The failed rules put Command before Tab or moved Tab outside that useful ordering. The investigation did not first search for the established reversed composition.
**Fix:** Emit one self-contained `{ "key_code": "tab", "modifiers": ["left_command"], "repeat": false }` first, followed by `{ "key_code": "left_command", "repeat": true }` last. Karabiner sends Command-Tab once, then keeps the final Command held until button 2 is released. On 10 August Ethan physically confirmed the installed exact-device Corsair and Razer rules open and hold the native switcher correctly. Remove the unnecessary Agentic Mouse Switch App command receiver and CGEvent state machine; keep Agentic Mouse only for its real runtime features.
**Guard:** Before adding a privileged app, shell command or custom event state machine for a common Karabiner behavior, search the official lifecycle documentation, inspect the event-sender ordering, and look for a working public composition. Pin the native event order in generator tests, preserve exact-device scoping, and still require physical acceptance; generation and lint alone do not prove the interaction.
---

---
**Date:** 2026-08-10
**Trigger:** Ethan noticed that the installed shared map and interactive guide had reverted to an older side-button layout.
**Symptom:** The generated bases put VoiceInk++ on Corsair side 4 and horizontal scrolling on sides 7/10, even though Ethan's later hands-on setup used sides 1/4 for horizontal scrolling and the separate top DPI control for VoiceInk++.
**Root cause:** The implementation treated the 6 August desired-state handoff as newer authority than the later, complete pre-removal iCUE export. Some saved assignment names were stale as well, so reading labels instead of the bound action payloads compounded the drift.
**Fix:** Parse the actual action payloads from the last complete, hash-verified vendor-profile export and reconcile them with later direct user corrections. The recovered global map uses 1/4 for horizontal left/right, 5/8 for Forward/Back, 6/9 for Next/Previous Track, top DPI for VoiceInk++, 2 for Switch App, 12 for multi-tap, and leaves 3/7/10/11 spare.
**Guard:** Rank evidence by timestamp and class: the latest verified hardware/profile state plus later direct user corrections outrank an older desired-state summary. Never treat an assignment label as its payload, and suspend physical semantic acceptance whenever the map under test is discovered to be stale.
---

---
**Date:** 2026-08-10
**Trigger:** One first-iteration colour demonstration needed to work from both exact mice without making Agentic Mouse a second Razer mapping or HID owner.
**Symptom:** A process-local mode flag could not identify which exact mouse and physical cell Karabiner had consumed, while a permanent Karabiner variable could strand the ordinary side-button actions after an app crash.
**Root cause:** Runtime mode state, exact-device ingress, physical-cell identity, ordinary semantic actions, and optional hardware lighting are separate responsibilities. Printed Razer numbers also do not identify the same physical positions as the Corsair numbers.
**Fix:** Generate exact-device `send_user_command` payloads from the existing physical binding crosswalk, render one universal non-activating HUD, and treat Corsair shared RGB as an optional output adapter. Generate the mode plus gated ordinary rules as one complete replacement artifact, separate from the ungated ordinary artifact. Let the app renew only a short absolute-expiry lease; entry gets a 1.2-second bootstrap and exit clears it immediately. Serialize `karabiner_cli` writes on a background queue so the two-second heartbeat never blocks AppKit, and report only failures from the currently active lease generation. Repeating a failed Corsair colour must retry the physical write rather than treating the desired frame as proof of success.
**Guard:** Pin the 12-colour palette, both 12-cell crosswalks, exact device conditions, rule order, ordinary-action exclusions, timeouts, and teardown paths in tests. Directly integration-test datagram delivery, owned-socket cleanup, and refusal to unlink a foreign receiver socket. The ordinary install artifact must contain zero mode expressions and zero user commands; never enable it alongside the complete colour-proof replacement. Keep Razer runtime RGB unavailable until an exact supported protocol is proven, and never promote generated/linted rules or simulated iCUE frames to physical acceptance. A free-looking entry cell must also be checked against the last verified vendor-profile export: Corsair side 1 was Tilt Left, so the first C1/R3 candidate was withdrawn. On 10 August Ethan accepted C3/Razer printed 1, the complete proof replacement and updated app became live, and a controlled command proved enter/select/exit plus lighting release; physical button acceptance remains a separate final boundary.
---

---
**Date:** 2026-08-09
**Trigger:** The exact-device Corsair wheel rule was installed correctly, but clean EventViewer presses still appeared as raw `pointing_button: button3` instead of Play/Pause.
**Symptom:** The generated/live manipulator matched the connected Corsair pointing interface `6940:11008`, yet the rule never ran.
**Root cause:** Karabiner Devices had **Modify events** off for the physical Corsair pointing interface. Exact `device_if` matching controls scope only after Karabiner is allowed to modify that interface.
**Fix:** Back up the entire live configuration, enable **Modify events** only for the physical `6940:11008` pointing row, and canonically compare the result. Karabiner added exactly one device record with `ignore: false`; no rule or unrelated profile state changed.
**Guard:** Before physically testing any exact-pointing-device rule, verify both the rule condition and the Devices-page switch. Do not enable the vendor virtual pointing interface as a substitute, and do not call the semantic output accepted until a clean post-enable physical press is captured.
---

---
**Date:** 2026-08-09
**Trigger:** Ethan removed the current VS Code behavioral differences and moved both mice's wheel Play/Pause semantics into Karabiner.
**Symptom:** Full app-specific copies forced the same baseline action to be edited twice and could drift, while iCUE-owned wheel media assignments prevented the two mice from sharing one semantic source.
**Root cause:** A Karabiner rule without a frontmost-application condition already applies everywhere; cloning the full base is not inheritance. A wheel can likewise remain an ordinary device-specific middle-click input while Karabiner supplies one shared media output.
**Fix:** Keep one unfiltered base rule per exact device. Add an app-specific rule only for a deliberately overridden transport, paired with `frontmost_application_unless` on that one base binding. Bind each exact pointing device's `button3` to the shared `play-pause-current-media` action and leave the vendor wheel at its default middle-click source.
**Guard:** Generator tests require exactly two global Agentic Mouse rules, no frontmost-application conditions, one binding per side cell, and one exact-device wheel binding per mouse. Before a live replacement, back up the entire Karabiner configuration and prove every unrelated rule and profile field is unchanged.
---

---
**Date:** 2026-08-09
**Trigger:** Building an interactive map that explains one shared action layout across the oppositely numbered Corsair and left-handed Razer grids.
**Symptom:** A flat button table can make matching printed numbers look authoritative and can hide whether a Karabiner action emits a mouse, media, scroll, or keyboard event.
**Root cause:** Physical cell, device-local raw transport, shared semantic action, and emitted output type are four separate facts; collapsing them into one label makes the cross-device map misleading.
**Fix:** Key the visualizer by the authoritative physical-cell crosswalk, show both device transports and the literal output type, and highlight the two corresponding cells together. Keep configured state and physical acceptance stated separately. Label Normal/VS Code controls as previews of the same unfiltered base until a deliberately selected override exists. Keep the preview query parameter synchronized when the layer changes so reload and shared links preserve the visible state.
**Guard:** Validate all twelve visual pairs against `Karabiner/bindings/bindings.json`, inspect the installed exact-device rules for native output claims, and test desktop, mobile, keyboard, layer-switch plus reload, grid-key, and hover/focus tooltip interactions before publishing the page.
---

---
**Date:** 2026-08-09
**Trigger:** Ethan chose the Razer's separately captured lower DPI control as a second ergonomic VoiceInk++ trigger without changing the mirrored twelve-cell grid.
**Symptom:** Treating only the grid as shareable would leave the proven F22 transport unused, while mapping an unscoped F22 could affect an unrelated keyboard.
**Root cause:** The Naga onboard profile exposes DPI Down as a normal F22 keyboard transport; its semantic meaning is supplied later by Karabiner, not by the sensor or Synapse on macOS.
**Fix:** Bind F22 to `toggle-voiceink-speech-to-text` inside `Agentic Mouse — Razer base layer`, scoped to exact keyboard device `5426:141`. Leave F21 unchanged and keep this extra control independent of the side-grid crosswalk.
**Guard:** Pin the F22 source, VoiceInk action, and exact device condition in generator tests. Treat generated and installed state as implemented until a physical lower-DPI press proves VoiceInk++ toggles.
---

---
**Date:** 2026-08-09
**Trigger:** Extending the verified Corsair semantic map to the left-handed Razer Naga without reversing physical positions.
**Symptom:** Reusing the same printed side-button numbers would assign several actions to the wrong physical cells because the Corsair and left-handed Razer grids number corresponding columns in opposite directions.
**Root cause:** Printed labels are device-local transports, not the shared semantic identity. The Razer emits onboard main-row `1–9`, `0`, `hyphen`, and `equal_sign` from exact device `1532:008d`, while the Corsair emits keypad transports from `6940:65535`.
**Fix:** Generate separate exact-device adapters that inline the same action sources and map by the authoritative crosswalk: `C3↔R1`, `C2↔R2`, `C1↔R3`; `C6↔R4`, `C5↔R5`, `C4↔R6`; `C9↔R7`, `C8↔R8`, `C7↔R9`; `C12↔R10`, `C11↔R11`, `C10↔R12`. Each current adapter has twelve side-cell manipulators plus an exact-device wheel binding; the Razer base also has its F22 VoiceInk control.
**Guard:** Generator tests pin both namespaces, both exact device identities, and every Razer side's semantic action list. Install the Razer rules only after the returned exact device and ordered transports are physically captured. On 9 August that gate passed and the two exact-device Razer rules became live, but generated, linted, or installed still does not equal physical semantic acceptance.
---

---
**Date:** 2026-08-06
**Trigger:** A live iCUE audit disagreed with the repository's authoritative-intent map.
**Symptom:** The saved Normal and VS Code profiles still bound `Speech to text` to the top DPI toggle, had no assignment on side button 4, and kept button 11 as an empty keystroke even though the project record described the newer target map.
**Root cause:** The project mapping is a desired-state/verifier record; it does not configure iCUE, and earlier task summaries treated desired state as if it were saved live state.
**Fix:** Keep intended and observed mappings separate. Reconcile changes visibly through iCUE, then inspect the saved result read-only and perform a physical test before describing an assignment as live.
**Guard:** Every mouse handoff must name the evidence class for each claim: intended in source, saved in iCUE, observed in EventViewer, or physically proven. Never promote one class to another without evidence.
---

---
**Date:** 2026-08-06
**Trigger:** Computer Use attempted to record F16 in an iCUE keystroke field for button 11.
**Symptom:** The automation call succeeded, but iCUE visibly saved `Enter`, not F16.
**Root cause:** Synthetic high-function-key injection is not a trustworthy stand-in for a physical key capture in this iCUE/macOS path.
**Fix:** Clear the incorrect assignment and use either physical capture or another supported transport route.
**Guard:** After any automated key capture, verify the exact key displayed in iCUE and the emitted event in Karabiner-EventViewer before adding downstream rules.
---

---
**Date:** 2026-08-06
**Trigger:** The VS Code iCUE profile did not retain newer base-profile assignments such as Switch App.
**Symptom:** Buttons that worked in the Normal profile were missing or stale after VS Code became frontmost.
**Root cause:** iCUE profile duplication copies the current state once; linked profiles do not inherit later edits from their source profile.
**Fix:** Duplicate the complete Normal profile before adding app-specific overrides, then use iCUE's Assignments Library to mirror later baseline actions into every affected profile.
**Guard:** Treat each linked profile as an independent snapshot and verify all baseline-intent buttons after every profile-specific edit.
---

---
**Date:** 2026-08-06
**Trigger:** Mouse button 10 staged the current VS Code file but did not move to the next changed file.
**Symptom:** The Scimitar's F18 action behaved differently from Better Git's keyboard stage-and-advance action.
**Root cause:** VS Code user keybindings mapped F18 to `better-git-vscode.stage-current-file`, which intentionally stages without navigation.
**Fix:** Bind F18 to `better-git-vscode.stage-and-next-changed-file` and keep the Agentic Mouse mapping record explicit about the advancing semantic.
**Guard:** `NormalMappingTests.testVsCodeBetterGitBindings` pins the exact F18 command identifier; the live keybinding and a physical stage-and-next test remain separate verification boundaries.
---

---
**Date:** 2026-08-06
**Trigger:** Musixmatch needed a mouse control for whole-song Play/Pause without sending `Tab` on unrelated Chrome pages.
**Symptom:** The active Musixmatch Pro session was an ordinary tab in the main Google Chrome process, and no Musixmatch `.app` bundle or app-shim process existed for iCUE to target.
**Root cause:** iCUE app-linked profiles distinguish macOS applications, not URLs inside one browser application.
**Fix:** Stop before changing iCUE. Prefer a tiny local Chrome extension that matches only `https://pro.musixmatch.com/*`, accepts one EventViewer-proven unique transport from a genuinely free button, and directly activates the live-verified whole-song semantic control. Button 2 remains an ergonomic proposal, not a proven free control. Keep a dedicated web-app bundle only as the fallback if exact-origin fail-closed behaviour cannot be proven.
**Guard:** Never bind a site-only shortcut or `Tab` to all of Chrome. Require a trusted physical transport, refuse absent or ambiguous controls, test playback across a lyric-line boundary, and negative-test the same button on an unrelated Chrome tab before calling the route live.
---

---
**Date:** 2026-08-07
**Trigger:** Another device's configuration was added to Agentic Mouse's public scope even though the app implements only Corsair runtime features.
**Symptom:** The project appeared to own device configuration it neither reads nor writes, while its real iCUE and multi-tap boundaries became less clear.
**Root cause:** Cross-device coordination was confused with application ownership.
**Fix:** Keep device configuration ownership outside the app runtime. iCUE owns Scimitar hardware settings and the Naga onboard profile owns its hardware transports; Agentic Mouse must not pretend to read or write either device profile.
**Guard:** Do not add another device's live configuration, setup record or hidden synchronization path merely because a shared shortcut exists. The later approved shared semantic source/build tree is allowed precisely because physical bindings remain separate and empty until explicitly chosen.
---

---
**Date:** 2026-08-07
**Trigger:** Ethan retired Philips Hue-to-mouse mirroring and asked whether user-defined runtime mode colours were genuinely supported on macOS.
**Symptom:** Hue remained enabled in both preserved helper configs, while the repository's generic shared-lighting layer could be mistaken for a supported Mural/profile API.
**Root cause:** The product direction and the platform support boundary had diverged from the implementation. Corsair's public iCUE SDK reference still lists Windows requirements; the macOS app's bundled SDK library and approval UI prove a technical ABI exists, not that arbitrary macOS integration or Mural image switching is publicly supported.
**Fix:** Disable Hue in both live helper configs while preserving the Keychain credentials, remove the Hue runtime/configuration/UI/network code, and keep only explicit mode/alert colours that release back to ordinary iCUE lighting when inactive.
**Guard:** iCUE remains the single owner of baseline profiles, Device Memory Mode, hardware lighting and Murals. Treat Agentic Mouse runtime colours as experimental shared-layer output on the two audited Scimitar zones until Corsair documents macOS support and Ethan explicitly approves a guarded physical write/release test. Never use private iCUE files or a Mural-file replacement hack as a runtime-mode source of truth.
---

---
**Date:** 2026-08-07
**Trigger:** Ethan explicitly chose Agentic Mouse as the source-and-build home for a shared Corsair/Razer Karabiner action architecture while deferring every physical binding.
**Symptom:** The earlier Corsair-only repository rule treated shareable semantic source as if it were a second Razer device configuration, leaving no clean home for one-file-per-action definitions or deterministic Karabiner generation.
**Root cause:** Device transport ownership, live mapping ownership, and source-code ownership were collapsed into one boundary.
**Fix:** Keep iCUE and the Naga onboard profile responsible for hardware transports, Karabiner responsible for enabled exact-device mappings, and Agentic Mouse responsible for the named action catalog and generator. Generate a valid empty-rules artifact until approved physical bindings exist.
**Guard:** Keep actions and bindings in separate source trees; require a top-of-file behavior comment and stable action ID; fail generation on unknown actions or missing device-scoped bindings; never install generated output or choose a physical cell merely because the source builds.
---

---
**Date:** 2026-08-08
**Trigger:** The guarded Corsair transport pilot replaced a side-button Keystroke assignment with a Keyboard Remap through iCUE 5.49.34 on macOS.
**Symptom:** Activating the Keyboard option through its Accessibility checkbox made the tile look selected, but the editor still said `Remap: Keystroke`; selecting a NumKeyboard checkbox through Accessibility could also look correct until the assignment was reopened, when the target disappeared.
**Root cause:** These iCUE QML controls do not reliably commit assignment-type or key-target changes through their exposed checkbox actions alone.
**Fix:** Click the visible centre of the Keyboard tile, require the editor heading to change to `Remap: Keyboard`, choose the visible NumKeyboard key with a direct UI click, reselect the physical source cell, then switch away and reopen the assignment. Re-open Advanced and verify both `Retain Original Key Output` and `Imitate Holding Key` explicitly rather than assuming their values.
**Guard:** A highlighted assignment-type tile or key is not proof that iCUE saved the action. Capture the reopened heading, exact persisted NumKeyboard selection, advanced switches, and a clean EventViewer down/up cycle before installing any downstream Karabiner binding.
---
**Date:** 2026-08-12
**Trigger:** The running Agentic Mouse menu reported Accessibility unavailable immediately after an otherwise valid rebuilt app was installed, while the separately launched doctor process reported itself trusted.
**Symptom:** Multi-tap and Accessibility-backed Codex actions stopped working after each replacement, repeatedly sending Ethan back to the Accessibility pane.
**Root cause:** `package-app.sh` always ad-hoc signed the bundle. Its designated requirement was the build-specific CDHash, so every rebuilt executable was a new TCC identity even though the bundle id and `/Applications/AgenticMouse.app` path stayed unchanged.
**Fix:** Let packaging accept `CODE_SIGN_IDENTITY` and use Ethan's stable Developer ID identity for every installed build. Keep the portable default ad-hoc only for uninstalled development artifacts. Grant the stable signed app once through System Settings.
**Guard:** Before any installed replacement, verify the certificate-backed designated requirement and use the same identity, bundle id, and path. Packaging must fail closed when signing or signature verification fails; a warning followed by a usable-looking bundle can otherwise reinstall the exact regression. Never reset TCC, edit its database, use `sfltool`, or install an ad-hoc build over the trusted app.
---
