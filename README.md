# captAI

A native, local-first macOS utility for capturing the screen, copying text with on-device OCR, and discussing captures with an AI assistant. Source documents: `docs/captAI_PRD.md`, `docs/captAI_Design_Spec.md`, `docs/captAI_Implementation_Plan.md`.

**Status:** Milestone M0 (foundation). The app is a menu-bar shell with a Settings window. Capture, OCR and AI arrive in later milestones.

## Requirements

- Xcode with a macOS SDK that includes macOS 26 (built with Xcode 27 beta).
- No other tools or dependencies.

## Project file

**Xcode owns `captAI.xcodeproj`.** Open it in Xcode, edit it there, and commit the changes. `scripts/generate_project.rb` bootstrapped the project and is kept only for reference. It refuses to run without `--force`, because running it replaces the project and discards any change made in Xcode.

When you add a source file under `App/`, `Features/` or `Core/`, tick its target membership for `captAI`, `captAIUnitTests` and `captAIIntegrationTests`. The unit and integration bundles compile those sources directly instead of launching the app, so a file missing from them is not tested. Files under `Tests/Unit` and `Tests/Support` belong to the unit and integration targets as before, and `Tests/UI` to `captAIUITests`.

## Commands

```sh
scripts/build.sh [Debug|Release]      # build
scripts/test.sh [unit|integration|ui|fast|all]   # fast = unit + integration (default)
scripts/run.sh                        # build Debug and launch; look for the camera icon in the menu bar
```

The same builds and tests run from Xcode: open `captAI.xcodeproj`, choose the `captAI` scheme, ⌘R to run, ⌘U to test.

UI tests drive the real app and need a logged-in desktop session with Accessibility access for Xcode's test runner.

If a build inside another macOS sandbox fails with "external macro implementation type ... malformed response", set `CAPTAI_DISABLE_SWIFT_SANDBOX=1` for the script (see `docs/KNOWN_ISSUES.md`, KI-006).

## Signing

Builds are ad-hoc signed by default. Screen Recording permission is tied to the signature, so to keep it across rebuilds, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (gitignored) and set your team.

## Layout

```text
App/        menu-bar app, composition root (AppEnvironment), window coordinator, permissions
Features/   Settings (more features per milestone)
Core/       models, geometry, storage, security/diagnostics, utilities (no UI)
Tests/      Unit, Integration, UI, shared Support fakes, Fixtures
docs/       DECISIONS, TEST_MATRIX, KNOWN_ISSUES, MILESTONE_REPORTS
```
