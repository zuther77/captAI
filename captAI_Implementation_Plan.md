# captAI — Coding Agent Implementation Plan

**Version:** 1.0  
**Date:** 17 November 2026  
**Target:** Native macOS 26+ application; SwiftUI, AppKit, ScreenCaptureKit, Vision, AVFoundation, SQLite  
**Baseline:** `captAI_PRD.md` (requirements) and `captAI_Design_Spec.md` (interface/interaction contract)  
**Execution style:** Sequential, independently demonstrable milestones; do not start a new milestone before the preceding gate is accepted.

## 1. What we are shipping

**v1 includes:** native Liquid Glass menu-bar app; screenshot-region selection and a frozen selected image with adjacent floating assistant; local OCR quick copy with no account; screenshot analysis and chat; BYOK, Ollama vision and compatible custom endpoints; model/provider settings and explicit cloud disclosure; heuristic screenshot actions; editable non-destructive annotations; region/full-screen recording with optional audio; post-recording video summaries, timestamped moments and follow-up questions; local media/conversation history, FTS5 text search and local semantic screenshot search; configurable shortcuts and save destinations.

**Not a v1 release blocker:** ChatGPT subscription/account integration unless an authorized and eligible integration is actually available. Do not use undocumented login, scraped cookies, or credential sharing as a workaround.

**Deferred to v2:** live analysis while recording, advanced video timeline search, sophisticated adaptive frame sampling, proactive automatic issue detection, cloud sync, autonomous computer control.

**Essential product behavior:** Screenshot `shortcut → dim → select → capture → undim → frozen region + adjacent assistant`; Quick Copy `shortcut → dim → select → local OCR → clipboard + toast`; Video `shortcut → select region/display → record → save locally → analyze on demand/according to privacy policy → video assistant`.

## 2. Authority, assumptions, and hard rules

1. Use the PRD for *what* is required and the Design Spec for *how it behaves and looks*. This plan defines the build order and verification gates. If these disagree, flag the conflict with a proposed resolution before implementing it.
2. Use actual native macOS APIs and verify precise signatures against the **installed SDK**, especially ScreenCaptureKit, display/window exclusion, audio recording and SwiftUI Liquid Glass. Do not invent APIs.
3. The app runs locally without a backend. Keep provider adapters independent of SwiftUI; use Keychain for API secrets; use OS-approved permissions and disclose any upload of screen content.
4. Never couple Quick Copy to provider setup, a network request, history indexing, or a chat UI. Default Quick Copy history **off**.
5. Never silently fall back from a chosen local provider to a cloud provider, or from unsupported video input to an unapproved upload. Expose capability and consent before the request.
6. Use separate coordinate spaces for display points, backing pixels, and normalized image geometry. Always record conversion metadata. Annotation geometry must not alter original capture bytes.
7. A provider's image/video/audio support is discovered or explicitly configured, not guessed from its name. When direct video is unavailable, use a bounded, timestamped frame-based fallback if the model supports images; otherwise produce an actionable error.
8. If a milestone depends on access to physical macOS hardware, simulator/CI results are **not** sufficient for completion. Record the manual validation result on a real supported Mac.
9. Preserve the PRD's proposed shortcuts (`⌘⇧2`, `⌘⇧3`, `⌘⇧C`) as editable **defaults only after conflict checking**. Do not override existing system shortcuts without a clear prompt.
10. Prefer a working narrow vertical slice to placeholder screens. A disabled, clearly labeled feature is better than a button that does nothing.

## 3. Delivery protocol for the coding agent

**At the beginning of each milestone:** read its acceptance criteria, inspect the current repo, list SDK/API risks, identify files to change, and propose a short implementation checklist. Work only within the milestone plus necessary shared infrastructure.

**At the end of each milestone, deliver:**
- Functional change summary and architectural notes; key files and new interfaces.
- Commands run and results for build, unit tests, integration tests and static checks; list any skipped tests explicitly.
- A manual test script with observed results on a real Mac (when relevant), including relevant screenshots or a short screen capture of the implementation.
- Privacy/network behavior and permissions touched; known limitations and open bugs.
- A gate decision: `PASS`, `FAIL`, or `BLOCKED` with evidence. Do not declare `PASS` on unrun tests.

**Repository conventions:** `main` stays releasable; create `milestone/M0-foundation`, etc., or equivalent small PRs. Commit changes with descriptive messages. Add tests with the feature, not as a retrospective cleanup. Maintain `docs/DECISIONS.md` for approved deviations, `docs/TEST_MATRIX.md` for manual results, and `docs/KNOWN_ISSUES.md` for unresolved issues.

## 4. Recommended architecture and project tree

```text
captAI/
  App/                     # menu bar app lifecycle, DI, startup, permissions
  Features/
    Capture/               # region selection, per-display overlay, still capture
    QuickCopy/             # Vision OCR, text reconstruction, pasteboard, toast
    Assistant/             # frozen capture canvas, NSPanel, messages, actions
    Annotations/           # vector types, edit/undo/redo, coordinate adapters
    Recording/             # screen recording HUD and file lifecycle
    VideoAnalysis/         # frame extraction, direct-video route, event timeline
    Library/               # saved assets, sessions, search and detail views
    Settings/              # provider, OCR, shortcuts, folders, capture, privacy
  Core/
    Models/                # CaptureAsset, OCRBlock, Annotation, Message, Event
    Geometry/              # points/pixels, display transforms, normalized bounds
    Providers/             # provider protocol, capabilities, adapters, consent
    OCR/                   # Apple Vision adapter and testable layout logic
    Storage/               # SQLite migrations, files, FTS5, embeddings
    Security/              # Keychain, privacy/consent ledger, safe logging
    Utilities/             # clocks, IDs, error mapping, cancellation
  Tests/
    Unit/                  # pure logic + mock provider/storage services
    Integration/           # SQLite, Keychain, OCR fixture, fake provider transport
    UI/                    # app UI smoke tests (where automation is reliable)
    Fixtures/              # synthetic screenshots, video clips, OCR outputs
  docs/
    DECISIONS.md
    TEST_MATRIX.md
    KNOWN_ISSUES.md
    MILESTONE_REPORTS/
```

**Protocol boundaries (define early):** `ScreenSelectionService`, `StillCaptureService`, `OCRService`, `ClipboardService`, `ShortcutService`, `CaptureStore`, `ConversationStore`, `AIProvider`, `ProviderCapabilities`, `ConsentService`, `ScreenRecorder`, `VideoFrameSampler`, `EmbeddingService`. Core model types must not depend on a provider SDK. Use dependency injection to supply mocks and avoid permission prompts in pure unit tests.

## 5. Milestone map

| ID | Deliverable | Key dependency | Exit demonstration |
|---|---|---|---|
| M0 | Native shell, tests, permissions, menu bar | None | App runs; menu bar and test suite work |
| M1 | Screenshot selection overlay and still capture | M0 | Select/cancel on real screens; correct pixels |
| M2 | Zero-configuration offline OCR Quick Copy | M1 | Copy screen text offline without provider |
| M3 | Frozen screenshot and floating Liquid Glass assistant | M2 | Adjacent draggable chat shell; no model needed |
| M4 | Providers, streaming AI chat, privacy and Settings | M3 | Real image analysis using Ollama/BYOK as configured |
| M5 | Context actions and non-destructive annotations | M4 | Classify/copy/annotate; region-aware follow-up |
| M6 | Local persistence and history library | M5 | Restart app; reopen media, chats, annotations |
| M7 | Reliable local screen recording | M6 | Region/full-screen video saves and plays |
| M8 | Post-recording AI analysis workspace | M7 | Summary, timestamps and grounded follow-up |
| M9 | FTS5 + local semantic screenshot search | M8 | Retrieve captures by text and concept offline |
| M10 | Release hardening and distribution | M9 | Full regression, accessibility, packaged signed build |

Suggested engineering order follows dependencies, not calendar promises. If a milestone is too large for one agent run, break it into vertical sub-PRs **without weakening its final acceptance gate**.

---

## M0 — Foundation, project shell, and baseline verification

**Objective:** Establish a runnable native utility and a testable, modular codebase before using screen APIs.

**Implement**
- macOS 26+ Xcode project, SwiftUI app/menu bar experience, AppKit window coordinator/hosting surface and Settings skeleton.
- Structured error types, debug diagnostics without screenshot contents, dependency injection and build configurations.
- macOS permission-status UI for screen capture, microphone (if requested later), and relevant system access; use appropriate OS approval flow.
- Define model IDs, capture modes and display-geometry abstractions; install unit/integration/UI test targets.
- Add scripts or documented commands to build, test and run; no required server.

**Automated tests**
- App/configuration model serialization and settings defaults.
- Window-coordinator state logic using fake window adapters; permission-status mapping with mocks.
- Clean build and test run from a fresh checkout on supported SDK.

**Manual real-Mac test**
1. Launch app: menu-bar icon is present and menus open without an unwanted main window.
2. Settings opens, closes, reopens; appearance works in light/dark modes.
3. Permission UI correctly distinguishes not-determined, granted, and denied states.

**Gate M0:** A fresh checkout builds and launches, tests pass, settings is navigable, and no unrelated permissions are requested at startup.

## M1 — Native screenshot region selection and still capture

**Objective:** Recreate macOS-like dimmed selection accurately across displays.

**Implement**
- Global screenshot shortcut with registration, conflict detection, Esc cancellation and single-active-capture serialization.
- Per-display dimmed transparent overlay; crosshair, drag selection in four directions, clear area, selection border and minimum-size guidance.
- ScreenCaptureKit still image pipeline; image exclusion where supported; capture coordinates in screen points/backing pixels; clear overlay after selection.
- Permission-denied and protected-content states with recoverable errors. No AI UI yet.

**Automated tests**
- Geometry conversion for 1×/2× display scaling, negative display origins, reverse dragging and clipping.
- Selection state machine: idle/selecting/cancel/commit; debounced repeated hotkeys.
- Capture-service mocked success/error; metadata includes source display and image pixel dimensions.

**Manual real-Mac test**
1. Select regions in every screen quadrant; pixel output matches displayed area and includes no app overlay.
2. Repeat on external display, mixed scaling and display arrangement with negative coordinates; verify no offset.
3. Esc cancels leaving no image or stuck dim; repeated shortcuts do not stack overlays.
4. Test a fullscreen app/Space, Dock/menu bar vicinity, permission denial and resolution change.

**Gate M1:** Correct still images on a real Mac and at least one external-display scenario; cancel/permission errors leave no orphan windows.

## M2 — Instant on-device OCR Quick Copy (zero-configuration)

**Objective:** Deliver a valuable offline utility before AI integration.

**Implement**
- Independent editable Quick Copy shortcut; reuse capture selector without opening the assistant.
- Apple Vision text recognition with Fast/Accurate setting; normalized boxes, reading order and preserved line breaks as feasible.
- Copy recognized text through `NSPasteboard`; transient copied/empty/error toast; manual retry.
- No history entry by default, no request to any provider, no dependency on account setup.

**Automated tests**
- Deterministic OCR layout: multi-line code, columns, Unicode, blank areas, duplicate lines; coordinate transformations.
- OCR integration on checked-in synthetic image fixtures, with documented tolerance for OS OCR variations.
- Mock clipboard assertion; networking spy fails test if a local-only path invokes a remote transport.
- Empty image and permission failure do not overwrite previous clipboard content.

**Manual real-Mac test**
1. On fresh install with **no API key, Ollama, or internet**, select terminal text and paste into TextEdit; compare output.
2. Copy code with indentation, a paragraph, multilingual text and an image with no text; inspect feedback.
3. Verify no AI panel, provider call, media file or history record created by default.
4. Run OCR speed benchmark on reference hardware; record p50/p95 and compare with PRD's aspirational ~2 s target.

**Gate M2:** Offline Quick Copy works with no provider configured; clipboard correct in representative cases; zero observed network/provider calls.

## M3 — Frozen screenshot workspace and adjacent Liquid Glass UI

**Objective:** Match the supplied interaction sketch before connecting real model inference.

**Implement**
- Frozen screenshot canvas at the original selected screen location; restored normal desktop brightness.
- SwiftUI assistant hosted in movable/resizable AppKit floating panel; right-side placement preference and collision-aware alternatives.
- Native Liquid Glass control surfaces with readable opaque content; analysis loading/empty/error placeholders, action row, composer, provider footer.
- Pin, dismiss, keyboard focus, panel drag/resize and safe handling if original app contents change.
- Screenshot can zoom/fit and optionally hide/detach if implemented in Design Spec; do not accidentally re-capture live screen while annotating.

**Automated tests**
- Deterministic panel-placement algorithms for left/right/top/bottom edges and tiny capture regions.
- Workspace state changes: captured/loading/ready/error/close and panel position persistence per session.
- Fake analysis stream populates UI without network; screenshots kept separate from mutable overlay geometry.

**Manual real-Mac test**
1. Select screenshot near right edge: assistant flips to left and remains fully visible.
2. Open at different display scales and screen sizes; drag, resize, pin and dismiss assistant.
3. Change underlying application after selection: frozen screenshot remains unchanged.
4. Keyboard navigation, reduced transparency and dark/light modes remain legible.

**Gate M3:** Sketch's two-overlay flow works and the window never requires switching to a full main app. AI may be mocked at this stage, visibly labeled as such.

## M4 — Provider integration, AI chat, settings and privacy gate

**Objective:** Make screenshot conversations real, with safe provider switching.

**Implement**
- Provider protocol covering messages, image inputs, streaming, cancellation, capability errors, token/upload metadata where available.
- Real adapters: configured Ollama vision model; at least one hosted BYOK vision provider; OpenAI-compatible custom endpoint if supported/tested. Additional hosted adapters may ship as independent sub-PRs.
- Settings > Providers: named profiles, endpoint and model IDs, Keychain-backed secret entry, test connection/capability check, provider/model selector and Local/Cloud status.
- Clicking provider footer opens native Settings directly on Providers; changes affect **next** request, not an in-flight request.
- Explicit remote content disclosure/consent policy; never transmit if user chooses local-only or cancels. Support usable OCR without a provider.
- Streaming analysis, follow-up chat, request cancellation, rate limit/retry errors and no-provider state. Add editable shortcut, OCR and screenshot save folder settings per PRD.
- Account-based ChatGPT integration is feature-gated, **not** required or simulated.

**Automated tests**
- Contract tests using fake transports: correct image attachment, multi-turn history, streaming chunk assembly, cancellation and 401/429/5xx errors.
- Keychain wrapper tests with safe test entries; API secrets excluded from logs, DB and export data.
- Consent test matrix: local request bypasses cloud consent; remote request obeys policy; switching providers cannot auto-upload.
- Capability check rejects text-only Ollama models when an image is required; malformed custom endpoints fail safely.

**Manual real-Mac test**
1. Configure Ollama vision model; analyze screenshot while internet is disconnected; send follow-up.
2. Configure a valid BYOK provider; see disclosure, approve once per chosen policy, receive streaming answer.
3. Deny upload: local OCR still works and screenshot remains available; no network request sent.
4. Click provider chip → Settings > Providers; switch model → next request uses new model; previous message attribution retained.
5. Enter invalid key/URL, stop generation midway, and test text-only model; verify useful errors.

**Gate M4:** End-to-end screenshot AI works with a tested local vision model and at least one tested cloud provider, with explicit verified privacy boundaries.

## M5 — Context-aware actions, OCR selection, and non-destructive annotation

**Objective:** Make a screenshot actionable without wasting model calls on simple tasks.

**Implement**
- Deterministic OCR/local classifiers for terminal errors, code, paragraphs, charts, products where signals are adequate; confidence-aware fallbacks to general actions.
- Suggested chips such as Explain Error, Find Fix, Copy Code/Text, Analyze Chart, Find Alternatives; only model-dependent chips initiate AI inference.
- Copy All and selected OCR text blocks inside screenshot workspace; local clipboard copy bypasses AI.
- Vector circle/rectangle/arrow/highlight drawing, selection/edit/delete, undo/redo, zoom-coordinate mapping, saved normalized geometry.
- Region-aware chat sends original image plus annotation coordinates and optionally crop, with context preserved; provider adapter documents the effective payload.

**Automated tests**
- Heuristic classifier fixtures; avoid asserting false certainty when category is ambiguous.
- Action dispatch: copy chips never call model; analysis chips invoke exactly one request per user action.
- Annotation add/move/delete, undo/redo, serialize/deserialize and normalized point transforms across zoom/resize.
- Original file hash identical before and after adding annotations; test large/small crops and out-of-range points.

**Manual real-Mac test**
1. Capture a terminal error: relevant local/error actions appear; Copy Text works offline.
2. Circle an element and ask about it; visually inspect crop/coordinate context passed to test adapter.
3. Resize panel/zoom screenshot, edit marks, undo/redo; marks stay attached to the intended pixels.
4. Quit and relaunch after data persistence exists (M6) to validate saved geometry.

**Gate M5:** Quick actions are correctly routed; annotations are non-destructive and region-specific questions demonstrably reference marked content.

## M6 — Durable local assets, conversations and history library

**Objective:** Make the application robust to restarts and ready to store recordings.

**Implement**
- Local media folder service and native folder picker; screenshot storage defaults and video location placeholders; safe bookmark/access handling where applicable.
- SQLite migrations for `CaptureAsset`, `OCRBlock`, `Annotation`, `Conversation`, `Message` and later `RecordingEvent`; provider/model per reply and upload/transmission metadata.
- Atomic file/DB commit, missing-file recovery, retention and cascading delete; avoid orphaned thumbnails/index records.
- Library UI: screenshot cards, preview/detail and associated chat; delete and retention controls; no automatic storage from Quick Copy.
- Persist provider profiles/settings securely (never raw API keys in DB) and restore active sessions.

**Automated tests**
- In-memory and temporary-folder DB migration/restart tests, version upgrades and rollback on write failure.
- Media path changes affect new captures; existing media remains readable at old location unless explicit migration.
- Delete removes files and associated OCR/chat/annotation index records; no dangling references.
- No accidental Quick Copy history; transcript/message attribution survives restart.

**Manual real-Mac test**
1. Analyze screenshot, annotate it, quit and relaunch; library reopens full media and conversation.
2. Change screenshot folder and save a new capture; old capture still opens.
3. Delete an asset, verify associated data gone; simulate inaccessible folder/disk full with clear recovery.

**Gate M6:** Reopening sessions after a cold restart is reliable; deletes and folder changes do not corrupt the library.

## M7 — Reliable local region and full-screen recording

**Objective:** Ship recording as an independent local feature before attempting AI interpretation.

**Implement**
- Separate global recording shortcut and region/display selector; native recording HUD with elapsed time, visible stop, pause/resume only if verified supported, system/mic audio toggles.
- ScreenCaptureKit recording pipeline and file finalization; region crop or selected-display output, recording quality/duration guards and bounded memory.
- Recording HUD excluded from video when supported; display visible recording indicator and permissions state. Save local media and metadata to M6 store.
- Recover from cancellation, permissions change, display unplug, low disk and finalize errors; never report success before playable output exists.

**Automated tests**
- Recording state machine `idle → selecting → recording ↔ paused → stopping → saved/error`; rapid Stop and duplicate hotkey handling.
- Test filename collision, destination errors, duration/size limits, metadata and atomic file handoff using a fake recorder.
- Integration verification that output is readable with AVFoundation and has nonzero expected duration using controlled fixture/source.

**Manual real-Mac test**
1. Record a region and entire display; stop and play both local files, checking duration, dimensions and region boundaries.
2. Try mic on/off and system audio on/off after proper permission; verify recorded tracks.
3. Attempt stop twice, run long enough for resource observation, unplug external display if available, and deny permission.
4. Confirm no AI/cloud request occurs merely because recording started or stopped.

**Gate M7:** Recorded region/full-screen files are playable, scoped correctly and saved locally even with all AI providers disabled.

## M8 — Post-recording AI analysis and timestamped video workspace

**Objective:** Understand saved video after capture, with time-grounded conversation.

**Implement**
- Native playable video preview (AVKit), seek/scrub/timecode; separate Liquid Glass assistant with summary, key moments, action chips and follow-up composer.
- Provider capability router: direct video when genuinely supported; otherwise timestamped frame extraction via AVFoundation, bounded count and sampling interval, local OCR and optional permitted audio/transcript adapter.
- Mark event summaries as observed vs inferred; persist `RecordingEvent` with timestamp(s), frame provenance and model attribution; click event to seek.
- Document sampling limitations to the user; privacy gate discloses whether whole video, frames, audio or transcript will be uploaded and provides a cancel option.
- Suggested actions: summarize, explain at time, extract visible error, create tutorial/bug-report draft (text only).

**Automated tests**
- Frame sampling yields bounded chronological timestamps within clip duration; no full-video allocation required.
- Routing matrix for native-video, image-only, text-only, offline and remote providers; unsupported routes error before upload.
- Model outputs parsed/validated against available time range; malformed/out-of-range timestamps handled without a bad seek.
- Privacy tests assert approved media categories only; request cancellation halts further sends; failure preserves local recording.

**Manual real-Mac test**
1. Record a reproducible 60–120 s workflow with a recognizable event; analyze and inspect timestamps.
2. Click a key moment: player seeks correctly; ask a follow-up about that moment.
3. Test one compatible direct-video provider (if available) and one frame-based fallback; clearly label which route was used.
4. Decline cloud transmission; recording remains playable and can be analyzed with a compatible local vision provider if available.
5. Analyze a large/long recording; verify bounded memory, clear progress and recoverable errors.

**Gate M8:** A real local recording produces a grounded post-recording explanation, timestamp-seekable moments and functioning follow-up chat using at least one verified analysis path. Unsupported paths remain explicit, not faked.

## M9 — Searchable local history, FTS5 and semantic retrieval

**Objective:** Retrieve prior screenshots without accessing cloud embeddings.

**Implement**
- SQLite FTS5 index for screenshot OCR, conversation text, timestamps and app metadata; incremental updates/rebuild and filtered search UI.
- Local embedding abstraction and a real on-device embedding model suitable for captured OCR or screenshot descriptions; persist model/version and vectors. Use local vector scoring for semantic screenshot search with FTS results as fallback.
- Search by keyword, app, date and capture type; show useful excerpt with source asset. Index video summary/transcripts as text when available; **advanced visual video timeline search stays v2**.
- Background indexing with cancellation, deduplication and safe migration/reindex when embedding model changes.

**Automated tests**
- FTS5 fixture corpus: exact error string, punctuation, Unicode, empty OCR, timestamp/app filters and deleted assets.
- Semantic ranking fixture: conceptual paraphrase ranks expected screenshot above unrelated corpus; deterministic embedding doubles for unit tests, real-model smoke test separately.
- Index consistency after edit, delete and migration; no remote calls for local search.

**Manual real-Mac test**
1. Save multiple captures, search an exact visible code error and open correct screenshot/chat.
2. Search conceptually (e.g., “the screenshot about a missing Node dependency”) and verify relevant results.
3. Turn internet off and repeat search; delete capture and verify it disappears from results and local indexes.
4. Restart app and verify stable queries; test empty search and large library responsiveness.

**Gate M9:** Exact and semantic screenshot search work locally against persistent data and deleted assets are not returned.

## M10 — Accessibility, privacy, failure recovery and release readiness

**Objective:** Turn functional milestones into a safely distributable Mac application.

**Implement**
- Full system tests for multiple displays, scaling, Spaces, accessibility and appearance; respect VoiceOver, keyboard nav, Reduce Motion/Transparency and large text.
- Security and privacy review: Keychain, remote upload disclosure, log redaction, recording/mic permissions, clear history/retention and no unauthorized networking.
- Crash/restart recovery: unfinished captures, interrupted recording finalization, provider timeouts, expired folder permissions and DB migrations.
- App signing, hardened runtime, notarization/distribution path appropriate to chosen channel, version/migration strategy, clear installation and permission onboarding.
- Performance profiling: capture latency, OCR p50/p95, RAM during recording/video analysis, library search latency; optimize observed bottlenecks.

**Automated tests**
- Clean build (release and debug), all unit/integration/UI suites, static analysis and permission-independent fixture regressions.
- Data migrations across known schema versions, corrupt/unavailable media paths, safe cancellation and no-network local workflows.
- Tests ensure provider keys and raw screen content do not appear in ordinary diagnostic logs.

**Manual release matrix**
1. Fresh install, grant/deny/revoke permissions, use Quick Copy before any provider setup.
2. Screenshot selection, OCR, chat, annotations, history and settings with local and cloud providers.
3. Region/full-screen recording, playback, post-recording analysis, time navigation and history search.
4. 1-display and multi-display configurations; different scale factors, light/dark, Reduce Transparency and VoiceOver.
5. Interrupted recording, no disk space, invalid provider, network offline, user cancels upload, inaccessible save folder.
6. Test distributed build on a clean supported Mac, including signature, launch permissions and updates if applicable.

**Gate M10 / v1 release candidate:** All P0 requirements from the PRD pass on real hardware; P1 features are either complete with their acceptance gates or explicitly removed from the release scope **with product-owner approval**; no known critical data loss, unintended uploads or stuck-overlay bugs. Sign-off includes a regression report, known limitations, and distributable build.

---

## 6. Cross-milestone test and privacy matrix

| Scenario | M1 | M2 | M4 | M6 | M7 | M8 | M9 | M10 |
|---|---|---|---|---|---|---|---|---|
| No configured AI provider | Capture | OCR copy | Helpful empty state | Restore history | Record | Playback only | Search | E2E |
| Network disconnected | Capture | No-network assertion | Local Ollama if configured | Local data | Record | Local-only path | Offline search | E2E |
| Permission denied/revoked | Capture error | Safe failure | Still allow local history | Safe reopen | Recording error | Preserve media | Search existing | E2E |
| Multiple monitors/scaling | Geometry | OCR alignment | Panel | Saved coords | Capture region | Playback | — | E2E |
| Cloud consent canceled | — | — | Zero upload | Preserve asset | Zero upload | Zero upload | Local search | Audit |
| Quit/relaunch | — | No history default | Persist settings | Asset/chat restore | Finished file | Events restore | Index restore | Recovery |
| File or provider failure | Safe overlay cleanup | Clipboard unchanged | Retry/error | Atomic writes | Finalization error | No fabricated moments | Reindex | E2E |

**Evidence minimum:** automated test logs plus a concise manual test checklist for every milestone. Treat application behavior not testable in CI (window levels, permission prompts, multi-display selection, microphone capture) as a required real-Mac test, not an assumed pass.

## 7. Definition of done for every milestone

A milestone is complete only when all conditions below hold:

- Functional acceptance criteria pass using actual UI and real services where required.
- Project builds cleanly, automated tests pass, and newly added logic has tests. No unreported skipped tests.
- Accessibility and error states implemented for any new visible controls.
- No secrets/raw screenshot contents are exposed in logs; network-bound steps are disclosed and tested.
- No new crashes, hanging overlays, corrupt assets or unexpected history entries in regression runs.
- At least one real-Mac smoke test is documented for any system integration.
- `docs/DECISIONS.md`, `docs/TEST_MATRIX.md`, `docs/KNOWN_ISSUES.md` and milestone report updated.
- Product owner can reproduce the listed demo and explicitly accepts the milestone before next one begins.

## 8. Recommended agent instruction (paste at the beginning of each milestone)

> You are implementing captAI, a native macOS 26+ utility. Read `captAI_PRD.md`, `captAI_Design_Spec.md`, and `captAI_Implementation_Plan.md` in full. Implement **only milestone M[NUMBER]** and the minimum shared foundation it requires. First summarize existing repository state and SDK/API uncertainties. Create a brief task checklist and tests before implementing. Use SwiftUI/AppKit/ScreenCaptureKit/Vision/AVFoundation and native Liquid Glass as specified; verify installed SDK signatures rather than guessing. Do not create pretend integrations, hardcode secret keys, or silently upload captures. Keep Quick Copy functional without a model or network. After implementation, run the relevant tests, report exact commands/results, provide a manual real-Mac verification checklist, and state `PASS`, `FAIL`, or `BLOCKED` with evidence. Do not start the next milestone until I approve this one.

## 9. Open decisions to settle during implementation

These are design or platform-dependent details left intentionally open in the baseline documents; record resolutions instead of silently changing requirements.

| Decision | Suggested validation point | Default until proven otherwise |
|---|---|---|
| Global shortcuts and OS conflicts | M1 / M2 | Editable suggested shortcuts; warn and request remap |
| Screenshot overlay exclusion and multi-display spanning | M1 | Constrain selection to active display if necessary and explain clearly |
| Recognition language and OCR engine customization | M2 / M4 | Apple Vision Fast/Accurate; custom engine only if an adapter is implemented |
| Screen recording pause/resume OS support | M7 | Disable control if actual pipeline cannot pause safely |
| Direct video/audio providers and Ollama model support | M4 / M8 | Capability checks; frame-based fallback for image-capable models |
| Local embedding model, footprint and indexing throughput | M9 | OCR/text embeddings stored on-device; benchmark before choosing model |
| Cloud consent default and policy persistence | M4 | Ask before sending screenshots/media to new remote provider/context |
| ChatGPT account access | M4 or later | Feature-gated pending documented authorized eligibility |
| Packaging channel (direct/notarized vs App Store) | M10 | Choose based on needed permissions and signing requirements |

## 10. Traceability to source specifications

- **PRD:** CAP-01/02 → M1/M3; OCR-01/02 → M2/M5; AI-01/02 → M4; CFG-01/PRIV-01 → M4/M6/M10; ACT-01/ANN-01 → M5; VID-01 → M7; VID-02 → M8; HIST-01 → M6; HIST-02 → M9; EXT-01 conditional; VID-ADV v2.
- **Design Spec:** S0 → M0; S1 → M1/M2; S2 → M3–M5; S3 → M2; S4 → M7; S5 → M8; S6 → M6/M9; S7 → M4/M6/M7; coordinate contracts → M1/M5; state machines → corresponding milestones; accessibility → continuous and M10.

**Final delivery target:** One fully functioning, local-first macOS utility with three independently useful capture flows, a reliable AI assistant for screenshots and recorded video, and a searchable local history. Any capability not verified end-to-end remains visibly disabled and is documented rather than declared complete.
