# Test matrix

Status values: **PASS**, **FAIL**, **NOT PERFORMED** (no one has run it), **BLOCKED**. Only results someone actually observed are PASS.

## Automated

| Suite | Command | Result |
|---|---|---|
| Unit (156 tests, 20 suites) | `scripts/test.sh unit` | PASS (2026-11-18, M1 branch, after cross-display support; run through `xcrun xctest` because the scheme `test` action cannot run in the agent sandbox) |
| Integration (17 tests, 3 suites) | `scripts/test.sh integration` | PASS (2026-11-18, M1 branch, after cross-display support; same note) |
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

The product owner ran this list on a real Mac on 2026-11-18 with an external display. Items 1–3 and 5–12 passed. Item 4 is partial: see its row and the note below. Items 13–15 were added after the D-017 change and have not been run. The agent cannot observe the screen, so these results are the owner's reports. Run `scripts/run.sh`, then grant Screen Recording and use "Relaunch captAI" if prompted.

| # | Step | Expected | Status |
|---|---|---|---|
| 1 | Press ⌘⇧8 (or use Menu > Capture Screenshot) | Every display dims, crosshair cursor, hint pill | PASS (product owner, 2026-11-18) |
| 2 | Drag a region in each screen quadrant, including reverse drags (right-to-left, bottom-to-top) | Clear hole follows the cursor; W × H pill is correct; release saves `~/Pictures/captAI/captAI <date> at <time>.png`; pixel size equals the pill size × display scale | PASS (product owner, 2026-11-18) |
| 3 | Open the saved PNGs | Content matches the selected area exactly; no dim, border, pill or crosshair in the image | PASS (product owner, 2026-11-18) |
| 4 | Repeat on the external display, then with mixed scaling (Retina + non-Retina) and with the external display left of or below the main one (negative origin) | No offset; PNG matches the selection | PARTIAL (product owner, 2026-11-18): the external display works, but a drag that starts on one display cannot cross onto the other. This is the designed behavior (D-013); the overlay does not explain it yet. Mixed scaling and negative origin: see the note below. |
| 5 | Press Esc during selection; also click without dragging (under 6 pt) | Overlay disappears, no file written, no stuck dim; a tiny release keeps the overlay open | PASS (product owner, 2026-11-18) |
| 6 | Press ⌘⇧8 repeatedly and quickly; choose the menu item while an overlay is open | One overlay at a time; no stacking | PASS (product owner, 2026-11-18) |
| 7 | Start a capture inside a fullscreen app Space; start one near the Dock and menu bar | Overlay appears over the fullscreen Space on every display; selection near the Dock and menu bar is accurate | PASS (product owner, 2026-11-18) |
| 8 | Change resolution or unplug the external display while the overlay is open | Overlay closes cleanly with no image; a new capture works afterwards | PASS (product owner, 2026-11-18) |
| 9 | Revoke Screen Recording in System Settings, then capture | Alert with Open System Settings / Relaunch captAI / Cancel; no overlay left behind; after granting and relaunching, capture works | PASS (product owner, 2026-11-18) |
| 10 | Settings > Shortcuts: change the screenshot shortcut; try ⌘⇧3, ⌘Space, a shortcut with no modifier, and the Quick Copy shortcut | New shortcut works and the old one stops; the others show a red reason and are not saved | PASS (product owner, 2026-11-18) |
| 11 | Capture a window showing DRM or protected video | Documented outcome: the content is black. The app warns "capture looks blank" instead of failing silently | PASS (product owner's report, 2026-11-18; confirm this was tested with protected content) |
| 12 | Quit and relaunch | No leftover windows; Screen Recording prompt does not appear until the first capture | PASS (product owner, 2026-11-18) |
| 13 | Drag a selection that starts on the main display and crosses onto the external one, and the reverse | The overlay shows the selection on both displays, the W × H label appears once, and the PNG contains both parts in the right places with no seam or offset | NOT PERFORMED |
| 14 | Span a selection across a Retina and a non-Retina display | The PNG is at the Retina scale; the non-Retina part is upscaled and otherwise correct | NOT PERFORMED |
| 15 | Drag past the edge of the displays into an empty area of an uneven arrangement | The selection stops at the edge of the displays; any uncovered part is black, not transparent | NOT PERFORMED |

**Note on item 4.** The product owner found that a drag could not cross onto the external display. That was the design at the time (D-013). It is now replaced by D-017: a selection can span displays, so item 4 has been changed to test that and must be run again. The status above describes the earlier build.

## Cross-milestone privacy matrix (M0 slice)

| Scenario | M0 evidence |
|---|---|
| No permission requested at startup | `AppEnvironmentTests.startupOpensNoWindowsAndRequestsNoPermissions` (PASS); manual item 5 PASS |
| Reading permission state never prompts | `systemProviderStatusReadsDoNotThrowOrPrompt`, `creatingAStoreReadsStatusButNeverRequests` (PASS) |
| No network use | No networking code exists in M0. The Release binary links no ScreenCaptureKit, Vision or Network framework (`otool -L`, PASS). A network spy arrives with M2. |
| Credentials absent from settings file | `savedFileContainsNoCredentialFields` (PASS) |
| Sensitive values absent from logs | `DiagnosticsTests` redaction cases (PASS) |
