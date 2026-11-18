# Test matrix

Status values: **PASS**, **FAIL**, **NOT PERFORMED** (no one has run it), **BLOCKED**. Only results someone actually observed are PASS.

## Automated

| Suite | Command | Result |
|---|---|---|
| Unit (76 tests, 10 suites) | `scripts/test.sh unit` | PASS (2026-11-18) |
| Integration (12 tests, 2 suites) | `scripts/test.sh integration` | PASS (2026-11-18) |
| UI (6 tests) | `scripts/test.sh ui` | PASS (2026-11-18, run by the product owner on a real Mac: 6 tests, 0 failures). The first run had 4 failures: the tests located the Settings window by title, but the SwiftUI `navigationTitle` renames it to the selected pane. The window now has the identifier `settings.window` (KI-001). |
| Debug build, warnings as errors | `scripts/build.sh Debug` | PASS (2026-11-17) |
| Release build, warnings as errors | `scripts/build.sh Release` | PASS (2026-11-17) |

## Manual: M0 (real Mac)

Item 0 was performed by the agent without a display session. Items 1–5 were performed by the product owner on a real Mac on 2026-11-18.

| # | Step | Expected | Status |
|---|---|---|---|
| 0 | Launch the Debug build with `--ui-testing`; list windows through the window server | Exactly one on-screen window (Settings); none after quit | PASS (agent, automated observation; not a visual check) |
| 1 | `scripts/run.sh`; look at the menu bar | `camera.viewfinder` icon present; clicking it opens a menu; no Dock icon; no main window | PASS |
| 2 | Menu > Settings…, close, reopen via menu and ⌘, | Window opens, closes and reopens in the same place; all six sidebar panes selectable | PASS |
| 3 | Toggle System Settings > Appearance between Light and Dark with Settings open | All panes legible in both | PASS |
| 4 | Privacy pane with Screen Recording never requested, then granted, then removed in System Settings | "Not requested" + Request Access; "Granted" with no button; "Denied" + Open System Settings | PASS (second attempt; the first showed "Denied" after granting because of a stale grant from an earlier ad-hoc build, fixed by `tccutil` reset and re-grant) |
| 5 | Launch fresh, quit without touching anything; check System Settings > Privacy & Security | captAI is **not** listed under Screen Recording or Microphone | PASS |

## Cross-milestone privacy matrix (M0 slice)

| Scenario | M0 evidence |
|---|---|
| No permission requested at startup | `AppEnvironmentTests.startupOpensNoWindowsAndRequestsNoPermissions` (PASS); manual item 5 PASS |
| Reading permission state never prompts | `systemProviderStatusReadsDoNotThrowOrPrompt`, `creatingAStoreReadsStatusButNeverRequests` (PASS) |
| No network use | No networking code exists in M0. The Release binary links no ScreenCaptureKit, Vision or Network framework (`otool -L`, PASS). A network spy arrives with M2. |
| Credentials absent from settings file | `savedFileContainsNoCredentialFields` (PASS) |
| Sensitive values absent from logs | `DiagnosticsTests` redaction cases (PASS) |
