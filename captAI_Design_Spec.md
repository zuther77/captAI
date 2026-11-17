# captAI — Interface & Interaction Design Specification

**Version:** 1.0 · Agent implementation companion to PRD  
**Date:** 17 November 2026  
**Target:** macOS 26+ · SwiftUI + AppKit · Apple native Liquid Glass  
**Reference:** User-provided concept image: large highlighted screenshot region left, narrow assistant overlay on right. This is a directional sketch, not a pixel-perfect asset.

## 1. Experience principles
1. **Capture-first, not chat-first.** Start with a native-feeling dim-and-drag overlay; the AI is revealed only after selection.
2. **Preserve visual context.** Frozen image stays where selected; assistant floats adjacent without obscuring the subject unless no alternative.
3. **Local is explicit.** Quick Copy always works offline. Users can immediately see where analysis happens.
4. **Glass as chrome, not content.** Apply Liquid Glass to compact controls, toolbars, buttons, sidebar/navigation. Use opaque, accessible reading surfaces for images, code, chat, video.
5. **Fast perceived feedback.** Show capture confirmation/local OCR results immediately, then progressively render AI results.
6. **Non-destructive and dismissible.** Original screenshot/video remains unchanged; Esc consistently cancels transient UI.

## 2. Information architecture
- **Menu bar utility:** Capture Screenshot, Record Screen, Quick Copy Text, Open Library, Settings, Pause/Resume recording when active, Quit.
- **Capture overlay:** display dim, selection viewport, crosshair, optional mode hints, Escape cancel.
- **Screenshot workspace:** frozen selected region, annotation toolbar, floating AI panel.
- **Recording controller:** timer, pause where available, stop, mic/system audio indicators.
- **Video workspace:** video playback panel, key moments, summary, actions, chat.
- **Library:** local screenshot/recording grid or list, search/filter, detail view, delete/export.
- **Settings:** Providers, OCR, Shortcuts, Storage, Capture & Recording, Privacy (native macOS settings window).

## 3. Layout system, dimensions, and positioning
- macOS coordinates are points; captured bitmap coordinates are pixels. Persist both image pixel size and display scale at capture time.
- Capture overlay: edge-to-edge per display, neutral black dim approximate 30–40% opacity, adjustable for contrast; selected region remains undimmed with ~1–2 pt high-contrast outline.
- Screenshot region: freeze image at original screen rectangle after mouse-up; avoid permanent dark dimming in analysis state.
- AI panel: initial width 400 pt (acceptable 360–460), min 340, max ~600; initial max height min(720 pt, available display height − 48 pt); corner radius guided by system glass styling; safe margin ≥16 pt from display visible frame.
- Placement priority: right of selected region +12–16 pt gap → left → above/below → overlay anchored to safest screen edge. Never let panel leave visible frame; if no side space, prefer independent movable panel without covering most of capture.
- Panel uses title/header, one scrollable content region, sticky prompt composer, footer model/privacy indicator. Panel resize impacts scrolling but must not detach annotation coordinates.
- Overlays follow display selection, including negative multi-monitor global coordinates; geometry normalization uses screenshot-relative coordinates [0,1].
- Full-screen apps and Spaces require validation of window levels/activation. UI must not steal keyboard focus while dragging and must restore focus appropriately when chat activates.

## 4. Visual style tokens
| Token | Guidance |
|---|---|
| Primary surface | System-adaptive, readable, preferably opaque for chat/media |
| Glass | Native `.glassEffect()` / `GlassEffectContainer`; avoid hand-built faux glass |
| Controls | Native glass buttons, segmented controls, menu, popover, toolbars |
| Corner radius | Native first; content cards around 12–16 pt where needed |
| Spacing scale | 4 / 8 / 12 / 16 / 24 / 32 pt |
| Typography | SF system fonts; body 13–15 pt; section title 15–17 pt; metadata 11–12 pt |
| Iconography | SF Symbols; text labels for ambiguous actions |
| Semantic accent | System accent; red recording indicator; green local state; neutral cloud state |
| Motion | Subtle 150–250 ms transitions; respect Reduce Motion |
| Contrast | Respect accessibility settings including Reduce Transparency |

Use light and dark mode automatically. Do not fake Liquid Glass by layering arbitrary opacity and blur behind screenshot content. API names and availability must be confirmed in current SDK.

## 5. Detailed screen states
### S0. Idle / menu bar
- No persistent main window required. Menu bar symbol opens command menu, current provider indicator, Settings, Library.
- Shortcut handling works when application is in background. Fresh install onboarding requests screen capture permission and explains storage; does **not** force AI signup.

### S1. Capture mode: screenshot/Quick Copy
- On hotkey: dim each relevant display; pointer crosshair; optional hint "Drag to select · Esc to cancel" near pointer or bottom.
- Mouse-down starts selection rectangle; drag makes selected region clear; pointer coordinates display in subtle HUD only if useful.
- Mouse-up commits; zero-size/micro-selection rejects with gentle feedback; Escape destroys overlay cleanly.
- For screenshot AI mode, freeze image and open assistant. For Quick Copy mode, run OCR in memory and close overlay, show transient copy toast.

### S2. Screenshot AI workspace
Panel structure top-to-bottom:
1. **Header (fixed):** captAI icon/title; content mode chip "Screenshot"; pin; minimize; close.
2. **Context status:** small captured-app name and time (when permission available); optional "View capture" toggle.
3. **Analysis (scroll):** streamed summary with placeholders, retry/cancel, errors in-place.
4. **Suggested actions:** chips from OCR classifier: Explain Error, Find Fix, Copy Code, Analyze Chart, Find Alternatives, Copy Text. No irrelevant chips.
5. **Conversation (scroll):** chat bubbles or clean prose blocks; provider/model label per response optionally on hover/details.
6. **Composer (fixed):** multiline text input, send, optional annotation attach indicator; Enter send, Shift+Enter newline (configurable).
7. **Footer (fixed):** clickable `Provider · Model` opens Settings > Providers; privacy state `Local` or `Cloud` and concise tooltip.

- Frozen screenshot remains separate and visible at selected region; toolbar anchored near its edge with Select, Circle, Rectangle, Arrow, Highlight, Undo, Redo, Copy Text, Save/Export.
- Annotation selection invokes a detail popover or crop+chat action "Ask about selection"; maintain selection until user clears.
- Window close vs capture close: closing assistant hides workspace; persistence follows history policy; menu bar Library allows re-opening.

### S3. Quick Copy success / empty / error
- Success: small ephemeral toast near selection, clipboard check + "Copied text"; no chat; no upload; do not save raw screenshot by default.
- Empty OCR: "No text detected" with Retry and optional "Open Screenshot AI" if configured; do not erase existing clipboard.
- Failure: brief clear recoverable error; no clipboard overwrite.

### S4. Recording selection and active state
- Shortcut opens selection overlay with "Region" and "Entire display" modes; include audio controls in pre-recording confirmation if capture UI permits.
- Recording state: unobtrusive control HUD outside target area where practical; red dot, `00:00`, Stop, Pause/Resume (when supported), Mic, System Audio. Hide from encoded video where supported.
- Recording state is never silently active: persistent icon and menu bar status, shortcut/action to stop, confirmation if discard.
- On stop: show local finalize progress, then analysis state. Show disk/permission errors with recovery, never claim success until file finalized.

### S5. Video assistant workspace
- Similar glass panel or wider detachable window if media preview is too cramped.
- Top: preview with native player, playback scrubber, timecode, mute.
- Analysis card: overview with observations separated from inferred causes.
- Key Moments list: time chip, short event title, optional supporting frame thumbnail; clicking seeks.
- Suggested actions: Summarize, Explain at timestamp, Extract error, Create steps / bug-report draft (text output only in v1).
- Chat composer maintains recording context and supports questions tied to time ranges.
- Show analysis strategy in details: `Direct video` or `Sampled frames` to convey limitations.

### S6. Library
- Native window with glass left sidebar or toolbar: All, Screenshots, Recordings, Favorites (optional v1), Settings link.
- Search bar supports OCR/exact match and semantics with filters: Date, App, Type. Grid cards show thumbnail, timestamp, app, title, short analysis summary, Local/Cloud history marker when helpful.
- Detail opens associated media and chat; delete confirmation makes clear files, OCR index, embeddings, and conversation association will be removed.
- Empty state suggests shortcuts and notes offline Quick Copy does not save history by default.

### S7. Settings
- Section navigation: Providers / OCR / Shortcuts / Storage / Capture & Recording / Privacy.
- Providers: active provider, named saved profiles, endpoint URL/model ID, vision/video capability indicators, API credential masked input, Test Connection, Add/Delete endpoint, local/cloud badge. Provider indicator in assistant always navigates directly here.
- OCR: Apple Vision default; Fast / Accurate; language preference; optional custom OCR adapter only when implemented (do not show a nonfunctional engine selector).
- Shortcuts: native key-combination recorder, collision warnings, Restore Defaults. Screenshot `⌘⇧2`; Recording `⌘⇧3`; Quick Copy `⌘⇧C` are proposals and not guaranteed available.
- Storage: screenshot and recording folder pickers (may be separate), database status, retention, clear history, export/import where implemented.
- Capture & Recording: default region/display, quality, system audio/mic toggles, auto-analyze after stop, analysis mode Automatic/Frames/Direct when supported, overlay behavior.
- Privacy: local-only mode toggle if desired; ask-before-cloud policy, data categories transmitted, API key storage note, local retention, clear data.
- Settings never imply changes are saved until persisted successfully; test connection returns verified capability/error.

## 6. Keyboard, mouse, and accessibility behaviors
- Esc in selection cancels; Esc in annotation tool clears active mark/selection before dismissing panel; Esc in recording does not silently discard captured video.
- Cmd+C copies recognized text only when text selection is active; otherwise standard copy context maintained.
- Cmd+Z / Shift+Cmd+Z undo/redo screenshot annotations while annotation canvas focused.
- Tab cycle through assistant and toolbar; VoiceOver readable tool labels and timing; all controls keyboard operable.
- Respect high contrast, Reduce Motion, Reduce Transparency, large text; allow keyboard access to recording Stop.
- UI should never silently transmit capture on changing provider; require deliberate trigger or consent policy.

## 7. UI component specification
| Component | Inputs | States | Outputs |
|---|---|---|---|
| CaptureOverlay | display, mode, shortcut | idle/selecting/canceled/committed | selected screen bounds |
| FrozenCaptureCanvas | image, scale, annotations | viewing/editing/selection | normalized annotation vectors |
| AnnotationToolbar | tool, undo stack | selected/disabled | draw, edit, copy command |
| FloatingAssistantPanel | session, provider, analysis | loading/streaming/ready/error | prompt, action, settings event |
| ContextActionChips | OCR category, capabilities | pending/ready/disabled | deterministic/AI action |
| ProviderIndicator | provider ID, model, locality | connected/offline/error | open Providers settings |
| RecordingControlHUD | capture session | preroll/recording/paused/stopping | stop/pause/audio |
| VideoTimeline | media URL, event list | seeking/playing | selected time/time range |
| LibrarySearch | query, filters | loading/empty/results/error | opened session |
| SettingsWindow | preferences/profile | clean/dirty/testing/error | validated persisted settings |

## 8. State machines and transitions
### Screenshot
`idle → selecting → captured → OCR running → assistant loading → streaming/ready → closed`.
Alternate: `selecting → canceled`; `captured → capture error`; `assistant → annotation editing → assistant`; `assistant → settings → assistant`.
### Quick Copy
`idle → selecting → OCR running → copied toast → idle`. Alternate `OCR empty/error → feedback → idle`.
### Recording
`idle → selecting → pre-recording → recording ↔ paused → stopping/finalizing → local saved → analyzing → video workspace`. Alternate permission/disk/finalization errors recover without false success.
### Provider request
`idle → capability validation → privacy gate (if remote) → request → streaming/result/error/canceled`. No request if capability check fails.

## 9. Data and coordinate contracts (developer-facing)
- `CaptureAsset`: id, kind(image|video), fileURL, creationTime, originatingApp?, displayID?, widthPx, heightPx, captureBoundsPoints, backingScale, durationMs?, audioFlags, providerTransmissionHistory.
- `OCRBlock`: id, captureID, text, confidence?, boundsNormalized{x,y,w,h}, sequenceIndex, language?. Convert Vision coordinate origin to app canvas convention consistently.
- `Annotation`: id, captureID, type(circle|rectangle|arrow|highlight), pointsNormalized, strokeWidth, colorToken, createdAt, zIndex, optional text.
- `Conversation`: id, assetID, createdAt, title, messages[]; `Message`: role, content, providerProfileID, modelID, timestamps, referencedAnnotationIDs, citedTimeRanges.
- `RecordingEvent`: id, assetID, startMs, endMs?, title, description, origin(observed|inferred), sourceFrameTimesMs[].
- Keep session record schema separate from provider SDK types; adapters translate to provider-specific media and response formats.
- Atomic saves: capture to temp, finalize, then persist database; rollback dangling indexes on failure.

## 10. Responsive behavior and edge cases
- Tiny selected region: assistant opens at screen edge, not attached to unreadably small capture; allow zoom on capture.
- Region near right edge: panel flips to left; region across monitors: capture on selected display or explicit multimonitor policy with warning.
- Selected screenshot overlays obscured by Dock/menu bar: use visibleFrame positioning and manual move.
- Fullscreen app/Spaces: avoid changing Space unexpectedly; test overlay levels.
- Protected/blank capture: show permission or protected-content explanation, avoid hallucinated AI output.
- Cloud provider unavailable or image model unsupported: retain local screenshot and OCR; show model selection path and retry.
- Large recordings: cap duration/size via configurable warning; show estimated frame/upload size; enforce memory-bounded frame extraction.
- Multiple concurrent capture hotkeys: serialize capture sessions, no stacked overlay windows.
- No text / multilingual / rotated code: show OCR uncertainty, permit manual correction before copying.

## 11. Screen-by-screen acceptance checklist
- Screenshot capture matches reference concept: dim backdrop, clear selection, frozen region, right-side overlay when space exists.
- After selection, dimming disappears; chat can remain open without obscuring work.
- Active provider chip opens Settings > Providers; changing profile updates next request and footer indicator.
- Quick Copy with no API keys extracts into clipboard offline, emits toast and no history artifact.
- Annotation overlay stays registered during drag, zoom, and panel resize; original asset unchanged.
- Recording stops and produces playable local video; assistant shows analysis and timestamp seeking.
- Library retrieves screenshots by visible exact OCR string and can open past chats.
- All controls work in dark/light, reduced-transparency, VoiceOver and keyboard navigation modes.

## 12. Suggested coding-agent implementation sequence
**Milestone 1 — Shell and capture:** menu bar app, window coordinator, shortcut recorder, dim/selection overlay; test geometry across displays.
**Milestone 2 — Offline quick copy:** ScreenCaptureKit still capture, Vision OCR, NSPasteboard, copy toast, zero network.
**Milestone 3 — Screenshot workspace:** frozen capture, NSPanel-hosted SwiftUI assistant, layout placement, streaming chat shell.
**Milestone 4 — Providers and settings:** Keychain, model adapters, Ollama vision, BYOK/custom endpoints, capability checks, privacy gate.
**Milestone 5 — Actions and annotations:** heuristic chips, vector geometry, crop/annotation prompt context.
**Milestone 6 — Video:** recorder and HUD, local file finalization, AVFoundation preview/frames, post-recording summary and timestamps.
**Milestone 7 — History/search:** SQLite schema/migrations, FTS5 OCR/message index, local semantic search, deletion, retention.
**Milestone 8 — hardening:** performance/privacy testing, accessibility, notarization/packaging, permission recovery.

For every milestone, write unit tests for pure logic and integration/UI tests for macOS-specific windows/permissions. Do not claim completion from UI mockups alone.

## 13. Dependencies and validation notes
- SDK verification required for precise ScreenCaptureKit stream/recording APIs, audio capture, macOS-specific window exclusion and SwiftUI Liquid Glass modifiers.
- Validate Ollama model vision capabilities and custom endpoint multimodal schemas at runtime; do not assume arbitrary models can view frames.
- ChatGPT account connection is not a guaranteed release requirement and must remain feature-gated pending authorized availability.
- Use only system-approved capture permissions and respect protected content; disclose whenever remote providers receive screen contents.
