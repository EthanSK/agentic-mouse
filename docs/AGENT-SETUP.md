# Set up another person's Mac

Give this guide to your coding agent together with the [setup guide](SETUP.md). The repository describes Ethan's setup. His devices, signing certificate, keyboard layout, shortcuts and permissions are **not** facts or authorization about another person's machine.

## Establish the owner's setup

Before changing hardware, ask the owner which mouse models, hand or hands, keyboard layout and apps they want to use. Inspect exact device interfaces in Karabiner-EventViewer, existing profiles and the installed app version. Record the source commit and Git state. Preserve all unrelated staged, unstaged and untracked work.

Use a read-only build and diagnostics first. Do not launch an ad-hoc GUI app, replace an installed binary, send synthetic input, register a login helper, change vendor profiles, reset permissions or write lighting merely to inspect the project. Arrange an attended test before actions that interrupt the owner's desktop, media or editor.

Create private backups of the live Karabiner file, app configuration, vendor profile export and installed signed app before an authorized installation. Keep them outside Git. Never publish device serials, screenshots of private work, passwords, config files or signing material.

## Adapt from the source of truth

| Concern | Authoritative source |
|---|---|
| Physical cell and printed-number crosswalk | [PhysicalCell.swift](../Sources/ScimitarKit/App/PhysicalCell.swift) |
| Neutral transports and exact-device filters | [bindings.json](../Karabiner/bindings/bindings.json) |
| Semantic Karabiner actions | [actions/](../Karabiner/actions/) |
| Mode definitions and transitions | [ScimitarKit/](../Sources/ScimitarKit/) and its coordinator tests |
| macOS output and external app contracts | [AgenticMouseApp/](../Sources/AgenticMouseApp/) |
| User configuration defaults | [config.example.json](../Config/config.example.json) |
| Public map and walkthrough | [ShowcaseExporter/](../Sources/ShowcaseExporter/), then `make test-site` |

Do not hand-edit generated Karabiner JSON or invent a second browser button map. Update the owner of the behavior, regenerate and test. Twelve physical actions are mirrored across the two adapters; printed numbers are not interchangeable. Each hand has independent mode and legend state.

Ethan uses `DVORAK - QWERTY CMD`. Some app routes deliberately encode physical keys for that layout. Verify the destination shortcut and actual key lifecycle on the owner's layout before adapting it. Do not copy those chords blindly to QWERTY or change global OS shortcuts to conceal a mismatch.

Consult the dependency table in [SETUP.md](SETUP.md). VoiceInk++ / YouTube Bridge and Better Git are external integrations, not shipped features you can promise on a fresh Mac. Ask which unavailable controls the owner wants to replace or leave unused. Do not silently install an unrelated app or claim that the included VS Code Bridge implements Better Git.

## Install only the reviewed candidate

1. Run `make check` from the intended source checkout. Report failures instead of weakening tests or security gates.
2. Verify the owner's available stable signing identity. Use `CODE_SIGN_IDENTITY`; Ethan's certificate is only for his own Mac. Keep the bundle identity and `/Applications/AgenticMouse.app` path stable across updates.
3. For Corsair lighting, use the audited SDK version from [SETUP.md](SETUP.md). An explicit SDK-free build is appropriate for a Razer-only setup; missing Corsair RGB must remain visible.
4. Package one successful `make install-candidate`. Record the version, executable hash, signature and embedded SDK version. Do not consume another version by repeating packaging without a source change.
5. Dry-run the complete runtime installer against the captured live hash and an unused private backup path. Use `--initialize` only when no Agentic rules exist. Never import the partial base export or replace the owner's entire profile.
6. On an update, keep the old runtime alive while the rule installer closes both coordinators and reloads Karabiner. Record visible Default legends first.
7. Use **Quit Agentic Mouse** to disarm the supervisor before replacing its exact bundle. If that fails, follow [RECOVERY.md](RECOVERY.md); do not loop on process killing.
8. Replace only the authorized app, launch its exact installed path, verify signature/version/hash and command-receiver ownership, then restore the recorded legends after the unlocked-session gate becomes ready. Let the owner handle macOS permission prompts.

## Verify the owner's real case

Record pass, fail or not tested for each relevant item:

- Exact transports from each mouse; ordinary keyboard and other mice unaffected.
- Default legend, every selected mode, universal Exit and independent two-hand state.
- Clipboard, Keypad focus changes, held-wheel direction, and hold/release cancellation.
- Installed external receivers and their actual actions; staging tests in a disposable repository.
- Lock/unlock, sleep/wake, app restart, intentional Quit and normal input restoration.
- Physical lighting for each installed mouse, including idle colour and release on exit.
- Rollback to the preserved app/rule block without losing newer unrelated configuration.

Tests against fake hardware and browser clicks do not prove any physical item. A configured Ethan setup is not evidence of another model, another Mac or another owner's permissions. Report the exact remaining blockers and leave the owner a recoverable working state.

## Finish the handoff

Summarize the source commit, installed version, enabled integrations, private backup locations, checks performed and physical tests still pending. Link the setup, recovery and generated map. Honor that owner's commit, deployment and installation permissions; Ethan-specific standing permissions in the root `AGENTS.md` do not transfer to a fork.
