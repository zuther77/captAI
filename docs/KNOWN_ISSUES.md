# Known issues

| ID | Milestone | Severity | Issue | Status |
|---|---|---|---|---|
| KI-001 | M0 | Medium | `captAIUITests` could not run in the agent environment: the UI-test runner aborted with "Test crashed with signal abrt before establishing connection". The 6 UI tests compile but have **never executed**. | Open: run `scripts/test.sh ui` on a real Mac session. |
| KI-002 | M0 | Medium | Only Xcode 27 beta / macOS 27.3 was available. The app targets macOS 26.0 but has not been launched on macOS 26. | Open: verify on a macOS 26 machine before M10. |
| KI-003 | M0 | Low | App icon set is empty (placeholder). The menu-bar icon uses the SF Symbol `camera.viewfinder`. | Open: design asset needed before M10. |
| KI-004 | M0 | Low | Default signing is ad-hoc. macOS may re-prompt for Screen Recording after rebuilds because TCC ties the grant to the signature. | Mitigation: copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set your team. |
| KI-005 | M0 | Low | Granting Screen Recording through the system prompt usually takes effect only after relaunching captAI. The Privacy pane can still show "Not requested" or "Denied" until then. | Open: add a "Relaunch captAI" affordance in M1 when the status changes. |
| KI-006 | M0 | Info | Building inside another macOS sandbox (some CI runners, agent harnesses) fails with "external macro implementation type ... produced malformed response". | Workaround: `CAPTAI_DISABLE_SWIFT_SANDBOX=1 scripts/build.sh`. Not needed on a normal developer Mac (unverified there). |
| KI-007 | M0 | Low | Shortcut display names only cover ANSI letters and digits; other keys show as `Key <code>`. | Open: the M1 shortcut recorder will map keys through the active keyboard layout. |
| KI-008 | M0 | Info | `⌘⇧3` default for recording collides with the macOS screenshot shortcut. See DECISIONS D-004. | Awaiting product-owner decision. |
| KI-009 | M0 | Info | `Tests/Fixtures/` is empty. OCR and video fixtures arrive with M2 and M7. | Expected. |
