# Contributing

Start with the [README](README.md), [architecture](docs/ARCHITECTURE.md), and [agent setup guide](docs/AGENT-SETUP.md). You can build and test without mice or the iCUE SDK.

## Make a focused change

1. Fork the repository, create a branch, and run `npm ci --ignore-scripts --prefix Integrations/VSCode` to install the locked local packaging tool.
2. Change the source that owns the behavior. Keep device routing exact and preserve unrelated controls.
3. Run `make check`. For packaging changes, also run `ICUE_SDK_FRAMEWORK=/nonexistent/agentic-mouse-sdk make app`; it packages an ad-hoc development bundle without launching or installing it.
4. For website changes, serve `.build/site` after `make test-site`. Check desktop and phone widths, both hands, drag rotation, keyboard controls, native HUD interactions and the no-WebGL fallback. Keep screenshots and personal data outside Git.
5. Describe the concrete before/after behavior, validation and any missing physical acceptance in the pull request.

The app CI runs the clean hardware-free gate and an SDK-free package build. The Pages workflow builds and tests the website; only pushes to `main` publish it. A green check does not authorize an installation on someone's Mac.

## Keep generated data derived

Edit Karabiner actions/bindings and native mode definitions, then use `make karabiner` and `make test-site`. Commit changed tracked Karabiner outputs with their sources. The generated website stays under ignored `.build/site`. Do not maintain a separate browser mapping or edit the historical `docs/script.js` table for the showcase.

Run the generator's `--check` path before submission; stale generated rules fail CI. Preserve exact-device filters, unlocked-session gates, short mode leases, universal Exit and process-targeted output. See root [AGENTS.md](AGENTS.md) for product invariants and its opening scope note before applying Ethan-specific instructions.

## Report a problem

Use [GitHub Issues](https://github.com/EthanSK/agentic-mouse/issues). Include the commit/app version, macOS version, mouse model, keyboard layout, action attempted, expected result and actual result. Distinguish browser simulation from installed-app and physical observations.

Share only redacted diagnostics. Do not upload your live Karabiner/config files, serial numbers, passwords, signing identities or private desktop screenshots. For a suspected security issue, use GitHub's private vulnerability-reporting option if the repository offers it; otherwise report only a non-sensitive summary until a private channel is agreed.

## Release changes

Follow [RELEASE.md](docs/RELEASE.md). Website deployment, native packaging, installing a local build and distributing a notarized release are separate outcomes. Claim only those actually verified.
