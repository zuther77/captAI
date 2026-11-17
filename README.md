# captAI

A native, local-first macOS utility for capturing the screen, copying text with on-device OCR, and discussing captures with an AI assistant. Source documents: `captAI_PRD.md`, `captAI_Design_Spec.md`, `captAI_Implementation_Plan.md`.

**Status:** Milestone M0 (foundation). The app is a menu-bar shell with a Settings window. Capture, OCR and AI arrive in later milestones.

## Requirements

- Xcode with a macOS SDK that includes macOS 26 (built with Xcode 27 beta).
- No other tools or dependencies. The Ruby `xcodeproj` gem is needed only to regenerate the project file.

## Commands

```sh
scripts/build.sh [Debug|Release]      # build
scripts/test.sh [unit|integration|ui|fast|all]   # fast = unit + integration (default)
scripts/run.sh                        # build Debug and launch; look for the camera icon in the menu bar
ruby scripts/generate_project.rb      # regenerate captAI.xcodeproj after adding/removing source files
```

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
