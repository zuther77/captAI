# Decisions

Approved deviations and resolved open questions. Status values: **Accepted** (applied), **Proposed** (needs product-owner review).

## D-001 Xcode owns the project file — Accepted (amended 2026-11-17)
`captAI.xcodeproj` was bootstrapped by `scripts/generate_project.rb` (the `xcodeproj` Ruby gem), because XcodeGen and Tuist were not installed and `brew install` failed inside the agent sandbox.
**Amendment:** the product owner will develop in Xcode from here on. The project file is now edited in Xcode and committed as the source of truth. The script is kept for reference only and refuses to run without `--force`, since regenerating discards Xcode changes. There is no generated-project workflow and no `project.yml`.
*Consequence:* new source files must be added to the right targets in Xcode (see D-002).

## D-002 Unit and integration tests are not hosted by the app — Accepted
The two bundles compile `App/`, `Features/` and `Core/` directly (minus the `@main` entry file). Tests never launch the menu-bar app, need no window server, and cannot touch real settings or permissions. Only `captAIUITests` launches the real app.
*Why:* hosted tests hung before connecting in the agent environment, and unhosted tests are faster and more deterministic. *Trade-off:* sources compile three times; acceptable at this size.
*Xcode workflow cost:* because Xcode owns the project (D-001), every new file under `App/`, `Features/` or `Core/` must be ticked for `captAI`, `captAIUnitTests` and `captAIIntegrationTests`. A file missing from the test targets is untested, and tests that reference it fail to compile. Extracting that code into a framework target would remove this step; not done, pending the product owner's decision.

## D-003 Not sandboxed; hardened runtime in Release — Accepted for M0, revisit at M10
M0 requests no entitlements. Screen Recording is a TCC permission, not an entitlement. Release enables the hardened runtime; Debug does not (ad-hoc test bundles would fail library validation).
*Open:* App Store distribution would require the sandbox and changes the file-access and global-shortcut design. PRD §11 and the plan's §9 defer this to M10.

## D-004 Default recording shortcut `⌘⇧3` collides with macOS — Proposed
`⌘⇧3` is the system "save screenshot of screen" shortcut, enabled by default. The PRD proposes it as the recording default, and plan hard rule 9 says defaults ship only after conflict checking.
*M0 behavior:* the value is stored as a default but **nothing is registered** until M1.
*Proposal:* M1 reads the system symbolic hotkeys and refuses to register a colliding default, prompting the user to pick another. The product owner should also choose a non-colliding default for recording, for example `⌃⌥⌘3`. `⌘⇧2` (screenshot) and `⌘⇧C` (Quick Copy) have no system-level conflict, but `⌘⇧C` is used by individual apps (for example Finder's Computer window), which a global shortcut will shadow. M1 conflict checking should surface this to the user.

## D-005 Menu items for unbuilt features are visible but disabled — Accepted
Plan rule 10 asks for a disabled, labeled feature over a button that does nothing. The menu bar lists Capture, Quick Copy, Record and Library as "— Coming Soon" and disabled. Settings controls whose effect arrives later carry a visible note.

## D-006 Settings persist as JSON in Application Support — Accepted
`~/Library/Application Support/captAI/settings.json`, written atomically, tolerant of missing keys, versioned. A corrupt or newer-version file is renamed to `settings.backup-<unix time>.json`, never overwritten. API keys are never part of this file (Keychain in M4); a test asserts no credential-named fields.

## D-007 Screen Recording status is derived, not queried — Accepted
`CGPreflightScreenCaptureAccess()` returns only true/false and never prompts. "Not determined" versus "denied" is inferred from a local record of whether captAI has ever asked (`PermissionRequestLedger`). If the user granted access through System Settings before first launch, the status reads as granted. If the ledger is cleared while access is denied, it reads as "not requested" until the user clicks Request Access once.

## D-008 Toolchain and deployment target — Accepted (target amended by D-010)
Built with Xcode 27 beta (Swift 6.4, macOS 27.0 SDK) on macOS 27.3, Swift 6 language mode, strict concurrency complete, warnings as errors. The deployment target is now 27.0 (D-010). Nothing has been run on a macOS 26 machine; see KNOWN_ISSUES KI-002, which is now deferred. M0 uses only system chrome, which receives Liquid Glass automatically. Explicit `glassEffect` use begins in M3 and must be verified against the SDK then.

## D-009 `@Observable` and `MenuBarExtra` — Accepted
The Observation framework and SwiftUI `MenuBarExtra` keep M0 free of third-party dependencies. The Settings window is an AppKit `NSWindow` hosting SwiftUI, owned by `WindowCoordinator`, so later panels and HUDs share one lifecycle owner (plan §4).

## D-010 Deployment target raised to macOS 27.0; backwards compatibility deferred — Accepted (2026-11-18)
The product owner's machine runs macOS 27 and cannot be downgraded, and macOS 27 is the only OS available for testing. `Config/Shared.xcconfig` now sets `MACOSX_DEPLOYMENT_TARGET = 27.0`.
*Consequence:* the app will not install or run on macOS 26 or earlier. KI-002 is deferred.
*Deferred:* supporting macOS 26 again means lowering the target, guarding macOS 27-only APIs with availability checks, and testing on real macOS 26 hardware (plan rule 8). This is tracked as a later task. Until then, the PRD (§1, §8), the implementation plan and the design spec still say "macOS 26+"; they should be updated when the product owner confirms this scope change.

## D-011 Screenshot default shortcut is ⌘⇧8 — Accepted (2026-11-18)
The product owner chose ⌘⇧8 as the default screenshot shortcut, replacing the PRD's proposed ⌘⇧2. `AppSettings.screenshotShortcut` now uses `KeyCombo.keyCode8`. Apple's default screenshot shortcuts are ⌘⇧3, ⌘⇧4 and ⌘⇧5, so ⌘⇧8 is not expected to collide. This was checked against Apple's documented defaults, not by querying the live system; M1 conflict checking should still verify it at runtime. The recording (⌘⇧3) and Quick Copy (⌘⇧C) defaults are unchanged, and D-004 still applies to recording.

*M1 update to D-004:* the shortcut validator now reports `⌘⇧3` as a system shortcut in Settings > Shortcuts. The recording shortcut is still not registered (recording arrives in M7), so nothing collides at runtime today. The product owner still needs to pick the recording default.

## D-012 Screenshots are saved as PNG to `~/Pictures/captAI` — Accepted for M1 (2026-11-18)
M1 has no clipboard, OCR or assistant yet, so a finished selection is written as a PNG named `captAI yyyy-MM-dd 'at' HH.mm.ss.png` (with ` 2`, ` 3` on collisions) in the `screenshotFolderPath` setting if set, else `~/Pictures/captAI`. Settings > Storage only displays the folder; it cannot be changed in the UI yet. Writes go to a temp file and are moved into place, so a failed save never leaves a partial image. The menu offers "Reveal Last Capture".
*Open:* M6 replaces this with the library; whether files then stay in the folder is decided there.

## D-013 Selection is limited to the display where the drag starts — Superseded by D-017 (2026-11-18)
The plan (§9) allows constraining a selection to one display. Spanning displays would need stitching images of different scales. The drag is clamped to the starting display; stitching is not planned.
*Superseded:* the product owner chose to allow selections across displays after the first manual run (D-017).

## D-014 Capture uses ScreenCaptureKit with exclusion by window ID; overlay is also `sharingType = .none` — Accepted for M1
The still is taken with `SCScreenshotManager` for one display and a pixel-aligned `sourceRect`, excluding the overlay windows by `windowID`. Cursor is not captured. Region math is a pure function (`DisplayLayout.captureRegion`) that floors the minimum edges and ceils the maximum edges, so the PNG always covers the selection and is never smaller by a pixel.
*Unverified:* real exclusion and pixel alignment on mixed-scale displays (TEST_MATRIX M1 items 3 and 4).

## D-015 Global shortcuts use Carbon `RegisterEventHotKey`; conflicts checked against live system shortcuts with a fallback — Accepted for M1
`RegisterEventHotKey` needs no Accessibility or Input Monitoring permission and works while another app is frontmost. Before registering, `CopySymbolicHotKeys` is read for enabled system shortcuts; if that call fails (it does inside the agent sandbox), Apple's documented defaults are used and the issue text says it was not verified live. A shortcut without a modifier is rejected, a duplicate of another captAI shortcut is rejected, and registration failure is shown as "unavailable" rather than assumed to work. Only shortcuts for modes that have an action are registered (screenshot in M1).

## D-016 Screen Recording granted at the prompt may need a relaunch — Accepted for M1 (resolves KI-005)
When a request leaves the permission not granted, the coordinator reports `permissionPendingRelaunch`; the alert offers Open System Settings, **Relaunch captAI**, or Cancel. Relaunch starts a new instance through `NSWorkspace` and quits the current one.

## D-017 Selections may span displays; output uses the highest scale involved — Accepted (2026-11-18, supersedes D-013)
The product owner chose to allow selections across displays. A drag can start on any display and cross into others, bounded by the area covered by all displays. The selection is captured as one slice per display, each taken with ScreenCaptureKit at the output size, then composited into one image.
*Output scale:* the highest backing scale among the displays touched, so no selected edge is lost. Lower-scale slices are upscaled, so text on a 1x display looks softer in a 2x output.
*Gaps:* if the arrangement is not rectangular, area not covered by any display is filled with opaque black.
*Metadata:* `CaptureMetadata.displayIDs` lists every display used.
*Unverified:* seams, scale accuracy and timing between slices on real mixed-scale displays (TEST_MATRIX "Manual: M1" item 4).

## D-018 Quick Copy reads text with Vision and lays it out in reading order, offline — Accepted for M2 (2026-11-18)
Recognition runs through `VNRecognizeTextRequest` on the Mac (Fast or Accurate per settings). With no languages chosen, `automaticallyDetectsLanguage` is on, because Vision does not detect the language by default (found in testing: Japanese and Chinese came back empty without it). Fast mode supports only English, French, Italian, German, Spanish and Portuguese, so CJK text needs Accurate. Fragments are converted to image pixels with a top-left origin, then grouped into lines by vertical overlap, sorted left to right, and joined with spaces, or tabs across wide gaps. Indentation is approximated from horizontal position. Identical text in the same place is treated as a duplicate and dropped.
*Clipboard rule:* the pasteboard is written only when there is text. A blank capture, no text, or a failed recognition leaves the previous clipboard contents unchanged.
*Unverified:* accuracy of reading order on real content and OCR speed (TEST_MATRIX "Manual: M2").

## D-019 Quick Copy default shortcut is ⇧⌘H — Accepted (2026-11-19)
The product owner chose ⇧⌘H as the default Quick Copy shortcut, replacing the PRD's proposed ⇧⌘C (KI-019). `AppSettings.quickCopyShortcut` now uses `KeyCombo.keyCodeH`. Settings saved before this change keep whatever value they hold; only new installs and Restore Defaults get ⇧⌘H.
*Known conflict:* Finder uses ⇧⌘H for Go > Home. While captAI runs, its global hotkey takes precedence in Finder. The validator does not check other apps' shortcuts (KI-019).

## D-020 No OCR language picker; recognition detects the language automatically — Accepted (2026-11-19)
The product owner decided a language picker is not needed because `automaticallyDetectsLanguage` is on when no languages are chosen (D-018). PRD FR-O01 asks for language choices only "where practical", so this is treated as met. The stored `ocrLanguages` setting stays as a hidden override. Fast mode still reads only six Latin-script languages, so other languages need Accurate.

## D-021 A screenshot saves its PNG and opens a workspace; one workspace at a time — Accepted for M3 (2026-11-19)
After the drag, the capture is saved exactly as in M1 (D-012) and then shown frozen at the screen rectangle it came from, with the assistant panel beside it (PRD Journey A). Dimming has already cleared. Quick Copy is unchanged and never opens a workspace. Only one workspace exists: a new screenshot replaces the previous one when it completes, and a cancelled screenshot leaves the old one open. Both workspace windows are kept out of other apps' captures (`sharingType = .none`) and are also excluded by window number from every later screenshot and Quick Copy, so the assistant's text is never read back by OCR. The frozen image is a copy, so changes in the original app never alter it, and the workspace never captures the live screen again.
*Display changes:* the workspace closes when the display arrangement changes, like the selection overlay, because its saved geometry would no longer match.
*Unverified:* behavior over full-screen Spaces, and window ordering and focus (TEST_MATRIX "Manual: M3").

## D-022 Assistant panel design and behavior — Accepted for M3 (2026-11-19)
*Window:* a borderless, resizable `NSPanel` hosting SwiftUI, movable by its background and header. Opens at 340 × 400 pt (product owner, 2026-11-19; the Design Spec's 400 pt width and 720 pt height were the earlier default), shorter only when the visible height minus 48 pt is less. The user can resize between 340 and 600 pt wide, up to the visible height tall, always at least 16 pt inside the visible frame (Design Spec section 3).
*Placement* (`PanelPlacer`): right of the capture with a 12 pt gap, then left, then above or below (shortened if needed, never under 320 pt tall), then a screen edge. A capture whose larger side is under 150 pt gets an edge placement instead of attaching to it. If nothing fits, as with a full-screen capture, the panel covers part of the capture rather than leave the screen.
*Look:* one semi-transparent Liquid Glass window (`glassEffect`) around the whole assistant, so the header, composer and footer text always sit on the window and never on whatever is behind it. The first version put glass on separate bars over a transparent window, and the footer became unreadable over busy content (product owner, 2026-11-19). Controls inside the window are flat (borderless, bordered, prominent) because glass on glass is hard to read. The analysis and conversation sit on a card that is 90% opaque, and fully opaque with Reduce Transparency on.
*Pin* means "stay on top": pinned (the default) puts both windows at floating level; unpinned makes them ordinary windows that other apps can cover.
*Focus:* the assistant activates the app and takes keyboard focus so the composer works at once; closing restores the app that was frontmost. Esc closes. Return sends and Shift+Return adds a line at the end of the draft (the composer inserts it itself, because the text view would select all; the insertion point is not used, a known limit). Clicking either window raises both (capture below, assistant on top); a click on the capture, which cannot take focus itself, also activates the app and makes the assistant key (product owner, 2026-11-19). The capture is not raised while hidden.
*Border:* the frozen capture's outline is a setting (Settings > Capture & Recording > Screenshot border): system accent color by default or a custom opaque sRGB color, and a width of 0 to 8 pt in 0.5 pt steps (1 pt by default, 0 for none). The outline is drawn inside the capture's bounds so the window stays where the capture was taken. It is read when a workspace opens, so a change applies to the next screenshot.
*Not done:* minimize, zoom/fit and detach of the capture (optional in the plan), and a stored panel position (nothing is reopened yet, so the panel keeps its own position for the life of the session).

## D-023 Analysis is a labelled mock behind a small seam — Accepted for M3 (2026-11-19)
`AnalysisSource` streams text chunks for a request and describes itself (name, detail, mock or not, local or cloud). `MockAnalysisSource` is the only implementation: it streams fixed text, never touches the network, and the assistant labels its output "Mock analysis" with a "Local" badge so it is never mistaken for a model. Errors cross the seam as `AppError`; any other error is shown as `analysisFailed`. M4 replaces this with the real provider protocol (images, cancellation, consent), so this seam is deliberately minimal and will change. A blank capture is never sent for analysis.

## D-024 Cloud consent is decided per request by a pure rule; secrets live in the Keychain — Accepted for M4 sub-PR 1 (2026-11-20)
`CloudConsent.decision` returns `proceed`, `askFirst` or `refuse` from the source's locality, the consent policy and the set of approved provider IDs. Local sources always proceed. `localOnly` refuses cloud requests. `askEveryTime` asks for every cloud request, and approval never carries over. `askOncePerProvider` asks until that provider ID is approved. Approval is keyed by a stable provider ID, not a display name. API keys go through the `SecretStore` protocol, implemented by `KeychainSecretStore` (generic passwords, this-device-only, never synced). Keys are never in settings, logs or exports.

## D-025 Ollama adapter: `/api/chat` with a vision check first; locality follows the endpoint — Accepted for M4 sub-PR 2 (2026-11-20)
The adapter streams newline-delimited JSON from `POST /api/chat` and sends the screenshot as base64 on the first user message, so follow-ups see the image once. Before any image is sent, `POST /api/show` is checked: a model whose `capabilities` list lacks `vision` is rejected. Servers that report no capabilities are allowed through, because the check cannot be made. Locality follows the endpoint host: loopback is local, any other host is cloud, and a remote Ollama gets its own provider ID so consent never carries over from the local one. Network access goes through an `HTTPTransport` seam, so the tests run on scripted responses. A missing model (404), auth, rate-limit, server and malformed-line errors map to their own `AppError` cases; error text from the server is never shown.
*Not yet covered:* cancellation of an in-flight Ollama request is wired (task cancellation ends the stream) but has no test; the stop button arrives in sub-PR 6.
*Wire check (2026-11-20, agent, curl against the owner's Ollama):* `gemma4:e4b-mlx` reports `completion, vision, audio, tools, thinking`. `/api/chat` with a base64 PNG streams NDJSON: it first sends `message.thinking` chunks with empty `content`, then the answer in `content`, then `done: true` with `done_reason: stop`. The adapter reads only `content`, so thinking is never shown or stored. A short image took about 5 seconds end to end.

