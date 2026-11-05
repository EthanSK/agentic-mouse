# Release readiness

**Distribution uses signed, notarized GitHub releases with standard Sparkle updates.** Device commissioning and external integrations still need per-owner setup. A successful workflow and downloaded-artifact verification are required before calling an individual release published.

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

## Automatic release pipeline

Main pushes run the full hardware-free checks and build a universal unsigned candidate on GitHub's macOS runner. The source commit and archive hash travel with that candidate. A dedicated logged-in signing runner verifies both before applying Developer ID signatures, Apple notarisation and Sparkle's final-archive signature. Private keys remain in that Mac's Keychain; no certificate export or repository signing secrets are required. Fork pull requests never reach the signing runner.

Register the signing runner with the `agentic-mouse-release` label, an accessible Developer ID identity, a `notarytool` profile selected by `NOTARY_PROFILE`, and the Sparkle Keychain account `com.ethansk.AgenticMouse`. Keep the public verification key in `Resources/Info.plist`. Each app-changing release must advance the recorded version and build; published versions are immutable and reruns never overwrite them.

Public archives omit the proprietary Corsair SDK. Corsair lighting needs a separately installed SDK; the source build remains available for owners using an audited local framework. The public SDK EULA does not establish permission to redistribute that framework, so the pipeline rejects an accidentally bundled SDK. The optional external SDK requires the main app's library-validation entitlement; the helper and doctor do not receive it.

`SHA256SUMS` and `release.json` record the exact downloadable ZIP, source commit, architectures, minimum macOS and notarization result. The website checks the latest published release and offers its ZIP; without a verified release manifest it retains the source/setup links. Initial installation follows SETUP.md. Updater-enabled installations use the signed appcast and wait for the protected idle boundary before relaunch.

**Independent clean-Mac acceptance remains separate:** verify first installation, device setup, update and removal on each supported configuration. A local Developer ID signature alone is not notarisation.

## Before calling a download fully accepted

- Produce a Developer ID distribution build with the appropriate hardened-runtime settings, notarize it with Apple, and staple and verify the result. `Publish signed app` implements these gates and fails closed if credentials or any verification step is missing.
- Confirm redistribution terms for the proprietary SDK and other bundled material before publishing binaries. Source builds use the owner's local SDK.
- Test the downloaded artifact on a separate clean Mac: Gatekeeper, Accessibility, Karabiner setup, login supervisor, first installation, update and removal.
- Publish the exact supported Mac architectures, macOS versions, mouse models and transport interfaces that passed physical acceptance.
- Make required external receivers available with compatible versioned installation instructions, or clearly ship a reduced setup that omits their controls. The current source still describes Ethan's full map.
- Resolve or explicitly document every applicable **Needs repair** control in the generated map.
- Include release notes, artifact checksums, version/commit provenance and a tested rollback path.

These are open gates, not claims of completed validation. Do not describe the current repository as a universal plug-and-play app.

## Validate each source release

1. Run `make check` from the exact intended source and confirm generated rules are current.
2. Package an SDK-free development bundle. Packaging checks the framework search path in every architecture and runs the actual executable with `--check-packaged-launch`; this exits before AppKit, hardware, the instance lock or recovery starts. The signing gate repeats this check on the final extracted release archive. A passing signature or notarisation alone does not prove the executable can load its frameworks.
3. Verify relevant physical behavior on the intended installed signed build at an attended, safe time. Preserve the previous app and rule backup.
4. For website changes, manually check desktop/mobile, keyboard input, both hands, rotation and mode transitions. Confirm images keep their aspect ratio.
5. Review the staged diff for private files, unrelated work and accidental generated changes.
6. Publish only with the repository owner's authorization. Confirm app CI and Pages checks for the exact pushed commit, then inspect the deployed website.

A native installation is unnecessary for a website or documentation-only release. Never overwrite a newer locally developed runtime with an older public source build merely to validate a website.
