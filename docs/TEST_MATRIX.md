# Test matrix

Status values: **PASS**, **FAIL**, **NOT PERFORMED** (no one has run it), **BLOCKED**. Only results someone actually observed are PASS.

## Automated

| Suite | Command | Result |
|---|---|---|
| Unit (336 tests, 38 suites) | `scripts/test.sh unit` | PASS (2026-11-24, M6 library; Keychain OK outside agent sandbox, KI-025) |
| Integration (17 tests, 3 suites) | `scripts/test.sh integration` | PASS (2026-11-24, M5 gate) |
| UI (6 tests) | `scripts/test.sh ui` | PASS on M0–M3 (product owner's Mac) and on M4 (2026-11-23). |
| Debug build, warnings as errors | `scripts/build.sh Debug` | PASS (2026-11-24, M5 gate) |
| Release build, warnings as errors | `scripts/build.sh Release` | PASS (2026-11-24, M5 gate) |

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

Quick Copy is wired to the ⇧⌘H shortcut and the menu, with toast feedback. The product owner ran this list on a real Mac on 2026-11-19; item 4 was skipped.

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

## Manual: M3 (real Mac, no AI provider, no network)

A screenshot (⌘⇧8 or Menu > Capture Screenshot) now saves the PNG as before and then opens the capture frozen where it was taken, with the assistant beside it. The assistant's analysis is a labelled mock. None of these have been performed: the agent cannot observe a screen, and Liquid Glass rendering, window levels, Spaces and focus can only be judged on a real Mac. Run `scripts/run.sh`.

| # | Step | Expected | Status |
|---|---|---|---|
| 1 | Take a screenshot of a region in the middle of the screen | Dimming clears; the frozen capture sits exactly where you dragged, with a thin accent outline; the assistant opens to its right at 340 × 400 pt, fully on screen; the PNG is still saved (Reveal Last Capture works) | PASS |
| 2 | Take a screenshot hugging the right edge of the screen | The assistant flips to the left of the capture and stays fully visible | PASS |
| 3 | Take a very small screenshot (about 60 × 40 pt), then a wide thin strip across the screen | Small: the assistant sits at a screen edge, not attached to the capture. Strip: the assistant opens above or below it | Pass |
| 4 | Look at the assistant | Header, "Mock analysis. No AI model is connected yet." banner, text streaming in after "Analyzing…", "Copy Text" button, composer, footer "Mock analysis · No model connected" with a green "Local" badge; text is readable ; clicking the composer draws no square outline around the window | Pass |
| 5 | Drag the assistant by its header, by the empty space beside the title, and by the footer or the border around the cards; resize it from an edge and a corner | It moves and resizes freely; width stays between about 340 and 600 pt; it can be dragged onto another display | PASS |
| 6 | Click Pin to turn it off, then open another app's window over the capture; turn Pin back on | Unpinned: other windows can cover the capture and assistant. Pinned: both stay on top | PASS |
| 7 | Click "Hide capture", then "Show capture" | The frozen capture disappears and returns; the assistant stays | PASS |
| 8 | Change what is on screen under the capture (play a video, type in a document), then compare | The frozen capture does not change | PASS |
| 9 | Click Copy Text on a capture containing text | "Copying text…" then "Copied N lines" toast; the text is on the clipboard | PASS |
| 10 | Type a question in the composer; press Return, then Shift+Return | Return sends and a mock reply streams in; Shift+Return adds a new line; the Send button is disabled while the box is empty or a reply is streaming | PASS |
| 11 | Press Esc with the assistant focused; click the close button on another one | The capture and assistant both close; focus returns to the app you were using | PASS |
| 12 | Click the footer "Mock analysis · No model connected" | Settings opens on the Providers pane | PASS |
| 13 | With a workspace open, take another screenshot, then try Quick Copy over the old workspace | The new screenshot replaces the old workspace; neither capture shows the old capture or assistant in its image; Quick Copy does not read the assistant's text | PASS |
| 14 | Take a screenshot while a full-screen app is active | The capture and assistant appear over the full-screen app without switching Spaces | PASS |
| 15 | Unplug or reconfigure a display while a workspace is open | The workspace closes cleanly; a new screenshot works afterwards | PASS |
| 16 | Turn on System Settings > Accessibility > Display > Reduce transparency, then switch between Light and Dark | The assistant stays legible; the analysis and conversation sit on an opaque surface | PASS |
| 17 | First turn on System Settings > Keyboard > Keyboard navigation (macOS ships with it off, and then Tab only reaches text fields, so with one text box nothing moves). Then use Tab and Shift+Tab, then VoiceOver | Focus moves through Pin, Close, Hide capture, Copy Text, the composer, Send and the footer; each control has a spoken label | PASS |
| 18 | Capture a protected (DRM) window, if you have a source | The capture is black and the assistant shows "This capture looks blank…" and does not run the analysis | SKIPPED (a DRM source was not available in M1 either, KI-018) |
| 19 | Unpin, open other apps so one sits under the assistant, then click the app under the assistant, then click the capture, then click the assistant | Clicking the app raises it over both. Clicking the capture raises the capture and the assistant together, with the assistant on top and ready for typing. Clicking the assistant raises both | PASS |
| 20 | Settings > Capture & Recording > Screenshot border: switch off "Use system accent color", pick a color, set the width to 0, 1 and 8, then take a screenshot each time | The preview matches the capture's outline; width 0 shows no outline; the color and width persist after relaunching the app | PASS |

## Manual: M4 (real Mac, provider configured)

Providers, consent, Stop, and the set-up empty state. The agent cannot observe a screen or call your API keys. Run `scripts/run.sh`. Mark PASS only from what you see.

| # | Step | Expected | Status |
|---|---|---|---|
| 1 | Fresh settings (no profiles). Take a screenshot | Assistant shows "Set up a provider…" with Open Providers; no mock stream; footer says No provider | PASS |
| 2 | Settings > Providers: Add Ollama, set model (for example gemma4:e4b-mlx), Save, Test connection | Test succeeds; profile is Active | PASS |
| 3 | Screenshot with Ollama active; ask a follow-up | Analysis streams; reply streams; footer Local; PNG was used (answer refers to the image) | PASS |
| 4 | Quit Ollama (or wrong model), screenshot | Clear provider error; Retry works after fixing | PASS |
| 5 | Add OpenAI profile with a real key; Privacy = Ask every time; screenshot | Consent alert; Allow → analysis; Deny → nothing sent, declined message | PASS |
| 6 | Privacy: Don't ask before sending; screenshot with OpenAI | No consent alert; analysis runs | PASS |
| 7 | Privacy: Local only; screenshot with OpenAI active | Cloud blocked; local Ollama still works if switched | PASS |
| 8 | Add Anthropic profile with a real key; screenshot and follow-up | Consent (unless skip-ask); streams; Cloud badge | PASS |
| 9 | During streaming analysis or a reply, press Stop | Streaming stops; partial text remains; Send returns | PASS |
| 10 | Remove all profiles (or clear Active); screenshot | Set-up empty state again | PASS |
| 11 | Add ChatGPT account profile → Continue with ChatGPT; allow plan usage; screenshot | Browser sign-in; analysis streams via ChatGPT plan; Cloud badge; Manage usage opens ChatGPT settings | PASS |
| 12 | Sign out of ChatGPT; screenshot with that profile still active | Clear “sign in” refusal / set-up, nothing sent | PASS |

## Manual: M5 (real Mac)

Heuristic chips and non-destructive annotations. Mark PASS only from what you see. Run `scripts/run.sh`.

| # | Step | Expected | Status |
|---|---|---|---|
| 1 | Screenshot a terminal error; wait for chips | Explain Error, Find Fix, and Copy Text appear | PASS |
| 2 | Tap Copy Text / Copy Code with no network | Text copies; no provider call | PASS |
| 3 | Tap Explain Error with a provider active | One follow-up streams; consent still applies for cloud | PASS |
| 4 | Screenshot plain UI copy with little structure | Only Copy Text (no spurious error/chart chips) | PASS |
| 5 | On the frozen capture, draw a highlight and an arrow; undo then redo | Marks appear over the pixels; undo removes the last mark; redo restores it; Reveal Last Capture PNG is unchanged | PASS |
| 6 | Select a mark, delete it; draw an arrow and highlight | Delete removes only the selection; remaining tools draw correctly | PASS |
| 7 | With a provider active, select a mark and tap Ask about selection | A follow-up streams; the answer refers to the marked region; composer shows the annotation badge while marks exist | PASS |
| 8 | Type a normal follow-up while marks remain | Reply streams; badge still shown; full capture context still used | PASS |
| 9 | Resize/move the assistant; leave the capture where it is | Marks stay locked to the capture pixels | PASS |
| 10 | Quit and relaunch; open the same PNG from disk | File on disk still has no burned-in marks (vectors are session-only until M6) | PASS |

## Manual: M6 (real Mac)

History library persistence. Mark PASS only from what you see. Run `scripts/run.sh`.

| # | Step | Expected | Status |
|---|---|---|---|
| 1 | Screenshot, wait for analysis, annotate, ask a follow-up; close workspace; Open Library | Capture listed; detail shows chat and annotation count; Open in Workspace restores marks and chat without re-analyzing | PASS |
| 2 | Quit and relaunch; Open Library; open the same capture | Same chat and marks return | PASS |
| 3 | Settings > Storage → Choose screenshot folder; capture again | New PNG lands in the chosen folder; older library entries still open | PASS |
| 4 | Delete a capture in Library | Confirm; row gone; PNG removed; chat/annotations gone | PASS |
| 5 | Quick Copy text | Clipboard updates; Library unchanged | PASS |
| 6 | Cmd/Shift-select several Library rows → Delete… | Confirm shows count; all selected rows and PNGs gone; remaining rows stay | PASS |

## Manual: M7 (real Mac)

Region and full-screen recording. Mark PASS only from what you see. Run `scripts/run.sh`.

| # | Step | Expected | Status |
|---|---|---|---|
| 1 | Record a region; stop; open the saved file | Playable; duration and dimensions match the region | PASS |
| 2 | Record an entire display; stop; open the saved file | Playable; full-display framing | PASS |
| 3 | Toggle mic on/off and system audio on/off (with permission); record briefly | Tracks match the toggles | PASS |
| 4 | Stop twice quickly; leave a longer recording running; unplug a display if available; deny Screen Recording | No crash; no false “saved” without a playable file | PASS |
| 5 | Start/stop recording with all AI providers disabled | No AI/cloud request; file still saved locally | PASS |

## Manual: M8 (real Mac)

Post-recording analysis and timestamped video workspace. Mark PASS only from what you see. Run `scripts/run.sh`.

| # | Step | Expected | Status |
|---|---|---|---|
| 1 | Record a 60–120 s workflow with a recognizable event; open and analyze | Summary / key moments with timestamps | PASS |
| 2 | Click a key moment; ask a follow-up about that time | Player seeks; follow-up answers about that moment | PASS |
| 3 | Try a direct-video provider (if available) and a frame-based fallback | Route labeled clearly; both usable | SKIPPED  |
| 4 | Decline cloud transmission; analyze with a local vision provider if available | Recording stays playable; no unwanted upload | PASS |
| 5 | Analyze a longer recording | Bounded memory; clear progress; recoverable errors | PASS |

## Manual: M9 (real Mac)

Local FTS5 + optional semantic library search. Mark PASS only from what you see. Run `scripts/run.sh`.

| # | Step | Expected | Status |
|---|---|---|---|
| 1 | Capture several screenshots with distinct visible text; close workspaces; Open Library; search an exact OCR phrase | Matching capture listed with a useful excerpt; Open in Workspace restores it | PASS |
| 2 | Search a conceptual paraphrase of one capture (e.g. “missing dependency”) | Relevant capture ranks near the top when OS sentence embeddings are available; otherwise keyword/FTS still finds exact terms | PASS |
| 3 | Filter by Screenshots vs Recordings; filter by app name when known | Filters narrow the list; clearing them restores browse | PASS |
| 4 | Turn Wi‑Fi off; search again; delete a hit | Search still works offline; deleted capture disappears from results | PASS |
| 5 | Quit and relaunch; repeat a prior query | Same results; empty query shows recent captures | PASS |

## Manual: M10 (real Mac)

Release readiness. Mark PASS only from what you see. Prefer a Release / notarized build when available.

| # | Step | Expected | Status |
|---|---|---|---|
| 1 | Fresh install; grant/deny Screen Recording; use Quick Copy before any provider | Permission flow is clear; Quick Copy works with no AI setup | |
| 2 | Screenshot → OCR chips → chat → annotations → Library search; try local and cloud providers | End-to-end still works; cloud consent cancel uploads nothing | |
| 3 | Region and full-display record; analyze; seek moments; search history | Playback and post-recording path remain correct | |
| 4 | Multi-display / scale if available; light/dark; Reduce Transparency; VoiceOver + keyboard | UI remains usable; Reduce Motion avoids toast window animation | |
| 5 | Settings > Storage: retention, purge missing, Clear All History | Maintenance actions match confirmations; Library updates | |
| 6 | Interrupted recording / offline / invalid provider / inaccessible folder | Clear errors; no false “saved”; local data preserved | |
| 7 | Distributed signed build on a clean Mac (when available) | Launches; Gatekeeper OK; permissions and updates documented | |

## Cross-milestone privacy matrix (M0 slice)

| Scenario | M0 evidence |
|---|---|
| No permission requested at startup | `AppEnvironmentTests.startupOpensNoWindowsAndRequestsNoPermissions` (PASS); manual item 5 PASS |
| Reading permission state never prompts | `systemProviderStatusReadsDoNotThrowOrPrompt`, `creatingAStoreReadsStatusButNeverRequests` (PASS) |
| No network use | No networking code exists in M0. The Release binary links no ScreenCaptureKit, Vision or Network framework (`otool -L`, PASS). A network spy arrives with M2. |
| Credentials absent from settings file | `savedFileContainsNoCredentialFields` (PASS) |
| Sensitive values absent from logs | `DiagnosticsTests` redaction cases (PASS) |
