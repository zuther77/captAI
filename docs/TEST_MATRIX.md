# Test matrix

Status values: **PASS**, **FAIL**, **NOT PERFORMED** (no one has run it), **BLOCKED**. Only results someone actually observed are PASS.

## Automated

| Suite | Command | Result |
|---|---|---|
| Unit (156 tests, 20 suites) | `scripts/test.sh unit` | PASS (2026-11-18, M1 branch, after cross-display support; run through `xcrun xctest` because the scheme `test` action cannot run in the agent sandbox) |
| Integration (17 tests, 3 suites) | `scripts/test.sh integration` | PASS (2026-11-18, M1 branch, after cross-display support; same note) |
| UI (6 tests) | `scripts/test.sh ui` | PASS on M0 (2026-11-18) and on M1 (2026-11-18, product owner's Mac, after the Shortcuts pane rewrite) |
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

The product owner ran this list on a real Mac on 2026-11-18 with an external display. All items passed except item 11, which could not be tested because no protected-content source was available. Items 4 and 13–15 were run after the D-017 change. The agent cannot observe the screen, so these results are the owner's reports. Run `scripts/run.sh`, then grant Screen Recording and use "Relaunch captAI" if prompted.

| # | Step | Expected | Status |
|---|---|---|---|
| 1 | Press ⌘⇧8 (or use Menu > Capture Screenshot) | Every display dims, crosshair cursor, hint pill | PASS (product owner, 2026-11-18) |
| 2 | Drag a region in each screen quadrant, including reverse drags (right-to-left, bottom-to-top) | Clear hole follows the cursor; W × H pill is correct; release saves `~/Pictures/captAI/captAI <date> at <time>.png`; pixel size equals the pill size × display scale | PASS (product owner, 2026-11-18) |
| 3 | Open the saved PNGs | Content matches the selected area exactly; no dim, border, pill or crosshair in the image | PASS (product owner, 2026-11-18) |
| 4 | Repeat on the external display, then with mixed scaling (Retina + non-Retina) and with the external display left of or below the main one (negative origin) | No offset; PNG matches the selection | PASS (product owner, 2026-11-18, rerun after D-017) |
| 5 | Press Esc during selection; also click without dragging (under 6 pt) | Overlay disappears, no file written, no stuck dim; a tiny release keeps the overlay open | PASS (product owner, 2026-11-18) |
| 6 | Press ⌘⇧8 repeatedly and quickly; choose the menu item while an overlay is open | One overlay at a time; no stacking | PASS (product owner, 2026-11-18) |
| 7 | Start a capture inside a fullscreen app Space; start one near the Dock and menu bar | Overlay appears over the fullscreen Space on every display; selection near the Dock and menu bar is accurate | PASS (product owner, 2026-11-18) |
| 8 | Change resolution or unplug the external display while the overlay is open | Overlay closes cleanly with no image; a new capture works afterwards | PASS (product owner, 2026-11-18) |
| 9 | Revoke Screen Recording in System Settings, then capture | Alert with Open System Settings / Relaunch captAI / Cancel; no overlay left behind; after granting and relaunching, capture works | PASS (product owner, 2026-11-18) |
| 10 | Settings > Shortcuts: change the screenshot shortcut; try ⌘⇧3, ⌘Space, a shortcut with no modifier, and the Quick Copy shortcut | New shortcut works and the old one stops; the others show a red reason and are not saved | PASS (product owner, 2026-11-18) |
| 11 | Capture a window showing DRM or protected video | Documented outcome: the content is black. The app warns "capture looks blank" instead of failing silently | UNABLE TO TEST: no DRM or protected-video source available (KI-018) |
| 12 | Quit and relaunch | No leftover windows; Screen Recording prompt does not appear until the first capture | PASS (product owner, 2026-11-18) |
| 13 | Drag a selection that starts on the main display and crosses onto the external one, and the reverse | The overlay shows the selection on both displays, the W × H label appears once, and the PNG contains both parts in the right places with no seam or offset | PASS |
| 14 | Span a selection across a Retina and a non-Retina display | The PNG is at the Retina scale; the non-Retina part is upscaled and otherwise correct | PASS |
| 15 | Drag past the edge of the displays into an empty area of an uneven arrangement | The selection stops at the edge of the displays; any uncovered part is black, not transparent |PASS |

**Note on item 4.** The first run (before D-017) passed for the external display only, because a drag could not cross displays (D-013). After D-017 the product owner reran it and it passed. Item 11 remains untested; see KI-018.

## Manual: M2 (real Mac, no AI provider, no network)

Quick Copy is wired to the ⇧⌘H shortcut and the menu, with toast feedback. Not yet performed on a real Mac.

| # | Step | Expected | Status |
|---|---|---|---|
| 1 | Fresh settings, no API key, Ollama, or internet. Select terminal text on screen and run Quick Copy; paste into TextEdit and compare | Pasted text matches the screen in reading order | PASS |
| 2 | Copy code with indentation, a paragraph, multilingual text, and an image with no text | Indentation and line breaks kept; the no-text image shows the "no text" feedback and leaves the clipboard unchanged | PASS |
| 3 | Check that no AI panel, provider call, media file, or history record was created | None | PASS |
| 4 | Benchmark OCR on reference hardware (Fast and Accurate) | p50 and p95 recorded against the ~2 s aspiration | SKIPPED |
| 5 | Press ⇧⌘H (or Menu > Quick Copy Text), select text, then wait | Toast appears top-centre on the pointer's display, says "Copied N lines", disappears after about 2 s; VoiceOver announces it | PASS |
| 6 | Quick Copy a blank or text-free area | Toast says "No text found in the selection"; clipboard unchanged from before | PASS |
| 7 | Press Esc during the Quick Copy selection | Overlay closes, no toast, clipboard unchanged | PASS |
| 8 | Deny Screen Recording, then Quick Copy | Permission alert (not a toast) with Open System Settings / Relaunch / Cancel | PASS |
| 9 | Menu shows "Quick Copy Text ⇧⌘H"; it is disabled while a capture is running | Item enabled when idle, disabled during a capture | PASS |
| 10 | Quick Copy a large selection, or text in a slow language (for example Japanese or Chinese), ideally while the Mac is busy | A "Copying text…" toast with a spinner appears as soon as the selection is released and stays until the result toast replaces it; it never lingers after the result | PASS |

## Cross-milestone privacy matrix (M0 slice)

| Scenario | M0 evidence |
|---|---|
| No permission requested at startup | `AppEnvironmentTests.startupOpensNoWindowsAndRequestsNoPermissions` (PASS); manual item 5 PASS |
| Reading permission state never prompts | `systemProviderStatusReadsDoNotThrowOrPrompt`, `creatingAStoreReadsStatusButNeverRequests` (PASS) |
| No network use | No networking code exists in M0. The Release binary links no ScreenCaptureKit, Vision or Network framework (`otool -L`, PASS). A network spy arrives with M2. |
| Credentials absent from settings file | `savedFileContainsNoCredentialFields` (PASS) |
| Sensitive values absent from logs | `DiagnosticsTests` redaction cases (PASS) |
