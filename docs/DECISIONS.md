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

## D-013 Selection is limited to the display where the drag starts — Accepted for M1
The plan (§9) allows constraining a selection to one display. Spanning displays would need stitching images of different scales. The drag is clamped to the starting display; stitching is not planned.

## D-014 Capture uses ScreenCaptureKit with exclusion by window ID; overlay is also `sharingType = .none` — Accepted for M1
The still is taken with `SCScreenshotManager` for one display and a pixel-aligned `sourceRect`, excluding the overlay windows by `windowID`. Cursor is not captured. Region math is a pure function (`DisplayLayout.captureRegion`) that floors the minimum edges and ceils the maximum edges, so the PNG always covers the selection and is never smaller by a pixel.
*Unverified:* real exclusion and pixel alignment on mixed-scale displays (TEST_MATRIX M1 items 3 and 4).

## D-015 Global shortcuts use Carbon `RegisterEventHotKey`; conflicts checked against live system shortcuts with a fallback — Accepted for M1
`RegisterEventHotKey` needs no Accessibility or Input Monitoring permission and works while another app is frontmost. Before registering, `CopySymbolicHotKeys` is read for enabled system shortcuts; if that call fails (it does inside the agent sandbox), Apple's documented defaults are used and the issue text says it was not verified live. A shortcut without a modifier is rejected, a duplicate of another captAI shortcut is rejected, and registration failure is shown as "unavailable" rather than assumed to work. Only shortcuts for modes that have an action are registered (screenshot in M1).

## D-016 Screen Recording granted at the prompt may need a relaunch — Accepted for M1 (resolves KI-005)
When a request leaves the permission not granted, the coordinator reports `permissionPendingRelaunch`; the alert offers Open System Settings, **Relaunch captAI**, or Cancel. Relaunch starts a new instance through `NSWorkspace` and quits the current one.

