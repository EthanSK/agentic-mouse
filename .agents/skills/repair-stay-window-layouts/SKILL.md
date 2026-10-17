---
name: repair-stay-window-layouts
description: Diagnose and repair Stay (Cordless Dog) saved window layouts when Ethan reports issues with Stay, says Stay is broken or windows are not restoring, Restore is disabled, the monitor layout does not match, or Organize Windows fires without moving windows. Also use after monitor replacement, rearrangement or rescaling, or a stored app changes such as OBS Studio to OBS++. Does not cover the ordinary word stay, generic macOS search or unrelated mouse mappings.
---

# Repair Stay window layouts

Recover the existing intended layout without replacing good saved windows with the current broken arrangement.

Project: [Agentic Mouse](../../../README.md).

## Continuous improvement

Improve this skill as part of using it, but don't add every finding. When Ethan explicitly requests generic behavior or clearly expresses an interest in how this skill should work normally, favor a small same-task update to the existing guidance for that general case. His statement establishes his preference: no repeated examples, reproduced failure or explicit “save this” request is needed. Preserve his wording, conditions and scope; don't turn ordinary curiosity, hypothetical questions or task-only requests into lasting defaults. Follow existing destination and approval rules.

For agent-discovered findings, make a quick judgment: is this verified lesson likely to be useful again frequently enough, save meaningful repeated work, or prevent a serious future mistake? Its expected benefit must justify the extra instructions and maintenance. Assume agents are capable and getting better; skip routine advice they can reasonably work out and isolated incident facts. When an improvement has credible future value, err on the side of a concise useful update without a lengthy audit or waiting for another failure. This filters agent-initiated learning, not Ethan's explicit requested instructions or preferences.

For a qualifying lesson, update this skill during the same task without waiting for a separate request. Prefer refining or merging existing guidance to appending another rule. Update its instructions, scripts, tests, or references as appropriate, retest affected behavior, and validate the skill before finishing. After every modification, review whether `SKILL.md` remains a concise operating contract and router; move conditional detail into directly linked references when that reduces irrelevant context without hiding universal safeguards or fragmenting the skill unnecessarily. Preserve reusable knowledge; do not record guesses, duplicate guidance, secrets, credentials, or transient runtime state.

Mark agent-initiated additions or material changes with a visible `Self-improved — YYYY-MM-DD` note beside the affected guidance, including a quick reason and an evidence reference. For scripts or larger changes, use a concise `Self-improved` section identifying the affected file or section, reason, evidence, and validation performed. Keep lengthy audit evidence in a directly linked reference. Do not label changes preserving Ethan's expressed general-behavior preferences as self-improved, invent historical provenance, or overwrite intervening manual changes.

## Skill usage announcement

Whenever this skill is used, tell Ethan in commentary before taking any skill-directed action. Name the skill and briefly say why it applies. Use the **Skill use** announcement format defined in `$response-preferences`, and preserve explicit silent-use exceptions.

## Discovery across chats

Use this skill automatically when Ethan says there are issues with Stay in the future, including “Stay is broken”, “Stay is not restoring windows”, or “Organize Windows does nothing”; he does not need to name the skill. Keep diagnosis and any authorized repair within the safeguards below.

The canonical skill belongs to the Agentic Mouse project. A user-scope installation can symlink to this folder so the same procedure is discoverable outside the project without maintaining another copy. Resolve the loaded skill folder's real path before following project-relative links.

## Diagnose before changing anything

1. Read project rules and relevant entries in [LEARNINGS.md](../../../LEARNINGS.md), searching for `Stay`, `Organize Windows`, `Replace Stay profile apps`, and display configuration. Recover actual prior evidence before claiming a monitor migration worked. An app replacement is not proof of a monitor replacement.
2. Establish the exact installed Stay and Agentic Mouse versions, target saved workspace, current display identities/bounds, stored window count, shortcut, and automatic-restore settings. Use `$use-macbook-display` before native interaction and preserve unrelated windows/Spaces. Selected text is context, not permission to overwrite a layout.
3. Classify the failure: **same displays with changed origins**, **changed resolution/scaling**, **changed display identity**, **shortcut dispatch/collision**, or **window matching**. Restore being disabled must be resolved before interpreting a posted shortcut as a working restore.
4. Read only the matching section of [recovery procedures](references/recovery.md). The supported Stay UI is authoritative; an optional private-schema read is diagnostic evidence, not a supported editing interface.

## Repair boundaries

- Preserve the intended saved windows, title rules, other profiles and automatic-restore settings. Never edit Stay's Core Data database or its preference plist directly. For read-only inspection/backups use a consistent SQLite backup, or copy while Stay is quit; do not copy a live main file alone and lose WAL data.
- Before an authorized live repair, capture rollback state and use `$macos-heads-up-notification` for display changes or a workspace restore that will interrupt Ethan. Existing task authorization applies; do not ask again for an already authorized repair. If the intended arrangement or overwrite scope is genuinely ambiguous, clarify before that dependent mutation.
- Keep raw databases, window titles, serials, display IDs and local rollback artifacts outside public source. Derive IDs, origins, refresh rates, scaling and main-display choice from the current machine; never use historical values as defaults.
- Agentic Mouse's runtime remains manual: one configured Organize Windows shortcut, no automatic restoration, Stay AppleScript/UI-driving code, daemon, hook or new background supervisor. An attended repair through supported visible UI is distinct from adding runtime automation.

## Verify and report

Read back every display's identity, origin, dimensions, main/mirroring status and mode after a display change; verify unchanged saved profiles/windows semantically. Check Stay's live Restore enabled state, not only the display command exit code. For a window repair, compare actual intended window frames and matching rules. If screenshots support a claim, load them into vision; file existence or AX alone does not prove appearance.

Report the cause, repair performed, rollback location, and remaining limits. Distinguish shortcut posted, Restore enabled, actual window restoration, and physical mouse acceptance; leave the latter pending until Ethan confirms it. Record only verified reusable lessons in the project's existing LEARNINGS.md, with source evidence and any unresolved acceptance status.
