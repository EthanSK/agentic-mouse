# Stay recovery procedures

Read only the section matching the diagnosed failure. Historical facts belong in the project's [LEARNINGS.md](../../../../LEARNINGS.md); inspect its actual entries rather than maintaining another incident chronology here.

## Display arrangement, scaling or identity

Stay binds a workspace to the whole display configuration, including origins. A monitor being slightly higher/left is enough to disable Restore even when names and resolutions match. Compare identities separately from bounds before replacing anything.

For accidental arrangement drift when the saved layout is the intended one, preserve the stored workspace and return the live arrangement to it. Stay documents **Edit Stored Windows → Make Display Configuration Active** for a compatible configuration. This changes live display positions; it is not a layout-only data migration. Alternatively, an already installed `displayplacer` can apply a reversible OS arrangement change. Read its current help and `list` output first; save its full rollback command and preserve every display's resolution, refresh rate, colour depth, scaling, rotation, main-display and mirroring choice. Apply only the established intended difference, then independently read back all displays and Stay's Restore state. Never hard-code IDs/coordinates from earlier evidence.

If the current arrangement was deliberate, do not silently move it back or overwrite all stored windows. Re-storing may capture today's misplaced window frames. Establish the intended windows and scope first, back up, then use supported UI to capture only what was requested.

A changed monitor identity is a separate branch. Read prior evidence and current Stay documentation for supported migration. Do not assume an app-replacement procedure migrates monitors, or issue SQL UPDATEs to ZDISPLAY. If no verified supported migration is available, state that precise limit and prepare the smallest supported recapture/reconstruction rather than inventing a database repair.

Official sources: [Stay FAQ](https://cordlessdog.com/stay/documentation/faq/) and [Editing stored windows](https://cordlessdog.com/stay/documentation/editing-stored-windows/). Recheck live docs if behaviour/version differs.

## Shortcut delivery and collisions

Read the actual configured Organize Windows chord from current project source and Stay's supported settings. Older notes may contain superseded chords; verify the live registration and physical key code rather than copying them. Preserve the rest of the shortcut map. Check collisions with Agent Flow/Karabiner only when evidence points there; do not change other shortcuts speculatively.

A disabled Restore remains disabled regardless of event delivery. Once enabled, inspect the existing Chrome pre-move and single hardware-shaped chord lifecycle before changing dispatch code. Keep the visible Space unchanged. A logged event proves dispatch only; verify a real saved window returns to its stored frame. Preserve source-specific mouse mapping, recording and running app state. Do not reintroduce the older synthetic Quartz F14 route that failed to activate Stay.

## App replacement and window matching

Search LEARNINGS for **2026-08-20 — Replace Stay profile apps through supported capture and exact read-back** and related OBS++ title-rule entries. The verified procedure is:

1. Back up state and record semantic rows for target and non-target workspaces/apps.
2. Establish the exact replacement bundle and intended current main window; exclude helper/AXDialog windows. Bring only the intended app into focus through supported attended UI.
3. Use Stay's supported **Store All Windows for [that app]** overwrite, scoped to that app. Never use global Store to repair one app.
4. Poll persisted state through a read-only consistent snapshot: check the replacement bundle, intended frame/count and regex flags; preserve the intended title-matching rule.
5. Remove an obsolete app/window only through Stay's editor, after the replacement is verified. Preserve other profiles and automatic-restore settings.
6. Check actual restore, then separately obtain the user's physical mouse acceptance. Protect active OBS recording; do not quit OBS or recapture auxiliary windows as a shortcut.

When the bundle is unchanged but titles drift, inspect the existing matching rule before recapture. Broad regexes must not match auxiliary windows. OBS Custom Browser Docks disappearing is a different job: use `$restore-obs-browser-docks` only for that actual symptom.
