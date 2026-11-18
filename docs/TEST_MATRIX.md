# Test matrix

Status values: **PASS**, **FAIL**, **NOT PERFORMED** (no one has run it), **BLOCKED**. Only results someone actually observed are PASS.

## Automated

| Suite | Command | Result |
|---|---|---|
| Unit (150 tests, 19 suites) | `scripts/test.sh unit` | PASS (2026-11-18, M1 branch; run through `xcrun xctest` because the scheme `test` action cannot run in the agent sandbox) |
| Integration (17 tests, 3 suites) | `scripts/test.sh integration` | PASS (2026-11-18, M1 branch; same note) |
| UI (6 tests) | `scripts/test.sh ui` | PASS on M0 (2026-11-18, run by the product owner on a real Mac: 6 tests, 0 failures). The first run had 4 failures: the tests located the Settings window by title, but the SwiftUI `navigationTitle` renames it to the selected pane. The window now has the identifier `settings.window` (KI-001). **Not re-run on the M1 branch**: the Shortcuts pane was rewritten, so run `scripts/test.sh ui` again. |
| Debug build, warnings as errors | `scripts/build.sh Debug` | PASS (2026-11-18, M1 branch) |
| Release build, warnings as errors | `scripts/build.sh Release` | PASS (2026-11-18, M1 branch) |

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

## Manual: M1 (real Mac, with at least one external display)

Nothing below has been performed. The agent cannot see a screen, move windows between displays, or press a global shortcut, so every row is **NOT PERFORMED** until the product owner runs it and reports what happened. Run `scripts/run.sh`, then grant Screen Recording and use "Relaunch captAI" if prompted.

| # | Step | Expected | Status |
|---|---|---|---|
| 1 | Press ⌘⇧8 (or use Menu > Capture Screenshot) | Every display dims, crosshair cursor, hint pill | NOT PERFORMED |
| 2 | Drag a region in each screen quadrant, including reverse drags (right-to-left, bottom-to-top) | Clear hole follows the cursor; W × H pill is correct; release saves `~/Pictures/captAI/captAI <date> at <time>.png`; pixel size equals the pill size × display scale | NOT PERFORMED |
| 3 | Open the saved PNGs | Content matches the selected area exactly; no dim, border, pill or crosshair in the image | NOT PERFORMED |
| 4 | Repeat on the external display, then with mixed scaling (Retina + non-Retina) and with the external display left of or below the main one (negative origin) | No offset; PNG matches the selection | NOT PERFORMED |
| 5 | Press Esc during selection; also click without dragging (under 6 pt) | Overlay disappears, no file written, no stuck dim; a tiny release keeps the overlay open | NOT PERFORMED |
| 6 | Press ⌘⇧8 repeatedly and quickly; choose the menu item while an overlay is open | One overlay at a time; no stacking | NOT PERFORMED |
| 7 | Start a capture inside a fullscreen app Space; start one near the Dock and menu bar | Overlay appears over the fullscreen Space on every display; selection near the Dock and menu bar is accurate | NOT PERFORMED |
| 8 | Change resolution or unplug the external display while the overlay is open | Overlay closes cleanly with no image; a new capture works afterwards | NOT PERFORMED |
| 9 | Revoke Screen Recording in System Settings, then capture | Alert with Open System Settings / Relaunch captAI / Cancel; no overlay left behind; after granting and relaunching, capture works | NOT PERFORMED |
| 10 | Settings > Shortcuts: change the screenshot shortcut; try ⌘⇧3, ⌘Space, a shortcut with no modifier, and the Quick Copy shortcut | New shortcut works and the old one stops; the others show a red reason and are not saved | NOT PERFORMED |
| 11 | Capture a window showing DRM or protected video | Documented outcome: the content is black. The app warns "capture looks blank" instead of failing silently | NOT PERFORMED |
| 12 | Quit and relaunch | No leftover windows; Screen Recording prompt does not appear until the first capture | NOT PERFORMED |

## Cross-milestone privacy matrix (M0 slice)

| Scenario | M0 evidence |
|---|---|
| No permission requested at startup | `AppEnvironmentTests.startupOpensNoWindowsAndRequestsNoPermissions` (PASS); manual item 5 PASS |
| Reading permission state never prompts | `systemProviderStatusReadsDoNotThrowOrPrompt`, `creatingAStoreReadsStatusButNeverRequests` (PASS) |
| No network use | No networking code exists in M0. The Release binary links no ScreenCaptureKit, Vision or Network framework (`otool -L`, PASS). A network spy arrives with M2. |
| Credentials absent from settings file | `savedFileContainsNoCredentialFields` (PASS) |
| Sensitive values absent from logs | `DiagnosticsTests` redaction cases (PASS) |
