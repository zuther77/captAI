# Test matrix

Status values: **PASS**, **FAIL**, **NOT PERFORMED** (no one has run it), **BLOCKED**. Only results someone actually observed are PASS.

## Automated

| Suite | Command | Result (2026-11-17) |
|---|---|---|
| Unit (76 tests, 10 suites) | `scripts/test.sh unit` | PASS |
| Integration (12 tests, 2 suites) | `scripts/test.sh integration` | PASS |
| UI (6 tests) | `scripts/test.sh ui` | BLOCKED: runner aborted before connecting in the agent environment (KI-001) |
| Debug build, warnings as errors | `scripts/build.sh Debug` | PASS |
| Release build, warnings as errors | `scripts/build.sh Release` | PASS |

## Manual: M0 (real Mac)

Performed by the agent without a display session: only item 0. Items 1–5 need a person at a Mac.

| # | Step | Expected | Status |
|---|---|---|---|
| 0 | Launch the Debug build with `--ui-testing`; list windows through the window server | Exactly one on-screen window (Settings); none after quit | PASS (agent, automated observation; not a visual check) |
| 1 | `scripts/run.sh`; look at the menu bar | `camera.viewfinder` icon present; clicking it opens a menu; no Dock icon; no main window | NOT PERFORMED |
| 2 | Menu > Settings…, close, reopen via menu and ⌘, | Window opens, closes and reopens in the same place; all six sidebar panes selectable | NOT PERFORMED |
| 3 | Toggle System Settings > Appearance between Light and Dark with Settings open | All panes legible in both | NOT PERFORMED |
| 4 | Privacy pane with Screen Recording never requested, then granted, then removed in System Settings | "Not requested" + Request Access; "Granted" with no button; "Denied" + Open System Settings | NOT PERFORMED |
| 5 | Launch fresh, quit without touching anything; check System Settings > Privacy & Security | captAI is **not** listed under Screen Recording or Microphone | NOT PERFORMED |

## Cross-milestone privacy matrix (M0 slice)

| Scenario | M0 evidence |
|---|---|
| No permission requested at startup | `AppEnvironmentTests.startupOpensNoWindowsAndRequestsNoPermissions` (PASS); manual item 5 NOT PERFORMED |
| Reading permission state never prompts | `systemProviderStatusReadsDoNotThrowOrPrompt`, `creatingAStoreReadsStatusButNeverRequests` (PASS) |
| No network use | No networking code exists in M0. The Release binary links no ScreenCaptureKit, Vision or Network framework (`otool -L`, PASS). A network spy arrives with M2. |
| Credentials absent from settings file | `savedFileContainsNoCredentialFields` (PASS) |
| Sensitive values absent from logs | `DiagnosticsTests` redaction cases (PASS) |
