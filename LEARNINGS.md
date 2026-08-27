# Learnings

## 2026-08-27 — Keep ordinary action feedback inside the user's legend state

**Trigger:** Ethan double-pressed the top-level Screenshot button to paste the last Agentic Mouse screenshot. The paste succeeded, but its feedback unexpectedly opened the closed Default legend.

**Finding:** Screenshot copy, paste-queued, pasted, and failure callbacks sent feedback directly to the shared `AppKitModeHUDPresenter`. `flashFeedback` always reconciled panels with `show: true`, even after the Default coordinator had marked its legend closed. The same top-level bypass existed for a Horizontal Scroll posting failure, and delayed app-mode feedback could arrive after its owning page had closed.

**Fix:** Route every Screenshot result and the top-level Horizontal Scroll failure through the source's `DefaultMapHintCoordinator`, which accepts ordinary feedback only when that source's Default legend is already open. Ignore ordinary `flashFeedback` when the presenter's model is inactive, and require the delayed iPhone Mirroring verification to still belong to the same active source, app-specific page, and target before showing it. Keep deliberate system/readiness problems on the standalone problem path because they report that mouse input itself is unavailable. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)

**Guard:** A successful or failed top-level action may update an already-open Default legend but must never open one. A delayed mode result must verify its current page and target before touching the HUD. Preserve explicit user visibility as the single source of truth; do not make `ModeHUDPresenting` feedback a second visibility controller.

**Verification:** The focused Screenshot, Default-map, and AppKit lifecycle suites passed 37 tests, including hidden-legend success/failure and inactive-presenter regressions. The complete clean gate passed 657 Swift tests, six Musixmatch tests, six VS Code bridge tests, 17 Karabiner generator tests, both Karabiner lints, packaging/version contracts, and shell syntax; the updated `configure-mice` skill passed validation. Developer-ID-signed Agentic Mouse v1.0.138 (build 144) is installed as main PID 99098 with supervisor PID 99112, stable Accessibility trust, command-socket ownership, and an active Unix connection to iCUE's live SDK server. Its executable SHA-256 is `cbd70376f5e7f2d7b528749738720e1a06686fce800f2a30495e7de5e2eae896`; the embedded iCUE SDK, live config, live Karabiner file, and VS Code keybindings remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `aa1499d88bd34875dc11f9a2873165d09cd2323c590126f425da4fd72e3189be`, `b8a0048a76dda9aa03e38aeb538da4346d465428d078f7eeca7593c264698bbd`, and `8d23c9fae7eb21104cda9203be4b95e2cebacfb08e708f806977dcb3720b60aa`. Full-display pixel captures of all three current Spaces plus Accessibility window count zero prove the pre-install closed legend state remained closed after replacement. The exact prior app is preserved at `Rollbacks/AgenticMouse-v1.0.137-build143-before-v1.0.138.app` and recoverably in Trash. Literal physical Screenshot double-paste acceptance remains Ethan-owned.

## 2026-08-25 — Start VS Code Terminal toggling with Hide

**Trigger:** Ethan reported that VS Code mode's Toggle Terminal control needed two presses before it began hiding and showing the integrated Terminal as expected.

**Finding:** VS Code's built-in Control-` toggle is focus-sensitive. When the Terminal is already visible but the editor has focus, the first toggle focuses the Terminal instead of hiding it, so the first physical mouse press appears to repeat Show and the second finally hides it.

**Fix:** Route the same shared VS Code cell 4 through the existing allow-listed VS Code Bridge. Start each extension-host session with the explicit `workbench.action.closePanel` Hide command, then alternate with `workbench.action.terminal.focus` Show and repeat. Keep one bridge-owned sequence shared by both mice and every automatic/manual VS Code-mode journey. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)

**Guard:** Do not restore Control-`, Command-J, synthetic keyboard delivery, user-keybinding edits, or separate per-mouse Terminal state. Accept only the exact `/terminal/toggle` URI while VS Code is frontmost; the first accepted press must Hide, the second must Show, and the third must Hide again.

**Verification:** The focused Swift and Node suites proved no keyboard fallback, the exact new URI, frontmost-only routing, and Hide → Show → Hide ordering. The complete clean gate passed 647 Swift tests, six Musixmatch tests, six VS Code bridge tests, 17 Karabiner generator tests, both Karabiner lints, packaging/version contracts, and shell syntax. Bridge v0.1.1 was installed and its `bridge.js` hash matched source. Developer-ID-signed Agentic Mouse v1.0.130 (build 136) passed strict verification and briefly ran with its stable Accessibility grant, exact command socket, supervisor, config, Karabiner rules, and iCUE framework preserved. The existing VS Code extension host had been running since before the update and rejected the new URI, while the live VS Code window had active working-tree and debugger/watchdog state; do not restart or reload that editor blindly. Agentic Mouse v1.0.129 (build 135) was restored so Toggle Terminal remains usable until Ethan safely reloads VS Code, after which v1.0.130 still needs its final live install and one physical Hide-then-Show acceptance.

## 2026-08-25 — Reattach HUD panels to the current macOS Spaces

**Trigger:** Ethan still could not see the Default legend after Accessibility and CGWindow inspection reported three Agentic Mouse panels and direct per-window captures showed fully rendered v1.0.128 content.

**Finding:** The panels existed but belonged to stale, non-current macOS Spaces. Full screenshots of all three currently visible displays showed no legend, and the CGWindow records lacked `kCGWindowIsOnscreen`. Toggling the Corsair Default legend off and on made one panel visible on the Samsung display, while the other two current display Spaces still had no legend. `.canJoinAllSpaces`, AX window counts, and direct window captures therefore do not prove that a HUD is visible in the user's current Spaces.

**Fix:** Observe `NSWorkspace.activeSpaceDidChangeNotification` in both AppKit HUD presenters. While the model remains explicitly active, discard the cached `HUDPanel` instances and recreate one panel per target display on a later main-queue turn, then repeat once after 500 ms so separate-Spaces-per-display transitions have settled. Hiding a HUD discards its panels and clears the active model first, so neither the immediate nor delayed Space reconciliation can reopen a legend the user closed. (Codex task: 01a03a49-d2a9-7d63-85c0-f74ef52aeeab)

**Guard:** Preserve the existing `.nonactivatingPanel`, click-through, status-bar-level, `.canJoinAllSpaces`, and full-screen auxiliary contract by recreating the same `HUDPanel` type. Treat full-display pixel evidence from every connected display's current Space as the visibility proof; AX counts and direct panel captures prove only that windows exist and render.

**Verification:** Three focused AppKit lifecycle tests prove that an active all-display legend replaces every visible panel after a Space-change notification, an explicitly hidden legend stays hidden after the same notification and delayed pass, and every recreated panel retains the non-activating click-through contract. Developer-ID-signed Agentic Mouse v1.0.129 (build 135) was installed as PID 83847 with supervisor PID 83890. Its status menu reported the exact Scimitar, iCUE connected, Accessibility granted, and self-recovery enabled; the process also had the bundled iCUE framework open. After the genuine-session input gate opened, one normal Corsair Default toggle logged a successful open. Full-display pixel screenshots then visibly proved one v1.0.129 legend on each current AVT GC553G2, Built-in Retina Display, and LS27A800U Space; the requested Horizontal Scroll + Wheel and Copy / Paste + Wheel positions were visible in every legend.

## 2026-08-25 — Restore attended Default HUD visibility after replacement

**Trigger:** Agentic Mouse input, iCUE, Accessibility, and its supervisor were healthy after the v1.0.128 replacement, but Ethan reported that no HUD was visible.

**Finding:** The signed app restart cleared the Default legend's intentionally in-memory visibility. Closing the stuck runtime coordinators and verifying zero windows proved the modal HUD was gone, but zero windows was the wrong handoff because Ethan had expected his persistent Corsair Default legend to remain visible. A direct source-specific Default toggle immediately created three 705×376 panels, and direct app-specific entry replaced them with three mode panels, proving the renderer and all-display presenter were healthy.

**Fix:** Restore the Corsair Default legend through its normal source-specific toggle command. A direct Chrome-mode entry then suspended it, and a normal source-specific Exit restored it automatically. Record visible source legends before future attended replacement and reopen exactly those legends only after the relaunched app passes its active-session input gate. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)

**Guard:** Default legend visibility is process-local by design and must never survive lock, sleep, or a user-session transition. For an attended signed replacement only, distinguish a healthy neutral app from the user's desired presentation state: read the pre-install source HUDs, preserve that intent outside the app process, restore it after readiness, and verify one panel per connected display. Do not claim a zero-window readback is correct merely because no mode is stuck.

**Verification:** Installed Agentic Mouse v1.0.128 (build 134) remained PID 54513 with supervisor PID 54524, iCUE connected, Accessibility granted, and the six-rule live runtime configuration intact. The direct Default toggle produced exactly three 705×376 panels at the three current display frames. Direct Chrome-mode entry suspended the Default panels and showed three mode panels. Source-specific Exit logged `default mouse map restored after runtime mode` and left exactly three Default panels visible with the neutral `Agentic Mouse` status item.

## 2026-08-25 — Install the complete runtime Karabiner artifact

**Trigger:** After the top-level wheel swap was installed, Agentic Mouse could open Codex, app-specific, and Keys HUDs but physical cell 10 could not dismiss them, making the live app appear dead.

**Finding:** The live install used the five-rule `Karabiner/generated/agentic-mouse.json` base export instead of the six-rule `agentic-mouse-runtime.json` artifact. The base export deliberately omits `Agentic Mouse — Modes (expiring, exact-device)`. Base entry commands therefore still opened HUDs, but every active-mode selection and the universal cell-10 Exit route were absent. Agentic Mouse itself, its supervisor, iCUE session, Accessibility permission, and command socket were all healthy. Karabiner CLI's `--list-system-variables` output does not expose custom variables created through `--set-variables`, so absence from that output was not evidence that an app coordinator had closed.

**Fix:** Restore the complete six-rule runtime artifact while preserving the swapped base rules and all three non-Agentic rules. Send idempotent close commands to both app coordinators before every live reload, independent of lease visibility. Make the live installer reject any candidate that does not contain exactly one runtime Modes rule. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)

**Guard:** Use `Karabiner/generated/agentic-mouse-runtime.json` for every live Agentic Mouse replacement. Never install the importable five-rule base artifact or infer custom lease state from `karabiner_cli --list-system-variables`. Require one runtime Modes rule, preserve the contiguous Agentic block and every non-Agentic rule, close both app coordinators before replacement, and read back the live rule descriptions plus the exact source-specific cell-10 close payloads.

**Verification:** The repaired live Karabiner file has SHA-256 `b8a0048a76dda9aa03e38aeb538da4346d465428d078f7eeca7593c264698bbd`, contains the locked-session sink, one runtime Modes rule, both VS Code rules, and both base rules, and preserves all three non-Agentic rules. Its Modes rule maps Corsair `keypad_0` and Razer `equal_sign` to canonical physical cell 10 close commands under their source-specific expiring leases. The installer probe rejected the five-rule base artifact without writing a backup, accepted the six-rule runtime artifact in dry-run mode, and all 17 generator tests plus both Karabiner lints passed; the updated `configure-mice` skill passed `quick_validate.py`. Installed Agentic Mouse v1.0.128 (build 134) remained PID 54513 with supervisor PID 54524; after the repair it reported zero HUD windows and the neutral `Agentic Mouse` status item. Literal physical open-then-exit acceptance remains Ethan-owned on each mouse.

## 2026-08-25 — Swap the two top-level wheel controls across both mice

**Trigger:** Ethan asked to exchange the existing top-level Copy / Paste wheel and Horizontal Scroll wheel positions.

**Finding:** These behaviors are shared canonical semantics, but their physical ownership is recorded in several layers: `PhysicalCell` aliases, the readable Default map, exact-device Corsair and Razer bindings, generated Karabiner output, HUDs, tests, public maps, project instructions, and the durable `configure-mice` reference. Changing only the app resolver or only Karabiner would leave the other layer advertising or arming the old control.

**Fix:** Canonical physical cell 1 (Corsair printed 1 / Razer printed 3) now owns `Horizontal Scroll + Wheel`. Canonical physical cell 4 (Corsair printed 4 / Razer printed 6) now owns `Copy / Paste + Wheel`. Preserve horizontal wheel up as right and down as left, clipboard wheel up as Paste and down as Copy, and keep all app-specific cell-4 overrides unchanged. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)

**Guard:** Relocate the semantic ownership in both exact-device base adapters and every current mapping source together. Before replacing the live selected Karabiner block, send the app's idempotent close command to both source coordinators even when neither Karabiner lease is present, then verify the leases are clear: a file reload resets Karabiner's short mode variables immediately, so an app HUD can remain open after its lease disappears and cell 10 can no longer match the active Exit rule. During signed app replacement, use the exact `Quit Agentic Mouse` status-menu item; a generic AppleEvent Quit bypasses `disableForIntentionalQuit`, leaves the registered supervisor running, and relaunches the old app. Do not change the physical-cell crosswalk, iCUE transports, fixed 2,750 DPI, lighting, wheel polarity, horizontal magnitude, semantic debounce policy, Utility mappings, or app-specific child mappings. A source/build/install proves configuration only; literal acceptance of the new physical positions remains Ethan-owned.

**Verification:** The focused mapping, wheel, mode-picker, default-map, and Karabiner generator tests passed. The complete clean gate passed twice with 644 Swift tests, six Musixmatch extension tests, five VS Code bridge tests, 17 Karabiner generator tests, generated-source freshness and lint, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene; the updated `configure-mice` skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.128 (build 134) is installed as main PID 54513 with executable SHA-256 `e7d8b8fb112eca935b02cd4f9cec52bcb4ace5cc34a42da54ae864b192fa796e`, CDHash `3a0c072d55d1eebe8184f522301db27bc7b13d18`, Team ID `T34G959ZG8`, Accessibility granted, iCUE connected, and exclusive ownership of the mode-0600 Karabiner command socket. Its matching signed runtime supervisor runs as PID 54524 with executable SHA-256 `12b6e8cf55e4fcc594f6b354f3743a1b36065e0b8391d2ad001a85a126671d5f`. Live Karabiner readback proves canonical physical cell 1 routes to horizontal scroll and physical cell 4 routes to clipboard on both exact mice; all three non-Agentic rules were preserved byte-equivalently. The exact prior app is preserved at `Rollbacks/AgenticMouse-v1.0.127-build133-before-v1.0.128.app`, the replaced application is recoverable from Trash, and the prior live Karabiner file is preserved at `Rollbacks/karabiner-before-v1.0.128-wheel-control-swap.json`. The stuck Codex HUD was closed and verified absent. A final audit then caught an orphaned Corsair app-specific HUD with no remaining Karabiner lease; sending both exact source close commands removed all three overlay windows and restored the neutral status item. The installer now sends those idempotent close commands to both source coordinators before every live Karabiner reload, and the signed-install procedure now uses the exact status-menu Quit command so the supervisor cannot relaunch the replaced build. Literal physical acceptance remains Ethan-owned: on each mouse, hold top-level physical cell 1 and verify wheel up scrolls right and wheel down scrolls left, then hold physical cell 4 and verify wheel up pastes and wheel down copies.

## 2026-08-24 — Resolve YouTube scrub from physical ratchet direction

**Trigger:** Ethan physically reported that the installed YouTube Scrub wheel moved the video in the opposite direction from the ratchet.

**Finding:** `WheelChordDirection` represents the normalized Quartz delta sign rather than the direction Ethan feels. On both accepted mouse routes, a physical upward ratchet reaches `youtubeSeekAction` as `.down`; the original implementation treated `.up` as physical up and therefore reversed the live result.

**Fix:** Invert only `youtubeSeekAction`: normalized `.down` seeks forward five seconds and normalized `.up` seeks backward five seconds. Derive HUD feedback from the resolved action so the footer stays truthful.

**Guard:** Preserve physical cell 6, both-mouse parity, the fixed 80 ms leading-edge duplicate-burst filter, immediate reversal, exact five-second bridge notifications, target selection, focus, and playback state. Do not globally flip `WheelChordDirection` or change another wheel family.

**Verification:** All 25 focused wheel tests passed, including the inverted YouTube action and matching feedback copy. The complete clean gate passed 644 Swift tests, six Musixmatch extension tests, five VS Code bridge tests, 17 Karabiner generator tests, generated-source freshness and lint, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene; the updated `configure-mice` skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.127 (build 133) is installed as main PID 28527 with executable SHA-256 `f5d87b1bde7cfba9f64e6bdb59ace3928ed159e273c8879866e0c13d7938420a`, CDHash `473840c0612bd6d865f2dd02c5419dd230458ec7`, Team ID `T34G959ZG8`, Accessibility granted, iCUE connected, and exclusive ownership of the mode-0600 Karabiner command socket. Its matching signed runtime supervisor runs as PID 28545 with executable SHA-256 `cb99487b3413a2c0168572ffbe3567d15dd0463732cf84ea48673d96f3013b91` and CDHash `5b519420172dc97d61c79c4d59440d67c71ad44f`. The embedded iCUE SDK, live Agentic Mouse configuration, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `aa1499d88bd34875dc11f9a2873165d09cd2323c590126f425da4fd72e3189be`, and `efa14686651b1d551095294d17321f50247986cc757857245c63ba2dc8cd68d6`. The exact prior app is preserved at `Rollbacks/AgenticMouse-v1.0.126-build132-before-v1.0.127.app`, and the replaced application is also recoverable from Trash. Literal physical acceptance remains Ethan-owned: on each mouse, hold top-level physical cell 6 and verify wheel up seeks forward five seconds while wheel down seeks backward five seconds without changing Chrome focus or playback state.

## 2026-08-24 — Name the Codex chat wheel by its selection purpose

**Trigger:** Ethan said the Codex held-wheel control should be called `Chats Selection + Wheel` rather than `Chat History + Wheel`.

**Finding:** The control's behavior already selects the previous or next chat and does not present or inspect a history view. The old label described the underlying navigation concept rather than the action Ethan performs.

**Fix:** Rename only the user-facing control to `Chats Selection + Wheel` across the live HUD, public map, tests, repository instructions, and durable shared-mouse guidance. Preserve internal case names where they are implementation details.

**Guard:** Do not move physical cell 11, alter Option-Command-Left/Right, reverse the accepted wheel directions, change its fixed 80 ms ratchet reconstruction, touch iCUE/Karabiner, or rename unrelated history controls such as VS Code Cursor History.

**Verification:** The focused wheel, mode-picker, and Codex executor suites passed 116 tests. The complete clean gate passed 644 Swift tests, six Musixmatch extension tests, five VS Code bridge tests, 17 Karabiner generator tests, generated-source freshness and lint, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene; the updated `configure-mice` skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.126 (build 132) is installed as main PID 19691 with executable SHA-256 `6a75fb3ededefe24cf74811c080801dfe78cad2d8af8109d74eb9db900ad93b9`, CDHash `16082b3e5c0ed51d4cf42166819af24b24c6072f`, Team ID `T34G959ZG8`, Accessibility granted, iCUE connected, and exclusive ownership of the mode-0600 Karabiner command socket. Its matching signed runtime supervisor runs as PID 19754 with executable SHA-256 `581d3ad376542b6eb9e9a5960eb634b03223038dad821ea302e07a0acae550c4` and CDHash `ab151de0be7774e855ae914bf90cbd02b4bba3ad`. The embedded iCUE SDK, live Agentic Mouse configuration, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `aa1499d88bd34875dc11f9a2873165d09cd2323c590126f425da4fd72e3189be`, and `efa14686651b1d551095294d17321f50247986cc757857245c63ba2dc8cd68d6`. The exact prior app is preserved at `Rollbacks/AgenticMouse-v1.0.125-build131-before-v1.0.126.app`, and the replaced application is also recoverable from Trash. The rename changes presentation only; the existing physical behavior and transport remain unchanged.

## 2026-08-24 — Swap Codex Voice Mode with Reasoning Effort without changing their transports

**Trigger:** Ethan asked to exchange the existing Voice Mode and Reasoning Effort positions in Codex mode now that both exact mice share one semantic map.

**Finding:** Both the automatically detected Codex journey and the manually selected Codex journey already consume one `CodexMode.definition`. Reasoning Effort is a held-wheel control owned by `WheelChordControl`, while Voice Mode is a press action owned by `CodexModeAction`; swapping their physical cells therefore does not require an iCUE assignment, a new Karabiner transport, or separate Razer behavior.

**Fix:** Shared physical cell 4 (Corsair printed 4 / Razer printed 6) now owns `Reasoning Effort + Wheel`. Shared physical cell 12 (Corsair printed 12 / Razer printed 10) now owns `Voice mode`. Preserve every shortcut, process-targeting rule, verification path, wheel polarity, and debounce interval.

**Guard:** Never implement this as a Corsair-only or Razer-only change, duplicate the Codex definition, alter the Voice Mode shortcut, change the accepted Reasoning Effort direction, or move any other Codex control. Keep the Voice Mode repair marker until Ethan physically accepts it.

**Verification:** The complete clean gate passed 644 Swift tests, six Musixmatch extension tests, five VS Code bridge tests, 17 Karabiner generator tests, generated-source freshness and lint, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene. The focused Codex-mode and wheel suites passed 99 tests after correcting one stale old-layout assertion, and the updated `configure-mice` skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.125 (build 131) is installed as main PID 97515 with executable SHA-256 `d86f65620afde85f32662bce5de097053d191d61d3db040675e023848e8daf42`, CDHash `b0db61cdfeb95c782da51f1ff8247a831cf7a16d`, Team ID `T34G959ZG8`, Accessibility granted, iCUE connected, and exclusive ownership of the mode-0600 Karabiner command socket. Its matching signed runtime supervisor runs as PID 97576 with executable SHA-256 `7c8414611e11f53dbccc084d8b448b618486b2c0a3c663fa161b115b287ea2e9` and CDHash `936e2df21cd5404de7a942a5d86d31d3892429eb`. The embedded iCUE SDK, live Agentic Mouse configuration, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `aa1499d88bd34875dc11f9a2873165d09cd2323c590126f425da4fd72e3189be`, and `efa14686651b1d551095294d17321f50247986cc757857245c63ba2dc8cd68d6`. The exact signed v1.0.124 bundle is preserved at `Rollbacks/AgenticMouse-v1.0.124-build130-before-v1.0.125.app`, and the replaced application is also recoverable from Trash. Literal physical acceptance remains Ethan-owned: in Codex mode on each mouse, verify cell 4 arms Reasoning Effort + Wheel and cell 12 invokes Voice Mode.

## 2026-08-24 — Turn the Default YouTube action into a five-second held-wheel scrubber

**Trigger:** Ethan wanted the existing top-level YouTube button to behave like a video timeline wheel: hold it, ratchet forward or backward, and move exactly five seconds per physical detent.

**Finding:** Physical cell 6 already had a strict cross-device semantic position and the app already reconstructed phase-free mouse ratchets. Replacing that path with browser keyboard events would lose background targeting and duplicate the VoiceInk bridge. The safe extension is one source-specific Karabiner press/release lifecycle, the existing app event tap, and two fixed no-payload bridge notifications.

**Fix:** Default physical cell 6 (Corsair printed 6 / Razer printed 4) now arms `youtubeScrub`. Wheel up/forward emits `com.ethansk.agenticmouse.youtube.seekForwardFiveSeconds`; wheel down/back emits the existing backward notification. Both use the fixed 80 ms leading-edge duplicate-burst filter, accept an immediate reversal, update only an already-visible Default legend, and remain inert while the session is locked. The bridge accepts only exact `+5` or `-5`, preserves its PiP/active/audible/recent target order, changes only the selected video timeline, clamps within zero and finite duration, and never focuses Chrome or changes play state.

**Guard:** Keep the action on canonical physical cell 6 for both mice and every ordinary app context. Do not turn it back into a release-only command, accept arbitrary seek values, synthesize Chrome shortcuts, remove duplicate-ratchet protection, or auto-show the legend from wheel feedback. A bridge-down ratchet remains edge-triggered and must be dropped rather than replayed later.

**Verification:** The complete repository gate passed 644 Swift tests plus all extension, bridge, generator, packaging, supervisor, shell, generated-freshness, and diff checks. Developer-ID-signed Agentic Mouse v1.0.124 (build 130) is installed at `/Applications/AgenticMouse.app`; its matching ServiceManagement runtime supervisor is enabled and running. The live selected Karabiner profile contains exact press/release `youtubeScrub` routes for Corsair keypad 6 and Razer key 4, while its three non-Agentic rules remain canonical-equal to the rollback. The embedded iCUE SDK and live Agentic Mouse configuration remain byte-identical. The updated Developer-ID VoiceInk bridge helper and native host are installed, the exact unpacked extension was reloaded, and Chrome reconnected to the new host. Literal physical acceptance remains Ethan-owned: on each mouse, hold the top-level button and verify one wheel-up detent seeks +5 seconds and one wheel-down detent seeks -5 seconds without changing Chrome focus or playback state.

## 2026-08-24 — Promote YouTube rewind to Default and move Intelligence on Demand into Utility

**Trigger:** Ethan uses the background YouTube five-second rewind much more often than Codex's global Intelligence on Demand window and asked to exchange their existing controls.

**Fix:** Keep one shared canonical map across both exact mice: top-level physical cell 6 (Corsair printed 6 / Razer printed 4) now sends one source-specific release command that asks the existing VoiceInk bridge to rewind the selected YouTube target without focusing Chrome. Utility physical cell 8 (printed 8 on both mice) now opens Intelligence on Demand through one complete hardware-shaped left-Option + Space lifecycle.

**Guard:** Swap semantic ownership, HUD copy, source actions, generated exact-device bindings, public documentation, tests, and durable mouse guidance together. Do not change the physical-cell crosswalk, iCUE transports, DPI, lighting, VoiceInk target selection, or either mouse independently. Top-level rewind must remain release-only and must not auto-show a hidden legend. Utility Intelligence on Demand must remain behind the unlocked-session and Accessibility gates.

**Verification:** Focused mapping, command-decoder, Utility executor, and HUD tests passed 111 Swift tests. The complete clean gate passed 637 Swift tests, six Musixmatch extension tests, five VS Code bridge tests, 17 Karabiner generator tests, generated-source freshness and lint, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene; the updated `configure-mice` skill passed `quick_validate.py`. The signed-candidate workflow advanced and installed Developer-ID-signed Agentic Mouse v1.0.122 (build 128) as main PID 49457 with executable SHA-256 `b104d0caa3aecb67d1299b8aa367252da0d9858a237ad95fe8449f21059eb1a6`, CDHash `9b7a04b62f6dafc85637873ede2b126b62d50305`, Team ID `T34G959ZG8`, Accessibility granted, iCUE connected, and exclusive ownership of the mode-0600 Karabiner command socket. Its matching signed runtime supervisor runs as PID 49484 with executable SHA-256 `7ded3a5f4dca84b4cecb0a880ebb05addc12d0b3469b7e4ca5a586a80039f211` and CDHash `f409d3171d43db3bf1f01dedfd31f4cd474b09a4`. The embedded iCUE SDK and live Agentic Mouse configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe` and `aa1499d88bd34875dc11f9a2873165d09cd2323c590126f425da4fd72e3189be`. The live Karabiner SHA-256 intentionally changed from `6d7fa44a06bcf7c060e61ff513ceecadc1dd7d90b2a66f3ac25e9dfb612c44d6` to `a35400421e750d888f7ff440a5b236e84cdfa34a7c3022c778f3321179d95ce6`; read-back proves all three non-Agentic rules stayed byte-equivalent and Corsair `keypad_6` plus Razer printed `4` both emit the strict cell-6 rewind command only after release. The exact prior app and Karabiner file are preserved in `Rollbacks/`. A supervised relaunch intentionally remains fail-closed until the first real unlocked-session input; do not replace that real-input proof with synthetic testing. Literal physical acceptance remains Ethan-owned: on each mouse, press top-level physical cell 6 and confirm the selected YouTube video rewinds five seconds without Chrome focus changing, then enter Utility and press physical cell 8 to confirm Intelligence on Demand opens once.

## 2026-08-24 — Promote Copy/Paste to Default and move Spaces into Utility

**Trigger:** Ethan uses Copy/Paste substantially more often than Space switching and asked to exchange their existing held-wheel controls.

**Fix:** Keep one shared canonical map across both exact mice: top-level physical cell 1 (Corsair printed 1 / Razer printed 3) now owns `Copy / Paste + Wheel`, while Utility physical cell 3 (Corsair printed 3 / Razer printed 1) owns `Spaces + Wheel`. Preserve the accepted physical wheel polarity: up pastes or moves one Space right; down copies or moves one Space left. Copy/Paste keeps discrete-ratchet debouncing, while Spaces retains its one-action-per-hold latch and observed active-Space feedback inside the visible Utility HUD.

**Guard:** Swap semantic ownership, HUD copy, source actions, generated exact-device bindings, docs, and tests together. Do not change iCUE neutral transports, DPI, lighting, the physical-cell crosswalk, or either mouse independently. A top-level clipboard failure must not open a hidden mode HUD, and Utility Spaces must never bypass its active mode lease.

**Verification:** The focused mapping and wheel suites passed 117 Swift tests plus 16 generator tests before the clean gate. The complete clean gate then passed 634 Swift tests, six Musixmatch extension tests, five VS Code bridge tests, 17 Karabiner generator tests, generated-source freshness and lint, packaging/version contracts, runtime-supervisor packaging, and shell syntax; the updated `configure-mice` skill passed `quick_validate.py`. The signed-candidate workflow advanced and recorded Developer-ID-signed Agentic Mouse v1.0.121 (build 127), followed by a passing post-bump version test and packaging contract. It is installed as main PID 75955 with executable SHA-256 `98d1b43436c676ca87e1c112d3170fb0341c5ce06acac97611e474427809f8c2`, CDHash `8b7c1ad245959ab270017bd44e036d7c68940671`, Team ID `T34G959ZG8`, Accessibility granted, iCUE connected, and exclusive ownership of the mode-0600 Karabiner command socket. Its matching signed runtime supervisor runs as PID 75991 with executable SHA-256 `6110b015746351627efae663e62f98d4b7d34f1139d57b525361c9eb65ba64bf` and CDHash `47b4563575b3f93a054710a4e7c918e63ef9b74c`. The embedded iCUE SDK and live Agentic Mouse configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe` and `aa1499d88bd34875dc11f9a2873165d09cd2323c590126f425da4fd72e3189be`. The live Karabiner SHA-256 intentionally changed from `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd` to `6d7fa44a06bcf7c060e61ff513ceecadc1dd7d90b2a66f3ac25e9dfb612c44d6`; independent read-back proves all three non-Agentic rules stayed byte-equivalent and both exact-device base cells now send the `clipboard` control. The exact prior app and Karabiner file are preserved in `Rollbacks/`. Literal physical acceptance remains Ethan-owned: on each mouse, hold top-level physical cell 1 and ratchet up/down for Paste/Copy, then enter Utility, hold physical cell 3, and ratchet up/down for one Space right/left before release.

## 2026-08-24 — Rebuild Codex Voice and queued Edit at observable boundaries

**Trigger:** Voice Mode and Edit Queued Message still did nothing in the current ChatGPT 26.818.61809 build, despite earlier transports reporting successful dispatch.

**Cause:** Voice still used a Dvorak-translated key code through System Events even though `realtimeVoice` is an OS-global Electron/Carbon accelerator registered by ANSI key position; it also had no Codex-owned completion observation. Edit repeatedly reread multiple cross-process AX attributes for thousands of Chromium nodes on the main actor, then searched the same large tree up to fifteen more times. A small popover window could sit beyond the shared traversal cap, making a visible queued row look absent while the HUD had no useful diagnostic stage. The first repair still compared a small focused-window Voice preflight against a broader postflight, treated capped scans like authoritative absence, and could spend the whole Edit budget reading irrelevant AX attributes before opening the row menu.

**Fix:** Deliver Voice Mode as one complete hardware-shaped Control-down, Shift-down, physical ANSI V (key code 9) down/up, Shift-up, Control-up lifecycle while ChatGPT is frontmost. Use the same finite AX scope, messaging timeout, element cap, and wall-clock budget before and after dispatch; inspect every non-minimized top-level Codex window for exact enabled pressable inactive controls (`Start voice chat`, `Start new voice chat`, `Resume voice chat`, `Open voice chat`) versus exact `Stop voice chat`, and confirm only an observed state transition from two complete scans. For Edit, de-duplicate nodes when enqueuing them, require the initial focused-window traversal to complete, read role and exact relevant labels before requesting frame/enabled/actions, reserve a separate popup budget, choose only the visually highest unambiguous exact Steer/Delete/Actions row, prefer an exact newly exposed `Edit message` control from a 6,000-element focused-window search, and search every other top-level window independently with a 1,500-element budget. Only one Edit journey may run; nested attempts preserve the original mouse owner, and the journey rechecks input and Accessibility authority before each AXPress and after each main-run-loop yield. Lock, sleep, mode exit, and teardown cancel all delayed Voice, Pin, and Edit work. Log only counts, stages, roles, and frames—never queued text.

**Guard:** Preserve Ethan's keyboard-shortcut file. Never read Codex AX state before the lock and Accessibility gates, compare unequal Voice scan scopes, treat a capped/cancelled traversal as an inactive state, claim Voice success from event posting, or claim Edit success from opening the actions menu. Never broaden Edit to substring labels, arbitrary menu items, coordinate clicks, ambiguous popovers, or a background queued row. Do not re-press an actions menu blindly when no exact Edit item was observed. Keep both repair markers until Ethan physically accepts the signed build on each mouse.

**Verification:** Two Claude Opus 5 review passes examined the actual implementation. Their final three blockers—nested Edit ownership, unequal Voice observation scopes, and eager Edit snapshot cost—were repaired before release. The complete clean gate passed 634 Swift tests, six Musixmatch extension tests, five VS Code bridge tests, 17 Karabiner generator tests, generated-source parity and lint, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene; the updated `configure-mice` skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.119 (build 125) is installed as main PID 92370 with executable SHA-256 `5aecbdafb0f1d38c40438e8a47a98d6a596b7748dc37af34534dc23260a4daed`, CDHash `433eeb6571706f7248a668e0c4441caacfc5b1ac`, Team ID `T34G959ZG8`, Accessibility granted, iCUE connected, and exclusive ownership of the 0600 Karabiner command socket. Its enabled signed runtime supervisor runs as PID 92419 with executable SHA-256 `bdd53baf7d605e214eddbaa784d9aa40ad78dc4229b8c3e444ef14b66e65c942` and CDHash `57bcad36a999380286fdb682febed04dfe8408e0`. The embedded iCUE SDK, live Agentic Mouse configuration, live Karabiner configuration, and VS Code keybindings remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `aa1499d88bd34875dc11f9a2873165d09cd2323c590126f425da4fd72e3189be`, `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`, and `8d23c9fae7eb21104cda9203be4b95e2cebacfb08e708f806977dcb3720b60aa`. The exact signed v1.0.118 bundle is preserved at `Rollbacks/AgenticMouse-v1.0.118-build124-before-v1.0.119.app`. Literal physical Voice, Edit, Claude, and Quit App acceptance remains Ethan-owned.

## 2026-08-24 — Make Extra Utilities Quit App deliberate and one-shot

**Trigger:** Ethan restored the previously removed Quit App utility and explicitly placed it in Extra Utilities.

**Cause:** A repeatable Command-Q control can accidentally quit a chain of applications because the frontmost target changes after each successful quit. A force-quit or Agentic-Mouse-target fallback would also violate the normal app save/confirmation boundary.

**Fix:** Put Quit App on canonical physical cell 9 inside Extra Utilities. Resolve the actual frontmost external application at press time, exclude both Agentic Mouse's main and runtime-supervisor bundle identifiers plus the current PID, and deliver one normal Command-Q directly to that PID. Latch the request once per Extra Utilities visit; leaving and re-entering deliberately resets it. Reject an unexpected native Karabiner route before dispatch and without burning the retry latch.

**Guard:** Keep universal cell 10 as Exit and Organize Windows on cell 1. Never force quit, bypass save dialogs, activate a target, quit either Agentic Mouse process, accept a mismatched route as success, or emit a second quit during the same page visit. Source and installed tests do not replace literal physical acceptance on both mice.

## 2026-08-24 — Specialize Claude from observed Claude controls, not copied Codex commands

**Trigger:** Claude mode's generic starter map contained actions that did not match Claude, while Ethan wanted useful equivalents to Codex wherever Claude genuinely supports them.

**Cause:** Treating Claude as another generic browser-like Electron app made the HUD look populated but did not preserve Claude's actual menu accelerators or UI controls. A visually corresponding Codex card is not proof that Claude exposes the same command.

**Fix:** Give Claude one specialized definition shared by automatic and manual app-specific journeys. Keep Codex muscle-memory positions for Voice Mode, New Chat, Voice Mic, and Enter only where an equivalent is intended; use Claude's observed native Settings, New Conversation, Reload, Previous Tab, and Next Tab shortcuts plus exact enabled pressable Search, Sidebar, Voice, and Microphone Accessibility labels. Traverse only Claude's focused window through an index-based, identity-de-duplicated queue with a finite AX messaging timeout. Broad, missing, or ambiguous Accessibility matches fail closed and the failure message interpolates the real action title.

**Guard:** Preserve exits on physical cells 2 and 10 and keep both journeys on one source of truth. Never invent a Claude keybinding, reuse a Codex command identifier, or call an AXPress physically accepted until Ethan verifies the installed control.

## 2026-08-24 — Align equivalent Safari and Chrome actions without dropping Safari controls

**Trigger:** Ethan asked for Safari's app-specific buttons to occupy the corresponding Chrome positions wherever that made sense, while preserving Safari functionality.

**Cause:** Safari still inherited the generic Firefox/Opera browser grid. Its six Chrome-equivalent actions were scattered across different cells, and the recent Safari-only Web Inspector action occupied cell 12 even though Chrome already established DevTools on cell 3.

**Fix:** Give Safari one explicit `StandardAppMode` grid. Align Close Tab / DevTools / New Tab / Reload / Reopen Tab / Find Page with Chrome cells 1/3/5/6/11/12. Keep Safari's separate Previous/Next Tab controls on 4/7 and move Back/Forward to the remaining cells 8/9. Preserve cells 2 and 10 as Exit, every existing shortcut, the automatic/manual shared definition, and Firefox/Opera's original Downloads grids.

**Guard:** Align only genuinely corresponding actions. Do not delete Safari-only navigation, copy Chrome's YouTube-specific controls, duplicate the default Back/Forward transport as a new Chrome shortcut, alter iCUE/Karabiner/device transports, or create separate automatic and manual Safari maps. Web Inspector remains Option-Command-I dispatched to the running Safari PID; posting is not physical confirmation.

**Verification:** An independent OpenAI agent inspected the live Chrome/Safari definitions, durable rules, dispatcher, and tests and reached the same permutation; it found no safer higher-alignment pure reorder. Focused tests pin the complete ten-action Safari grid, every preserved key code/modifier, both printed mouse projections, both exits, the automatic/manual shared definition, exact Option-Command-I on cell 3, and Firefox/Opera isolation. The complete clean gate passed 610 Swift tests, six Musixmatch extension tests, five VS Code bridge tests, 17 Karabiner generator tests, generated-source freshness/parity, both Karabiner lints, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene; the updated `configure-mice` skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.117 (build 123) is installed as main PID 17878 with executable SHA-256 `936f4532922b0bd294a5b0598120abdb1be04b5dafea5e41d4736c32e9f11686`, CDHash `e22a7cebd844fc317dca606a541bb6fd6265ee61`, Team ID `T34G959ZG8`, Accessibility trust, exclusive ownership of the 0600 Karabiner command socket, iCUE connected, and the embedded iCUE SDK preserved at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`. Its signed runtime supervisor is enabled and running as PID 17928 with executable SHA-256 `595fed2832138b78022bf55c8bff9431e13cf8649c1544625166a4163b696fd8`, CDHash `442664f2e4e7b502b499ce0cc91ae36d1592b601`, and Service Management parent build 123. The live Agentic Mouse config, Karabiner configuration, and VS Code keybindings remain byte-identical at SHA-256 `aa1499d88bd34875dc11f9a2873165d09cd2323c590126f425da4fd72e3189be`, `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`, and `8d23c9fae7eb21104cda9203be4b95e2cebacfb08e708f806977dcb3720b60aa`. The exact signed v1.0.116 bundle remains as rollback. Literal physical acceptance remains: exercise all ten Safari actions on each mouse through automatic Safari mode, sample the same page through Choose App → Safari, and confirm cells 2/10 exit without Safari losing focus or any action disappearing.

## 2026-08-24 — Tune Horizontal Scroll magnitude independently of ratchet filtering

**Trigger:** Ethan physically reported that Horizontal Scroll was much too slow in VS Code, Chrome, Firefox, and the AIMVS Timeline.

**Cause:** Every accepted physical detent emitted exactly one non-precise horizontal Quartz line unit. Chromium turns that into roughly 40 CSS pixels while Firefox derives line travel from local font metrics, so the same single-line output felt slow everywhere and particularly slow on the AIMVS Timeline. The separate 80 ms leading-edge filter correctly suppresses duplicate raw events from one physical detent and was not itself a movement-magnitude control.

**Fix:** Add the bounded `input.horizontalScrollLinesPerRatchet` setting with a normal-fast default of 4 and supported range 1...12. Multiply only the accepted axis-2 line delta by that setting, after the state machine has reconstructed the physical ratchet. Preserve the accepted direction and every unarmed or phased wheel/trackpad pass-through rule.

**Guard:** Never speed Horizontal Scroll by removing the discrete-ratchet filter, accepting momentum-phased input, changing physical direction, adding an AIMVS-only multiplier, or altering iCUE, DPI, or Karabiner mappings. Sanitize unsafe configured magnitudes back to 4, fail closed if an unsanitized value reaches the emitter, and pin both output magnitude and unchanged ratchet cadence in tests. Installation proves the configuration and event path, not physical feel across applications; Ethan owns that final acceptance.

**Verification:** Three focused output tests proved the default/custom line magnitude, accepted polarity, and fail-closed bounds; nineteen configuration tests proved lenient older-file decode, 1...12 customization, sanitization, and round-trip behavior; and all 25 wheel-state tests proved the unchanged 80 ms discrete filter, immediate reversal, phased pass-through, source ownership, and teardown. The complete clean gate passed 610 Swift tests, six Musixmatch extension tests, five VS Code bridge tests, 17 Karabiner generator tests, generated-source freshness/parity, both Karabiner lints, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene. The updated `configure-mice` skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.116 (build 122) is installed as main PID 29451 with executable SHA-256 `32346d46b596a60dfbe05f8247ab91a0829b214e434bfd262f14658b22d10578`, CDHash `d9ff2c2f42a5259ac5e9f13aa16f56e9593ee259`, Team ID `T34G959ZG8`, Accessibility trust, exclusive ownership of the 0600 Karabiner command socket, and the embedded iCUE SDK loaded at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`. Its matching signed runtime supervisor is enabled and running as PID 29471 with executable SHA-256 `eecf34ce66eb78a261c2cb8908d24f4f79fcf325ae2f8bdcf4ed504a93c3d93d`, CDHash `311ff4a836f0e7b6a36775cbaa598b700270c5bd`, and Service Management parent build 122. The live 0600 configuration resolves `horizontalScrollLinesPerRatchet: 4` at SHA-256 `aa1499d88bd34875dc11f9a2873165d09cd2323c590126f425da4fd72e3189be`; the live Karabiner configuration and VS Code keybindings remain byte-identical at SHA-256 `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd` and `8d23c9fae7eb21104cda9203be4b95e2cebacfb08e708f806977dcb3720b60aa`. The exact signed v1.0.115 bundle and pre-setting config are preserved as rollback. Literal physical acceptance remains: hold top-level physical cell 4 on either mouse and compare deliberate ratchets in VS Code, Chrome, Firefox, and the AIMVS Timeline; confirm travel is normal-fast, direction is unchanged, each detent acts once, and ordinary wheel/trackpad input still passes through when unarmed.

## 2026-08-24 — Put Safari Web Inspector on shared app-specific cell 12

**Status:** The Web Inspector shortcut remains current, but the later Chrome-alignment entry above moves it from cell 12 to cell 3.

**Trigger:** Ethan asked Safari mode for a button that opens Safari developer tools.

**Cause:** Safari's data-driven browser starter grid already occupied every non-exit cell and used physical cell 12 for Downloads. The generic browser template had no Safari-specific way to prefer Web Inspector without also changing Firefox and Opera.

**Fix:** Replace only Safari's cell-12 Downloads action with `Open DevTools` and send Safari's native Option-Command-I Web Inspector shortcut directly to the running Safari PID. Keep Firefox and Opera Downloads unchanged. Both automatic frontmost Safari mode and manual Choose App → Safari continue to resolve the same `StandardAppMode` definition.

**Guard:** Preserve app-child exits on cells 2 and 10, handle only the press phase, keep release inert, and do not add iCUE, Karabiner, device-specific, focus-changing, or page-extension routes. Developer features must already be enabled in Safari; successful event dispatch is not proof that Web Inspector appeared.

**Verification:** The focused shared-map test proved that Safari alone replaces cell-12 Downloads with `Open DevTools` while Firefox and Opera retain Downloads, and the dispatcher test proved the exact Option-Command-I PID-targeted key cycle. The complete v1.0.116 clean gate and signed install receipt are recorded in the Horizontal Scroll entry above. Safari 26.5.2 has both Develop-menu and WebKit developer-extras preferences enabled on this Mac. Literal physical acceptance remains: enter automatic frontmost Safari mode and manual Choose App → Safari, press physical cell 12, and confirm Web Inspector opens without Agentic Mouse activating a different app.

## 2026-08-24 — Preserve native Screenshot saving while adding copy and double-press paste

**Trigger:** Ethan wanted the existing selected-area Screenshot to keep saving normally, also place the captured image on the clipboard, and rapid-double-paste it from the same side button. He also required the Default HUD card to expose the added behavior.

**Cause:** The accepted physical-cell-3 path intentionally emitted exact Shift-Command-4 and observed only mouse-up or Escape. That correctly preserved macOS's configured destination, sound, and floating thumbnail, but Agentic Mouse never identified the saved file, never owned a screenshot pasteboard item, and classified every later idle press as another capture.

**Fix:** Preserve exact Shift-Command-4 behind a bounded 280 ms same-source single/double classifier. Snapshot only macOS's configured Screenshot directory before capture; after selection completes, poll for one new image, prefer macOS screenshot metadata, fail closed on ambiguity, and copy the saved image as its native type plus TIFF. Remember only the resulting pasteboard change count. A rapid same-source double press sends one hardware-shaped Command-V while that item is still current; an external clipboard change makes the action unavailable instead of restoring stale data. A press while the crosshair is active still sends Escape immediately, and a double press while the native save is pending may defer only the paste until copying succeeds.

**Guard:** Do not replace the native flow with `screencapture`, take a second screenshot, request Screen & System Audio Recording, infer a file from its localized name alone, choose among ambiguous new images, restore a stale clipboard item, or combine presses from opposite mice into one double gesture. Lock, screen sleep, app teardown, and reload cancel the classifier, watcher, deferred paste, and exact capture. Keep the Default card truthful as `Screenshot`, `Cancel screenshot`, `Copying screenshot…`, or `Screenshot · 2× Paste`.

**Verification:** The final focused Screenshot suite passed 16/16 tests, including delayed single press, bounded same-source double recognition, cross-source isolation, native capture/cancel lifecycles, unique-file copying, deferred paste, pasteboard-ownership loss, ambiguity timeout, lock gating, cancellation, and all four truthful HUD states. The complete clean gate passed 602 Swift tests, six Musixmatch extension tests, five VS Code bridge tests, 17 Karabiner generator tests, generated-source freshness/parity, both Karabiner lints, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene; the updated `configure-mice` skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.115 (build 121) is installed as main PID 4298 with executable SHA-256 `6a188aac0d401bc671756d08630208c48079ac908c874767284d297b503e6e8d`, CDHash `011ffe91e3c87988d2181506736456028efc6da7`, Team ID `T34G959ZG8`, Accessibility trust, exclusive command-socket ownership, and the embedded iCUE SDK loaded. Its matching signed runtime supervisor is enabled and running as PID 4323 with executable SHA-256 `16f88f93240998cfca4023c183f5b7657299791634edcc005a124532f40739c7`, CDHash `34679acc59cd50f07c57ec836018041c0fde68f8`, and Service Management parent build 121. The embedded iCUE SDK, live Agentic Mouse config, live Karabiner configuration, and VS Code keybindings remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`, and `8d23c9fae7eb21104cda9203be4b95e2cebacfb08e708f806977dcb3720b60aa`. The exact signed v1.0.114 bundle is preserved at `Rollbacks/AgenticMouse-v1.0.114-build120-before-v1.0.115.app`. Literal physical acceptance remains: on each mouse, press Screenshot once, select an area, verify the file saves and the HUD reaches `Screenshot · 2× Paste`, rapidly double-press to paste it once into a safe image target, and confirm one press still cancels an active screenshot crosshair.

## 2026-08-24 — Give Codex Chat History one step per physical ratchet

**Trigger:** Ethan physically confirmed that Codex Chat History works, then reported that consecutive same-direction ratchets were being treated like one continuing action. He asked for every ratchet to move exactly one chat up or down.

**Cause:** Chat History shared Reasoning Effort's sliding 150 ms quiet-gap coalescer. Every suppressed same-direction raw event restarted that gap, so a sequence of physical detents without a full 150 ms silence could collapse into one semantic history step.

**Fix:** Keep Chat History's accepted Option-Command-Left/Right transport and polarity unchanged. Give Chat History alone a fixed 80 ms leading-edge duplicate-burst filter: duplicate raw events from one detent are suppressed, but suppression does not extend the window, so each later physical ratchet can dispatch one history step. Keep Reasoning Effort and VS Code Cursor History on their sliding 150 ms quiet-gap reconstruction.

**Guard:** Do not globally change held-wheel cadence, reverse Chat History, alter Codex shortcuts, or touch iCUE and Karabiner for this repair. Pin the fixed policy in tests, prove a suppressed duplicate does not restart the window, and preserve immediate reversal. Installation is not physical acceptance of the revised cadence; test several same-direction ratchets during one hold and confirm each moves exactly one chat before clearing the outstanding check.

**Verification:** The focused wheel suite passed 25 tests, including the fixed 80 ms Chat History policy, a suppressed duplicate that does not restart the window, a later same-direction ratchet without a quiet gap, immediate reversal, and unchanged Reasoning Effort reconstruction. The complete clean gate passed 594 Swift tests, six Musixmatch extension tests, five VS Code bridge tests, 17 Karabiner generator tests, generated-source freshness/parity, both Karabiner JSON lints, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene; the updated `configure-mice` skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.114 (build 120) is installed as main PID 4568 with executable SHA-256 `5e559bd998963cd27f3bccc8feddac89b8cbc50115a34cdb323f6321be63bedf`, CDHash `9dc29771106fe8bab459efb5d06a7392b0c005d2`, Team ID `T34G959ZG8`, Accessibility granted, iCUE connected, and exclusive ownership of the 0600 Karabiner command socket. Its matching signed runtime supervisor is enabled and running as PID 4584 with executable SHA-256 `9317197e178b38b2e30f469b295937ca28efe6caabb9ddb4eed7ef449ebe196f`, CDHash `78a19be21412116a93270170a5ac8430374572e5`, and Service Management parent build 120. The embedded iCUE SDK, live Agentic Mouse config, live Karabiner configuration, and VS Code keybindings remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`, and `8d23c9fae7eb21104cda9203be4b95e2cebacfb08e708f806977dcb3720b60aa`. The exact signed v1.0.113 bundle is preserved in the task rollback directory. Literal physical acceptance remains: enter Codex mode, hold physical cell 11, use several consecutive same-direction ratchets, and verify each detent moves exactly one chat before release restores ordinary scrolling.

## 2026-08-24 — Distinguish physical wheel motion from normalized Quartz sign

**Trigger:** Ethan physically tested Codex `Reasoning Effort + Wheel` and reported that its increase/decrease directions were reversed.

**Cause:** The Reasoning Effort resolver treated `WheelChordDirection.up` as physical wheel-up. That enum names the normalized Quartz primary-axis sign. On Ethan's accepted Corsair and Razer wheel routes, the physical upward ratchet reaches the resolver as `.down`, so the direct mapping reversed the action Ethan felt.

**Fix:** Keep the user-facing contract intuitive: physical wheel up increases Reasoning Effort through the existing Hyper-F18 binding and physical wheel down decreases it through Hyper-F19. Implement that local conversion as normalized `.down -> increase` and `.up -> decrease`. Keep Chat History and every other wheel family unchanged because each has its own physically established polarity.

**Guard:** Never derive HUD or semantic direction from the `WheelChordDirection` case name without checking the control's physical contract. Pin the raw normalized input-to-action mapping and the resulting footer title in focused tests. Do not globally rename or flip `WheelChordDirection` to correct one family, and do not alter iCUE, Karabiner, or Codex's keyboard shortcuts for this fix. An installed build still needs one literal physical up/down check before the polarity is accepted end to end.

**Verification:** The focused 24-test wheel suite passed, including normalized `.down -> increase`, `.up -> decrease`, truthful footer copy, unchanged Chat History polarity, ratchet coalescing, and immediate reversal. The complete clean gate passed 593 Swift tests, six Musixmatch extension tests, five VS Code bridge tests, 17 Karabiner generator tests, generated-source freshness/parity, both Karabiner JSON lints, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene. The updated `configure-mice` skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.113 (build 119) is installed as main PID 68431 with executable SHA-256 `fd22be74b75fa29c0cde4c2506bb622fb85ca27b46b5245702d62eaccea3d502`, CDHash `7a0dccf4ad1e74aa3cbaaf507fee6556580289fa`, Team ID `T34G959ZG8`, Accessibility granted, iCUE connected, exclusive command-socket ownership, and its matching runtime supervisor enabled and running as PID 68439. The embedded iCUE SDK, live Agentic Mouse config, live Karabiner configuration, and VS Code keybindings remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`, and `8d23c9fae7eb21104cda9203be4b95e2cebacfb08e708f806977dcb3720b60aa`. The exact signed v1.0.112 bundle is preserved in the task rollback directory. Literal physical acceptance remains: after real local input clears the intentional post-launch fail-closed gate, enter Codex mode, hold physical cell 12, ratchet upward once for one effort increase and downward once for one decrease, then confirm separated repeat ratchets and release restore ordinary scrolling.

## 2026-08-24 — Execute VS Code Cursor History through the command API

**Trigger:** Ethan physically tested signed Agentic Mouse v1.0.111 and reported that Cursor History was still exactly as broken as before. He asked to do the action more directly inside VS Code.

**Cause:** Both key-based repairs stopped at the wrong proof boundary. A complete target-PID Quartz modifier lifecycle can be constructed and posted successfully while Electron still does not resolve the intended VS Code keybinding. The later Hyper-key experiment was also unsuitable: it would have modified Ethan's normal keyboard shortcuts, and Control-Left/Right overlaps macOS Spaces. While investigating with two isolated VS Code processes, macOS also treated the identical bundle identifiers as one application for activation, which made System Events focus tests address the original process rather than the intended isolated one.

**Fix:** Bundle a minimal Agentic Mouse VS Code Bridge extension with one exact URI authority and only two Cursor History routes. Agentic Mouse requires an unlocked session plus a running, frontmost VS Code and opens `vscode://ethansk.agentic-mouse-vscode-bridge/cursor-history/back|forward` without activation. The extension rejects every other route, rejects a non-focused receiving window, and calls `vscode.commands.executeCommand('workbench.action.navigateBack'|'workbench.action.navigateForward')` directly. Wheel down remains Back, wheel up remains Forward, and the existing sliding 150 ms ratchet reconstruction remains the input boundary. Ethan's user keybindings are untouched.

**Guard:** Never restore a synthetic-key fallback for VS Code Cursor History or call a successful `CGEvent.postToPid` proof of editor navigation. Test the URI allow-list, lock/frontmost/focus failures, and unknown-route rejection. Then run a real VS Code extension-host test that opens A, B, A and proves Back changes A to B and Forward changes B to A through the actual built-in commands. A normal VS Code extension install and literal physical cell-6 wheel test remain separate evidence boundaries.

**Verification:** Five Node route tests, five Swift bridge tests, twenty application-shortcut tests, and twenty-four wheel tests passed. A real VS Code 1.133 extension-test host loaded the development extension, executed the handler against the built-in Back and Forward commands, observed A to B to A editor transitions, and exited zero. The complete clean gate passed 593 Swift tests, six Musixmatch extension tests, five VS Code bridge tests, 17 Karabiner generator tests, generated-source freshness/parity, both Karabiner JSON lints, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene. The `configure-mice` skill passed `quick_validate.py`. The bridge VSIX 0.1.0 is installed in VS Code's normal extension directory, but the live VS Code process predates that installation and did not dynamically activate it; a safe user-owned VS Code reload remains required rather than interrupting the active editor. Developer-ID-signed Agentic Mouse v1.0.112 (build 118) is installed as main PID 33663 with executable SHA-256 `de4479eaf04482d071c160b19252fc1de446067b1b37bf4beb771a1abdba9b21`, CDHash `4fb756b0427b975631caecf863fdf6a203471bf4`, Team ID `T34G959ZG8`, Accessibility trust, exclusive command-socket ownership, iCUE connected, and the matching signed runtime supervisor enabled and running as PID 33694. The embedded iCUE SDK, live Agentic Mouse config, live Karabiner configuration, and Ethan's restored VS Code keybindings remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`, and `8d23c9fae7eb21104cda9203be4b95e2cebacfb08e708f806977dcb3720b60aa`. The exact signed v1.0.111 bundle is preserved in the task rollback directory. Literal physical acceptance remains: after reloading VS Code, enter VS Code mode, hold physical cell 6, ratchet down once for exactly one Back, ratchet up once for exactly one Forward, then use separated repeat ratchets and confirm ordinary scrolling resumes on release.

## 2026-08-23 — Preserve the full modifier lifecycle for VS Code Cursor History

**Status:** Superseded and physically disproven by the direct VS Code command-API route above. The wheel polarity and 150 ms ratchet reconstruction remain current; the target-PID keyboard transport does not.

**Trigger:** Ethan physically retested installed v1.0.110 and confirmed the prior Cursor History repair was still incomplete: only Back worked, and it arrived from the wheel direction intended for Forward.

**Cause:** The direction classifier and physical ANSI key positions were already correct. The remaining fault was the target-PID shortcut transport: it posted only the action key down/up with Control-Shift attached as flags. Electron did not observe a real Shift modifier transition, so the intended Control-Shift-Minus Forward chord degraded into Back while the separate Back chord did not resolve reliably. The earlier Dvorak-only diagnosis below was therefore incomplete.

**Fix:** Keep wheel up as Forward and wheel down as Back. Build one complete hardware-shaped modifier lifecycle for each VS Code Cursor History ratchet: Control down, optional Shift down, action key down/up, then modifier releases in reverse order. Post that entire lifecycle to the resolved VS Code PID so a manually selected VS Code page cannot leak the shortcut into another frontmost app. Preserve physical ANSI Quote for Ethan's Control-Apostrophe Back binding and physical ANSI Minus for VS Code's Control-Shift-Minus Forward binding. Do not alter his VS Code keybindings, iCUE profile, Karabiner rules, or another held-wheel family.

**Guard:** A multi-modifier app shortcut is not proven by attaching flags only to the action key, and successful `CGEvent.postToPid` creation is not proof that Electron accepted it. Pin the exact Control-only and Control-Shift event sequences in tests, keep the target PID and locked-session/Accessibility gates, preserve the 150 ms ratchet coalescer, and require literal physical Back/Forward acceptance after installation.

**Verification:** Focused verification passed 24 application-shortcut tests and 24 wheel-state tests, including exact modifier order, flags, timing, process targeting, direction mapping, coalescing, and fail-closed lock/Accessibility paths. The complete clean gate passed 592 Swift tests, six extension tests, 17 Karabiner generator tests, generated-source freshness/parity, both generated Karabiner JSON lints, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene; the updated `configure-mice` skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.111 (build 117) is installed as main PID 4846 with executable SHA-256 `9a6b72d9471f6a5452deb867ea3e0c72564fd7f050e711b1f0177c2e83318a40`, CDHash `545f1a2bd98e62d93f9c5f614eaffc4046731bee`, Team ID `T34G959ZG8`, Accessibility trust, exclusive command-socket ownership, and the embedded iCUE SDK loaded. Its matching signed runtime supervisor is running as PID 4863 with executable SHA-256 `ce7f07e29fb3dac2193b1c55a4ba56664b73ef7ad72a3f3a99c1008346aa3a97`, CDHash `950a74e138865884503f96a86f06706557f20373`, and Service Management parent build 117. The embedded iCUE SDK, live Agentic Mouse config, live Karabiner configuration, VS Code keybindings, and aggregate iCUE profile state remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`, `8d23c9fae7eb21104cda9203be4b95e2cebacfb08e708f806977dcb3720b60aa`, and `5089c37454fcd0d332dc3e60fd0085e30333d239825b46b3297b1d26dece8d6a`. The exact signed v1.0.110 bundle is retained in the task rollback directory. Literal physical acceptance remains: inside VS Code mode, hold physical cell 6, ratchet down once for exactly one Back, ratchet up once for exactly one Forward, use several deliberately separated ratchets without releasing, then release and confirm ordinary scrolling resumes.

## 2026-08-23 — Audit public claims against the installed system before publishing

**Trigger:** The public homepage and supporting documentation had drifted behind the installed Agentic Mouse build. Several visible button maps, the VoiceInk coalescing interval, keypad delivery method, Razer lighting description, and public-release wording no longer matched the source, generated rules, or physically verified boundaries.

**Fix:** Treat the installed signed app version, current Swift maps, generated Karabiner rules, live hardware record, and explicit physical-acceptance evidence as separate sources of truth. Correct every public surface together, including the interactive homepage, transport map, README, setup, architecture, limitations, mouse notes, and Karabiner guide. Clearly distinguish implemented, installed, physically accepted, and publicly downloadable states; the repository is source-available, but it currently has no signed or notarized public binary release.

**Guard:** Every mapping or transport change must re-audit `docs/script.js`, `docs/mouse-map.js`, `README.md`, `docs/MICE.md`, `docs/SETUP.md`, `docs/ARCHITECTURE.md`, `docs/LIMITATIONS.md`, and `Karabiner/README.md`. Never infer physical acceptance from tests or successful event posting, never present an experimental or retired transport as live, and rotate static-asset cache keys whenever published JavaScript or CSS changes.

**Verification:** Claude Opus 5 independently audited the public surfaces against current source and generated rules. The clean repository gate passed 589 Swift tests, six extension tests, 17 Karabiner generator tests, generated-source freshness and parity, both generated Karabiner JSON lints, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene. GitHub Pages built exact documentation commit `39aac3a6e926f3e2e03c5be5770d84cc2fca3c89`; live SHA-256 read-back matched the local `index.html`, `styles.css`, `script.js`, `mouse-map.html`, and `mouse-map.js` byte for byte. Personal-Chrome QA exercised all eleven current layers with 24 rendered cells each, both source views, the left-handed Razer arrow exception, desktop and 390-pixel mobile layouts, and both deployed pages with zero browser warnings or errors.

## 2026-08-23 — Consolidate Codex effort and chat navigation into held-wheel controls

**Status:** Superseded for Reasoning Effort polarity by the later 24 August physical-direction correction, and superseded for Chat History cadence by the one-step-per-ratchet correction above. The cell placement, Hyper-F18/F19 shortcuts, Chat History mapping, and Reasoning Effort's 150 ms ratchet reconstruction remain current.

**Trigger:** Ethan asked Reasoning Effort Up/Down to become one held-wheel Codex control and wanted the newly freed shared physical cell 11 to move backward or forward through Codex chats with Option-Command-Left/Right.

**Cause:** Codex mode spent two cells on separate immediate Reasoning Effort actions even though the shared wheel architecture already models bounded two-way controls. The freed cell had no semantic action, and routing it as an ordinary press would not preserve Ethan's established one-ratchet-per-step navigation convention.

**Fix:** Keep Reasoning Effort on shared physical cell 12 and resolve wheel up to the existing Hyper-F18 increase shortcut and wheel down to Hyper-F19 decrease. Put `Chat History + Wheel` on shared physical cell 11; wheel up sends Option-Command-Right to advance and wheel down sends Option-Command-Left to go back. Both controls use the same app-specific source ownership in automatic and manually chosen Codex mode, target the running Codex PID without activation, show direction-specific bottom-left HUD feedback, and coalesce a same-direction raw burst through a sliding 150 ms quiet gap while accepting immediate reversal.

**Guard:** Treat named Corsair/Razer cells as the shared canonical physical cell unless Ethan explicitly requests a hardware-specific divergence. Preserve Codex's existing keyboard shortcuts and the exact-device transport adapters; this change needs no iCUE or live Karabiner mutation. Clear each chord on release, app retarget, exit, lock, sleep, source loss, reload, and shutdown. Do not call event posting proof that Codex changed chat or effort state.

**Verification:** Focused mapping, wheel-state, and Codex-dispatch verification passed 106 tests. The complete clean gate passed 589 Swift tests, six extension tests, 17 Karabiner generator tests, generated-source freshness/parity, both generated Karabiner JSON lints, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene. The updated `configure-mice` skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.110 (build 116) is installed as main PID 3781 with executable SHA-256 `71205c8056b5fa6e545ed3559f2603b58cfae864f65cd167e5a90f15d29e900e`, CDHash `2fa3fd04fd6bdf59de0c33ad4ab680b296608d5d`, Team ID `T34G959ZG8`, Accessibility trust, exclusive command-socket ownership, and the embedded iCUE SDK loaded. Its matching signed runtime supervisor is running as PID 3811 with executable SHA-256 `c6137edf6662ed2ba9b689b46196278460e11f2ba20e51cbc8473a2a20bfa05a`, CDHash `db29e9026c4a50db562f5bc188560a1819cc925e`, and Service Management parent build 116. The live menu reports `Modes: ready`, iCUE connected, Accessibility granted, and self-recovery enabled. The embedded iCUE SDK, live Agentic Mouse config, live Karabiner configuration, and VS Code keybindings remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`, and `8d23c9fae7eb21104cda9203be4b95e2cebacfb08e708f806977dcb3720b60aa`. The exact signed v1.0.109 bundle is retained in the task rollback directory. Literal physical acceptance remains: in Codex mode on each mouse, hold physical cell 12 and ratchet up/down once for effort increase/decrease, then hold physical cell 11 and ratchet up/down once for next/previous chat; use separated repeat ratchets, release, and confirm ordinary scrolling resumes.

## 2026-08-23 — Fix VS Code Cursor History key positions and ratchet reconstruction

**Status:** Superseded in part by the later modifier-lifecycle finding above. The physical ANSI positions and 150 ms ratchet coalescer remain correct; the claimed target-PID key-down/up transport was not sufficient for Electron.

**Trigger:** Ethan reported that `Cursor History + Wheel` in VS Code moved Back on physical wheel-up while physical wheel-down did nothing. He required down to go Back, up to go Forward, and every deliberate ratchet during one hold to cause exactly one jump.

**Cause:** The shared wheel classifier was not inverted. Cursor History alone passed VS Code's Control-Apostrophe Back and Control-Shift-Minus Forward bindings through the active-layout semantic-character resolver. Under `DVORAK - QWERTY CMD`, that produced the wrong physical `KeyboardEvent.code` positions for Electron/VS Code: the attempted Forward chord landed on Back, while the attempted Back chord landed on an unbound position. Its separate 80 ms leading-edge debounce also measured from the last dispatched action, so a long same-direction raw burst could outlive the window and dispatch twice from one physical notch.

**Fix:** Preserve the accepted shared physical direction contract: wheel down is Back and wheel up is Forward. Send VS Code Back as physical ANSI Quote plus Control and Forward as physical ANSI Minus plus Control-Shift through the bounded target-PID dispatcher; do not rewrite the user's keybindings. Keep terminal character delivery on its separate Dvorak semantic resolver. Give Cursor History alone a sliding 150 ms same-direction quiet gap: every suppressed raw event extends the gap, an intentional reversal remains immediate, and a later distinct ratchet in the same hold can dispatch again. Derive footer copy from the resolved history command.

**Guard:** Do not globally flip `WheelChordDirection`, change another accepted wheel family's polarity/cadence, or merge VS Code keybinding positions with terminal text semantics. A one-ratchet test must span longer than the original leading-edge window while every inter-event gap stays under 150 ms, then prove a later same-direction ratchet and immediate reverse ratchet both dispatch once. Release, lock, sleep, mode teardown, source loss, and automatic app retargeting retain their existing fail-closed clearing.

**Verification:** Claude Opus 5 independently inspected the wheel state machine, event monitor, VS Code shortcut resolver, app dispatcher, mode routing, live keybindings, project rules, and tests. Its physical-position diagnosis matched the exact asymmetric symptom. Focused verification passed 22 wheel tests, 21 application-shortcut tests, and 67 mode-routing tests. The complete clean gate passed 585 Swift tests, six extension tests, 17 Karabiner generator tests, generated-source freshness/parity, both generated Karabiner JSON lints, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene. The updated `configure-mice` skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.109 (build 115) is installed as main PID 37256 with executable SHA-256 `3586835967079ded48b2a7cbd10f4ee4fc34dbe3309a630d7d902242886b745c`, CDHash `bc6c6bf4975637e7f9138f76835384bc65a2f70e`, Team ID `T34G959ZG8`, Accessibility trust, exclusive command-socket ownership, and the embedded iCUE SDK loaded. Its matching signed runtime supervisor is running as PID 37279 with executable SHA-256 `178715a982e7d02e053aeaa672f938a52bf57713b926e68e3b8a02b38f4d13ac`, CDHash `c59680a2e1d0e9a89893ea56b2ecd38e28c9f143`, and Service Management parent build 115. The live menu reports iCUE connected, Accessibility granted, and self-recovery enabled. The embedded iCUE SDK, live Agentic Mouse config, live Karabiner configuration, and VS Code keybindings remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`, and `8d23c9fae7eb21104cda9203be4b95e2cebacfb08e708f806977dcb3720b60aa`. The exact signed v1.0.108 bundle is retained in the task rollback directory. Literal physical acceptance remains: inside VS Code mode, hold physical cell 6, ratchet down once for exactly one Back, ratchet up once for exactly one Forward, use several deliberately separated ratchets without releasing, then release and confirm ordinary scrolling resumes.

## 2026-08-23 — Show honest bottom-left results for every held-wheel action

**Trigger:** Ethan asked every hold-plus-wheel control, including Copy / Paste, to show bottom-left HUD feedback after the requested action so he can tell whether the ratchet actually did anything.

**Cause:** Wheel routing already counted and logged accepted detents, but visible feedback was inconsistent across action families. Several routes showed only failures, some showed no result, and the temporary Default trace described input detection rather than the actual dispatched action. Reusing the trace alone would also have violated the accepted ownership rule by risking a hidden top-level legend appearing during ordinary Spaces or Horizontal Scroll.

**Fix:** Give every actionable `WheelChordControl` direction one canonical action title and format one shared result footer containing that action plus the cumulative ratchet count. Publish feedback only after the real executor, dispatcher, notification bridge, or sequenced-key queue reports its outcome. Active Utility and app-specific modes use their own source HUD; top-level Spaces and Horizontal Scroll update only that source's already-visible persistent Default legend. Space actions first report dispatch and then replace it with an observed confirmation or a bounded no-change result when macOS exposes the active-Space notification.

**Guard:** Never call input detection action completion. Use informational `sent` wording for dispatch-only evidence, confirmed tone only for an observed destination state, and not-confirmed tone when posting or queueing fails or an expected observation is absent. Preserve the ignored App Exposé wheel-up direction as consumed but actionless. Feedback must neither open a hidden Default legend nor cross from one mouse's presenter into the other mouse's HUD.

**Verification:** The focused wheel suite passed 21 tests and the Default legend suite passed 15 tests. The complete clean gate passed 584 Swift tests, six extension tests, 17 Karabiner generator tests, generated-source freshness/parity, both generated Karabiner JSON lints, packaging/version contracts, runtime-supervisor packaging, and shell syntax. The updated `configure-mice` personal skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.108 (build 114) is installed as main PID 26007 with executable SHA-256 `043254a7a463b65a52ec2b796bbd188a791758e4fffba3459dafaa12320a5dfd`, CDHash `90fd9e2b840abe426000719bceaf31871d6e5c24`, Team ID `T34G959ZG8`, Accessibility trust, the embedded iCUE SDK mapped into the live process, and exclusive ownership of the 0600 Karabiner command socket. Its matching signed runtime supervisor is running as PID 26022 with executable SHA-256 `0ab7ad48ec3d6c773e9fbd2f260bb2b659674ad121823af8f41b6b23a6af929b`, CDHash `7b87107bd0e46392bf888fae84f37918dd0927ef`, and Service Management parent build 114. The live menu reports `Modes: ready`, iCUE connected, Accessibility granted, and self-recovery enabled. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. The exact prior signed v1.0.107 bundle is retained in the task rollback directory. Literal physical acceptance remains one Copy/Paste wheel gesture, one other Utility gesture, one app-specific wheel gesture, and top-level feedback with the Default legend first visible and then hidden; the hidden case must perform the action without opening the legend.

## 2026-08-23 — Combine VS Code Stage/Undo and add cursor-history wheel

**Trigger:** Ethan asked for VS Code child cell 9 to keep Stage + Next on one click and move exact Undo Stage onto its rapid double-click, freeing cell 6 for a held-wheel cursor-history control. Wheel down must go to the previous cursor location and wheel up to the next.

**Cause:** The child page still spent cells 9 and 6 on separate immediate Better Git actions. The existing app-specific wheel architecture supported Chrome and Spotify but not VS Code, and its live diagnostic label would show `B0` for every app-specific chord because those controls have neither a Default nor Utility cell. Ethan's installed VS Code keybindings also explicitly remove the default `Control-Minus` Back binding and replace it with semantic `Control-Apostrophe`; blindly posting the guessed chord would fail despite otherwise correct wheel routing.

**Historical v1.0.107 fix:** Keep the existing per-mouse 300 ms classifier and assign `VSCodeModeAction.stageAndNext` both F18 Stage + Next as its single and F16 exact Undo as its double. Canonical physical cell 6 now arms `Cursor History + Wheel` in both automatic and manually chosen VS Code mode. The first release attempted to resolve both VS Code history keys through the active layout. Every wheel control also gained a canonical diagnostic cell so app-specific traces show the real source-specific printed number instead of `B0`.

**Status:** The active-layout history-key assumption was disproven by Ethan's asymmetric v1.0.108 physical report and is superseded by the physical `KeyboardEvent.code` fix in the section above. The cell assignment, Stage/Undo classifier, PID targeting, diagnostic cell, and untouched user-keybindings boundary remain current.

**Guard:** Keep top-level cell 6 as global Option-Space and top-level cell 9 as Keys mode. Cancel a pending Stage + Next rather than emitting it when a matching second click converts the gesture to Undo. Arm cursor history only from exact VS Code child cell 6, preserve ordinary scrolling while unarmed, clear the chord on release and every existing teardown boundary, and disarm before automatic frontmost-app retargeting so a held VS Code control cannot act on another app. Do not rewrite VS Code settings; preserve the current section's explicit distinction between physical VS Code keybinding positions and semantic terminal characters.

**Verification:** Focused mapping, gesture, wheel-routing, and shortcut-dispatch tests passed 125 tests. The complete clean gate passed 581 Swift tests, six extension tests, 17 Karabiner generator tests, generated-source freshness/parity, both Karabiner JSON lints, packaging/version contracts, shell syntax, and diff hygiene. The updated `configure-mice` personal skill passed `quick_validate.py`. Developer-ID-signed Agentic Mouse v1.0.107 (build 113) is installed as main PID 16682 with executable SHA-256 `bfcec2c3b328e37c498c8ccf0bd5f6feb4e087bd9732dad7490429f300a9f77e`, CDHash `c543803e1d6311aa7c949bd4061edbfe931cb59e`, Team ID `T34G959ZG8`, Accessibility trust, the embedded iCUE SDK mapped into the live process, and exclusive ownership of the 0600 Karabiner command socket. Its matching signed runtime supervisor is running as PID 16698 with executable SHA-256 `1a634c9ea86b90ac936cf05138e2706c00722c13af2c43fb68b05fe36d749fca`, CDHash `57e2ec0c9be550a2b8ffe500fba64cff59156acd`, and Service Management parent build 113. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. Ethan's VS Code keybindings file was read-only and remains SHA-256 `8d23c9fae7eb21104cda9203be4b95e2cebacfb08e708f806977dcb3720b60aa`. The exact signed v1.0.106 rollback is retained in the task rollback directory. Literal physical acceptance remains one cell-9 single, one cell-9 double, and cell-6 wheel down/up from either mouse inside VS Code mode; ordinary scrolling should resume on release. The newly launched runtime remains fail closed until a real user input re-establishes its unlocked-session lease.

## 2026-08-23 — Combine Spotify volume into one held-wheel app control

**Trigger:** Ethan wanted one Spotify app-specific button that changes Spotify volume up or down according to the ratcheted wheel direction while the button is held.

**Cause:** Spotify's shared app definition spent two scarce cells on separate one-press Volume Down and Volume Up shortcuts. The existing held-wheel architecture already provided exact-device press/release ownership, per-source lifecycle teardown, reconstructed-ratchet debounce, and bounded process-targeted shortcut delivery, but Spotify was not registered as one of its app-specific controls.

**Fix:** Canonical physical cell 7 now renders `Volume + Wheel` in both automatic and manually chosen Spotify mode; this projects to Corsair printed 7 and Razer printed 9. Wheel up resolves to Spotify's native Command-Up volume increase, wheel down resolves to Command-Down volume decrease, and both post directly to the running Spotify PID without activating it. Same-direction raw-event bursts coalesce for 80 ms, immediate reversals remain responsive, release restores ordinary scrolling, and former Volume Up cell 8 is honestly Spare. The HUD, runtime route, and shortcut meanings all resolve from the same `StandardAppMode` plus `WheelChordControl` source rather than copied device or journey maps.

**Guard:** App-specific wheel controls must arm only from their canonical cell inside their exact app child. Preserve independent source ownership, automatic/manual definition parity, app-PID targeting, all existing session-lock and teardown clearing, ordinary-scroll pass-through while unarmed, and exact printed-label projection. Do not add a second iCUE assignment, Razer-only semantic, focus-changing Spotify activation, or global media-volume surrogate.

**Verification:** The focused Spotify suite passed four tests. The complete clean gate passed 576 Swift tests, six extension tests, 17 Karabiner generator tests, generated-source freshness/parity, both Karabiner JSON lints, packaging/version contracts, shell syntax, and diff hygiene. The `configure-mice` personal skill also passed `quick_validate.py` after its shared mapping reference was updated. Developer-ID-signed Agentic Mouse v1.0.106 (build 112) is installed as main PID 46597 with executable SHA-256 `b98726972436e9542efba1d5ff8186f5a900185404ebb02000602d22190ed126`, CDHash `88b0d7dc7fee0918836536e9276d224b9d119f09`, Team ID `T34G959ZG8`, Accessibility trust, the embedded iCUE SDK mapped into the live process, and exclusive ownership of the 0600 Karabiner command socket. Its matching signed runtime supervisor is running as PID 46610 from the installed build with executable SHA-256 `cc08d43f0a504d6507e7d712fb663470f5767b1f84dd90c37279bc66f109c2f6` and CDHash `d03cdc69f7ace7935767a42e5d88b25c8bb011bb`. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. Exact signed v1.0.105 rollback bundles are retained in the task rollback directory. Literal physical acceptance remains: enter Spotify mode from each journey, hold cell 7 on each mouse, ratchet once in both directions, confirm Spotify volume changes without focus, then release and confirm ordinary scrolling resumes.

## 2026-08-23 — Keep top-level wheel diagnostics from acquiring legend ownership

**Trigger:** Ethan reported that using Default-map `Horizontal Scroll + Wheel` or `Spaces + Wheel` opened the floating legend even though he had not toggled the legend on or entered a runtime mode.

**Cause:** Temporary wheel-trace diagnostics deliberately created a Default legend snapshot whenever that source's persistent legend was hidden. A focused test then pinned that diagnostic-only panel as expected behavior. The code existed only in the current uncommitted wheel work rather than committed history, but it had already reached the installed build.

**Fix:** Keep raw held-wheel diagnostics in logs at all times. Mirror a trace into the footer only when that exact mouse source's persistent Default legend is already visible; otherwise do nothing to the HUD. Never inject a top-level wheel trace into an active runtime-mode presenter. Real runtime-mode entry continues to auto-show its own source-specific HUD independently.

**Guard:** Debug telemetry must never acquire user-visible panel ownership. Only an explicit Default legend toggle or a real mode-entry journey may create a legend panel. Tests pin the hidden, already-visible, active-mode, source-isolation, and next-explicit-toggle cases so another temporary diagnostic cannot reintroduce this regression.

**Verification:** The focused Default legend suite passed 13 tests and the runtime-mode suite passed 64 tests. The complete clean gate then passed 574 Swift tests, six extension tests, 17 Karabiner generator tests, generated-source freshness/parity, both Karabiner JSON lints, packaging/version checks, shell syntax, and diff hygiene. Developer-ID-signed Agentic Mouse v1.0.105 (build 111) is installed as main PID 76279 with executable SHA-256 `5c2239bd0482ad91de5360a9175380bc4389fc91161314bc9f68f66743bcc4a1`, CDHash `378bd1bd211e7002a6f09d69ce40f9fda9dfe7ca`, Team ID `T34G959ZG8`, Accessibility trust, the installed iCUE SDK loaded, and exclusive ownership of the 0600 Karabiner command socket. Its matching signed runtime supervisor is running as PID 76295 with executable SHA-256 `a09781d6d000a5e0dd22bb26848eca46c5f14657d9fa79a13b508034bf62e8b6`, CDHash `ea68c0a11a5f71364e929ba375241ea9773c5fc4`, and Service Management parent build 111. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. A live installed command-socket probe armed and released both top-level wheel chords from both mouse sources; WindowServer remained free of Agentic Mouse panels throughout. Exact signed v1.0.104 rollback bundles are retained in the task rollback directory. Literal physical acceptance remains one hidden-legend Spaces-wheel gesture and one hidden-legend Horizontal-scroll-wheel gesture on each mouse, plus one ordinary mode entry to confirm only that journey auto-shows its HUD.

## 2026-08-23 — Clear accepted Mission/Desktop and Magnet wheel repair markers

**Trigger:** Ethan explicitly reported that both `Mission / Desktop + Wheel` and `Magnet + Wheel` are working and asked for their stale red crosses to be removed.

**Cause:** `WheelChordControl.hudControlStatus` still hard-coded both shared controls as `.reportedBroken` from earlier physical failures. The status is static HUD evidence rather than a live health detector, so later physical success did not clear it automatically.

**Fix:** Render both combined wheel cards with normal status on both printed mouse projections. Preserve Mission/Desktop on canonical physical cell 4, Magnet on canonical physical cell 6, every accepted wheel direction and dispatch policy, the hardware-like keyboard lifecycles, both exact-device adapters, the iCUE profile, and live Karabiner rules.

**Guard:** A later explicit physical success supersedes the earlier repair marker. Ethan did not separately identify the source mouse, repeat the cross-display Magnet matrix, or accept every other wheel-family debounce case in this report, so remove the shared cards' crosses without overstating those narrower evidence boundaries or changing behavior.

**Verification:** The focused HUD assertion passed, followed by the complete clean gate: 573 Swift tests, six extension tests, 17 Karabiner generator tests, generated-source freshness/parity, both Karabiner JSON lints, packaging/version tests, shell syntax, and diff hygiene. Developer-ID-signed Agentic Mouse v1.0.104 (build 110) is installed as main PID 64499 with executable SHA-256 `24cff86afd0891d3d261a8656266c7f616f6de2261ba4b238bbb4e61f8d08845`, CDHash `cd6c3a098fe7b00179398acac90e7ed39ef003ef`, Team ID `T34G959ZG8`, Accessibility trust, the installed iCUE SDK loaded, and exclusive ownership of the 0600 Karabiner command socket. Its matching signed runtime supervisor is running as PID 64553 with executable SHA-256 `f23737aa4aaeca0efa9c1e82eb2e8b76f0c879655abf39b6d94aba7c51639e88`, CDHash `3b82868f0e4ea4cba374abde29aed6052b3bc37d`, and Service Management parent build 110. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. Exact signed v1.0.103 rollback bundles are retained in the task rollback directory.

## 2026-08-21 — Clear Keypad's repair marker after physical acceptance

**Trigger:** In direct response to the outstanding physical-acceptance check, Ethan reported that the shared Keypad is working fine.

**Cause:** The Keys-page `Keypad` destination still rendered `.reportedBroken` from the earlier focus-delivery failure even though the later direct report accepted the feature. The status is static HUD evidence, not a live runtime health detector.

**Fix:** Render the shared Keys-page Keypad destination normally and close its physical-acceptance item. Preserve the existing direct process-targeted UTF-16 keyboard route, multi-tap behavior, Backspace, Space, Return, secure-field support, pasteboard independence, canonical physical cell 6, both exact-device printed projections, iCUE profile, and Karabiner configuration.

**Guard:** A later explicit physical success supersedes an earlier repair marker, but its evidence boundary still matters. Ethan did not name the exact source mouse, target application, secure-field sample, or clipboard comparison in this report, so accept the shared Keypad without claiming a separately repeated matrix for both mice or those individual targets. Marker removal must not become a behavior, physical-cell, iCUE, or Karabiner change.

**Verification:** The focused Keypad HUD test passed, followed by the complete clean gate: 573 Swift tests, six extension tests, 17 Karabiner generator tests, generated-source freshness/parity, both Karabiner JSON lints, packaging/version tests, shell syntax, and diff hygiene. Developer-ID-signed Agentic Mouse v1.0.103 (build 109) is installed as main PID 54523 with executable SHA-256 `0678de0ede023786a5228ef85e7894195c7e02946b764672802b4fee7c0dc081`, CDHash `56e64e41cec249428c252ce9db969fd2e979fa11`, and Team ID `T34G959ZG8`; it owns the exact 0600 Karabiner user-command socket and has the installed iCUE SDK loaded. Its matching signed runtime supervisor is running as PID 54556 with executable SHA-256 `57f284d58e3297d93f591a261402ebb42cd25fb800b428eef2398030e06b86d9`, CDHash `70ffe35876e1df6cb1ff324a9a5639eea9566833`, and Service Management parent build 109. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. Exact v1.0.102 rollback bundles are preserved in the task rollback directory.

## 2026-08-21 — Clear Screenshot's repair marker after later physical success

**Trigger:** Ethan physically confirmed that the mouse Screenshot control works and asked why its Default legend card still carried a red cross.

**Cause:** `DefaultMapLegend.snapshot` still assigned `.reportedBroken` to Screenshot unconditionally. The repair marker was static HUD evidence from an earlier failure report, not a runtime health detector, so it survived both the working native route and Ethan's later success.

**Fix:** Render Screenshot with normal control status on the shared semantic card. Preserve physical cell 3 (Corsair printed 3 / Razer printed 1), the exact native Shift-Command-4 lifecycle, same-button cancellation, configured macOS save destination, floating thumbnail, both exact-device adapters, and every live mapping. The exact source mouse in Ethan's confirmation was not stated, so record the shared semantic acceptance without claiming that both device transports were separately retested.

**Guard:** A later explicit physical success supersedes an earlier failure and must clear the repair marker. Do not keep a stale cross merely because the status was once correct, and do not turn marker removal into a shortcut, physical-cell, iCUE-profile, or Karabiner change. Pin normal status plus the exact source-specific labels in the HUD test.

**Verification:** The focused Default legend test passed, followed by the complete clean gate: 573 Swift tests, six extension tests, 17 Karabiner generator tests, generated-source freshness/parity, both Karabiner JSON lints, packaging/version tests, shell syntax, and diff hygiene. Developer-ID-signed Agentic Mouse v1.0.102 (build 108) is installed as main PID 63275 with executable SHA-256 `bbc14a455657e3589fb1930c32d608c35b23b1190088cbc713af979002a8a265`, CDHash `7be0a99e6c5492da55e1434dc3fc31eb2a4989c4`, Team ID `T34G959ZG8`, Accessibility authorization, and exclusive ownership of the exact Karabiner command socket. Its matching signed runtime supervisor is running as PID 63291 with executable SHA-256 `914067493ee8d9475e29c9214f680a17bd32882f88f5b80b8ff4902c36473b72`, CDHash `c693d0230a45f9952629c671c194cf7178ac519b`, and Service Management parent build 108. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. Exact v1.0.101 rollback bundles are preserved in the task rollback directory.

## 2026-08-21 — Supervise the runtime and repair its volatile transports

**Trigger:** Ethan returned after clamshell sleep to both mice showing vendor fallback colours and Agentic Mouse absent, then asked for a supported self-recovering design so the shared runtime does not silently remain down.

**Cause:** `SMAppService.mainApp` launched Agentic Mouse at login but did not supervise it during the logged-in session. AppKit's automatic-termination opt-out protected only one termination mechanism and could not recover an already absent process. Several recoverable in-process edges were also one-shot: display wake was not observed, a failed unlocked-session lease write never retried, a missing or replaced Karabiner command socket stayed unavailable, wheel-event-tap creation was not retried, and reload stopped focus monitoring without restarting it. The first supervisor candidate also used the wrong outer bundle identifier, allowed a final helper tick to race intentional Quit, and would have granted an unlocked lease after relaunch or display wake at loginwindow; Opus 5 caught all three before installation. The exact original sleep-time termination mechanism was not logged and remains unclaimed.

**Fix:** Package a signed nested `AgenticMouseSupervisor.app` and register it through `SMAppService.loginItem`. The hidden AppKit helper locates its exact containing outer app, checks the real `com.ethan.agentic-mouse` bundle identifier every two seconds, refuses launch while loginwindow or the screensaver owns the session, relaunches through supported non-activating `NSWorkspace` configuration, backs off at 2/5/10/30/60 seconds, pauses five minutes after five attempts inside two minutes, and resets after one stable minute. Acquire a 0600 `flock` instance lock before AppKit or lease startup. Menu-bar Quit uses Service Management's asynchronous unregister completion and terminates only after the running helper was killed; refresh uses the same wait-before-register contract. On launch, display wake, or transition away from loginwindow, remain fail closed until a public global event monitor receives real input while a normal app is frontmost. Observe loginwindow activation through public `NSWorkspace.didActivateApplicationNotification` and clear the lease immediately. Inside the main process, coalesce display/system wake, retry the proof monitor and transient active-session lease failures, repair a vanished/replaced command socket only when its recorded device/inode/uid/type identity matches, retry or rebuild a disabled wheel tap, and restart focus monitoring on reload.

**Guard:** Use the supported signed nested login-item API, exact containing bundle, hidden AppKit run loop, non-activating launch configuration, single-instance lock, bounded retry, positive unlocked-input proof, and asynchronous explicit-Quit disarm. Do not install a LaunchAgent, edit private service state, depend on an unauthenticated quit notification, infer lock state from a private session dictionary, disable the locked-session sink, or treat `SMAppService.mainApp` or `disableAutomaticTermination` as runtime supervision. A crash marker may record only the exact socket identity needed to distinguish this app's stale filesystem node from another server's live socket. Keep `ProcessInfo.automaticTerminationSupportEnabled = true`: Apple's Foundation contract says the disable/enable calls have no effect unless support is enabled.

**Verification:** The final focused lifecycle, registration, instance-lock, wake/proof, health-monitor, exact socket-ownership, session-retry, and supervisor suite passed 38 tests with zero failures. The clean full gate passed 573 Swift tests, six extension tests, 17 Karabiner generator tests, generated-source freshness/parity, both Karabiner JSON lints, packaging/version tests, shell syntax, and diff hygiene. The same Claude Opus 5 session performed three read-only repository audits: it found the pre-install blockers, re-read the repairs, retracted one incorrect wheel-monitor finding, and finally reported no remaining source blocker. Developer-ID-signed Agentic Mouse v1.0.100 (build 106) is installed with outer Team ID `T34G959ZG8`, CDHash `132a6abe2fb06e4dae0f82fbc837c579d019c5e5`, executable SHA-256 `a546c5b476c07d420a8602c7cc88bdfaa7e00733b3dca3d57adc2fcd07aa19fc`, and a matching v1.0.100 nested supervisor whose CDHash is `a39d975870b6d11d86d475677ac90e7315d3fbdf` and executable SHA-256 is `e64bae622b7fe2c7b47d2733f7a320056dbaabacc0baaa0f9fff4afc690a5a93`. `SMAppService` reports the helper enabled and running as PID 20318. A controlled clean SIGTERM of main PID 20307 released the old socket; the supervisor detected the missing runtime at 22:14:00.695, accepted a non-activating relaunch at 22:14:00.798, and restored main PID 23400, its new exact socket marker, wheel tap, Accessibility trust, iCUE connection/macro subscription, and Corsair lighting target by 22:14:01.000. The live embedded iCUE SDK, Agentic Mouse config, and Karabiner configuration remained byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. The exact prior v1.0.99 bundle is preserved in the task rollback directory. Intentional menu-bar Quit non-relaunch and physical loginwindow/clamshell acceptance remain attended gates; do not infer them from the live unexpected-exit proof.

## 2026-08-21 — Resolve terminal Control-C semantically under Dvorak

**Trigger:** Ethan reported that VS Code mode's `Interrupt terminal` produced only a new line instead of stopping the terminal command.

**Cause:** The shared terminal shortcut hard-coded physical QWERTY-C key code 8. Ethan's active `DVORAK - QWERTY CMD` source applies its QWERTY compatibility only to Command shortcuts, not Control shortcuts. Live layout translation proved key code 8 is semantic `j`, so Agentic Mouse was sending Control-J—the terminal newline control character. Semantic `c` is currently key code 34.

**Fix:** Resolve semantic `c` from the active keyboard layout at every interrupt dispatch, then post the existing bounded Control-C key pair to the selected VS Code, Terminal, or iTerm PID. Fail closed with visible HUD feedback if the layout cannot resolve C. Keep the VS Code card marked broken only until Ethan physically proves the installed route; after that explicit success, render it normally without a red cross.

**Guard:** Never hard-code a QWERTY physical key position for a Control shortcut on this layout. Preserve the locked-session and Accessibility gates, process targeting, current app-mode cells, and release-inert behavior. Pin injected Dvorak resolution, old-key rejection, and failure-to-resolve behavior in tests; physically require a running command to stop rather than accepting a blank new prompt as success.

**Verification:** The focused dispatcher and mode tests passed, followed by the clean full gate: 546 Swift tests, 6 extension tests, 17 generator tests, generated-rule freshness/parity, both Karabiner lints, packaging/version checks, and shell syntax. Developer-ID-signed Agentic Mouse v1.0.99 (build 105) was installed with Team ID `T34G959ZG8`, CDHash `8e230d360966d12c9436490ea5355f2cf9f92309`, executable SHA-256 `53b3dc4b1c26f01dcd800af6dfa8eaf51678f57d3285ca7f308c21f9cfa70f0f`, Accessibility authorization, and exclusive ownership of the Karabiner user-command socket. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remained byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. Exact v1.0.98 rollback bundles are preserved in the task rollback directory. On 21 August 2026, Ethan physically confirmed that Interrupt terminal works in VS Code on installed Agentic Mouse v1.0.100 (build 106), superseding the earlier blank-newline failure and authorizing removal of the repair marker. The exact source mouse was not stated, so this accepts the shared semantic action without claiming a separate physical transport check on both mice. The marker-only follow-up passed the focused HUD test and the complete clean gate with 573 Swift tests, 6 extension tests, and 17 generator tests. Developer-ID-signed Agentic Mouse v1.0.101 (build 107) is installed as main PID 10980 with executable SHA-256 `e1b4c5b6d16a2b39e7b2464e0ce70864655539dc08805d54a80a020cc6e124e3`, CDHash `23fff5c276ea07e73d9ef4a9d998c07113e9b7c5`, and Team ID `T34G959ZG8`; its matching signed runtime supervisor is running as PID 11012 with executable SHA-256 `466f428496e3ed9bd1b23cf715e152f81440298979ee71e20d91807b65324e97` and CDHash `bf3b0b6681689a868d20bb2a3b29c86db7f0de6d`. Service Management reports parent build 107 and the main process owns the exact recorded Karabiner command socket while the embedded iCUE SDK is loaded from the installed bundle. The SDK, live Agentic Mouse config, and live Karabiner hashes remain unchanged. Exact v1.0.100 rollback bundles are preserved in the task rollback directory.

## 2026-08-21 — Keep Magnet wheel polarity independent from other horizontal wheel families

**Trigger:** Ethan reported that the arrows on Utility's `Magnet + Wheel` control were mapped the wrong way around.

**Cause:** `WheelChordControl.utilityAction(for:)` still mapped wheel up to Magnet Right and wheel down to Magnet Left. That polarity was inherited from the accepted Spaces, Horizontal Scroll, and Chrome Tabs gestures, but Magnet's physical window-placement gesture needs the opposite direction.

**Fix:** Change only Magnet's semantic projection: wheel up now selects `moveWindowLeftWithMagnet`, and wheel down selects `moveWindowRightWithMagnet`. Preserve physical cell 6 on both mice, the complete Control-Option-Arrow keyboard lifecycle, physical arrow flags, 150 ms raw-burst coalescing, 400 ms FIFO pacing, release cancellation, and Magnet's ownership of cross-display placement.

**Guard:** Do not globally flip `WheelChordDirection`, Horizontal Scroll, Spaces, Chrome Tabs, Brightness, Zoom, Clipboard, or system-overview controls when correcting one family. Pin every two-way family independently in `WheelChordTests`, and keep the physical Magnet failure marker until Ethan verifies both directions on the installed build.

**Verification:** The focused 18-test wheel suite passed, followed by the clean full gate: 545 Swift tests, 6 extension tests, 17 generator tests, generated-rule freshness/parity, both Karabiner lints, packaging/version checks, and shell syntax. Developer-ID-signed Agentic Mouse v1.0.98 (build 104) is installed as PID 51788 with Team ID `T34G959ZG8`, CDHash `6e1c5bb5dfd55cfaadf8538f8b250c06747a12f5`, executable SHA-256 `a7cca6512e56bf2cf510a28082f991b12313d8b4f25d3f2243616e04f7d4a4e8`, Accessibility authorization, and exclusive ownership of the Karabiner user-command socket. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. The exact prior v1.0.97 bundle is preserved at `/Users/ethansarif-kattan/Documents/Codex/2026-08-05/where-the-fuck-did-my-chat/Rollbacks/AgenticMouse-v1.0.97-build103-before-v1.0.98.app`. Physical acceptance still requires one wheel-up Magnet Left and one wheel-down Magnet Right placement, including a display boundary.

## 2026-08-21 — Treat Chrome-window choice as an explicit identity join

**Trigger:** Ethan asked whether the manual Stay restore could choose a Chrome window dynamically from the set of pinned Codex tasks.

**Cause:** The saved `Agentic Mouse Layout v1` Chrome row uses bundle ID `com.google.Chrome` with title regular expression `.*`, so several Chrome windows can satisfy the same stored row. Stay cannot infer a relationship between those windows and Codex. The live Codex state exposes 27 pinned task IDs, but pinnedness itself carries no browser-window or URL association. The installed Chrome AppleScript dictionary does expose each window's session-unique ID and mutable bounds plus every tab's title and URL, so a deterministic helper is technically possible only after an explicit join rule exists.

**Design boundary:** The zero-code option is one or more disjoint Stay title rules, but Chrome's window title follows its active tab and is therefore not a stable general identity. A robust advanced route must define an explicit mapping such as task ID → window role, tab-group label, or URL/domain rule; resolve exactly one Chrome window; and fail closed on zero or multiple matches. If a helper places Chrome directly, remove Chrome from the Stay profile so two placement authorities cannot fight. Do not mutate Stay's private database, rewrite page titles as a runtime sentinel, focus arbitrary tabs to discover identity, or fuzzy-match pinned task titles and silently choose a window.

**Verification:** A read-only live probe found four Chrome windows and confirmed supported access to their IDs, bounds, tab titles, and URLs. No Chrome row, window, tab, or Agentic Mouse source was changed; the mapping decision remains Ethan-owned.

## 2026-08-21 — Treat sleep-time runtime loss as a supervision failure

**Trigger:** Both exact mice simultaneously returned to their fallback colours after the Mac woke from clamshell sleep.

**Cause:** Installed Agentic Mouse v1.0.97 PID 76699 ran until the 18:51 sleep boundary and was absent after the 19:57 wake. The Mac had not rebooted, both physical devices remained enumerated, iCUE and Karabiner remained alive, and no Agentic Mouse crash report existed. `SMAppService.mainApp` was still enabled, but it launches at login rather than supervising an already logged-in process. The existing AppKit automatic-termination opt-out therefore cannot be treated as end-to-end keepalive proof. The exact termination mechanism was not logged and must remain unclaimed.

**Recovery:** Relaunch the exact signed `/Applications/AgenticMouse.app`, then verify a new PID, exclusive Karabiner user-command socket ownership, both physical devices, and the physical idle colours. Do not change iCUE profiles, DPI, Karabiner mappings, or hardware memory to repair simultaneous fallback colours when the shared Agentic Mouse runtime is absent.

**Guard:** Persistent acceptance requires a supported supervisor that restarts unexpected exits without defeating intentional Quit or locked-session fail-closed behavior. Verify login launch, clamshell sleep/wake recovery, socket ownership, both idle-lighting routes, and absence of a restart loop. Do not call login-item registration or the AppKit opt-out alone “always running.”

**Verification:** The exact signed v1.0.97 app relaunched at 20:12:03 as PID 43591 and reclaimed the Karabiner user-command socket while both physical mice remained enumerated. Physical colour confirmation remains Ethan-owned.

## 2026-08-21 — Use VS Code's native F12 definition shortcut on the remaining shared cell

**Trigger:** Ethan asked whether VS Code mode still had room for Go to Definition, then explicitly asked to add it.

**Cause:** Canonical physical cell 11 was genuinely Spare after Command Palette moved to cell 7. VS Code already exposes Go to Definition as the default F12 shortcut (`editor.action.revealDefinition`), so the requested action did not need UI automation, a custom VS Code binding, or a device-specific transport.

**Fix:** Add `VSCodeModeAction.goToDefinition` on canonical physical cell 11, which is printed 11 on both the Corsair and Razer. Resolve it through the existing process-targeted application shortcut dispatcher as one bounded F12 key cycle with no modifiers. Automatic frontmost VS Code mode and manual Choose App → VS Code continue to share the same `VSCodeMode.definition` source of truth.

**Guard:** Pin the canonical cell, both printed projections, exact title, single-command semantics, absence of a double command, and exact key code 111 with no flags. Keep this as a normal VS Code shortcut rather than Accessibility UI automation, and do not invoke it automatically against Ethan's active editor during installation; one attended press from each exact mouse remains the physical acceptance boundary.

**Verification:** Focused mapping and dispatcher tests passed, followed by the clean full gate: 545 Swift tests, 6 extension tests, 17 generator tests, generated-rule freshness/parity, both Karabiner lints, packaging/version checks, and shell syntax. Developer-ID-signed Agentic Mouse v1.0.97 (build 103) is installed as PID 76699 with Team ID `T34G959ZG8`, CDHash `013e88a4edb2d7b90d280bd73b1a615dae805e9a`, executable SHA-256 `7cf329e9641ae3edd670326de3f87172eb03e12e95a9a5637984c97ba2010b96`, stable Accessibility grant (`auth_value=2`, 164-byte designated requirement), and exclusive command-socket ownership. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. The exact prior v1.0.96 bundle is preserved at `Rollbacks/AgenticMouse-v1.0.96-build102-20260821-140050.app`. Physical acceptance still requires one VS Code-mode cell-11 press from each exact mouse with a valid symbol under the caret.

## 2026-08-21 — Put VS Code Command Palette on the requested shared cell

**Trigger:** Ethan asked for Command Palette in the spare Corsair printed 7 slot inside VS Code mode.

**Cause:** `VSCodeModeAction.commandPalette` already existed in the dirty source and already resolved to the correct bounded Command-Shift-P shortcut, but it was assigned to canonical physical cell 11. The installed v1.0.95 page still showed cell 7 as Spare, so neither the requested position nor the pending source placement was live.

**Fix:** Move only `VSCodeModeAction.commandPalette.cell` to canonical physical cell 7, which projects to Corsair printed 7 and Razer printed 9. Leave canonical cell 11 Spare. Automatic frontmost VS Code mode and manual Choose App → VS Code continue to resolve the same `VSCodeMode.definition`, and the existing process-targeted shortcut dispatcher still sends one Command-Shift-P cycle.

**Guard:** Treat a printed Corsair number as the shared canonical physical cell unless Ethan explicitly asks for a device-specific difference. Pin the action title, cell, Razer projection, absence on cell 11, non-double-click semantics, and exact Command-Shift-P transport. Do not physically open Command Palette in Ethan's active editor during installation; retain an attended press on each mouse as the final acceptance boundary.

**Verification:** The clean full gate passed 544 Swift tests, 6 extension tests, 17 generator tests, generated-rule freshness/parity, both Karabiner lints, packaging/version checks, and shell syntax. Developer-ID-signed Agentic Mouse v1.0.96 (build 102) is installed as PID 31289 with Team ID `T34G959ZG8`, CDHash `bc1eab7bb1d677482ba11d9d751943ef2b803e9a`, executable SHA-256 `9a4b7580fb0fa1e2ed7d37ab66194b6a0041d5a17bdb6f39aa2e308a31f453f3`, stable Accessibility grant (`auth_value=2`, 164-byte designated requirement), and exclusive command-socket ownership. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. The exact prior v1.0.95 bundle is preserved in the task rollback directory. Physical acceptance still requires one VS Code-mode cell-7 press from each exact mouse.

**Status:** The instruction to leave cell 11 Spare is superseded by the newer Go to Definition mapping above; Command Palette remains on cell 7.

## 2026-08-21 — Keep momentary and sticky YouTube 2× gestures on one safe lease

**Trigger:** Ethan asked for a double-click on Chrome mode's existing `Hold 2× speed` card to lock the selected YouTube video at 2×, with the next double-click returning it to 1×.

**Cause:** The accepted transport modeled only physical press, lease renewal, and release. Implementing sticky speed as a second independent browser command would have lost the existing opaque-token target ownership and exact-prior-rate fail-safe, while treating clicks from both mice as one gesture could lock speed accidentally.

**Fix:** Keep physical cell 7 shared across the Corsair and Razer projections. A short release followed by a second press from the same `MouseSource` within 340 ms converts the normal momentary sequence into a sticky renewal of the same browser-side lease. The next same-source double-click ends that bound lease with `restorePlaybackRate=1.0`. An ordinary release, the owning mouse leaving Chrome mode, session lock, sleep, bridge loss, or app teardown omits the override and therefore restores the exact saved prior rate. Different mice cannot combine taps, while simultaneous ordinary holds retain their existing last-release ownership.

**Guard:** Preserve the existing PiP → last-focused active → audible → active → playback-recency selector in the VoiceInk YouTube Bridge. Never focus Chrome, alter play/pause, replay a stale edge, claim playback success from notification dispatch, or force 1× from a fail-safe teardown. Tests pin same-source timing, cross-source isolation, ordinary long holds, sticky renewal, explicit second-double 1×, owner/non-owner mode exit, lock loss, stable notification names, and rejected begin behavior.

**Verification:** The clean full gate passed 544 Swift tests, 6 extension tests, 17 generator tests, generated-rule freshness/parity, both Karabiner lints, packaging/version checks, and shell syntax. Developer-ID-signed Agentic Mouse v1.0.95 (build 101) is installed as PID 93493 with Team ID `T34G959ZG8`, CDHash `52d6fb38f0061eba230218fad5dfa83b775ef343`, executable SHA-256 `bc6950503aba193c6e2bbf67602eb742dad43dc2a201161bcef754fb6f6780bc`, stable Accessibility grant (`auth_value=2`, 164-byte designated requirement), and exclusive command-socket ownership. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. The signed helper/native host and exact unpacked personal-Chrome extension were installed/reloaded; live logs accepted the new `restore=1.0` end contract and re-injected every open YouTube tab. All videos were paused, so literal 2× lock/unlock on a playing video remains physical acceptance on each mouse.

## 2026-08-21 — Do not duplicate Default navigation inside VS Code mode

**Status:** The removal of duplicate Back/Forward remains current. The cell-7 Spare decision and no-op acceptance gate are superseded by the later Command Palette assignment above.

**Trigger:** Ethan removed Back and Forward from the explicitly entered VS Code page, assigned Close tab to physical cell 1, and left physical cell 7 Spare.

**Cause:** The VS Code child still exposed its own Control-minus Back and Control-Shift-minus Forward controls even though the Default map already owns ordinary navigation. The duplicate pair consumed two scarce child-page cells without matching the intended VS Code workflow.

**Fix:** Replace the child-only cell-1 Back action with `Close tab`, delivered as one bounded Command-W cycle to the running VS Code process. Remove the child-only Forward action so canonical physical cell 7 is truly Spare. Keep Default Back/Forward, the exact-device Better Git overrides, and every other VS Code child action unchanged. Automatic frontmost VS Code mode and manual Choose App → VS Code continue to resolve the same `VSCodeMode.definition`.

**Guard:** Treat a printed Corsair or Razer number as the shared canonical cell unless Ethan explicitly requests a device-specific difference. Pin the semantic action, Command-W transport, shared HUD projection, and absent cell-7 action in tests. Never physically test a tab-close shortcut against an unsaved editor.

**Verification:** The focused mapping/dispatcher suite passed 81 tests, and the clean full gate passed 538 Swift tests, 6 extension tests, 17 generator tests, generated-rule freshness/parity, both Karabiner lints, packaging/version checks, and shell syntax. Developer-ID-signed Agentic Mouse v1.0.94 (build 100) is installed as PID 73506 with Team ID `T34G959ZG8`, CDHash `fa1faa530c209fdcf058e855b57f7fb7bbcdab12`, executable SHA-256 `6c8aa129fad7c6f29a03bfbec0e50a5b881739e53500e17bf757ba042c035be8`, stable Accessibility grant (`auth_value=2`, 164-byte designated requirement), and exclusive command-socket ownership. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. The prior signed v1.0.93 bundle is preserved as rollback. Physical acceptance still requires one Close tab press on an expendable VS Code editor and one cell-7 no-op check from either exact mouse; do not automate the tab close against Ethan's active work.

## 2026-08-20 — Swap Codex Side Chat and Voice Mic by canonical cell

**Trigger:** Ethan asked to swap Open Side Chat and Mute/Unmute Voice Mic inside Codex mode.

**Cause:** The accepted Codex shortcuts already worked, but their shared page positions no longer matched Ethan's preferred reach: Side Chat occupied canonical physical cell 6 and Voice Mic occupied canonical physical cell 9.

**Fix:** Move only the two `CodexModeAction.cell` assignments. Mute/Unmute Voice Mic now uses canonical cell 6 (Corsair printed 6 / Razer printed 4), and Open Side Chat now uses canonical cell 9 (Corsair printed 9 / Razer printed 7). Keep the System Events shortcut transports, action titles, status markers, automatic/manual app-targeting source, and every other Codex card unchanged.

**Guard:** Treat a printed Corsair or Razer number as a projection of the shared canonical physical cell unless Ethan explicitly requests a hardware-specific difference. A card relocation must update the source map, both printed-label assertions, legend ordering, durable project instructions, and the configure-mice reference without changing the action executor or live Karabiner profile.

**Verification:** The focused Codex mapping test passed, followed by the clean full gate: 537 Swift tests, six extension tests, 17 generator tests, generated-rule freshness/parity, both Karabiner lints, packaging/version checks, and shell syntax. Developer-ID-signed Agentic Mouse v1.0.93 (build 99) is installed as PID 57173 with CDHash `2a841d9a604a7c008d056807fba5ba297324fd68`, executable SHA-256 `9b46df680e3f5b2506d8d59bebf94d44b38368b173f44d3b87d1a36c34712a74`, stable Accessibility grant (`auth_value=2`, 164-byte designated requirement), and exclusive command-socket ownership. The embedded iCUE SDK, Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. Literal physical acceptance remains one Side Chat press on cell 9 and one active-voice mic toggle on cell 6 from either exact mouse.

## 2026-08-20 — Route iPhone Mirroring notifications through macOS Notification Center

**Trigger:** Ethan could not drag down from the top of the iPhone Mirroring window and asked for a notification shortcut in that app's automatic mode.

**Cause:** Apple's supported iPhone Mirroring surface and its live View menu expose no iPhone pull-down or Notification Center command. iPhone notifications are delivered to macOS Notification Center instead, and macOS documents Fn-N as its show/hide shortcut. Two transport defects existed. The first installed implementation hard-coded physical QWERTY-N (`keyCode 45`), while Ethan's selected `DVORAK - QWERTY CMD` layout maps that unmodified key to `b`; a direct `UCKeyTranslate` probe resolves semantic `n` to current key code 37. The next candidate corrected that key but still attached `maskSecondaryFn` only to the N down/up events. Posting those events can return success while macOS ignores the shortcut because no real Globe/Fn `flagsChanged` down/up lifecycle exists.

**Fix:** Recognize exact bundle ID `com.apple.ScreenContinuity` as an automatic-only `AppSpecificTarget`. Give its child page `Notifications` on canonical physical cell 1 (Corsair printed 1 / Razer printed 3). Resolve semantic `n` through the active Unicode keyboard layout at dispatch time, then send one complete hardware-shaped four-event cycle—Globe/Fn `flagsChanged` down, N down, N up, Globe/Fn `flagsChanged` up—only while iPhone Mirroring is frontmost. Capture the public WindowServer visibility state before dispatch and sample it twice afterward so the HUD says confirmed opened/closed only when macOS Notification Center actually changes. Preserve app-child exits on physical cells 2 and 10.

**Guard:** Keep the shortcut behind the unlocked-session lease and current Accessibility trust. Fail closed when semantic `n` cannot be resolved, iPhone Mirroring is missing, or it is no longer frontmost so a global Fn-N cannot leak into another workflow. Never replace semantic layout resolution with a QWERTY key-code assumption, omit the modifier lifecycle, or equate successful event posting with destination success. Ignore desktop widgets and transient notification banners when detecting Notification Center. Do not fake an unavailable mirrored-screen swipe, use Accessibility UI clicking, or consume a manual Choose App slot without an explicit replacement decision.

**Verification:** Apple's current iPhone Mirroring and macOS shortcut documentation establish the supported boundary; a live read-only View-menu inventory confirms that the app exposes Home Screen, App Switcher, and Spotlight but no iPhone Notification Center command. Ethan rejected installed v1.0.90. A current-layout probe then proved key code 45=`b`, key code 37=`n`; installed v1.0.91 corrected that key but preceded the Opus audit's modifier-lifecycle finding. Focused tests pin semantic resolution, the exact four-event Fn lifecycle, visible-panel classification, open/close transitions, retry, and honest unavailable/unchanged outcomes. The clean full gate then passed 537 Swift tests, six extension tests, 17 generator tests, generated-rule freshness/parity, both Karabiner lints, and packaging checks. Signed Agentic Mouse v1.0.92 (98) is installed as PID 65746 with Developer-ID CDHash `87ef09fa9e683a3be12902bbc053ea9fe6c2b81f`, executable SHA-256 `11371d19ea7e0bd1183b35adb90cb0911754ecc14b08ded81bcf076416822aae`, unchanged embedded iCUE SDK SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, stable Accessibility grant (`auth_value=2`, 164-byte designated requirement), and exclusive ownership of the Karabiner user-command socket. Live Agentic Mouse config and Karabiner SHA-256 values remained `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7` and `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`. The literal Corsair/Razer physical press remains attended acceptance because iPhone Mirroring currently reports that the iPhone is in use and its session is disconnected; do not call the action physically accepted yet.

## 2026-08-20 — Add shared Keys-mode Undo at the semantic layer

**Trigger:** Ethan asked for an Undo button on Corsair printed 3 while Keys mode is active.

**Cause:** Canonical physical cell 3 was genuinely Spare on the Keys page. The exact-device crosswalk projects that shared semantic cell as Corsair printed 3 and Razer printed 1; treating the request as Corsair-only would have split the two mice's semantic map.

**Fix:** Add `KeysModeAction.undo` on canonical physical cell 3 and generate one non-repeating Command-Z cycle for both exact-device sources. Keep the app-side executor's semantic fallback aligned with the generated Karabiner route, including the Command modifier.

**Guard:** Mode ownership is page-scoped: Default cell 3 remains Screenshot and Keypad cell 3 remains DEF. Keys cell 2 remains Spare. Keep exact-device source matching, the unlocked-session lease, and `selectNative` routing so one physical press cannot be synthesized twice.

**Verification:** The clean full gate passed 524 Swift tests, 6 extension tests, 17 generator tests, generated-rule parity, both Karabiner lints, packaging/version checks, and shell syntax. Developer-ID-signed Agentic Mouse v1.0.89 (build 95) is installed as PID 8479 with executable SHA-256 `0352a6fc62f40d5843084db23830d3e536b5aa8d75389ce3d4376467a37136db`, Team ID `T34G959ZG8`, CDHash `073e1078a0fdd1e91fd8eda451e4a47f37d70963`, current Accessibility authorization, and the exact command-socket owner. The embedded iCUE SDK and Agentic Mouse config remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe` and `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`. The intentional live Karabiner update is SHA-256 `9a02120b32c20428ab6221e125e32018a9814e478d37ce8d30c4d652937118cd`, preserves all three non-Agentic rules exactly, and contains one guarded Cmd-Z route per mouse. Physical acceptance still requires one expendable edit followed by one Corsair 3 press and one Razer 1 press in Keys mode; do not automate Undo against Ethan's active work.

## 2026-08-20 — Distinguish Chrome tab close from window close

**Trigger:** Ethan asked for Chrome mode physical cell 1 to close the current tab and physical cell 8 to close the current window on the shared Corsair/Razer semantic map.

**Cause:** The existing cell-1 card was labelled `Close current window` but emitted Command-W. Chrome documents Command-W as Close current tab; Close current window is Shift-Command-W. Cell 8 was still Spare after the earlier removal of duplicate browser-history controls.

**Fix:** Add a distinct `closeCurrentTab` action on canonical physical cell 1 (Corsair 1 / Razer 3) with Command-W, and move `closeCurrentWindow` to canonical physical cell 8 (Corsair 8 / Razer 8) with Shift-Command-W. Keep both automatic frontmost Chrome mode and manual Choose App → Chrome mode on the same `ChromeMode.definition`.

**Guard:** A Chrome child action on cell 8 does not replace or alter Default-mode cell 8 Back. Keep browser history navigation exclusively in the Default base map, route both close actions on press only through the bounded Chrome process dispatcher, and pin the distinct labels, cells, key code, flags, and shared-definition journeys in tests.

**Verification:** The focused Chrome mapping/dispatcher suite passed 72 tests, and the clean full gate passed 524 Swift tests, 6 extension tests, 17 generator tests, generated-rule parity, both Karabiner lints, packaging/version checks, and shell syntax. Developer-ID-signed Agentic Mouse v1.0.88 (build 94) is installed as PID 34402 with executable SHA-256 `46a730c5127ead2bca364cdbe3484c27929ce02f138f02ba4178d71b323da4d8`, Team ID `T34G959ZG8`, CDHash `e861e83075e677e5f25628c33298150a066a103c`, Accessibility authorization, and ownership of the Karabiner user-command socket. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `6c46f626dec9f36d72fe1d9e57e6f1c36e32a6ad2a99fc5856c2d6917280a607`. Physical acceptance still requires one tab-close and one window-close press on each exact mouse; do not automate those destructive checks against Ethan's live Chrome state.

## 2026-08-20 — Keep accepted VS Code Undo separate from Stage + Next

**Status:** Superseded on 2026-08-23 by the combined cell-9 single/double gesture and cell-6 Cursor History + Wheel control above.

**Trigger:** Ethan asked to place immediate Stage + Next on Corsair printed 9 and the shared equivalent, place Undo Stage on Corsair printed 6 and the shared equivalent, and remove Undo's failure marker after physically confirming that Undo works.

**Cause:** The VS Code child page still held the inverse placement—Stage + Next on canonical cell 6 and Undo Stage on canonical cell 9—and its HUD retained a stale `reportedBroken` status after the later physical success report.

**Fix:** Keep one `VSCodeModeAction` source for both automatic and manually chosen VS Code pages. Put Stage + Next on canonical physical cell 9 (Corsair 9 / Razer 7), put Undo Stage on canonical physical cell 6 (Corsair 6 / Razer 4), and render Undo normally without a red cross. This child-only swap must not change top-level cell 6 Intelligence on Demand or top-level cell 9 Keys mode.

**Guard:** A latest explicit physical success clears an older failure marker, but relocating a working action does not prove its new button placement. Preserve Undo's accepted Better Git F16 behavior and require a separate physical press before calling Stage + Next accepted on its new cell 9.

**Verification:** The focused VS Code mapping and HUD suite passed 79 tests, and the clean full gate passed 523 Swift tests, 6 extension tests, 17 generator tests, generated-rule parity, both Karabiner lints, packaging/version checks, and shell syntax. Developer-ID-signed Agentic Mouse v1.0.87 (build 93) is installed as PID 8200 with executable SHA-256 `af9bcac95c80f1feaa9c98ec74e711f1df6b99015d096e90bebc6c23649d2232`, Team ID `T34G959ZG8`, CDHash `de0bbaed50137536822aaad33d679b80e24f8376`, Accessibility authorization, and command-socket ownership. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `6c46f626dec9f36d72fe1d9e57e6f1c36e32a6ad2a99fc5856c2d6917280a607`. Ethan already physically accepted Undo's semantics; physical acceptance still requires one Stage + Next press on its new cell 9 and one Undo press on its new cell 6 to confirm the relocated cells on the live build.

## 2026-08-20 — Treat secure fields as ordinary Keypad keyboard targets

**Trigger:** Keypad refused to type into a password input and displayed that secure fields were blocked, even though Ethan required the mouse keypad to work in every editable input.

**Cause:** `AccessibilityTextTargetResolver` explicitly rejected the `AXSecureTextField` role before reaching the existing process-targeted keyboard output. That policy was not a macOS limitation and was not part of Ethan's requested security boundary.

**Fix:** Classify secure text fields as editable exact-element targets. Continue sending committed characters as process-targeted UTF-16 `CGEvent` keyboard events, with native process-targeted Backspace and Return. Never read `AXValue`, use the pasteboard, or synthesize Command-V.

**Guard:** The real security boundary is the unlocked-session lease, Accessibility trust, exact focus/application anchoring, and cancellation on focus or app change. Do not equate a field hiding its contents with permission to disable ordinary keyboard input. Pin `AXTextField` plus `AXSecureTextField` classification in tests and retain a physical password-field acceptance gate after the signed install.

**Verification:** The focused Keypad/text-target suite passed 85 tests, and the clean full gate passed 523 Swift tests, 6 extension tests, 17 generator tests, generated-rule parity, both Karabiner lints, packaging/version checks, and shell syntax. Developer-ID-signed Agentic Mouse v1.0.86 (build 92) is installed as PID 90234 with executable SHA-256 `1314df3ccbb072d4869a835824687388e6b4d700e8597612ce6d86d57991de74`, Team ID `T34G959ZG8`, CDHash `a6dad303249395490f5ea55f37c5d05ce1475088`, Accessibility trust, and command-socket ownership. The embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `6c46f626dec9f36d72fe1d9e57e6f1c36e32a6ad2a99fc5856c2d6917280a607`. Physical acceptance still requires typing a nonsecret sample into one secure/password input and confirming the clipboard remains unchanged.

## 2026-08-20 — Replace Stay profile apps through supported capture and exact read-back

**Trigger:** Ethan replaced OBS Studio with OBS++ and then made the current positions of the intended `Agentic Mouse Layout v1` applications authoritative while OBS++ was actively recording.

**Cause:** Stay persists Store/overwrite operations asynchronously, and a broad capture can include the wrong frontmost application or overwrite matching metadata. An immediate command return is therefore not proof that the requested app and frames reached the saved profile.

**Fix:** Back up Stay's database and preferences first. Verify the exact frontmost bundle before each supported Store/overwrite operation, poll Stay's persisted records until the expected bundle and current frames appear, remove the superseded application through Stay's own editor, and preserve existing title regular expressions. Never edit Stay's Core Data database directly.

**Guard:** Treat Ethan's explicitly arranged current windows as authoritative only for the intended profile applications. Compare every other profile semantically before and after, compare untouched target applications separately, keep both automatic restore settings disabled, and do not trigger a restore merely to validate a profile update—especially while OBS++ is recording.

**Verification:** `Agentic Mouse Layout v1` now contains nine stored windows across seven applications: Activity Monitor (three windows), ChatGPT, VS Code, Chrome, OBS++, Surfshark, and Telegram. Old `com.obsproject.obs-studio` rows are zero and `com.ethansk.obs-plus-plus` rows are one. Semantic hashes for every row outside this profile match before and after at `190f45609f0a98c01ae024060655a7d142031bbfcf8711d5492ed3d810de79ee`; untouched Chrome, VS Code, and Surfshark rows match at `c618671de38cad66704f3372d4d521184391595a607fadc32598abc5bc79d487`. Automatic restore remains disabled and the manual Control-Option-Shift-Command-A shortcut is unchanged. OBS++ remained recording throughout. Ethan then physically invoked Corsair 12 → 12 → 1 and reported that the restore worked; immediate read-back found OBS++ exactly at its stored `{{3441, -883}, {1010, 818}}` frame, proving the refreshed profile and physical Corsair route end to end.

**Follow-up verification (2026-08-21):** After Ethan resized the still-recording OBS++ window, a maintenance-only `Store All Windows for OBS++` → `Replace` operation changed its one stored frame to the exact live `{{3440, -905}, {1011, 952}}`. A semantic before/after comparison found no other profile-row change, the Stay database passed `PRAGMA integrity_check`, the preferences plist stayed byte-identical, both automatic-restore settings remained disabled, and OBS++ continued recording. For a one-app resize, prefer this exact supported app-only capture over a broad layout recapture, and never fire a restore merely to verify the saved frame.

**Follow-up verification (2026-08-23):** A later OBS++ recapture proved that `Store All Windows for OBS++` can include a transient app-owned `AXDialog` as well as the intended `AXStandardWindow`. Visual and Accessibility inspection identified the installed `/Applications/OBS++.app` main window by its `OBS++ 32.2.2-obs-plus-plus` title and exact live `{{3440, -905}, {958, 934}}` frame; read-back then exposed an additional anonymous `66×20` dialog row. Remove such auxiliary rows through Stay's supported `Agentic Mouse Layout v1` editor before accepting the capture. The final profile contains exactly one `com.ethansk.obs-plus-plus` window at the live main-window frame and zero `com.obsproject.obs-studio` rows; every non-OBS stored row remained semantically unchanged, both automatic-restore settings remained disabled, and OBS++ continued recording. No restore was fired merely to test the profile while recording.

**Follow-up verification (2026-08-23, Surfshark):** Surfshark has the same auxiliary-window hazard: an application-wide capture persisted both its live `800×600` `AXStandardWindow` and a hidden `66×20` `AXDialog`, both titled `Window`. Use Stay's supported active-window capture for Surfshark, then identify any already-captured helper row through a temporary descriptive label in Stay's editor before deleting it; row order alone is not a safe identity. The refreshed profile contains only the live Surfshark main window at `{{4542, -899}, {800, 600}}` and ChatGPT at `{{1689, 341}, {1402, 899}}`. OBS++, Telegram, Chrome, VS Code, and Activity Monitor remained semantically unchanged at hash `d12a5fa42ef545f3c8f17c0c1d2cfef0fe8b66085c91392f71d0642620f9b07d`; the final profile is still nine windows across the same seven applications, title match patterns remain `^ChatGPT$` and `.*`, automatic restores remain disabled, the restore-hotkey archive is unchanged, and `PRAGMA integrity_check` returns `ok`.

**Follow-up verification (2026-08-25):** A clean one-row OBS++ capture did not guarantee restoration. A real Corsair 12 → 12 → 1 request reached Stay, which restored the other six profile applications but logged `com.ethansk.obs-plus-plus` as `WAS UNMATCHED` during both position and size phases. The persisted OBS++ row still pointed at the intended titled `AXStandardWindow`, so another recapture was not the fix. Set that row's supported Stay title pattern to `^OBS\+\+ ` and enable **Use Title Match Pattern Exclusively** through Stay's editor; the stable prefix matches the titled main window across version, profile, and scene suffix changes while excluding the anonymous helper dialog. Read-back proved exactly that pattern and exclusive flag on stored row 269, the saved `{{3440, -905}, {958, 934}}` frame remained unchanged, both automatic-restore settings remained disabled, and `PRAGMA integrity_check` returned `ok`. Treat this as implemented but not end-to-end verified until one later physical Corsair restore logs an OBS++ match and the live frame reaches the stored frame. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)

## 2026-08-20 — Use an ordinary reserved chord for Stay, not Quartz F14

**Trigger:** Agentic Mouse showed `Stay restore requested`, but Stay did not move any window. Ethan required preservation of the first saved `Agentic Mouse Layout v1` and an end-to-end movement-and-restore test.

**Cause:** Agentic Mouse's exact Quartz F14 down/up reached a listen-only event tap with key code 107, but Stay's MASShortcut/Carbon global-hotkey path did not activate. The same F14 sent by macOS System Events arrived through a different system path and restored the layout, proving the saved profile was healthy and the failure was event delivery rather than window matching.

**Fix:** Record a reserved Control-Option-Shift-Command-A global shortcut in Stay through its supported Settings UI, then emit physical key code 0 with a complete hardware-like modifier lifecycle from Agentic Mouse's existing long-lived HID event source. Keep the one-request-per-Extra-Utilities-visit latch and truthful requested/already-requested feedback. Do not use Stay AppleScript, UI automation, a helper process, or automatic restoration.

**Guard:** A successfully created or observable synthetic key event is not proof that a Carbon/global-hotkey destination accepted it. For future external shortcuts, displace one harmless target, compare its exact frame before and after, and prefer an ordinary reserved key chord when a function-key event is ignored. Preserve and compare the destination's stored state before testing.

**Verification:** Before the code change, the live Stay database and the task-owned known-good backup contained the same nine stored frames. A standalone copy of the old Quartz F14 path left `CPU History` at `4750,-299`; macOS System Events restored it to the saved `4722,-473`. After Stay recorded the reserved chord, the same native chord lifecycle used by Agentic Mouse restored a deliberately displaced `CPU History` window from `4802,-413` to exactly `4722,-473`, size `610x280`. The focused executor suite passed 13/13 and the final clean gate passed 523 Swift tests, 6 extension tests, 17 generator tests, generated-rule checks, packaging/version checks, and shell syntax; the added coordinator regression proves that a failed post leaves the retry latch clear and gives no false requested feedback. Developer-ID-signed Agentic Mouse v1.0.85 (build 91) was installed with executable SHA-256 `d4cdcaddcfa8c36c2e0a18647a38d0042eb65dea8a7ebd72e69e8499dcbd862f`; the later accepted v1.0.86 install preserved this route. Its command socket and Accessibility trust were live, while the embedded SDK, Agentic Mouse config, and Karabiner config retained SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `6c46f626dec9f36d72fe1d9e57e6f1c36e32a6ad2a99fc5856c2d6917280a607`. The live installed Corsair command route restored deliberately displaced `CPU History`, Telegram, and Surfshark windows to the exact original frames, and every other saved window also matched the untouched profile afterward. On 20 August Ethan physically invoked Corsair 12 → 12 → 1 against the refreshed OBS++ profile; immediate read-back found OBS++ at its exact saved frame, completing physical Corsair acceptance.

## 2026-08-20 — Latch slow external actions and report requests honestly

**Status:** Superseded for transport by the reserved Control-Option-Shift-Command-A chord documented above. The one-request-per-visit latch and honest requested-versus-confirmed feedback remain current.

**Trigger:** Ethan physically opened Extra Utilities and pressed Organize Windows while his windows were out of place. The HUD gave no visible result, so he retried; the live log recorded nine accepted presses in eight seconds while Stay did not visibly respond immediately.

**Cause:** The first implementation treated successful Quartz event submission as a completed action, left all later presses enabled, and updated only the selected card border. Stay owns the actual multi-display restore and can take several seconds; Agentic Mouse has no supported completion callback. Silence therefore encouraged a queue of repeated F14 restores without any truthful indication of what had happened.

**Fix:** Allow only one Organize Windows request per Extra Utilities visit. Immediately show `Stay restore requested` as informational—not confirmed—then show `Stay restore already requested` for later presses without emitting another F14. Exiting and deliberately re-entering Extra Utilities resets the latch for an intentional retry.

**Guard:** External one-shot actions with no authoritative result API must distinguish request submission from destination confirmation. Do not infer Stay success from CGEvent creation, do not let uncertainty generate repeated destructive/rearranging work, and never add an arbitrary timer that silently re-enables the action while the external app may still be processing.

**Verification:** The focused 74-test mode/utility suite and the full gate passed: 522 Swift tests, 6 extension tests, 17 generator tests, generator freshness, both Karabiner lints, packaging/version checks, and shell syntax. Developer-ID-signed Agentic Mouse v1.0.84 (build 90) is installed as PID 8064 with executable SHA-256 `b3bcabcf22e2cdfb2a89eb80f73494a54336a37ad334058bb35bb0f2bbbef18c`. Live logs prove the active macOS session, Accessibility trust, event tap, Karabiner command socket, iCUE reconnection, and both exact-device keypad routes. The embedded iCUE SDK, Agentic Mouse config, and live Karabiner configuration remain byte-identical; the install and automated checks emitted no F14 restore. Physical acceptance still requires one deliberate request and observation of Stay's resulting layout.

## 2026-08-20 — Nest infrequent manual utilities without changing device transports

**Status:** Superseded for transport by the reserved Control-Option-Shift-Command-A chord documented above. The nested page, canonical cell mapping, manual-only ownership, and universal exit remain current.

**Trigger:** Ethan wanted the spare physical cell 12 inside Utility to open an `Extra Utilities` page, with a manual Stay window-layout restore and the existing universal cell-10 exit.

**Cause:** Top-level physical cell 12 already opens Utility and both exact devices already deliver all twelve canonical press/release cells while a runtime mode is active. Replacing the top-level action or adding an iCUE/Karabiner transport would have duplicated ownership and regressed the accepted Utility entry.

**Fix:** Preserve top-level cell 12 as Utility, then reinterpret the same canonical cell only inside Utility as the nested Extra Utilities entry. Put `Organize Windows` on canonical cell 1 (Corsair printed 1 / Razer printed 3) and emit one unmodified F14 down/up lifecycle through the existing unlocked-session and Accessibility-gated semantic executor. Stay remains the profile and window-placement owner; Agentic Mouse never restores automatically and never uses Stay AppleScript or UI automation.

**Guard:** Keep page semantics above the shared canonical crosswalk, preserve universal cell 10 as the direct exit to Default, and leave live iCUE/Karabiner bytes unchanged. Tests must pin both mice's printed projections, page navigation, single press-only dispatch, exact F14 lifecycle, lock/TCC failure paths, and absence of automatic restore. Physical acceptance still requires one deliberate restore from each mouse after the signed install.

**Verification:** The full gate passed 521 Swift tests, 6 extension tests, 17 generator tests, generator freshness, both Karabiner lints, packaging/version checks, and shell syntax. Developer-ID-signed Agentic Mouse v1.0.83 (build 89) is installed as the sole PID 57526 with executable SHA-256 `474681fe23b16b10c5fddfef45c9a43cb9b6e51f1498cae5203294356ea1c768`; its designated requirement and deep/strict signature validate. The system Accessibility grant is current and certificate-based, the Karabiner user-command socket is owned by PID 57526, and the embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and `6c46f626dec9f36d72fe1d9e57e6f1c36e32a6ad2a99fc5856c2d6917280a607`. No F14 restore was emitted during automated verification; physical page navigation and one deliberate Stay restore remain Ethan-owned acceptance.

## 2026-08-19 — Reuse the app-mode entry cell as a child-only exit

**Trigger:** Ethan wanted every automatic or manually selected app-specific child to exit through the same physical cell 2 that opens frontmost-app mode, while preserving universal cell 10 as Exit.

**Cause:** The app pages treated cell 2 as an ordinary action slot. Merely changing the HUD label would have left the old action reachable on release or after a later rendering change, and the parent Choose App selector legitimately uses cell 2 to select Terminal.

**Fix:** Reserve physical cells 2 and 10 structurally on every `.appSpecific` child, consume both press/release phases, and let either press end the mode. Keep the parent `.appSelector` exception: cell 2 selects Terminal there and cell 10 exits. Render both child cards from the same exit rule in specialized, data-driven, and unsupported app definitions. Move Codex New Chat to cell 5, move Chrome Hold 2× Speed to cell 7, retire the redundant broken Codex New Voice Chat card, and remove the displaced Quick Open/New Window or packed starter-page cell-2 actions rather than leaving hidden collisions.

**Guard:** Automatic and manual journeys must keep sharing `AppSpecificTarget.definition`. Tests must pin both exits on every configured and unsupported child, verify cell-2 release is inert, prove selector cell 2 still chooses Terminal before becoming Exit, and reject any app action assigned to either reserved exit cell.

**Verification:** The full gate passed 518 Swift tests, 6 extension tests, 17 generator tests, generator freshness, both Karabiner lints, and packaging/version checks. Signed Agentic Mouse v1.0.82 (build 88) was installed as PID 80257 with executable SHA-256 `3a1282d8f2e2f253acd6edd6df55fc1fbf9e23645b603dad4faf3c8e97d2f934`; the embedded iCUE SDK, live Agentic Mouse config, and live Karabiner configuration remained byte-identical.

## 2026-08-18 — Keep Chrome history navigation in the Default base map

**Status:** Superseded in part on 2026-08-20. Chrome history navigation still belongs only to Default mode, but Chrome child cell 8 is now the distinct non-history `Close current window` action.

**Trigger:** Chrome mode exposed separate Back and Forward cards, and the Forward card zoomed the page instead of navigating history on Ethan's active Dvorak layout.

**Cause:** The child action synthesized Command-Left-Bracket / Command-Right-Bracket by physical key code. That layout-sensitive transport was not equivalent to the already-working native auxiliary-button Forward/Back behavior in the Default map.

**Fix:** Remove Chrome-specific Back and Forward actions completely. Keep Chrome cell 8 as an honest Spare, move New Tab to physical cell 5, move Reload Current Tab to physical cell 6, and later reuse cell 7 for Hold 2× Speed when app-child cell 2 became a duplicate Exit. Preserve browser history navigation only in the Default base map.

**Guard:** Automatic and manual Chrome journeys must share this one `ChromeMode.definition`. Tests must reject Back/Forward history actions, keep close-tab/window distinct from history, and pin New Tab/Reload on cells 5/6. Never reintroduce Command-Bracket browser history shortcuts as a substitute for the native base mouse buttons.

## 2026-08-18 — Keep frequent Codex Steer under the closest thumb cell

**Trigger:** Ethan uses Steer Queued Message frequently and asked for it on Corsair printed 1, with the less-frequent Voice Mic toggle moved to Corsair printed 9.

**Fix:** Swap only the canonical Codex action cells: Steer uses physical cell 1 and Mute/Unmute Voice Mic uses physical cell 9. Project both through the established crosswalk, so the left-handed Razer shows Steer on printed 3 and Voice Mic on printed 7. Keep the action executors and shortcuts unchanged.

**Guard:** Automatic frontmost Codex mode and manually selected Codex mode must continue to share `CodexMode.definition`. Pin both canonical cells and both devices' printed projections in tests; never interpret a Corsair-number request as permission to diverge the Razer semantics unless Ethan explicitly asks for device-specific behavior.

## 2026-08-18 — Resolve Realtime Voice through the active Dvorak modifier path

**Trigger:** Codex Open Side Chat and Mute/Unmute Voice Mic were physically accepted, but both Voice Mode cards still did nothing even though Agentic Mouse reported dispatching Codex's configured Control-Shift-V `realtimeVoice` hotkey.

**Cause:** The selected input source is `DVORAK - QWERTY CMD`. Control+Shift does not activate its QWERTY-Command remap. macOS key code 9 therefore resolves to semantic `k`, not `v`; a direct `UCKeyTranslate` probe pinned key code 47 as semantic `v`. The earlier Side Chat repair was the same class of bug: its accepted Command+Option-S route uses key code 41 rather than QWERTY-S key code 1.

**Fix:** Keep the supported foreground System Events transport and Ethan's existing Codex binding unchanged, but send key code 47 with Control+Shift for both Voice Mode and New Voice Chat. Continue to invoke `realtimeVoice` directly without creating a plain Command-N chat first. Do not return to `AXPress` or coordinate clicking: the current sidebar exposes an exact enabled `Start new voice chat` button, but prior live testing proved that a successful Accessibility press did not make Electron perform the action.

**Guard:** Pin the physical keycode and modifiers in the executor and AppleScript-generation tests. Treat displayed shortcut letters as semantic characters that must be resolved against the active modifier/layout path. Clear repair markers only from Toggle Terminal, Open Side Chat, and Voice Mic, which Ethan explicitly accepted; keep Voice Mode and New Voice Chat marked until a later physical success report.

## 2026-08-18 — Coalesce paired DPI releases before VoiceInk Primary gestures

**Trigger:** Pressing and releasing both Razer DPI buttons together emitted two normalized VoiceInk++ Primary chords, so the first could begin recording and the second immediately stop or cancel it.

**Cause:** Karabiner exclusively owns the Razer and Corsair keyboard interfaces and normalizes F21, F22, and F19 into the same Primary shortcut. VoiceInk++ cannot recover the originating transport. Its old 500 ms generic shortcut cooldown is intentionally bypassed for Primary because applying it would erase the accepted 450 ms double-click pause and triple-click clipboard gestures.

**Fix:** Keep all three exact-device transports release-only and make VoiceInk++ the single coalescing owner. Before its existing Primary gesture classifier, accept the first complete chord immediately and discard only a second complete chord whose event timestamp is within 90 ms. Do not add a second timer in Agentic Mouse or Karabiner and do not attempt passive raw-HID source sniffing while Karabiner holds exclusive ownership.

**Guard:** Pin the narrow duplicate window, handler-level `.starting` cancellation race, deliberate double/triple timing, modifier normalization, Primary/Next isolation, recovery, HUD, queue, and lock behavior in VoiceInk tests. Require physical F21, F22, F19, paired-release-from-idle, paired-release-while-recording, deliberate double, genuine triple, both Next routes, and locked-session acceptance before closing the hardware item.

**Verification:** The signed installed VoiceInk++ v2.0.303 source is `c109d7b24bc64bbc94eddb44b3362a89b3d7a932` with implementation commit `b10650016afe4a5147958d43dac973d7b1ad8284`; executable SHA-256 is `9f463eefac137e20d8839295fb2a3fad04d1c85a54f6bdf097ec7a9e2d7d3834`. After the canonical Xcode action stalled for ten minutes with zero named tests, the documented already-built-bundle fallback passed 249/249 named tests across 8/8 suites with zero failures. The pre-install recording completed without interruption and official `/Applications/VoiceInk.app` remained byte-identical.

## 2026-08-18 — Reconstruct wheel ratchets and post hardware-like shortcuts

**Trigger:** One physical wheel ratchet could arrive as several phase-free Quartz events, so Copy/Paste repeated, two-state system controls could toggle themselves back, and Magnet often failed to traverse a second display even though the same physical Control-Option-Arrow shortcut worked from the keyboard.

**Cause:** The HUD diagnostic throttle never changed action cadence. Most wheel actions posted synthetic events synchronously from the event-tap callback, modifier keys used ordinary key-down events rather than `flagsChanged`, each call created a fresh event source with the default local-event suppression interval, and Magnet emitted an unpaced six-event burst before its previous animated placement had committed. A queued Magnet request could also outlive the physical hold through a main-queue race.

**Fix:** Give every `WheelChordControl` an explicit semantic dispatch policy. Brightness and Zoom remain continuous; Horizontal Scroll, Copy/Paste, Chrome Tabs, and Magnet coalesce same-direction raw bursts while accepting an immediate reversal; Mission Control / Show Desktop, App Exposé, and Spaces act once per physical hold. Post all synthetic keyboard work only after returning from the Quartz callback through one long-lived HID source with local suppression disabled, real `flagsChanged` modifier transitions, pre-created events, increasing timestamps, and bounded dwell. Reconstruct Magnet detents with a 150 ms quiet window, serialize them 400 ms apart through a three-request FIFO, and reject or cancel pending work when the exact hold releases or the input lease closes.

**Guard:** Never use the HUD throttle as an action debounce, never debounce analogue Brightness/Zoom, and never blindly drop a direction reversal. Pin action cadence, raw-burst suppression, physical event phases/flags, Magnet FIFO order/depth, release cancellation, lock teardown, and generated/live-state preservation in tests. Keep Magnet and Mission/Desktop marked `❌` until Ethan physically accepts both directions; successful event creation is not proof that the destination app handled the shortcut.

**Verification:** The focused 45-test wheel/executor suite and the full gate passed: 515 Swift tests, 6 extension tests, 17 generator tests, generator freshness, both Karabiner lints, the app-version contract, and packaging-script syntax. Signed Agentic Mouse v1.0.78 (84), executable SHA-256 `30c6b799d10872226164377fb31a41e3ee459ed6702bcaa49065cbaa9bae5ce4`, is installed as PID 87040 with Accessibility trust, command-socket ownership, embedded audited iCUE SDK SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, config SHA-256 `e762a0851f7f202c9353e68ded68cb426d2126bfc8773d33400feb92a71bd3e7`, and live Karabiner SHA-256 `6c46f626dec9f36d72fe1d9e57e6f1c36e32a6ad2a99fc5856c2d6917280a607`. Physical wheel and cross-monitor Magnet acceptance remains open.

## 2026-08-18 — Replace Utility window cycling with native App Exposé

**Trigger:** `App Windows + Wheel` cycled the frontmost app with Command-` / Shift-Command-`, but Ethan clarified that he meant the native four-finger swipe-down view of all windows for the current app.

**Fix:** Keep shared physical cell 5 in the existing held-wheel router, rename it `App Exposé + Wheel`, ignore and consume wheel-up, and map the first wheel-down per physical hold to this Mac's enabled Application Windows symbolic hotkey 33: Control-Fn-Down. Route it through `SystemOverviewActionExecutor` rather than Accessibility or Dock UI automation.

**Guard:** Treat App Exposé as a system toggle and allow only one invocation per physical hold; extra ratchets must remain consumed until release. Pin the local keycode/flags, down-only direction, one-action latch, duplicate-press resistance, HUD copy, and shared Corsair/Razer physical cell in tests. The 17 August Command-` window-cycle entry below is superseded.

**Verification:** The full gate passed 509 Swift tests, 6 extension tests, 17 generator tests, generator freshness, both Karabiner lints, the app-version contract, and packaging-script syntax. Signed Agentic Mouse v1.0.77 (83), executable SHA-256 `df643dc459adc75ebf48faf9d06702fc2cb0aa0888c3c0e4a03ee996eae9972c`, is installed and Accessibility-trusted with the prior config, live Karabiner file, and embedded audited iCUE SDK preserved. Physical App Exposé acceptance remains open on both mice.

## 2026-08-18 — Limit Spaces to one move per physical hold

**Trigger:** Multiple wheel ratchets during one held top-level Spaces chord jumped across several desktops, which made the compact gesture too easy to overshoot.

**Fix:** Let the first accepted phase-free wheel event after physical cell 1 is pressed choose Space Right or Space Left from its sign and post exactly one configured Control-Fn-Arrow lifecycle. Consume every later ratchet, including a reversed sign, without another action until the real release clears the hold and the next press re-arms it.

**Guard:** A duplicate press command cannot re-arm an already-held Spaces chord. Reset on release, source loss, lock, sleep, reload, event-tap teardown, and app shutdown. Keep Horizontal, Utility, Chrome Tabs, and Magnet per-ratchet; pin both the one-action latch and those unaffected families in tests.

## 2026-08-18 — Derive app-specific starter pages from measured use and one canonical definition

**Trigger:** Most recognized apps still showed Spare cards even though Ethan wanted immediately useful starter controls for the apps he actually uses, available through both frontmost detection and the lower-priority manual chooser.

**Fix:** Rank apps from aggregate Screen Time `/app/usage` durations without reading titles, URLs, messages, or document text; corroborate the result against installed bundle identities and the Dock. Derive commands from each installed app's exact Accessibility menu accelerators plus current official shortcut documentation. Put ordinary shortcut-only pages in `StandardAppMode`, keep stateful/gesture pages specialized, and resolve both journeys through the same `AppSpecificTarget.definition`.

**Guard:** Universal cell 10 remains Exit, shortcut cells must be unique, and every action stays bounded by lock, Accessibility, exact bundle, and running-process gates. Do not invent a shortcut to fill a slot, expose private usage hours in public docs, or activate an app merely to simulate background delivery. Keep maintenance apps sparse when their real menu exposes only a few safe commands, and require physical acceptance before treating a starter map as final.

## 2026-08-18 — Finish requested Agentic Mouse changes in the installed app

**Trigger:** A fully tested Keypad correction was left only in source because an older one-turn no-silent-install boundary was incorrectly treated as a permanent project rule.

**Fix:** Treat an explicit request to change or fix Agentic Mouse as authorization for the repository's normal stable signed install/relaunch completion step. After the full gate, bump both real version identifiers once, preserve the installed bundle as rollback, warn before the brief restart, install and relaunch the exact `/Applications` path, then read back identity, hashes, PID, socket, and preserved live state.

**Guard:** Stop short only for an explicit source-only/no-install instruction, a current ownership or safety conflict, or a real user-only permission gate. Never confuse automated/install verification with physical acceptance, and never extend this narrow app-install authority to Karabiner, iCUE, permissions, firmware, publication, or unrelated software.

## 2026-08-18 — Keep runtime Keypad labels physical and put editing on the back corner

**Trigger:** The runtime Keypad still displayed the historical phone `* / 0 / #` bottom row and spent its rear controls on Shift and Space/Return, leaving no convenient Backspace. The Razer's large labels therefore looked vertically wrong even though its small source labels used the correct crosswalk.

**Fix:** Keep universal cell 10 as Exit, make cell 11 Space, and make cell 12 tap Backspace or hold Return. Remove the runtime Shift control. For `.modesKeypad`, render each large legend from `PhysicalCell.printedSide(on:)` instead of `MultiTapKey.keypadLegend`; this gives Corsair 1–12 and places Razer printed 1 at its real top-right position without changing canonical semantics.

**Guard:** Retain the classic phone glyphs only for the standalone historical keymap. Runtime source labels and big positional legends must agree, cell 3 must remain DEF, cells 1–9 retain digit holds, and cell 10 must remain the universal exit. Pin both source grids and the tap/hold command lifecycles in hardware-free tests, then require a physical both-mouse typing sweep.

## 2026-08-18 — Keep Chrome New Tab browser-native and share one app definition

**Superseded placement:** New Tab was first added on physical cell 6. The current top entry moves it to physical cell 5 when Reload and New Tab are swapped.

**Trigger:** Ethan requested a New Tab button in Chrome mode.

**Fix:** Add `New tab` on canonical physical cell 6 (Corsair printed 6 / Razer printed 4) and send Chrome's standard Command-T accelerator directly to the running Chrome process on press only. Source the card from the same `ChromeMode.definition` used by automatic frontmost-app mode and manual Choose App → Chrome.

**Guard:** Preserve release as inert, the lock and Accessibility gates, Chrome's current focus/window state, and every existing Chrome control. Mark the card normal until a physical failure is reported; awaiting acceptance alone is not a broken-control marker. Pin the canonical cell and exact key code/flags in tests, then require one physical New Tab invocation from each mouse before acceptance.

## 2026-08-18 — Keep HUD repair markers tied to Ethan's latest physical report

**Trigger:** Source changes and successful automated checks repeatedly made a control look finished even when Ethan's latest physical attempt still failed. Edit Queued Message is the clearest current example: its card exists, but pressing it does nothing.

**Fix:** Give each `ModeHUDLegendItem` an explicit `ModeHUDControlStatus`. Render `reportedBroken` as a red-cross suffix on the exact source label (`Corsair n ❌` or `Razer n ❌`) while leaving the action title and shared semantic mapping unchanged. Reconcile that state from the chronological physical reports: a later explicit success clears an earlier failure; a source fix, test pass, reinstall, or lack of testing does not.

**Guard:** Do not mark merely untested controls. Keep a combined wheel card marked when either direction remains broken or materially unreliable. Remove retired controls instead of preserving them with a cross. Update source, tests, the hardware reference, and the outstanding-item acceptance record together whenever a physical report changes a marker.

## 2026-08-17 — Resolve Codex Side Chat through the active Dvorak modifier path

**Trigger:** Open Side Chat reported successful System Events dispatch but did not toggle Codex's side chat. Ethan identified that he physically invokes the displayed Command-Option-S accelerator from the semicolon-position key, not the QWERTY S-position key.

**Cause:** The selected input source is `DVORAK - QWERTY CMD`. With Command+Option held, Codex's semantic S accelerator is reached through macOS key code 41, the physical semicolon position. Agentic Mouse was sending key code 1, the physical QWERTY S position, so System Events honestly sent the wrong layout-resolved character.

**Fix:** Keep Codex frontmost and retain the supported System Events route, but send key code 41 with Command+Option for `openSideChat`. Do not change Ethan's Codex keyboard shortcut or globally change shortcut dispatch for unrelated actions.

**Guard:** Pin the exact physical key code and modifiers in both executor and AppleScript-generation tests. Treat the menu's S as a semantic character, not proof that QWERTY key code 1 is correct under a non-QWERTY input source with multiple modifiers. Require physical toggle acceptance before calling Side Chat fixed.

## 2026-08-17 — Pace repeated Magnet accelerators without dropping ratchets

**Trigger:** One Utility Magnet wheel ratchet could move the frontmost window, but immediately ratcheting Right again usually failed at the display boundary even though the identical physical Control-Option-Right shortcut traversed monitors reliably.

**Cause:** Every accepted detent posted a complete six-event Magnet shortcut immediately. Magnet animates placement and derives the next Right/Left result from the window's newly committed frame and screen. A second synthetic accelerator could therefore arrive while Magnet still held the previous placement state. Event creation and a posted-shortcut log proved only dispatch, not that Magnet had committed the first move.

**Fix:** Keep the working physical Control-Option-Arrow lifecycle, but pass accepted Magnet detents through one main-actor FIFO sequencer with a 250 ms minimum interval between shortcut posts. Preserve order and direction and never discard a legitimate ratchet. Log accepted queue depth and each actual post separately so a physical trace can distinguish duplicated ingress from Magnet handling.

**Guard:** Do not add a blind global debounce or return to menu automation. Cancel queued requests on lock, sleep, mode/source teardown, reload, or shutdown so a late shortcut cannot move a window after its input lease ends. Pin FIFO order, interval, per-source cancellation, lock cancellation, and stale callback rejection in tests; retain slow and rapid both-mouse, multi-display physical acceptance.

## 2026-08-17 — Use System Events for current ChatGPT Electron accelerators

**Trigger:** In installed Agentic Mouse v1.0.69 (75), Open Side Chat did nothing, Voice Mode did nothing, and New Voice Chat created only a plain chat. The current app is `/Applications/ChatGPT.app` 26.810.52044 with bundle identifier `com.openai.codex`.

**Cause:** The app still registers Command-Option-S for `openSideChat`, while the new sidebar Voice control uses the OS-global `realtimeVoice` command on Control-Shift-V. Complete Quartz key lifecycles and exact `AXPress` calls both reported success while Electron performed no action. The same shortcuts sent through macOS System Events immediately opened Side Chat and started/stopped the Realtime Voice overlay.

**Fix:** Keep ChatGPT frontmost and dispatch these Electron app/global accelerators through `NSAppleScript` to System Events. Map both Voice Mode and New Voice Chat to the current Realtime Voice shortcut; it creates the voice thread directly, so never create a plain Command-N chat first. Keep renderer-owned commands on the existing PID-targeted path.

**Guard:** Use only fixed keycodes and the four supported modifier flags; reject any unsupported flag. Keep the lock, Accessibility, frontmost-app, and exact-process gates. Preserve Ethan's existing Codex shortcuts and label results as sent until an authoritative UI state change is observed. Do not regress to Quartz timing tweaks or Accessibility-button success claims.

## 2026-08-17 — Preserve physical arrow flags in Magnet's global shortcut

**Trigger:** The Accessibility menu-command workaround moved windows within one display but did not reproduce the cross-monitor behavior Ethan gets from Magnet's configured Control-Option-Left/Right keyboard shortcuts.

**Cause:** The earlier global sender used Control and Option but omitted the physical arrow event's `maskSecondaryFn` and `maskNumericPad` flags. That produced terminal escape sequences while failing to reproduce Magnet's registered accelerator. A read-only Magnet preference/Accessibility audit confirmed its enabled shortcuts are Carbon keycodes 123/124 with Control+Option, and a disposable TextEdit probe proved the complete shortcut reaches Magnet.

**Fix:** After the wheel callback returns, post one pre-created six-event lifecycle from one HID event source: Control down, Option down, Arrow down/up with Control+Option+SecondaryFn+NumericPad, Option up, Control up. Let Magnet own placement and any display traversal; do not imitate it through menu-bar Accessibility actions.

**Guard:** Pin every keycode, phase, and flag. Build the whole sequence before posting so allocation failure cannot strand a modifier. Keep lock and Accessibility gates, one detent per action, and dual-source fail-closed routing. Retain a physical both-mice, multi-display acceptance gate rather than claiming cross-monitor success from event creation alone.

## 2026-08-17 — Prefer Codex's built-in Command-Return Steer shortcut

**Trigger:** The queued-message Steer card used brittle Accessibility-tree discovery because earlier investigation incorrectly treated Steer as an unbound row-only action. Ethan identified Codex's actual built-in Steer accelerator as Command-Return.

**Fix:** Route `CodexModeAction.steerQueuedMessage` through the same bounded, lock-gated, Accessibility-trusted `CGEvent.postToPid` dispatcher as Codex's other built-in shortcuts: one Command-Return key down/up cycle targeted to the running Codex process. Keep queued-row Accessibility discovery only for Edit Queued Message, which still has no keyboard accelerator.

**Guard:** Pin the exact Return keycode and Command flags in executor tests. Do not replace a working Codex built-in accelerator with UI automation, and do not describe successful event posting as proof that Codex completed the action.

## 2026-08-17 — Keep app-window cycling inside the shared held-wheel router

**Status:** Superseded by the 18 August native App Exposé mapping above.

**Trigger:** Ethan assigned Utility physical cell 5 to cycle the frontmost app's windows with one ratcheted-wheel control instead of spending two cells.

**Fix:** Add one shared `applicationWindowCycle` control to the existing exact-device Utility press/release lifecycle. One wheel-up detent posts a bounded Command-` key down/up cycle; one wheel-down detent posts Shift-Command-`. Reuse the source-owned wheel state, one-detent routing, lock gate, Accessibility gate, ambiguity handling, and release teardown rather than creating a second monitor or device-specific map.

**Guard:** Keep the action canonical on physical cell 5 for both mice, leave the frontmost app active, attempt key-up even after a failed key-down, and never retain global Command or Shift state between detents. Pin direction, keycode 50, modifier flags, HUD copy, exact-cell arming, and fail-closed errors in hardware-free tests; retain physical next/previous-window acceptance on both exact mice.

## 2026-08-17 — Invoke Magnet's command instead of synthesizing its shortcut (superseded)

**Status:** Superseded by the later physical-arrow-flag probe above. The failure applied to an incomplete synthetic arrow event, not to every complete Control-Option-Arrow lifecycle.

**Trigger:** Utility's Magnet card counted and consumed wheel ratchets, Magnet was running with enabled Control-Option-Left/Right shortcuts, but no window moved. With a VS Code terminal focused, the wheel printed `^[[1;7C` / `^[[1;7D`, proving the exact Control-Option-Arrow events leaked into the frontmost app.

**Historical diagnosis:** This was initially blamed on all synthetic Quartz shortcuts after the terminal consumed `^[[1;7C` / `^[[1;7D`. The later physical-event trace proved that conclusion was too broad: the rejected sequence omitted the physical arrow flags, so it was not a complete hardware-equivalent accelerator. Karabiner's CLI still cannot inject keys, and its real VirtualHID client remains intentionally root-only, so moving this user-level runtime onto that transport would introduce the wrong privileged-helper boundary.

**Fix:** Return from the wheel callback, find the running signed Magnet app by its exact bundle identifier, resolve `AXExtrasMenuBar`, require its one pressable status item, open it, then press only its exact enabled `Left` or `Right` menu command. `AXUIElementPerformAction` can return `cannotComplete` when opening the status item even though menu tracking started; accept only that result or success, then use the command press result as the authoritative boundary. This preserves Magnet as the placement-policy owner and leaves its private preferences untouched.

**Guard:** Never send Magnet's global shortcut through CoreGraphics, because successful event creation proves neither interception nor placement. Do not traverse only application `AXChildren`; status extras live under `AXExtrasMenuBar`. Require Accessibility trust, exact bundle/role/title/action matching, one unambiguous status item, bounded traversal, status-menu opening, and fail-closed cleanup. Pin direction, lock gating, exact command names, and failure handling in tests; retain one-detent physical acceptance on both exact mice.

## 2026-08-17 — Keep the optional credential action discreet on mapping surfaces

**Trigger:** Ethan did not want a casual user of the Mac to learn from the Utility legend that one button can type a stored credential.

**Fix:** Keep the internal `.pasteStoredPassword` action and its device-local Keychain security boundary unchanged, but render its action title as exactly `PP` in the live legend and public mouse map. Use only `Private action.` as the public map detail.

**Guard:** Treat `PP` as discreet presentation, not authentication. Continue requiring the unlocked-session lease, Accessibility trust, and the `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` Keychain item; never move the credential into labels, logs, source, config, generated rules, or the clipboard.

## 2026-08-17 — Hide presenters directly after lock-state teardown

**Trigger:** Ethan required every visible legend to disappear when the Mac locks.

**Fix:** Keep the coordinator-owned destructive session teardown, then perform one final presenter-level `hide()` sweep across both source-specific mode presenters and both Keypad presenters. This also removes transient feedback panels and any panel whose coordinator already believes it is inactive. Unlock starts from the ordinary map and never restores the hidden HUD.

**Guard:** Treat coordinator shutdown and presenter hiding as complementary security boundaries. Pin the final sweep across both presenter families in a hardware-free test, keep the call after state teardown, and never make unlock reconstruct prior legend visibility.

## 2026-08-17 — Resolve app-specific HUD artwork from app identity, not bundled assets

**Trigger:** Ethan asked app-specific mode slots to use a blurred version of the named app's real icon, then immediately rejected an implementation that spread the icon across the entire HUD panel.

**Fix:** Put a stable `ModeHUDAppBackdrop` only on `ModeHUDLegendItem` cards that name a concrete app. The top-level current-app slot provides the exact running `.app` path and bundle identifier; named `Choose app` slots provide their canonical bundle identifiers. Resolve and cache the installed icon in `ScimitarUI`, then enlarge it and apply only moderate blur edge-to-edge inside that slot behind its white label, preserving enough shape to recognise the app.

**Guard:** Never apply the app icon to the outer panel, the selected child app page, selector spares, or unrelated cards. Prefer an existing exact bundle path, fall back to `NSWorkspace` bundle lookup, never copy or persist icon bytes, and rebuild the resolved-card dictionary from each snapshot so stale artwork clears. Pin top-level path identity, selector bundle identity, path precedence, bundle fallback, cache, and clear-on-refresh behavior in tests.

## 2026-08-17 — Compact Mission Control and Show Desktop into one wheel chord

**Trigger:** Ethan asked to reclaim one Utility slot by pairing the two system-overview actions on a held ratcheted wheel.

**Fix:** Utility physical cell 4 now owns one `Mission / Desktop + Wheel` control on both mice. Wheel up invokes Mission Control and wheel down invokes Show Desktop through the existing bounded `SystemOverviewActionExecutor`; physical cell 5 becomes Spare. Top-level physical cell 4 remains Horizontal Scroll and is unaffected outside Utility.

**Guard:** Keep the pair inside `WheelChordControl` rather than the one-press `directAction` route, consume exactly one accepted detent per action, preserve the existing Accessibility and unlocked-session gates, and test both direction resolution and shared Corsair/Razer printed-cell projection. The older direct cell-4/cell-5 layout below is historical and superseded.

## 2026-08-17 — Keep terminal interruption inside terminal-capable app modes

**Status:** The terminal-specific ownership remains current. The sentence that Utility cell 12 stayed Spare was superseded on 2026-08-20 when that cell became the nested Extra Utilities entry.

**Trigger:** Ethan clarified that Ctrl-C is contextual rather than a general Utility action and asked to reclaim Utility cell 12.

**Fix:** Remove Interrupt Terminal from `ModeUtilityAction` and leave Utility cell 12 honestly Spare. Add Terminal and iTerm to the shared automatic/manual app registry, and expose one `Interrupt terminal` card on app-specific physical cell 12 for VS Code, Terminal, and iTerm. Route every variant through the same bounded PID-targeted Control-C shortcut with the existing lock and Accessibility gates.

**Guard:** Detect exact bundle identifiers (`com.microsoft.VSCode`, `com.apple.Terminal`, and `com.googlecode.iterm2`), keep automatic and manual app journeys on the same definitions, never reactivate the Utility route, and require one harmless physical interrupt in each app before acceptance.

## 2026-08-17 — Rotate GitHub Pages asset keys when map data changes

GitHub Pages served Agentic Mouse JavaScript with `Cache-Control: max-age=600`, so a successful Pages build did not by itself prove that a returning browser would load a changed interactive map. Whenever public CSS or JavaScript bytes change, rotate the version query in every referring HTML file, then fetch the exact versioned live URL and require its SHA-256 to match the committed asset before calling the UI current.

## 2026-08-17 — Fall back to a clipboard lease when an editor hides AX focus

**Status:** Historical and superseded for the active Keypad path by the direct-Unicode trial below. The ownership-marked implementation remains in source only as rollback evidence until physical acceptance is complete.

**Trigger:** Keypad entered normally over Spotify, but the focused Chromium-backed input produced `Could not determine what has keyboard focus` even though ordinary typing worked.

**Cause:** `AccessibilityTextTargetResolver` treated a missing or non-editable `AXFocusedUIElement` as proof that no text destination existed. Some custom/Chromium controls accept native Command-V while exposing only their frontmost application, so the fail-closed check rejected a real foreground editor before text output ran.

**Fix:** Keep exact AX element anchoring whenever it is available and keep secure AX roles blocked. Otherwise fall back to the unchanged frontmost application PID. Insert committed Keypad characters through one ownership-marked pasteboard lease and the ordinary Command-V lifecycle, then restore every prior pasteboard item only if that lease still owns the pasteboard. A newer user/app clipboard write always wins. Backspace and Return remain process-targeted native keys.

**Guard:** Re-resolve the destination before every irreversible event. An exact AX target still cancels on a same-app field move; an app-scoped fallback accepts stronger AX exposure in the same PID but cancels immediately on an app switch. Pin complete multi-format restoration, rapid consecutive characters, user clipboard races, target changes, late AX exposure, and native control keys in tests. Signed v1.0.54 (60) passed the full 481-Swift / 6-extension / 17-generator gate and retained Accessibility trust; physical Spotify entry remains the acceptance boundary.

## 2026-08-18 — Keep Keypad text direct and process-targeted

**Trigger:** After the clipboard fallback was installed, a dictated report described a suspicious Keypad 8 multi-tap interaction and Ethan asked to return to direct text delivery rather than altering the pasteboard.

**Fix:** Keep the AX resolver's exact-element-or-frontmost-PID safety boundary, but deliver committed characters as UTF-16 strings on process-targeted `CGEvent` key pairs. Accept a newly exposed AX element only when the captured anchor was application-scoped and its PID is unchanged. Backspace and Return remain process-targeted native keys.

**Guard:** Keypad must not read, write, lease, or restore the pasteboard and must not synthesize Command-V. Pin direct Unicode payloads, process targeting, same-PID AX strengthening, app-switch rejection, exact-element movement rejection, and native Backspace/Return in tests. Physical acceptance still needs an ordinary Cocoa field plus Spotify/Chromium before the unused clipboard fallback can be removed.

## 2026-08-17 — Keep Chrome reload browser-native and share one app definition

**Superseded placement:** Reload was first added on physical cell 5. The current top entry moves it to physical cell 6 when Reload and New Tab are swapped.

**Trigger:** Ethan requested a Chrome-mode button that reloads the current tab.

**Fix:** Add `Reload current tab` on canonical physical cell 5 and send Chrome's standard Command-R accelerator directly to the running Chrome process on press only. Source the card from the same `ChromeMode.definition` used by automatic frontmost-app mode and manual Choose App → Chrome.

**Guard:** Treat reload as browser chrome, not a page-level VoiceInk extension action. Preserve release as inert, lock and Accessibility gates, Chrome's current focus/window state, and every existing Chrome control. Pin the canonical cell and exact key code/flags in tests, then require one physical reload from each mouse before acceptance.

## 2026-08-17 — Compact paired Utility actions into held-wheel controls

**Status:** The compact physical-cell layout remains current. Its original Magnet menu-command transport is superseded by the complete keyboard-shortcut lifecycle documented at the top of this file.

**Trigger:** Ethan asked to reclaim Utility space by combining Copy/Paste on physical cell 3 and adding Magnet left/right window placement on physical cell 6.

**Fix:** Reuse the existing exact-device held-wheel state machine for both controls. Clipboard maps wheel up to one Command-V Paste cycle and wheel down to one Command-C Copy cycle. Magnet maps wheel up/down to one complete Control-Option-Right/Left accelerator lifecycle per accepted phase-free ratchet.

**Guard:** Remove Utility's old native one-press Copy/Paste Karabiner outputs so pressing or releasing the held control cannot fire an extra action. Keep Magnet as the placement-policy owner, preserve the unlocked-session and Accessibility gates, consume ambiguous dual-mouse holds without guessing, and require physical direction/one-ratchet acceptance on both exact mice.

## 2026-08-17 — Toggle VS Code's terminal, not its generic panel

**Trigger:** Ethan physically observed that VS Code mode's Toggle Terminal card closed an open terminal but did not reopen it.

**Cause:** Agentic Mouse translated the semantic terminal command to Command-J. That is VS Code's generic panel visibility shortcut, not the dedicated integrated-terminal toggle.

**Fix:** Translate `VSCodeModeCommand.toggleTerminal` to VS Code's documented Control-` `workbench.action.terminal.toggleTerminal` binding. Keep the physical cell, HUD title, shared automatic/manual app definition, and PID-targeted delivery unchanged.

**Guard:** Pin key code 50 plus Control in an app-shell regression test and explicitly reject the old Command-J pair. Require a physical close-then-reopen sequence before calling the installed route accepted.

## 2026-08-17 — Use Chrome's native accelerator for browser-owned DevTools

**Trigger:** Ethan requested an Open DevTools utility inside shared Chrome mode.

**Fix:** Add one canonical Chrome action on physical cell 3 (Corsair printed 3 / Razer printed 1) and deliver Google's documented Command-Option-I shortcut directly to the running Chrome process. Source the card from the same `ChromeMode.definition` used by automatic frontmost-app mode and the manual Choose App journey.

**Guard:** DevTools is browser chrome rather than page media, so do not route it through the VoiceInk YouTube extension. Handle press only, keep release inert, preserve the active Chrome mode, and require one physical open/close check on each mouse before calling the installed route accepted.

## 2026-08-17 — Keep terminal interruption keyboard-native and inside Utility

**Status:** Superseded twice. Terminal interruption moved into VS Code, Terminal, and iTerm app-specific cell 12; Utility cell 12 was temporarily Spare and now opens Extra Utilities under the 2026-08-20 design.

**Trigger:** Ethan requested a Ctrl-C mouse shortcut on physical cell 12 for stopping a running terminal command.

**Fix:** Preserve top-level physical cell 12 as the one-press Utility entry. Reuse the same physical cell only after Utility is active, where it posts exactly one Control-C key-down/key-up pair to the app that remained frontmost. A focused terminal interprets that ordinary keyboard chord as ETX/SIGINT; Agentic Mouse does not guess a PID, invoke a shell, or signal an unrelated process directly.

**Guard:** Keep the direct action behind the existing unlocked-session lease and Accessibility trust gates, attempt key-up even if key-down creation fails, mirror the canonical physical cell to Corsair printed 12 and Razer printed 10, and require one harmless physical terminal interruption before calling the live route accepted.

## 2026-08-16 — Treat browser speed boost as a leased physical hold, not two blind commands

**Trigger:** Ethan requested a Chrome-mode button that keeps the currently playing YouTube video at 2× only while the mouse button is physically held.

**Fix:** Forward both app-mode press and release phases to one source-aware `ChromeYouTubeSpeedHoldController`. Begin with an opaque UUID, renew every 750 ms, and end only after the last exact mouse releases. The VoiceInk YouTube Bridge chooses the target using its existing PiP/active/audible/recency policy, stores that video's actual prior playback rate, and maintains a 2.5-second content-script lease.

**Guard:** Cancel on mode exit, frontmost Chrome auto-mode retarget, lock, sleep, and app teardown. Serialize browser begin/renew/end operations so a quick release cannot overtake target selection. Restore the saved rate on explicit end, lease expiry, content-script cleanup, or supersession; never assume the prior rate was 1× and never focus Chrome or change play state.

**Live boundary:** Signed Agentic Mouse v1.0.48 (54), the signed menu helper, native host, and reloaded personal-Chrome extension completed the full begin/renew/end transport. With no playing YouTube target, the extension returned `no-playing-youtube-video` and the release completed without changing a tab. This proves the installed bridge and fail-closed selector; a physical hold on a playing video is still required to accept the visible 2× transition and exact-rate restoration.

## 2026-08-16 — Keep global intelligence on demand independent of the frontmost app

**Trigger:** Ethan assigned the spare top-level physical cell 6 to Codex's Option-Space intelligence-on-demand window on both mice.

**Fix:** Replace the silent app wildcard and its VS Code-only top-level override with one exact-device, non-repeating Option-Space action on canonical cell 6 (Corsair printed 6 / Razer printed 4). Keep Stage + Next on cell 6 only inside the explicitly entered VS Code child mode, where cell 9 remains exact Undo.

**Guard:** A global shortcut must not depend on the frontmost app or inherit a stale app-specific exclusion. Generate the same action for both exact mice, keep it behind the unlocked-session gate, render its fixed title in the Default legend, and physically verify it from both a Codex and non-Codex foreground app.

## 2026-08-16 — Give OpenAI Electron accelerators a real key hold (superseded)

**Status:** Superseded by the supported System Events route and the later Dvorak physical-key correction. The zero-duration HID diagnosis no longer describes the current implementation.

**Trigger:** Codex mode physical cell 6 reported that it sent the correct built-in Command-Option-S shortcut, but Codex did not open the current task in a side chat.

**Cause:** The system shortcut poster emitted its complete synthetic key lifecycle back-to-back. OpenAI Electron surfaces can accept Quartz event creation while ignoring a zero-duration key press; VoiceInk had already proven the same boundary for the Codex composer.

**Fix:** Keep Codex frontmost and send the exact built-in Command-Option-S binding as one HID S-down/S-up pair carrying Command+Option flags, with a 30 ms hold. Keeping modifiers on the bounded key pair avoids global Command or Option state that could become stuck if the app exits. Call the action `Open side chat`, matching Codex's own command title.

**Guard:** Treat successful CGEvent creation as delivery only. Pin the key code, flags, down/up order, and hold interval in tests, then require physical Codex acceptance before calling the command successful.

## 2026-08-16 — Remove a combined New Chat + Pin action when the new chat is not yet pinnable

**Trigger:** Ethan recognized that a brand-new empty Codex chat cannot be pinned before its first message is sent, so a button that immediately ran New Chat and then Pin was not useful.

**Fix:** Remove `New chat + pin` from the shared Codex action domain, executor, HUD, and tests. Do not move it to Default mode. Restore physical cell 6 (Corsair printed 6 / mirrored Razer printed 4) to Codex's built-in Command-Option-S `Open side chat` action for the current task.

**Guard:** Treat a workflow's real application state as part of its semantics. Do not combine two individually valid shortcuts when the first action creates an object that cannot yet accept the second action; remove rejected combinations completely instead of leaving dead routes or moving them to another page.

## 2026-08-16 — Recover Razer idle white after USB reconnect, not only after app launch

**Trigger:** The Naga's buttons worked after a daytime USB reconnect, but its LEDs remained on firmware Spectrum/rainbow while Agentic Mouse build 48 was still running.

**Symptom:** Unified logging recorded `exact Razer Naga 1532:008d was not found` when the device was absent. The mouse later re-enumerated and Karabiner input recovered independently, but no later Razer lighting write occurred because the app retried the vendor controller only at launch and wake.

**Fix:** Add a two-second read-only exact-VID/PID presence monitor. Stable connected polls never repaint. On removal, drop the stale USB handle without attempting Spectrum on an absent device and tear down the Razer's ephemeral mode state. On reappearance, retry the accepted `NOSTORE` idle-white frame until the device acknowledges it, then remain quiet until the next transition. Synchronize the same monitor around sleep/wake so true sleep still releases to Spectrum.

**Guard:** Treat input enumeration and vendor-lighting ownership as separate lifecycles. A working Karabiner map does not prove the lighting handle recovered. Pin disconnect-once, retry-until-acknowledged, stable-no-write, sleep synchronization, and no-Spectrum-on-physical-loss behavior in hardware-free tests; require a signed installed reconnect test before calling the physical recovery accepted.

## 2026-08-16 — Mount a new Codex chat before pinning it

**Superseded later the same day:** Ethan rejected this combined workflow because an empty new chat is not yet pin-eligible. The live map restores Codex cell 6 to Open in Side Chat; retain the notes below only as historical evidence of the rejected experiment.

- Codex physical cell 6 is now one shared `New chat + pin` action (Corsair
  printed 6 / Razer printed 4), replacing Open in Side Chat on that cell.
- Command-N is a frontmost Electron accelerator. Send it through the system
  event lifecycle, wait briefly for the new task to mount, then deliver
  Codex's existing Command-Option-P Pin/Unpin shortcut to the Codex PID.
- Capture Codex's persisted pin set before starting and verify that exactly one
  task was added after the delayed pin. A successful shortcut post alone is
  never confirmation, and a lock between the two phases must suppress pinning.

## 2026-08-16 — Keep app-specific wheel chords inside the shared mode coordinator

- The generated active-mode rule already forwards press and release for every
  canonical cell. A Chrome held-wheel chord therefore does not need another
  Karabiner action or a device-specific mapping.
- Arm the existing `ScrollWheelChordMonitor` from the source-specific
  `ModePickerCoordinator` only while Chrome mode is active, then send Chrome's
  documented Command-Option-Left/Right shortcuts through the generic PID
  dispatcher without activating Chrome.
- Resolve the control through the shared physical-cell crosswalk and the same
  `AppSpecificTarget.definition` used by automatic and manual Chrome journeys.
  Clear it on every ordinary release and lifecycle teardown, and never let an
  app-specific chord change unarmed scrolling.

## 2026-08-16 — Keep clipboard utilities adjacent and enter Keypad from Keys

- Ethan removed the low-frequency Quit App control. Remove its semantic route,
  executor path, generated output, and documentation rather than leaving a
  hidden shortcut behind.
- Utility physical cells 3 and 6 are the adjacent Copy/Paste pair. Emit one
  non-repeating Command-C or Command-V cycle from the unlocked exact-device
  Karabiner layer so the action does not depend on Agentic Mouse Accessibility.
- The optional device-local Keychain password moves to Utility cell 7. It
  remains a separate secure direct-text path and never enters the clipboard,
  generated configuration, or logs.
- Keypad is a Keys child on physical cell 6. Its preflight must allow entry
  while the source coordinator is still on `.keys`, then transition both the
  app navigation path and generated page variable to Keypad before forwarding
  the exact-device press/release stream.

## 2026-08-16 — Press Codex's real Voice button instead of trusting shortcut delivery

- The running desktop app is `/Applications/ChatGPT.app` even though its bundle
  identifier remains `com.openai.codex`; inspect the running bundle rather than
  a stale side-by-side `/Applications/Codex.app` installation.
- Codex 26.810.41047 still registers Control-Shift-V for
  `composer.startVoiceMode`, but Ethan repeatedly confirmed that the synthesized
  shortcut did nothing. A created CGEvent is delivery evidence, not command
  execution.
- The focused live Codex window exposes exactly one enabled pressable
  `AXButton` labelled `Start new voice chat`. Use that exact visible control for
  Voice Mode and after New Chat mounts for New Voice Chat. Reject broad labels,
  multiple candidates, background Codex, and locked sessions.
- Codex also registers Command-Option-S for `openSideChat`. It opens the current
  task as a side task, not a queued message, so it may occupy Codex physical
  cell 6 without reviving the rejected Recent Chats control.

## 2026-08-16 — De-duplicate Codex AX traversal before relaxing Steer matching

**Status:** Steer dispatch is superseded by the 17 August built-in
Command-Return route. The de-duplicated traversal and exact row cluster remain
current for Edit Queued Message.

- Chromium can expose the same Accessibility element through several wrapper
  paths. Appending those aliases repeatedly consumed the 10,000-element safety
  budget before a deeper queued-message row could be reached.
- Traverse each `AXUIElement` once using `CFEqual` identity. Keep the exact
  three-control queued-row cluster as the anchor for Edit's actions menu.
- Log only candidate counts, roles, exact-label status, frames, and selection
  reason. `AXPress` proves delivery, not that Codex processed the result, so
  keep the user feedback explicitly unconfirmed.

## 2026-08-16 — Remove broken Codex controls instead of preserving their slots

**Status:** Superseded on 2026-08-19 only for app-child physical cell 2: every app-specific child now reserves cells 2 and 10 as Exit, and Codex New Chat moved to cell 5. The rule to remove broken controls rather than advertise them remains current.

- Ethan physically rejected the Codex Recent Chats control because it did not
  work reliably. Remove the action and its executor path rather than leaving a
  card that advertises a broken shortcut.
- The accepted shared Codex placement is New Chat on physical cell 2 and
  Pin/Unpin on physical cell 3 (Corsair printed 3 / Razer printed 1). Physical
  cell 6 is honestly Spare in Codex mode. Apply this canonical placement to
  both mice and to both automatic and manually selected Codex journeys.

## 2026-08-16 — Reserve full card saturation for modes, not every action

- Full-strength action-family fills made every button inside Utility, Keys,
  Keypad, and app-specific pages compete with the mode itself. The intended
  hierarchy is a strongly saturated mode identity with quieter controls inside
  it.
- Keep the current mode accent full strength on the panel perimeter, every
  ordinary card border, mouse lighting, and the legend footer. Render ordinary
  action-family fills as darkened but fully opaque RGB surfaces so their groups
  remain recognizable without looking like twelve separate modes.
- A card that opens another mode or submenu is the deliberate exception: use
  the destination mode's exact saturated accent for both its fill and thicker
  border. Encode this through `destinationModeAccent` in the shared card-colour
  model so Default and nested mode navigation inherit the same rule.

## 2026-08-16 — Count accepted wheel detents in the live HUD trace

- Ethan physically confirmed that top-level Spaces switching now works and asked for the existing footer trace to expose how many ratchets Agentic Mouse accepted during the current hold.
- Count at the wheel-routing boundary, reset on every source press/release, and include the cumulative value in every scheduled Space diagnostic. This makes a two-event burst visibly read `2 RATCHETS` without changing direction, throttling, or action semantics.

## 2026-08-15 — Deliver Voice Mode through Codex's app accelerator

**Status:** Superseded by the exact Codex-owned Accessibility button route above.

- Codex 26.810.41047 registers `composer.startVoiceMode` as a `shortcutScope: app` Electron accelerator on Control-Shift-V. A successful `CGEvent.postToPid` does not prove that accelerator ran; the app can receive renderer key events while ignoring the app command.
- Require Codex frontmost and post one real bounded system modifier lifecycle for Voice Mode. New Voice Chat must use the same foreground accelerator path for Command-N, wait for the new composer, then use it again for Control-Shift-V.
- Fail closed if Codex is no longer frontmost before either system shortcut, and report the delayed Voice Mode failure instead of leaving a plain new chat looking successful.

- Codex's `realtimeVoice.toggleMicrophoneMute` command applies to an active Voice Mode session, not ordinary dictation or the idle composer. Name the Agentic Mouse card `Mute / unmute voice mic` so a no-op outside Voice Mode is not presented as a generic microphone failure.
- Codex 26.810.41047 still registers `composer.startVoiceMode` with its built-in Control-Shift-V binding. Agentic Mouse had regressed to custom Hyper-F17 despite its earlier native-shortcut rule, breaking both Voice Mode and New Voice Chat together. Deliver the built-in shortcut directly and keep custom keybindings only for commands with no accepted native route.
- Codex's `previousRecentThread` Control-Shift-Tab command is an Electron app-level accelerator. A `CGEvent.postToPid` key pair can report successful creation and delivery while Electron ignores it because it was not triggered through the app accelerator. For this command only, require Codex to be frontmost and emit one complete system Control-down, Shift-down, Tab-down/up, Shift-up, Control-up sequence. Fail closed when Codex is not frontmost so the global chord cannot reach another app.

## 2026-08-15 — Anchor Codex queued controls by their visible row, not omitted wrappers

- Codex 26.810.41047 renders each queued item with exact `Steer`,
  `Delete queued message`, and `Queued message actions` controls, but Chromium
  can flatten the React wrapper groups out of the macOS Accessibility tree. A
  small-ancestor requirement can therefore reject a genuine queued row.
- Require the three exact enabled `AXButton` controls in the same window, on
  one visible line, and in their real left-to-right order. Reject clipped
  offscreen controls, different rows, broad substring labels, and unrelated
  Steer buttons. Edit may open only from that validated row's Actions control.
- **Superseded placement:** this repair originally kept ordinary Enter on
  shared physical cell 7 and put Steer Queued Message on shared physical cell
  9. Ethan later moved frequent Steer to shared cell 1 (Corsair 1 / Razer 3)
  and Voice Mic to shared cell 9 (Corsair 9 / Razer 7); the current top entry
  is authoritative. Neither placement change alters the executors.

## 2026-08-15 — Reproduce the configured Space shortcut, including its modifier lifecycle

- Horizontal hold-plus-wheel proved that exact-device arming, VirtualHID wheel
  input, Quartz capture, direction conversion, and event consumption all worked
  in the installed app. The remaining Spaces-only failure belonged to the
  keyboard output boundary, not to Karabiner or the wheel state machine.
- This Mac's `com.apple.symbolichotkeys` entries 79 and 81 store Space Left and
  Space Right as Control-Fn-Left and Control-Fn-Right (`0x840000`), not plain
  Control-Arrow. A synthetic Arrow down/up carrying only `.maskControl` does not
  reproduce that configured shortcut reliably.
- Emit one bounded Control-down, Arrow-down/up with Control plus
  `.maskSecondaryFn`, and Control-up sequence from one `CGEventSource`. Create
  the complete sequence before posting any event so allocation failure cannot
  strand Control in the down state. Dispatch it after the consuming event-tap
  callback returns instead of posting synchronously inside that callback.
- Keep diagnosis visible but observational: rate-limit the source-specific HUD
  footer, show raw line/point/fixed deltas and phase fields, distinguish routing
  from posting, and report `activeSpaceDidChangeNotification` latency without
  claiming that notification proves causation. Add an action cooldown only if
  a physical trace proves multiple accepted events per ratchet.

## 2026-08-15 — Classify virtual ratchets by phase, not `isContinuous`

- Karabiner VirtualHID may expose an ordinary mouse-wheel detent as a Quartz
  event with `isContinuous == true`, no scroll or momentum phase, and direction
  only in the point or fixed-point delta. Rejecting every continuous event or
  reading only the line delta silently arms a held-button chord but never sends
  its semantic action.
- Treat a phase-free nonzero event as one ratcheted detent even when Quartz
  marks it continuous. Resolve its sign from line delta first, then point and
  fixed-point fallbacks. Reject only phase-bearing gesture or momentum events,
  so trackpad and smooth scrolling continue to pass through.
- Keep the output bounded. This entry's original one-event/one-action Spaces
  policy is superseded by the 2026-08-18 one-action-per-hold rule: first sign
  posts one configured Control-Fn-Left/Right chord, then later events are
  consumed until release. Karabiner still owns only the exact-device lifecycle
  that identifies which mouse armed physical cell 1.
- Automated coverage proves phase-free VirtualHID acceptance, phased gesture
  rejection, delta fallbacks, lifecycle cleanup, source-command validation,
  and one-event/one-action semantics. Exact detent count still requires a
  physical sweep because Quartz may report hardware events differently.

## 2026-08-15 — Keep repository-aware stage undo inside Better Git

- Agentic Mouse and Karabiner can transport F16, but they cannot safely infer
  which Git-index change should be reversed. Restrict them to the neutral key
  transport and let Better Git own repository state.
- Better Git v1.2.53 observes exact before/after index trees while `HEAD` stays
  unchanged. A stage from Better Git, VS Code's keyboard or Source Control UI,
  another mouse action, or terminal `git add` therefore becomes the same latest
  undo target. F16 refuses after an unexpected index or `HEAD` change and never
  mutates the working tree.
- Do not narrow the mouse wording back to “undo the last Stage + Next.” The
  physical gesture is stable; its installed Better Git consumer provides the
  cross-route semantics.
- The exact Marketplace-verified Better Git v1.2.53 VSIX is installed in normal
  VS Code and the CLI reads it back as 1.2.53. The currently running extension
  host predates that install, so physical acceptance must wait for Ethan's next
  normal VS Code reload or restart; do not restart his editor merely to prove
  this mouse feature.

## 2026-08-15 — Split a crowded app-mode gesture without changing its top-level shortcut

- A compact top-level wildcard can reasonably keep Stage + Next on one press
  and exact Undo on a rapid double, but the larger VS Code child has spare
  cells and should not impose that timing cost. Ethan assigned immediate Stage
  + Next to physical cell 6 and immediate Undo Stage to physical cell 9 inside
  VS Code mode only.
- Keep the two surfaces explicit in one `VSCodeModeAction` source: the child
  action title is `Stage + Next`, while its `topLevelTitle` remains
  `Stage + Next / Undo`. This prevents the Default legend from lying about the
  still-combined top-level classifier when the child UI is split.
- Automatic frontmost-app and manual Choose App journeys must continue resolving
  the same `VSCodeMode.definition`; a change to one VS Code child must appear in
  both without touching live Karabiner or the ordinary top-level mapping.

## 2026-08-15 — Emit the exact native shortcut for the floating screenshot thumbnail

- An explicit `screencapture -i -s <path>` child can save a selected area, but
  it bypasses the standard Screenshot UI path that produces macOS's sound and
  bottom-right floating thumbnail. Saving correctly therefore does not prove
  parity with Shift-Command-4.
- Emit one exact Shift-Command-4 key-down/key-up cycle through Core Graphics and
  let macOS own its configured destination and thumbnail behavior. Track the
  bounded interaction with a temporary global left-mouse-up/Escape monitor; a
  second mouse press sends Escape, and every terminal path removes the monitor.
- This path does not read screen pixels itself and therefore does not require
  Agentic Mouse to request Screen & System Audio Recording. It must not quit,
  restart, or toggle VoiceInk; the same VoiceInk++ process remained alive while
  this regression was investigated.

## 2026-08-15 — Preflight native screenshot permission before showing the crosshair

**Status:** Superseded by the exact Shift-Command-4 implementation above. This
remains evidence for the retired explicit `screencapture` child only.

- A selected-area `screencapture` child inherits Agentic Mouse's screen-capture
  privacy responsibility. Without a matching Screen & System Audio Recording
  grant, the native crosshair can still appear and accept a rectangle, then
  fail with `could not create image from rect` and create no file. This is not
  a destination-folder failure.
- Declare `NSScreenCaptureUsageDescription`, preflight with
  `CGPreflightScreenCaptureAccess`, and use Apple's
  `CGRequestScreenCaptureAccess` only when the grant is absent. Do not start the
  child process until permission is available; keep second-press cancellation
  independent of a later permission check.
- Continue passing the explicit collision-safe file inside the configured
  macOS Screenshot directory, and keep file existence plus nonzero size as the
  only saved-success proof.

## 2026-08-15 — Keep mode moves complete and preserve exact failure feedback

- A mode-card move is not complete when only the Swift legend changes. Update
  the canonical cell, native Karabiner output, generated runtime, focused tests,
  durable map, and live installation together. Keys now enters from top-level
  physical cell 9, uses cell 12 for Enter, leaves cell 2 spare, and moves the
  optional Keychain password to Utility cell 6.
- This Mac's enabled Mission Control symbolic shortcut includes both Control
  and the secondary Fn modifier on Up Arrow. A synthetic Control-Up without Fn
  can be ignored even though the visible keyboard key is labelled Mission
  Control; reproduce the exact enabled symbolic-hotkey modifiers.
- Do not let a coordinator replace a precise executor failure with a generic
  `could not be performed` banner. Utility actions return a structured outcome
  carrying the specific safe message, so missing Accessibility, lock state, or
  missing Keychain setup stays visible.
- Codex exposes queued-message Steer as an exact Accessibility button, but Edit
  is a menu item that is absent until the row's `Queued message actions` button
  opens its popover. Never require Steer and Edit to coexist in the tree. Anchor
  the row with its simultaneously exposed `Delete queued message` and `Queued
  message actions` buttons, reject broad ancestors, then either press Steer or
  open that exact menu and press `Edit message`. Describe either dispatch as
  unverified unless Codex exposes a real state change.

## 2026-08-15 — Keep top-level wheel chords independent of mode state

- A Spaces chord exposed only through Utility could appear armed while its wheel
  steps were rejected by Utility page, lease, or coordinator state. Top-level
  physical cell 1 now owns a dedicated exact-device press/release route, so one
  ratchet always invokes one bounded Space step without entering a mode.
- Utility keeps only its Brightness and Zoom wheel families. Physical cell 3 is
  a direct Quit App action that targets the actual frontmost external app with
  one bounded Command-Q shortcut; it must never fall back to the current app or
  quit Agentic Mouse itself.
- The final top-level placement is Keys on physical cell 9 and the fail-closed
  app wildcard on physical cell 6. Preserve that placement across source,
  generated rules, legends, tests, documentation, and live installation.

## 2026-08-15 — Move Codex cards by canonical cell, not by shortcut

- **Superseded placement:** Codex New Chat belonged to physical cell 3 and
  Pin/Unpin to physical cell 6 at this stage. The 2026-08-16 entry above moves
  them to cells 2 and 3 and removes Recent Chats.
- At this stage, New Chat was on physical cell 3 and Pin/Unpin on physical cell 6,
  Enter to physical cell 7, and Steer Queued Message to physical cell 9. The
  exact crosswalk is Corsair 3 / Razer 1, Corsair 6 / Razer 4, Corsair 7 /
  Razer 9, and Corsair 9 / Razer 7 respectively.
- A card relocation changes only `CodexModeAction.cell`, the shared HUD map,
  tests, and documentation. Preserve the existing Codex shortcut definitions
  and one `AppSpecificTarget.definition` source for both automatic and manual
  app-specific journeys.

## 2026-08-15 — Horizontal Scroll now belongs to physical cell 4

- Ethan moved the ordinary `Horizontal Scroll + Wheel` chord from canonical
  physical cell 1 to cell 4. Cell 4 is Corsair printed 4 / Razer printed 6;
  freed cell 1 is Corsair printed 1 / Razer printed 3.
- Preserve the accepted wheel polarity and source-specific press/release
  lifecycle. Change only the chord's physical owner across the semantic map,
  exact-device bindings, generated rules, legend, tests, and durable mouse
  reference; do not reinterpret it as a one-shot horizontal-scroll action.

## 2026-08-15 — Keep the outer Liquid Glass clear and unmasked

- On macOS 26, `NSGlassEffectView.Style.clear` with a nil tint is AppKit's
  strongest legitimate transparent glass substrate. A panel-colour gradient
  above it masks the environmental lensing, so keep the outer substrate clear
  and carry mode identity through the saturated cards and outer accent stroke.
- The HUD is deliberately a non-activating, click-through reference surface.
  AppKit's `NSGlassEffectView` has no interactive switch, and SwiftUI's
  interactive glass response would receive no pointer input in this window.
  Preserve native environmental refraction; do not fake press deformation with
  a custom shader or make the HUD steal input merely to animate the glass.

## 2026-08-15 — Keep active mode identity physically and visually strong

- Utility is the strong electric-purple mode and Keys is the strong saturated-
  orange mode. Keep those identities stable across the HUD, Default entry
  cards, Corsair zones, and Razer custom frames; do not swap them when tuning
  intensity.
- The Razer idle-white calibration and active-mode intensity are different
  concerns. Preserve the corrected idle output `(124,129,130)`, but send active
  mode colours at full scale. The Scimitar already receives full RGB mode
  frames through iCUE.
- A faint accent edge over a dark panel does not make the current mode obvious.
  Keep native Liquid Glass as the outer substrate and opaque semantic cards on
  top. The later clear-glass finding above supersedes this iteration's outer
  mode-colour tint; do not weaken action fills or replace them with nested
  glass.

## 2026-08-15 — Use Apple's bounded shortcuts for workspace overview actions

**Status:** The supported Fn-F11 and Control-Fn-Up event lifecycles remain current. The separate direct cell-4/cell-5 placement is superseded by the 2026-08-17 shared cell-4 wheel chord above.

- The outward trackpad gesture is macOS Show Desktop. Apple documents Fn-F11
  (and Command-Mission Control) for it, while Control-Up Arrow enters Mission
  Control. This Mac's enabled symbolic-hotkey records match Fn-F11 and
  Control-Fn-Up exactly.
- Keep these actions in Agentic Mouse's existing Accessibility-trusted bounded
  keyboard-event boundary: the Utility cell-4 wheel chord sends Fn-F11 for
  Show Desktop or Control-Fn-Up for Mission Control. Do not use shell commands, Dock UI
  automation, private CoreGraphics services, or persistent system-setting
  changes for either action.
- Both actions are one shared system-overview family in the HUD. The shared
  canonical cell projects to Corsair 4 / Razer 6; cell 5 is Spare on both maps.
- Route the system-overview pair through the held-wheel boundary and keep both
  actions out of `ModeUtilityAction.directAction(for:)`. The direct Utility
  executor still owns their bounded keyboard lifecycles after direction resolves.

## 2026-08-15 — Let physical acceptance set wheel polarity and keep Liquid Glass outside the cards

- Quartz's positive/negative wheel convention is an implementation detail, not
  the desired physical interaction. Ethan verified the held-wheel capture and
  explicitly rejected its first polarity. Preserve raw event classification,
  but map wheel up to Horizontal Right / Brightness Down / Zoom Out / Space
  Right and wheel down to Horizontal Left / Brightness Up / Zoom In / Space
  Left on both mice.
- Default Enter and Legend Toggle are real actions, not Spares. Resolve Enter
  to the shared green Enter family and give Legend Toggle its own cyan family
  accent so both read as intentional controls on the neutral Default page.
- macOS 26 provides the real AppKit `NSGlassEffectView`. Use one non-interactive
  native glass surface for the outer HUD panel and keep every semantic card as
  an ordinary coloured SwiftUI fill above it. Nested glass suppresses the
  action hierarchy. Older macOS releases use `NSVisualEffectView` as the
  compatibility background.

## 2026-08-15 — Split exact-device wheel chords across Karabiner and Quartz

- Karabiner basic manipulators cannot treat wheel movement as an input. Its
  supported wheel facilities generate, swap, flip, or discard wheel output;
  they do not convert a held mouse button plus incoming wheel detents into
  brightness, zoom, Spaces, or another semantic action.
- Use exact-device Karabiner press/release commands to arm one canonical
  physical-cell control, then let Agentic Mouse's Accessibility-trusted
  `CGEvent` tap consume only non-continuous vertical wheel events while exactly
  one chord is armed. This entry's original one-event/one-step policy is
  superseded for Spaces by the newer one-action-per-hold latch; the other wheel
  families remain one step per accepted event regardless of delta.
- Quartz wheel events have no source-device identity. Attribute the event to
  the one held exact-device chord, pass continuous trackpad events through, and
  consume simultaneous Corsair/Razer chords without guessing. Clear state on
  mode navigation, exit, lock, sleep, device loss, lease failure, shutdown, and
  event-tap restart.
- The accepted compact Utility layout is cell 1 Brightness + Wheel, cell 2 Zoom
  + Wheel, and cell 3 Spaces + Wheel; cells 4/5/6 were freed for new actions.
  The newer system-overview entry assigns cells 4/5 while cell 6 stays spare.
  Its initial wheel polarity is superseded by the physical correction in the
  newer entry above. Top-level cell 1 owns Horizontal Scroll + Wheel, freeing
  top-level cell 4.
- This supersedes the older paired Utility geometry, direct Karabiner Utility
  `selectNative` outputs, and the two-button top-level horizontal pair recorded
  later in this historical file. Keys-mode native Karabiner output remains the
  correct architecture because those inputs are ordinary keys, not wheel
  events.

## 2026-08-15 — Reuse Codex's built-in recent-task traversal

- **Superseded:** Ethan physically rejected this control on 2026-08-16 because
  it did not work reliably. Recent Chats is no longer a Codex-mode action.
- **Historical implementation only:** Codex Desktop exposed
  `previousRecentThread` as Control-Shift-Tab, but the resulting Recent Chats
  card was unreliable in physical use. Do not restore that route, infer recency
  from session metadata, or reserve a Codex-mode card for it.

## 2026-08-15 — AXPress is delivery evidence, not a confirmed Codex result

- Codex 26.810.41047's queued-message row renders visible `Steer` text inside
  an `AXButton` whose exact accessibility label/help is `Submit without
  interrupting the model`. Rejecting that phrase inverted the matcher and made
  the real queued-row control undiscoverable.
- Match only an `AXButton` whose normalized title, description, or help equals
  either `Steer` or `Submit without interrupting the model`; never use a broad
  substring match. Even then, an accepted `AXPress` proves only delivery;
  report the result as unconfirmed until Agentic Mouse can observe an
  authoritative queue-state transition.
- Never use a green confirmation or the word `confirmed` merely because a destination UI element accepted an Accessibility action. Confirmation requires a separate state readback tied to the requested outcome.

## 2026-08-15 — Keep Default legend and Utility on separate one-press cells

- The final Default-layer contract is direct and unambiguous: canonical physical cell 10 (Corsair printed 10 / Razer printed 12) toggles that source mouse's persistent Default legend with one press, while canonical physical cell 12 (Corsair printed 12 / Razer printed 10) opens Utility immediately.
- Cell 10 retains its contextual active-mode meaning as universal Exit. One physical control can therefore be `Legend toggle` outside modes and `Exit` inside a mode without a click-count classifier.
- Remove the obsolete cell-12 single/double classifier end to end. Keeping it in the generator, docs, or durable instructions after changing only the HUD/source creates exactly the regression Ethan hit: the visible map promises one gesture while live Karabiner still routes another.

## 2026-08-15 — A requested swap means exchange the existing canonical cells

- `New task should switch with Mute / unmute mic` means exchange the two existing Codex card positions, not merely restate them: Mute / unmute mic moves to canonical cell 1 and New task moves to canonical cell 8 on both mice.
- Resolve printed mouse labels through the shared physical-cell crosswalk, but preserve the action identities and their Codex shortcut implementations. Pin both canonical positions in the shared Codex-mode test.

## 2026-08-14 — Reuse the complete Better Git gesture inside VS Code mode

**Status:** Partly superseded on 2026-08-15. Cells 5 and 8 still reuse their
navigation double gestures, while child cells 6 and 9 now split Stage + Next
and exact Undo into immediate controls. The top-level wildcard remains combined.

- The VS Code child already placed Previous Change, Next Change, and Stage + Next on the same physical cells as the ordinary VS Code layer, but its app-side dispatcher emitted only the single-press F17/F13/F18 actions. That was visual parity, not behavioral parity.
- Keep one `VSCodeModeAction` source for the page cell, title, colour, single command, and double command. Physical cell 5 is F17 Previous / F19 Stage + Previous, cell 8 is F13 Next / F18 Stage + Next, and cell 9 is F18 Stage + Next / F16 exact Undo, all with the same bounded 300 ms classifier.
- Instantiate the classifier per exact mouse so independent Corsair and Razer mode journeys never merge clicks. Automatic frontmost-app mode and manual Choose App already share `AppSpecificTarget.definition`; they must also share this same command path.
- Cancel, rather than commit, a pending app-mode click on every mode teardown. Exit can mean lock, sleep, device loss, or lease failure, and those fail-closed boundaries must never release a delayed Better Git command.

## 2026-08-14 — Distinguish composer inversion from queued-message Steer

**Status:** Superseded by the 17 August built-in Command-Return Steer route.

- Codex 26.707.72221 still documents Command-Shift-Return as the one-message inverse of the configured follow-up behavior, but that shortcut submits text still present in the composer. It does nothing when the intended text is already represented by a queued-message row.
- For the Codex-mode `Steer queued message` action, search the background Codex Accessibility tree breadth-first for its real `Steer` button, require an advertised `AXPress` action, continue after failed or unpressable matches, and fail visibly when no queued Steer action exists. A successful key post is not evidence that a queued item moved.
- Keep the shared positions canonical: Steer is physical cell 7 (Corsair 7 / Razer 9), and Start New Voice Chat is physical cell 5 on both mice.

## 2026-08-14 — Move Codex cards by shared physical cell

**Status:** Superseded by the corrected 15 August swap above.

- A Codex-mode request naming Razer printed 7 resolves to canonical physical cell 9, so Pin/Unpin appears on both Razer 7 and Corsair 9. Do not create a Razer-only Codex action from the printed label.
- The attempted swap was recorded backwards here: New Task remained on cell 1 and Mute/Unmute remained on cell 8. The corrected mapping exchanges them as documented above.
- Pin the canonical cells and both printed Pin labels in the shared Codex-mode test so automatic frontmost-app and manual Choose App journeys keep one definition.

## 2026-08-14 — Verify the printed destination before moving a canonical cell

- Razer printed 7 is directly above printed 8 Back, and it maps to canonical physical cell 9. The shared app wildcard was already on canonical cell 9, so the requested reachable grouping requires no semantic swap: Corsair printed 9 / Razer printed 7 remain the wildcard, while Corsair printed 7 / Razer printed 9 remain Enter.
- A Razer printed label and a canonical physical-cell number are not interchangeable. Resolve the destination through `razerPrintedToPhysical` and inspect the source-specific HUD geometry before changing bindings.
- If a future relocation is real, move the VS Code F18/F16 Stage + Next / exact-undo classifier, fail-closed base sink, Default legend card, app-specific action definition, docs, and tests together. Never infer a canonical swap solely from the printed number.

## 2026-08-14 — Keep the frequent Keys entry on cell 6 and the rarer app journey on cell 2

**Status:** The cell-12 single/double classifier described below is superseded by the 15 August direct Legend/Utility rule above.

- The shared Default layer now uses canonical physical cell 2 (Corsair 2 / Razer 2) for the current frontmost app's mode, and canonical cell 6 (Corsair 6 / Razer 4) for Keys. This is one cross-mouse semantic swap, not a Razer-only exception.
- Preserve the established controls around that swap: cell 11 remains hold-open Switch App, and cell 12 remains the bounded Utility-single / independent Default-legend-double classifier. Universal active-mode Exit remains cell 10.
- Carry any future top-level relocation through the `PhysicalCell` aliases, ordinary map, exact-device bindings, action payloads, generated runtime, source-specific HUD, docs, tests, backup/install diff, and physical acceptance together. Never patch only the displayed label or only one mouse.

## 2026-08-14 — Mirror horizontal intent for the left-handed Razer, not the Corsair

- Canonical physical cells are shared transport identities, but a left-handed mouse can need the opposite semantic direction at the same gesture position. This is an explicit handedness exception, not permission for arbitrary per-device maps.
- Keep Corsair horizontal scroll as printed 1 Left / 4 Right. Project the Razer pair as printed 6 Left / 3 Right, and apply the same source-aware reversal to horizontal Keys arrows and Utility Space navigation.
- Pin the source-level HUD/action projection and generated exact-device outputs for all three families. Do not renumber cells, change neutral transports, or mirror unrelated actions.

## 2026-08-14 — Keep automatic and manually chosen app modes on one definition

- Frontmost detection and Choose App are two targeting policies, not two sets of controls. The automatic journey follows the current app, while the manual journey locks the selected target without activating it.
- Resolve both through `AppSpecificTarget.definition`, so Codex, Chrome, VS Code, and future configured apps expose the same title, accent, legend cards, actions, and Spares whichever journey opened them.
- Pin every configured target in one cross-journey regression test. Do not copy an app's card array into either coordinator path or let one path grow a private override.

## 2026-08-14 — Give top-level mode entries their destination's full-strength colour

- A destination-coloured outline around a 24%-opacity Default card still reads as a pale hint, so Keys, the current app mode, and Utility do not visually advertise the strong mode colour that appears after entry.
- On the neutral Default page, use `destinationModeAccent` for both the fully opaque fill and stronger border of every mode-navigation card. Keep ordinary Default actions on the existing neutral/translucent treatment, and keep active-mode pages on their action-family fills inside destination-coloured borders.
- Encode the distinction in `ModeHUDCardColors`, not in SwiftUI title checks or per-device cell checks, so future top-level mode entries inherit the same rule automatically.

## 2026-08-14 — Keep every mode-card label white

- Luminance-adaptive black text made bright Codex action cards look like a separate, unfinished visual system even though the cards shared the same renderer as Utility and Keys.
- Agentic Mouse uses saturated fills as action identity inside a dark HUD, not as conventional light surfaces. Keep both the action title and the smaller printed-button label fully white across every presentation style and fill colour; do not dim the printed label through opacity.
- Pin the invariant in the shared `ModeHUDCardColors` test so future palettes cannot reintroduce black text into Codex or another mode.

## 2026-08-14 — A frontmost-app wildcard card must name the real action

- The exact-device top-level wildcard can be silent for most apps and meaningful for one configured app. A static `App shortcut` label hides information Agentic Mouse already has and falsely suggests an action exists everywhere.
- Resolve the Default legend's physical-cell-9 title from the current `FrontmostAppModeContext`: VS Code shows `Stage + Next / Undo`, while Chrome, Codex, unsupported apps, and missing context show `Spare`. Refresh it through the same focus-change path as the live app-mode card.
- Keep presentation sourced from the same app-specific action definition, and keep the transport independent. The accepted Karabiner classifier remains one bounded F18 single press and F16 rapid double press on both exact-device adapters; Better Git owns the fail-closed exact undo.

## 2026-08-14 — Swap a top-level mode only through the shared canonical cell

**Status:** Superseded later on 14 August 2026 by the restored cell-2 App-specific / cell-6 Keys layout recorded above.

- Ethan swapped the two top-level mode entries: canonical physical cell 2 now opens Keys, while cell 6 opens the live frontmost-app mode. This is one shared semantic change after Corsair/Razer crosswalk normalization, not a device-specific exception.
- Carry a top-level relocation through `PhysicalCell` aliases, the ordinary map, exact-device bindings and action payloads, generated runtime rules, the Default legend, tests, public maps, durable project instructions, and physical acceptance. Utility cell 9 still enters Keys and Utility cell 11 still opens the manual configured-app selector; those downstream journeys did not move.
- Before installing a relocation, preserve the full live Karabiner file and selected-profile rule inventory. Afterward require both mice to prove cell 2 enters Keys, cell 6 enters the correct frontmost-app page, and universal cell 10 exits, while every unrelated rule remains byte-equivalent.

## 2026-08-14 — A shared single/double control needs one bounded classifier

**Status:** Superseded by the 15 August direct cell-10 Legend toggle / cell-12 Utility rule. The VS Code single/double gesture below remains current, but the Default-layer classifier does not.

- Physical cell 12 has two intentional top-level meanings on both mice: one press opens Utility, while a rapid second press toggles only that source mouse's persistent Default legend. Dispatching Utility immediately makes the second press land inside a mode; treating every first press as a legend action makes the common single press unusable.
- Consume the exact-device source event, start one 300 ms source-keyed classifier on the first press, and dispatch Utility only when that window expires without a second press. A qualifying second press cancels the pending Utility action and toggles the independent legend instead. Clear pending state on lock, sleep, reload, or shutdown.
- The same bounded-action pattern drives the VS Code wildcard: physical cell 9 sends F18 Stage + Next after the window, while a rapid double sends F16. Better Git owns the exact fail-closed undo and refuses if the Git index changed after the captured Stage + Next transaction.

## 2026-08-14 — A local install needs a new visible version, not only a new build

- Advancing only `CFBundleVersion` left successive local Agentic Mouse installs visibly named `1.0.0`, with the distinguishing number relegated to parentheses. Ethan needs the primary version itself to identify each installed iteration.
- For every successfully signed local install candidate, increment the patch component of `CFBundleShortVersionString` and the positive-integer `CFBundleVersion` together. Permit an explicit named major/minor version only when it is greater than the recorded marketing version.
- Record both values only after packaging and signature verification succeed. Failed candidates and ad-hoc development builds consume neither value, and the next guarded candidate must be rejected if its marketing version is equal to or below the recorded one.

## 2026-08-14 — A mode card needs an action name, not implementation prose

- Ethan rejected Codex and other mode cards that repeated implementation details such as `Codex custom shortcut`, `Native keyboard key`, shortcut chords, or explanations of a Spare. The HUD is a glanceable mouse legend, not developer documentation.
- Keep every Default and runtime-mode card to exactly two visible text roles: the concise action name and the small printed-button label for the invoking mouse. Put genuine failures and observable action results in the existing banner/footer instead of adding a third text layer.
- Remove the reusable `detail` field from `ModeHUDLegendItem` and `ModeHUDSelection` rather than merely hiding it in SwiftUI. This makes explanatory card subtext impossible to reintroduce accidentally when new modes are added.

## 2026-08-14 — A printed mouse button names a shared physical cell, not a semantic fork

- When Ethan says `Razer 12`, `Corsair 10`, or another printed mouse button, treat the device name as the way to locate the canonical physical cell through `PhysicalCell.crosswalk`. It does not authorize a different action on that mouse merely because Ethan happened to be holding or describing that device.
- The regression was exact: a late Razer-worded request was implemented as a Razer-only ordinary-map exception, splitting Default cells between the two devices. The corrected invariant is shared semantic behavior after crosswalk normalization: physical cell 2 opens the frontmost app mode, cell 3 is Screenshot, cell 6 opens Keys, cell 7 is Enter, cell 8 is Back, cell 9 is the app wildcard, cell 10 is Default Legend toggle outside modes and Exit inside modes, cell 11 is Switch App, and cell 12 opens Utility immediately.
- Require explicit wording and a concrete hardware, handedness, transport, or presentation reason before introducing a device-specific semantic exception. Keep legitimate source differences—printed-number crosswalks, neutral HID transports, independent HUD corners, Razer left-handed grid presentation, DPI transport, and lighting calibration—without letting them split the logical action map.
- Pin the invariant in source and generator tests for both exact-device adapters. Whenever one mouse binding changes, compare the corresponding canonical cell on the other mouse before packaging or installing.

## 2026-08-14 — A login item is not a keepalive policy

- `SMAppService.mainApp` launches Agentic Mouse at login, but it does not restart the process after AppKit terminates it. The app can therefore remain absent for the rest of the session even though the login-item status is enabled.
- A menu-bar-only runtime with no ordinary windows can be marked eligible for Transparent Application Lifecycle automatic termination. The physical failure was exact: AppKit logged `_kLSApplicationWouldBeTerminatedByTALKey=1`, the app died abnormally when the screen locked at 05:22:25, and no crash report was produced.
- Take the permanent `disableAutomaticTermination` opt-out during `applicationDidFinishLaunching`, after AppKit has completed the no-window launch transition. A hardware-free LaunchServices probe compared real menu-bar agents and proved the timing boundary. A second probe then proved that `AXIsProcessTrusted()` can republish `_kLSApplicationWouldBeTerminatedByTALKey=1` five seconds later even when either the documented opt-out counter or an `.automaticTerminationDisabled` activity is already held; that private LaunchServices field is therefore not a counter readback and must not be used as the acceptance oracle. Keep the lock path fail closed by clearing the three-second Karabiner lease and ephemeral modes; locking must suspend commands, not remove the process that will restore them after authentication. Physical lock/unlock remains the decisive end-to-end acceptance.

## 2026-08-14 — Give native selected-area screenshots an explicit file contract

**Status:** Superseded by the exact Shift-Command-4 implementation above. This
remains evidence for why the earlier `-p` and explicit-child variants failed.

- `screencapture -i -p` shows Apple's native interaction but `-p` delegates the target and destination to opaque Screenshot preferences, explicitly ignores any path argument, and provides no proof that a file was created. A user can complete the selection while Agentic Mouse silently records only that the child process ended.
- Keep Apple's native selected-area crosshair with `screencapture -i -s`, resolve the user's configured `com.apple.screencapture` location, expand `~`, verify the directory is writable, and pass one collision-safe PNG path explicitly. Fall back to Desktop only when the configured directory is unavailable.
- Treat process exit as success only when that exact output file exists and is non-empty. Preserve Escape/second-press cancellation as a distinct result and log a real failure instead of redirecting every diagnostic to `/dev/null`.

## 2026-08-14 — Keep app identity inside the established HUD, and version every signed candidate

- Ethan physically rejected the separate app-specific pastel panel treatment. App-specific pages must reuse the accepted bold opaque Utility/Keys panel; express the active app through its saturated accent, destination outline, and card fills rather than a second full-background gradient system.
- A HUD version label is useful only when it identifies the exact running bundle. Read `CFBundleShortVersionString` and `CFBundleVersion` from `Bundle.main` and show both in the compact footer; never hard-code a source version in SwiftUI.
- Advance the positive-integer bundle build only after a signed install candidate completes package and signature verification. Failed candidates and ad-hoc development builds do not consume numbers. Persist the resulting source plist value so later screenshots and bug reports can name one exact build.

## 2026-08-14 — Distinguish Codex command delivery from confirmed Codex state

- A successful `CGEvent.postToPid` proves only that Agentic Mouse delivered a shortcut to the Codex process. It does not prove that Codex accepted the command, changed the intended task, or completed the action. HUD copy must call this `sent`, never `successful` or `confirmed`.
- The installed Codex `0.147.0-alpha.6.5` app-server schema does not expose `isPinned` or an `isPinned` metadata update even though newer public protocol documentation does. Its `thread/list` parser silently accepts and ignores an `isPinned` filter, so a successful response is not pin evidence on this build.
- Codex desktop does persist the actual sidebar set in `~/.codex/.codex-global-state.json` under `pinned-thread-ids`. Read that file only; never mutate it. Capture the set before dispatch, poll after dispatch, and reserve green confirmation for exactly one added ID (`Pinned`) or exactly one removed ID (`Unpinned`). Treat no change, parse failure, more than one changed ID, and rapid repeated toggles as unavailable, ambiguous, or not confirmed.
- Give every other Codex action explicit informational footer feedback (`sent — result not exposed by Codex`) until it has an equally authoritative observable state. This makes future per-action verification additive without turning keyboard delivery into fake success.

## 2026-08-14 — Make the public story cinematic without hijacking scroll

- Agentic Mouse is not best explained as a generic two-device abstraction. Lead with Ethan's concrete idea: `The setup for the agentic future`, show the exact left-hand Razer and right-hand Corsair immediately, then reveal visible modes, security, and the physical desk as the page progresses.
- Build the takeover as a tall document section with one `position: sticky` viewport and scroll-derived CSS transforms. Keep native scrolling, links, keyboard navigation, and the reduced-motion static fallback intact; never trap the wheel or synthesize scroll steps for visual drama.
- Treat remote manufacturer product imagery as attributed reference material, keep the official source URLs visible in the page, and verify every asset still returns the expected image MIME type before publication. Use Ethan's public GitHub portrait only for the intentionally personal setup story; never infer or publish private order details, addresses, serials, or email content.
- Responsive acceptance must include the narrow personal-Chrome window, not only the desktop composition. Oversized display type that looks deliberate on a wide hero can clip a single word on mobile even when `overflow-x` hides the failure.

## 2026-08-14 — Advertise mode destinations with their own stronger outline

- A submenu card is both an action and a navigation preview. Give ordinary actions the current mode's perimeter, but mark every card that opens another mode with a thicker, fully opaque border in the destination mode's own accent. Keep the internal fill tied to the action family so navigation emphasis does not erase function grouping.
- Encode the destination accent in `ModeHUDLegendItem`, not in title matching or view-specific cell checks. Default, Utility, Keys, the manual app selector, and future nested modes can then share one renderer rule without duplicating physical mappings.
- Keep selection stronger than an unselected navigation card. Exit is not a submenu preview and retains the current mode border; the Default map keeps neutral white borders only for ordinary actions.

## 2026-08-14 — Rotate paired Utility controls by canonical physical cell

- **Superseded mapping:** this records the earlier four-button Utility layout.
  The 2026-08-17 held-wheel contract at the top of this file replaces it with
  one cell per two-way family.
- The accepted Utility geometry is a pair of vertical control families, not two horizontal rows: physical cell 1 is Brightness Up, cell 4 is Brightness Down, cell 2 is Zoom In, and cell 5 is Zoom Out. Through the left-handed Razer crosswalk these are printed 3/6 for brightness and 2/5 for zoom; Corsair prints the canonical 1/4 and 2/5 directly.
- Keep this as one shared semantic mapping. Change the `PhysicalCell` aliases, HUD legend, generated exact-device native outputs, public map, and generator tests together; never patch one mouse's printed numbers independently.

## 2026-08-14 — Project Keys by source and bind only real Codex commands

- Canonical physical cells are the transport vocabulary, but a left-handed mouse can need a source-specific presentation meaning. Keep Corsair cells 1/7 as Left/Right and project the Razer cells 1/7 as Right/Left so the physical horizontal gestures mirror correctly; pin both the generated output and the source-specific HUD labels without renumbering either device.
- **Superseded mapping:** Keys no longer owns Copy/Paste. Its current compact
  map keeps cells 1/4/5/7 for arrows, cell 6 for Keypad, cell 8 for Space,
  cell 9 for Next Track, cell 11 for Backspace, and cell 12 for Enter.
  Clipboard now uses Utility cell 3's held wheel control. Keep every generated
  event exact-device, non-repeating, and gated by the unlocked-session lease.
- Inspect the running Codex build's command registry and queued-row renderer before assigning a Codex card. `openSideChat` opens the current task as a side task; the current queued-message row exposes Steer, Delete, Edit, and queue-toggle controls, but no action or configurable command for opening that queued message in a side task. Never bind `openSideChat` as a false substitute; keep the requested action outstanding until Codex exposes a real command or row action. The historical cell-3 Spare and New Chat placements are both superseded by the current cell-2 New Chat / cell-3 Pin-Unpin map.
- Use command truth in visible copy. Codex registers `composer.startVoiceMode`, so the mouse card is `Start voice mode`; do not call it a toggle or imply that the same command stops an active voice session. `Start new voice chat` is a two-step action: create an empty task, wait for its composer to mount, then send that same built-in voice command.
- A CSS mirror used for left-handed device geometry also mirrors descendant text. Keep the Razer shell mirrored, but cancel that transform on the explicitly ordered thumb grid so printed numbers and action labels stay readable; the source-specific `DISPLAY_ORDER` remains the semantic authority.
- GitHub Pages serves static assets with a browser-cache lifetime. Version the public homepage's stylesheet and script URLs whenever the launch bundle changes, then verify the deployed page in the same personal Chrome profile that loaded the prior asset so visual acceptance cannot accidentally pass against stale CSS.

## 2026-08-14 — Keep app wildcards silent and move rare media into Keys

- A top-level app-specific wildcard must fail closed when the frontmost app has no configured meaning. Keep one exact-device base manipulator that consumes the neutral transport under the matching application exclusion, then add only narrow application overrides. Do not let the Corsair keypad or Razer main-row source key leak as text.
- Physical cell 9 is the wildcard on both mice: Corsair printed 9 / Razer printed 7. VS Code alone emits bounded non-repeating F18 Stage + Next on a single press and F16 exact undo on a rapid double; every other app receives no output until its own explicit override exists. Physical cell 7 is ordinary Enter, and physical cell 6 opens Keys directly.
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

- An in-mode Show/Hide Legend card spends a scarce action cell on hiding the reference needed to use the mode. Keep active-mode legends visible until universal physical cell 10 exits; restore Keypad cell 3 to `DEF`, and render cell 3 as `Spare` on child pages that have no real action there. The persistent Default legend remains independently toggleable through a rapid double press on physical cell 12 outside modes.

**Status:** The grouping and active-mode visibility rules remain current. The final Default legend sentence is superseded: physical cell 10 toggles the Default legend with one press outside modes, while physical cell 12 opens Utility immediately.

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
- Ethan's accepted Utility positions are canonical cells 1/4 Brightness Up/Down, 2/5 Zoom In/Out, 3/6 Space Left/Right, 7 Keypad, 8 YouTube −5 sec, 9 Keys, 11 manual app selector, and 10 universal exit. Keys cell 12 returns to Utility. Utility cell 3 is therefore not a legend toggle.

## 2026-08-13 — Historical cell-10 Default legend design

**Status:** Superseded by the shared semantic contract at the top of this file. Both mice now use cell 2 for Keys, cell 6 for frontmost app mode, cell 10 as blank / active Exit, cell 11 for Switch App, and cell 12 for Utility single / Default legend double.

- At this historical stage, Switch App was on physical cell 2, selected-area Screenshot was on physical cell 3, and the persistent Default legend was on physical cell 10.
- The context-gated cell-10 mechanism remains useful history, but it no longer describes the live ordinary action: the higher-priority Modes rule still owns cell 10 as Exit while active, and the base leaves cell 10 blank. Switch App now lives on physical cell 11.
- Screenshot needs a real lifecycle to support the same-button cancel request. Start `/usr/sbin/screencapture -i -s <explicit-output-path>` as one owned child process, clear ownership on a verified saved file or Escape, and terminate only that still-running child on the next screenshot command, lock, sleep, reload, or shutdown. Do not delegate saving through `-p`, emulate the lifecycle with a timer or synthetic Escape, or issue a global process kill.

## 2026-08-13 — Separate live frontmost-app mode from manual background targeting

- Ethan needs two app-specific journeys: top-level physical cell 2 follows the current frontmost application and refreshes as focus changes, while Utility cell 11 opens a lower-priority configured-app selector whose chosen target stays locked without activation.
- Use one generic bounded `CGEvent.postToPid` shortcut dispatcher selected by bundle identifier. App-specific code supplies only the shortcut meaning: Chrome cell 1 uses Command-W for Close current tab and cell 8 uses Shift-Command-W for Close current window, while Codex uses its own commands. This avoids one executor per app without pretending that all apps interpret the same shortcut identically.
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
- Ethan's accepted journey uses dedicated entries but one universal exit: Utility 12, Keypad 7, frontmost App-specific 6, and Keys 2 enter their pages; active physical cell 10 exits every page. Active-mode legends remain visible until exit, app-specific children retain cell 12 for a real app action, and Keypad uses cell 3 for DEF plus cell 12 for Space/hold-Return because cell 10 is reserved for Exit.
- Keep both app-specific journeys distinct. Top-level cell 2 follows the current frontmost process; Utility cell 11 shows an explicit Codex/Chrome/VS Code selector and locks the chosen target without activation. For Codex, preserve every normal shortcut and add only missing configurable commands as non-conflicting user bindings. Unsupported Chrome/VS Code cards remain visibly Spare until they own a tested command.

## 2026-08-13 — Split runtime ownership by mouse and fail closed before synthetic keys

- One shared mode coordinator, HUD presenter, and Karabiner lease made the two exact devices interfere: entering a Corsair mode also gated the Razer base, and a Razer legend press could retarget the Corsair HUD. Give each `MouseSource` its own coordinator, all-display presenter, lighting callback, and expiring variable. A wrong-source command must be ignored rather than changing ownership.
- A visible Accessibility toggle does not prove the running build is trusted. The enabled TCC row can still carry an old rollback build's exact CDHash; `CGEvent.post` then silently discards Arrow, Zoom, Space, and Brightness events. Every native executor must check `AXIsProcessTrusted()` before claiming success, use a `.hidSystemState` event source, and surface failure through the HUD. Install the final Developer-ID build before granting the exact `/Applications/AgenticMouse.app` so a later replacement does not invalidate the grant again.
- Physical cell 3 is Screenshot outside modes, Space Left in Utility, DEF in Keypad, and Spare on child pages without another action. It is not an in-mode legend toggle. The accepted conflicts moved YouTube rewind to cell 8 and Codex microphone mute to cell 1; universal cell 10 exits every mode and closes its HUD.
- Direct cell-9 Keys and cell-11 app-specific entry require the same short Karabiner bootstrap lease as cell-12 Utility entry. Prepend the source-specific `set_variable` before `send_user_command`, then let the app acknowledge and renew it; otherwise a rapid second press can leak through the ordinary map.
- Lighting can be source-specific without pretending each side button is an LED zone. Scimitar exposes logo plus whole thumb grid; Naga exposes wheel, logo, plus whole thumb grid. Use the mode colour on logo/wheel and the last-action accent on the grid, with a proven uniform fallback when a distinct Naga frame is rejected.

## 2026-08-13 — Keep top-level media and Keys mode distinct across every layer

- The accepted shared map uses physical cell 6 for direct Keys-mode entry and physical cell 9 for the app wildcard. Next Track still lives inside Keys on physical cell 9. Preserve the exact-device crosswalk: Keys is Corsair 6 / Razer 4, while the wildcard is Corsair 9 / Razer 7.
- Keys mode owns one orange, all-display legend and only four bounded native arrow actions: cells 5/4/7/1 are Up/Down/Right/Left. Universal cell 10 exits it and immediately restores the ordinary map.
- Utility mode may still use cells 6/9 for Space Left/Right because those bindings are scoped to its active lease. Keep top-level and child-mode semantics explicit in generated tests instead of inferring a conflict from matching physical cells.
- A visible card is not acceptance by itself. Pin the generated exact-device ingress, coordinator route, native key down/up executor, distinct Default-legend accent, installed command receiver, all-display HUD lifecycle and both exit paths separately; reserve physical arrow acceptance for the real mice.

**Status:** Current as of 14 August 2026. Physical cell 2 enters the frontmost app mode, physical cell 6 enters Keys, physical cell 7 is Enter outside modes, physical cell 9 is the fail-closed app wildcard outside modes, and Next Track lives on Keys physical cell 9 alongside Copy, Paste, Space, Backspace, and Escape.

## 2026-08-12 — Verify every HUD card against a real action boundary

- A visible mode legend is not proof that its controls work. Pin the generated exact-device ingress, coordinator routing, concrete executor, bounded down/up lifecycle, and failure presentation separately; then keep physical acceptance as its own final gate.
- For Codex 26.803.61601, the installed command registry proves New Task = Command-N, Pin/Unpin = Command-Option-P, and Toggle Voice Mode = Control-Shift-V. Plain Enter remains one unmodified Return cycle. Do not treat a composer-submission shortcut as the separate queued-row Steer action; verify the current installed Codex semantics before assigning either.
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

**Status:** Historical cell-3 contract only. The accepted map now uses cell 3 for Screenshot outside modes, cell 12 for each source's independent Default legend on rapid double, cell 11 for Switch App, and cell 10 for universal active-mode Exit, as recorded in the newer learning above.

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
**Status:** Superseded again by Ethan's final source-aware contract at the top of this file: cell 12 rapid-double toggles the source-specific Default legend, cell 11 is Switch App, cell 10 is blank / active Exit, and each mouse owns an independent legend that the other mouse cannot close or retarget.
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

**Status:** Historical hierarchy only. The accepted map now uses cell 3 for Screenshot, cell 11 for Switch App, cell 10 as blank / universal active-mode Exit, and cell 12 for Utility single / persistent Default-legend double; active modes do not reserve an independent legend-toggle cell.
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
**Status:** Historical prototype only. The accepted product contract now uses a direct one-press cell-10 Default Legend toggle and direct cell-12 Utility entry; universal cell 10 exits active modes.
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
**Status:** Historical gesture contract only. The all-display presenter remains valid, but the current Default toggle is one press on cell 10 and each source owns an independent legend; cell 12 opens Utility immediately and active modes exit through cell 10.
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
**Date:** 2026-08-14
**Trigger:** Ethan wanted either Razer DPI button to start or stop VoiceInk++ without a simultaneous two-button release toggling twice.
**Symptom:** The Naga already exposed upper F21 and lower F22 lifecycles, but only F22 had an unlocked exact-device semantic binding; F21 was consumed only by the locked-session sink.
**Root cause:** The earlier implementation treated F22 as a special extra trigger instead of recognizing both DPI transports as equivalent inputs to one existing VoiceInk++ primary action. Once Karabiner exclusively owns the mouse keyboard interfaces, VoiceInk++ receives only the normalized Primary chord and cannot recover whether F19, F21, or F22 produced it.
**Fix:** Bind both exact-device F21 and F22 to the same release-only VoiceInk++ action. Let VoiceInk++ coalesce only a second complete Primary chord arriving within 90 ms, before its existing gesture classifier can treat that duplicate as startup cancellation or pause. Keep later deliberate double-click pause and triple-click clipboard gestures intact.
**Guard:** Pin both exact transports, identical release output, exact device conditions, lock gating, and locked-session consumption in generator tests. Never restore the rejected 500 ms blanket cooldown or raw-HID source sniffing while Karabiner owns the interfaces. Physically prove each button alone and both released together before accepting the live behavior.
---

---
**Date:** 2026-08-24
**Trigger:** Ethan asked app-specific mode identity to reflect the real app icon without making HUD refreshes compute-heavy, and reported that the trigger-card artwork was too blurred.
**Symptom:** Configured apps used manually chosen static accents even though the UI already resolved their real installed icons; automatic and manual journeys could also resolve the same icon through different identities, and a 12-point blur smeared recognizable icon structure.
**Root cause:** Icon resolution was presentation-only and cached by the input identity tuple, while mode definitions and mouse lighting were created earlier in `ScimitarKit` from static colours. A raw average was not suitable because transparent padding and white icon plates dominate many macOS icons.
**Fix:** Share one AppKit icon/style provider across both source HUDs and mode-definition resolution. Resolve to the exact `.app` path, rasterize only 32 × 32 pixels on the first cache miss, choose the strongest populated chromatic cluster, normalize it to a legible saturated mode accent, and use a bounded grey for truly neutral icons. Feed that accent through the existing app definition so it drives the panel/perimeter, navigation card, and mouse lighting while semantic action-family fills remain unchanged. Cache both icon and colour in memory by resolved app path, and reduce the trigger artwork to an 8-point blur at 1.14× scale.
**Guard:** Automatic frontmost and manual Choose App journeys must use the same dynamic definition source and path cache. Never persist icon bytes or derived colours, sample on every redraw, flatten semantic action colours, spread artwork across a child app page, or claim the look physically accepted before Ethan checks the installed HUD.
---
---
**Date:** 2026-08-25
**Trigger:** The top-level YouTube button needed a plain-click rewind while retaining its held-wheel scrub gesture.
**Symptom:** The shared cell-6 transport exposed press, wheel, and release, but release always only disarmed the wheel chord, so a wheel-free click did nothing.
**Root cause:** The wheel state machine discarded the completed hold without reporting whether any scroll input occurred during that exact source lifetime.
**Fix:** Return a completed release record, mark every armed source after any nonzero vertical wheel input, and rewind five seconds only when the released control is YouTube Scrub and that record is still wheel-free. Keep accepted wheel ratchets on the existing ±5-second VoiceInk route.
**Guard:** Duplicate presses must not reset the wheel-seen latch. Filtered, phased, ambiguous, and failed wheel paths must suppress the release click, while stale releases, lock, sleep, reload, source clear, and teardown must never emit a rewind.
---

---
**Date:** 2026-08-25
**Trigger:** Ethan reported that Utility Zoom ran opposite the standard computer wheel convention.
**Symptom:** Physical wheel up zoomed out and wheel down zoomed in.
**Root cause:** Zoom inherited the earlier shared physical-polarity choice even though zoom direction should follow the conventional wheel metaphor.
**Fix:** Map physical wheel up to Zoom In and wheel down to Zoom Out on both mice.
**Guard:** Keep the change local to Zoom. Never flip Brightness, Spaces, Horizontal Scroll, Clipboard, YouTube, or another wheel family with it, and pin Zoom independently in resolver and HUD-feedback tests.
---

---
**Date:** 2026-08-26
**Trigger:** Ethan asked to switch the tab-wheel direction in Chrome mode.
**Symptom:** Chrome mode used wheel up for Next Tab and wheel down for Previous Tab, opposite Ethan's preferred navigation gesture.
**Root cause:** Chrome Tabs inherited the earlier right/forward held-wheel convention even though its direction is an independent app-specific preference.
**Fix:** Reverse only Chrome Tabs: wheel up selects Previous Tab and wheel down selects Next Tab on both mice. Derive footer feedback from `chromeTabAction(for:)` so the displayed result cannot drift from dispatch.
**Guard:** Keep this reversal local to Chrome Tabs. Do not flip Horizontal Scroll, YouTube Scrub, Spaces, Cursor History, Codex Chats Selection, or another wheel family, and pin the Chrome resolver and footer feedback together.
---

---
**Date:** 2026-08-27
**Trigger:** Cursor History closed VS Code mode immediately after its first wheel ratchet.
**Symptom:** The direct VS Code command ran, then the HUD and mode disappeared as the runtime supervisor relaunched Agentic Mouse.
**Root cause:** `NSWorkspace.open` delivered its completion on LaunchServices' private open queue. The completion flashed wheel feedback through `AppKitModeHUDPresenter`, which ran SwiftUI/AppKit layout off the main thread and aborted in `NSISEngine`.
**Fix:** Make `VSCodeCommandBridge` return every asynchronous URL-open result on the main queue before logging or touching the HUD.
**Guard:** Test an injected URL opener that completes from a background queue and require the bridge's public completion to run on the main thread. When a mode disappears after an otherwise successful action, inspect crash reports and supervisor/process start times before blaming wheel or focus state.
**Verification:** Both installed v1.0.133 crash reports from 17:29 showed the same LaunchServices completion → HUD feedback → `AppKitModeHUDPresenter.position` → `NSISEngine` abort. The focused bridge suite passed six tests, including a background-queue completion, and the complete clean gate passed 654 Swift tests, six Musixmatch extension tests, six VS Code bridge tests, 17 Karabiner generator tests, generated-source freshness and lint, packaging/version contracts, runtime-supervisor packaging, shell syntax, and diff hygiene. Developer-ID-signed Agentic Mouse v1.0.137 (build 143) is installed as main PID 50371 with executable SHA-256 `d128c25b565ca96cab7f4cb184b217acb2d3f1373073d4dbdd7f4da8fc6af67a`, CDHash `e138323e862219fb886d32b83747b7bc6c35db27`, Team ID `T34G959ZG8`, Accessibility trusted, iCUE connected, and exact ownership of the mode-0600 Karabiner command socket. Its matching signed runtime supervisor runs as PID 50410. The embedded iCUE SDK, live Agentic Mouse configuration, live Karabiner configuration, and VS Code keybindings remain byte-identical at SHA-256 `48bbc94bed670d036af8e1acca0017449b36d7c6d1e15dafe0791b42b6be84fe`, `aa1499d88bd34875dc11f9a2873165d09cd2323c590126f425da4fd72e3189be`, `b8a0048a76dda9aa03e38aeb538da4346d465428d078f7eeca7593c264698bbd`, and `8d23c9fae7eb21104cda9203be4b95e2cebacfb08e708f806977dcb3720b60aa`. No new crash report appeared after installation. The exact prior apps remain recoverable under `Rollbacks/` and Trash. Literal physical Cursor History acceptance remains Ethan-owned: enter VS Code mode on either mouse, hold Cursor History, and perform several wheel ratchets in both directions; the mode and HUD must stay open while cursor history moves.
---

---
**Date:** 2026-08-27
**Trigger:** After an installed replacement, Agentic Mouse logged successful legend commands and direct window captures showed fully rendered panels, but no legend appeared in full-display screenshots.
**Symptom:** The signed runtime, command socket, Accessibility permission, iCUE connection, HUD models, and panels were healthy, yet every visible display omitted the legend until a later launch-path fix.
**Root cause:** The install workflow relaunched the LSUIElement app with `open -gj`; `-j` asks LaunchServices to launch the app hidden, so macOS suppressed its fully rendered panel windows. The earlier conclusion that cached panels were stranded only on stale Spaces or app window sets was incomplete. A temporary panel probe showed every tested collection-behavior variant on current displays when its process was not launched hidden.
**Fix:** Call `NSApp.unhideWithoutActivation()` immediately after setting the accessory activation policy so even a hidden background launch can present the HUD without activating Agentic Mouse. Keep `.canJoinAllApplications` beside `.canJoinAllSpaces` as separate system-overlay hardening, and remove the failed recreate-on-every-show workaround that introduced AppKit layout recursion.
**Guard:** Never use `open -j` to relaunch the installed Agentic Mouse. Treat AX window counts and direct window captures only as render evidence; require full-display pixel screenshots across every connected current display and visible Space, plus a real toggle, before accepting HUD visibility.
**Verification:** The final v1.0.137 app was deliberately launched through the previously failing `open -gj` route. Full-display screenshots then showed the v1.0.137 legend on all three connected displays, and Ethan physically confirmed that the legend toggle was working. The complete clean gate passed on the final source, and the live runtime remained Developer-ID signed, Accessibility trusted, iCUE connected, and supervisor-managed.
---
