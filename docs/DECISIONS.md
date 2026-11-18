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

## D-008 Toolchain and deployment target — Accepted, with a verification gap
Built with Xcode 27 beta (Swift 6.4, macOS 27.0 SDK) on macOS 27.3, deployment target 26.0, Swift 6 language mode, strict concurrency complete, warnings as errors. Nothing has been run on a macOS 26 machine; see KNOWN_ISSUES KI-002. M0 uses only system chrome, which receives Liquid Glass automatically. Explicit `glassEffect` use begins in M3 and must be verified against the SDK then.

## D-009 `@Observable` and `MenuBarExtra` — Accepted
The Observation framework and SwiftUI `MenuBarExtra` keep M0 free of third-party dependencies. The Settings window is an AppKit `NSWindow` hosting SwiftUI, owned by `WindowCoordinator`, so later panels and HUDs share one lifecycle owner (plan §4).
