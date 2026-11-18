# captAI — Product Requirements Document

**Version:** 1.0 MVP baseline  
**Date:** 17 November 2026  
**Platform:** macOS 26+ (initial target)  
**Status:** Agreed product scope; implementation decisions requiring validation identified below  
**Audience:** Product owner, designer, coding agent, QA

## 1. Executive summary
captAI is a native, local-first macOS utility for capturing a screen region or recording a region/display and discussing it with an AI assistant in an adjacent floating panel. It also provides instant, offline text copying from the screen without invoking an AI model. The experience follows macOS native selection behavior: shortcut → dim desktop → select → capture → show context-aware assistant or copy text. Users can use their own API keys, compatible custom endpoints, or local Ollama vision models; ChatGPT-account-based access is conditional on integration availability and eligibility, not assumed for the MVP release.

**Product promise:** Understand, discuss, annotate, search, and reuse what's on your screen without breaking your workflow or unnecessarily uploading content.

## 2. Problem and target users
- People frequently need to interpret code errors, documentation, charts, UI screens, products, and complex visual information but must manually capture and switch into another AI app.
- Copying short text from an image should not incur latency, token costs, or cloud exposure.
- Screen recordings contain temporal context useful for understanding bugs and workflows, but current capture tools do not provide contextual follow-up chat.
- Technical users want model flexibility, local privacy controls, and ownership of screenshots and recordings.

**Primary audience:** developers, designers, researchers, support engineers, and other heavy macOS users. **Secondary:** general users who want fast OCR or visual explanations.

## 3. Goals, non-goals, and success measures
### Goals
- Invoke screenshot, recording, or quick text copy using independent configurable global shortcuts.
- Keep the screenshot visible in a frozen visual overlay and open a movable, resizable assistant beside it.
- Provide meaningful first analysis and context-specific suggested actions for still captures.
- Support post-recording video summaries, timestamped events, and contextual chat.
- Default to on-device OCR, local storage, and explicit clarity around network-bound processing.
- Support configuration of providers, endpoints, OCR, shortcuts, and storage.
- Search saved screenshots and conversations through text and semantic indexing.

### Non-goals for v1
- Continuous/live AI commentary while screen recording; real-time issue detection.
- Advanced searchable video timeline and sophisticated adaptive scene sampling.
- Cross-device synchronization, teams, cloud storage backend, browser extension, mobile support.
- Autonomous clicking, UI control, or edits to other applications.
- Guaranteed ChatGPT subscription integration without approved/eligible access.
- Guaranteed identical screenshot behavior in all protected-content apps / DRM surfaces.

### Proposed success criteria (validation targets, not promised performance)
- Quick Copy works on a fresh install without signing into or configuring any AI provider.
- Screenshot region capture and local copy function with network disconnected.
- Most normal-resolution OCR captures finish in under ~2 s on supported reference hardware (benchmark, not hard realtime SLA).
- Users can complete screenshot selection and enter a follow-up prompt without switching to a separate full application.
- Tests demonstrate no network calls during local-only workflows.
- App can reopen history and associate conversations with the correct media asset.

## 4. Scope and priority
| ID | Feature | Priority | Release |
|---|---|---|---|
| CAP-01 | Native dimmed screenshot region selector | P0 | v1 |
| CAP-02 | Frozen selected image + adjacent floating assistant | P0 | v1 |
| OCR-01 | Dedicated local OCR quick-copy shortcut | P0 | v1 |
| OCR-02 | Copy all or selected OCR text from screenshot chat | P0 | v1 |
| AI-01 | AI screenshot summary, streaming responses, follow-up chat | P0 | v1 |
| AI-02 | Bring-your-own-key / supported Ollama vision / custom endpoint | P0 | v1 |
| CFG-01 | Settings: providers, endpoints, model, OCR, shortcuts, locations | P0 | v1 |
| PRIV-01 | Local storage, explicit remote disclosure, Keychain secrets | P0 | v1 |
| VID-01 | Region / display video capture; optional audio; local output | P0 | v1 |
| VID-02 | Post-recording AI summary + timestamped events + questions | P0 | v1 |
| ACT-01 | Heuristic-first contextual screenshot action chips | P1 | v1 |
| ANN-01 | Non-destructive circle, rectangle, arrow, highlight annotations | P1 | v1 |
| HIST-01 | Local screenshot/video/conversation library | P1 | v1 |
| HIST-02 | OCR FTS5 and local embedding-based screenshot search | P1 | v1 |
| EXT-01 | ChatGPT account-based authorization if formally supported | Conditional | Not a v1 launch blocker |
| VID-ADV | Live AI, advanced timeline search, automatic issue detection | Deferred | v2 |

## 5. Core journeys and interaction rules
### Journey A: screenshot with AI
1. User presses screenshot shortcut (proposed `⌘⇧2`, conflict-checked and editable).
2. Desktop dims; pointer becomes crosshair; drag outlines a clear selection; Esc cancels.
3. Upon release, system captures pixel content and makes a frozen overlay at the chosen location. Dimming clears.
4. Compact Liquid Glass assistant opens alongside the region, preferably to its right; chooses left/above/below when necessary.
5. OCR executes locally and quick actions can appear immediately; remote vision analysis begins only per active provider and privacy policy.
6. Assistant streams analysis, retains screenshot context, and supports chat, annotations, copy text, and pin/move/resize.
7. Closing overlay does not delete persisted capture when history saving is enabled.

### Journey B: quick copy (no AI)
1. User presses Quick Copy shortcut (proposed `⌘⇧C`, editable).
2. Native-style dim/drag region selection; capture in memory.
3. Apple Vision extracts text locally; whitespace/reading order reconstructed; text copied to NSPasteboard.
4. Transient success indicator shows copied text count or failure with retry. No assistant window, AI provider, API credentials, or network needed.
5. By default, Quick Copy should not create screenshot or history entries; user may enable optional history in Settings in a later iteration.

### Journey C: recording + analysis
1. User presses recording shortcut (proposed `⌘⇧3`, editable).
2. Region or entire display selectable; recording controls appear with duration, stop, pause/resume (if supported), audio toggles.
3. Dim overlay disappears as recording starts. Clear recording indicator persists and can be used to stop.
4. Stop finalizes a local video file; analyze after recording when enabled, subject to cloud disclosure.
5. For compatible direct-video providers use native video input; otherwise extract timestamped frames, OCR, and optional local speech transcript, then analyze supported inputs.
6. Floating panel shows playable recording, short summary, timestamped key moments, suggested actions, and follow-up chat. Clicking timestamp seeks video.
7. Recordings remain local unless explicitly transmitted to chosen remote model; show upload estimate / confirm if configured.

### Journey D: provider and settings
1. Assistant footer shows active provider/model and Local or Cloud indicator.
2. Clicking provider indicator opens the native Settings window with Providers selected; provider may be switched there.
3. Settings include provider profiles (Ollama, supported hosted APIs, compatible custom endpoints), model IDs, tested capability badges, API keys, OCR mode/engine, all shortcuts, screenshot/video folder locations, history retention, privacy controls.
4. Switching provider affects the next request, not an in-flight request; history records provider/model per response.
5. Unsupported capability (e.g., text-only local model asked to analyze images) yields actionable error, not silent failure.

### Journey E: annotations and search
1. User selects Circle / Rectangle / Arrow / Highlight and marks a frozen screenshot; annotations are removable and editable.
2. Follow-up queries submit image plus annotation geometry and optionally a cropped region, preserving surrounding context.
3. Library supports text, app name, date, content type, and semantic query; result opens associated screenshot, recording, and chat.

## 6. Functional requirements and acceptance criteria
### Capture and windowing
- FR-C01: Register three independent customizable global shortcuts; detect and explain OS/app conflicts.
- FR-C02: Fullscreen overlay per display with dim outside selection; selection clear and border visible on light/dark backgrounds.
- FR-C03: Esc cancels; dragging works in all directions; subminimum regions show guidance; handle multiple monitors, display scaling, Spaces, menu bar, Dock.
- FR-C04: Exclude captAI overlays/panels from captured imagery where supported; never capture sensitive app content without OS permission.
- FR-C05: Position assistant next to selected bounds with screen-aware collision avoidance; drag/resize/pin/close; frozen overlay may be hidden or detached.
- AC-C01: Selecting any quadrant opens assistant fully on-screen; cancel leaves no capture or ghost overlay.
- AC-C02: Changing active display resolution does not corrupt saved pixel-region coordinates.

### OCR / Quick Copy
- FR-O01: Use Apple's Vision on device, default Accurate/Fast configurable, with recognition language choices where practical.
- FR-O02: Normalize recognition coordinates; group text by reading order while maintaining line breaks; expose selectable OCR boxes on screenshot.
- FR-O03: Copy to pasteboard with text/plain; offer Copy All and Copy Selection; preserve code formatting on best-effort basis.
- FR-O04: Quick Copy functions with no configured AI provider, no network, and no history artifact by default.
- AC-O01: Airplane/offline run copies visible text; model invocation counter remains zero.
- AC-O02: Empty recognition produces explanatory feedback and never overwrites clipboard with empty string.

### AI providers and chat
- FR-A01: Provider adapter capabilities: text, image, direct video, audio transcription, streaming, context limits.
- FR-A02: Support Ollama at local/custom base URL, hosted BYOK provider adapters, generic compatible endpoints; verify vision capability before submitting image.
- FR-A03: API credentials held in Keychain; never log secrets or store in database plaintext.
- FR-A04: Chat binds capture(s), system/context prompts, messages, provider/model snapshot, errors, token data when available.
- FR-A05: Context-aware chips generated locally from OCR heuristics, optionally expanded by selected model; examples: Explain Error, Find Fix, Copy Code, Analyze Chart, Find Alternatives.
- FR-A06: ChatGPT subscription sign-in is gated behind confirmed legal/technical eligibility and appropriate OAuth flow; never imply a Plus/Pro subscription is itself an API key.
- AC-A01: Offline Ollama vision query works with a tested local vision model; cloud request clearly marked and can be canceled.
- AC-A02: Switching model for new message does not alter previous response metadata.

### Annotation
- FR-N01: Store vectors in normalized screenshot-relative coordinates as separate records, not burned into original media.
- FR-N02: Support undo/redo, select, edit/delete, and contextual region crop.
- FR-N03: Hide overlay annotations from original export unless user explicitly selects Export Annotated.
- AC-N01: Resize assistant or screenshot rendering without shifting annotation anchors.

### Video
- FR-V01: ScreenCaptureKit captures selected region/display into locally playable video. Support system audio and microphone where permitted, with separate user toggles.
- FR-V02: Record controls show elapsed time, stop, and supported pause; gracefully handle permissions, disk exhaustion, sleep, display disconnect, failed write.
- FR-V03: Store duration, resolution, capture region, timestamps, optional transcript and scene event markers.
- FR-V04: Analyze after stop through direct video or frame-extraction compatibility strategy; missing audio/transcript cannot block video-only analysis.
- FR-V05: All key moments include timestamp, confidence/uncertainty context, playback seek. Distinguish observed events from inferred causes.
- AC-V01: A 60-second region recording can be opened, played, summarized, and discussed without corrupt file or missing timestamp links.
- AC-V02: Local recording works offline; remote analysis never silently starts before required disclosure/consent.

### History and search
- FR-H01: Persist screenshot/video metadata, file URLs, OCR text, conversation and annotation records in SQLite with migrations.
- FR-H02: FTS5 indexes OCR/messages; local embedding search for screenshot semantic similarity, with model download/storage disclosed and optional fallback to FTS if unavailable.
- FR-H03: User can filter by date/app/type, open item, delete individually or clear history; deleting removes associated thumbnails and indexes.
- AC-H01: Query exact visible OCR string retrieves expected screenshot; semantic query returns relevant screenshots on evaluation set.

### Privacy and accessibility
- FR-P01: Capture files and OCR stay local by default; indicate Local/Cloud processing on each assistant surface.
- FR-P02: For cloud models, clearly describe what may be transmitted (image, sampled frames/video, selected audio/transcript, text prompt); obtain consent according to Settings policy.
- FR-P03: Save locations selected via native file picker; avoid auto-migrating old captures on folder changes.
- FR-P04: Accessibility: VoiceOver labels, keyboard interaction, high contrast, reduced transparency/motion support, scalable text, full keyboard controls.
- AC-P01: Local Quick Copy produces no network connections in integration testing; user can delete history with related files.

## 7. UX and product defaults
- macOS 26+ native SwiftUI Liquid Glass for controls/navigation; screenshot/video content remains on opaque readable surfaces.
- Initial width of side panel approximately 380–440 pt; size adapts to display; always within visible screen frame.
- Overlay dimming applies only during selection, not throughout chat; selected image is frozen after capture.
- Quick Copy intentionally closes without AI window; local OCR is available as a chat quick action.
- Assistant shows analysis skeleton, cancellable streaming, suggested chips, prompt composer, model/privacy footer, recording video/timeline for video mode.
- Settings is a native standalone window opened from model indicator or menu bar; settings changes persist.

## 8. Architecture and data constraints
- Swift/SwiftUI + AppKit NSPanel/window management; ScreenCaptureKit for pixel capture/recording; Vision for OCR; AVFoundation for media reading/frames; NSPasteboard; Keychain; SQLite/FTS5 and local embedding index.
- Layer boundaries: CaptureService → OCRService/RecordingProcessor → AnalysisOrchestrator → ProviderAdapter → SessionRepository → UI.
- Provider capability checks; streaming cancellation and backoff; full local logging with sensitive-data redaction.
- Screenshot media immutable; annotation vectors stored separately; files stored at user-selected location; metadata/index in app support.
- API changes/OS limitations must be confirmed against installed Xcode and macOS SDK before writing native implementation.

## 9. Metrics and launch checklist
- Instrument locally, opt-in only for any analytics: shortcut use, capture-to-first-result, OCR latency, provider error rate, successful recording finalization, search usage, first-session quick-copy success. No raw screenshots or prompts in analytics.
- Test matrix: Intel/Apple Silicon if supported, 1–3 monitors, Retina/standard scaling, light/dark, different Spaces, fullscreen apps, offline, broken endpoints, permissions denied, disk full, protected content, reduced motion, VoiceOver.
- Launch gates: no silent uploads; clipboard behavior reliable; recording files finalized reliably; no API credentials in plaintext/logs; prompt history recoverable; no overlay left behind after Esc/stop/crash.

## 10. v2 backlog
- Real-time/live video understanding and proactive in-recording interventions.
- Advanced dynamic sampling, full searchable video timeline, automatic issue/change detection across video.
- Optional workflow-to-tutorial / bug-report automations beyond initial post-recording action templates.
- Optional cross-device sync, richer search embeddings and model management.

## 11. Open decisions for implementation
- Confirm product name/trademark before distribution; "captAI" is a working name.
- Validate macOS 26+ market reach against support expectations.
- Confirm native shortcut set does not collide with user-configured OS shortcuts; ship sensible editable defaults.
- Validate supported hosted providers, video modalities, OAuth eligibility, and custom endpoint compatibility at build time; disable unsupported rather than silently degrade.
- Choose signed/notarized distribution route and sandbox entitlement plan; test screen capture and file bookmarks in chosen route.
- Decide local-embedding model packaging/download strategy with size/quality/licensing benchmarks.
