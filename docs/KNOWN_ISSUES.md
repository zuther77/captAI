# Known issues

| ID | Milestone | Severity | Issue | Status |
|---|---|---|---|---|
| KI-001 | M0 | Medium | `captAIUITests` could not run in the agent environment: the UI-test runner aborted with "Test crashed with signal abrt before establishing connection". | Resolved 2026-11-18: all 6 UI tests pass on a real Mac. A first run failed 4 tests because they found the Settings window by title; the window now has the identifier `settings.window`. UI tests still cannot run inside the agent sandbox; run `scripts/test.sh ui` on a Mac. |
| KI-002 | M0 | Low | Only Xcode 27 beta / macOS 27.3 was available. The deployment target is now macOS 27.0 (D-010), so the app is not expected to run on macOS 26. | Deferred: backwards compatibility to macOS 26 is a later task (see D-010). |
| KI-003 | M0 | Low | App icon set is empty (placeholder). The menu-bar icon uses the SF Symbol `camera.viewfinder`. | Open: design asset needed before M10. |
| KI-004 | M0 | Low | `Config/Shared.xcconfig` signs ad-hoc, so an ad-hoc build gets a new identity each time and macOS may re-prompt for Screen Recording because TCC ties the grant to the signature. | Mitigated: the project targets are set to Apple Development signing with the owner's team, which keeps the grant stable. Not yet observed across several rebuilds. A fresh clone needs its own team in Xcode. |
| KI-005 | M0 | Low | Granting Screen Recording through the system prompt usually takes effect only after relaunching captAI. The Privacy pane can still show "Not requested" or "Denied" until then. | Open: add a "Relaunch captAI" affordance in M1 when the status changes. |
| KI-006 | M0 | Info | Building inside another macOS sandbox (some CI runners, agent harnesses) fails with "external macro implementation type ... produced malformed response". | Workaround: `CAPTAI_DISABLE_SWIFT_SANDBOX=1 scripts/build.sh`. Not needed on a normal developer Mac (unverified there). |
| KI-007 | M0 | Low | Shortcut display names only cover ANSI letters and digits; other keys show as `Key <code>`. | Open: the M1 shortcut recorder will map keys through the active keyboard layout. |
| KI-008 | M0 | Info | `⌘⇧3` default for recording collides with the macOS screenshot shortcut. See DECISIONS D-004. | Awaiting product-owner decision. |
| KI-009 | M0 | Info | `Tests/Fixtures/` is empty. OCR and video fixtures arrive with M2 and M7. | Expected. |
