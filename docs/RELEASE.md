# Release readiness

**Current status: a source project for developers who can commission their own setup.** The walkthrough is public. There is no ready-to-install signed and notarized download, and some controls depend on Ethan's external integrations.

## What the repository provides

| Area | Available |
|---|---|
| Build verification | Clean Swift build, hardware-free native tests, both extension suites, Karabiner generation/tests, installation tests and website tests |
| CI | Full app checks and an SDK-free development package; separate Pages build/test/deploy |
| First installation | Explicit dry run, live-file hash check, private backup and complete runtime rules |
| Updates | Stable signing identity supplied by the owner; guarded candidate versioning and rule replacement |
| Onboarding | Setup, per-owner agent instructions, dependency inventory and recovery/removal |
| Website | Native-generated controls, browser-only demos and automatic rebuilds on pushes to main |

Automated evidence covers the committed source. It does not certify every physical action, every hardware/OS combination, or a private local checkout with uncommitted changes. [LIVE-PROOF.md](LIVE-PROOF.md) and [LIMITATIONS.md](LIMITATIONS.md) retain the narrower physical evidence and known boundaries.

## Before a public app download

- Produce a Developer ID distribution build with the appropriate hardened-runtime settings, notarize it with Apple, and staple and verify the result. The current packager alone does not implement that distribution pipeline.
- Confirm redistribution terms for the proprietary SDK and other bundled material before publishing binaries. Source builds use the owner's local SDK.
- Test the downloaded artifact on a separate clean Mac: Gatekeeper, Accessibility, Karabiner setup, login supervisor, first installation, update and removal.
- Publish the exact supported Mac architectures, macOS versions, mouse models and transport interfaces that passed physical acceptance.
- Make required external receivers available with compatible versioned installation instructions, or clearly ship a reduced setup that omits their controls. The current source still describes Ethan's full map.
- Resolve or explicitly document every applicable **Needs repair** control in the generated map.
- Include release notes, artifact checksums, version/commit provenance and a tested rollback path.

These are open gates, not claims of completed validation. Do not describe the current repository as a universal plug-and-play app.

## Validate each source release

1. Run `make check` from the exact intended source and confirm generated rules are current.
2. Package an SDK-free development bundle without launching it to catch missing resources or helper packaging.
3. Verify relevant physical behavior on the intended installed signed build at an attended, safe time. Preserve the previous app and rule backup.
4. For website changes, manually check desktop/mobile, keyboard input, both hands, rotation and mode transitions. Confirm images keep their aspect ratio.
5. Review the staged diff for private files, unrelated work and accidental generated changes.
6. Publish only with the repository owner's authorization. Confirm app CI and Pages checks for the exact pushed commit, then inspect the deployed website.

A native installation is unnecessary for a website or documentation-only release. Never overwrite a newer locally developed runtime with an older public source build merely to validate a website.
