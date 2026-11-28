# Distribution (M10)

captAI targets a **signed, notarized direct download** for macOS 27+. App Store / sandbox packaging remains an open decision (plan §9, D-003).

## Versioning

- Marketing version: `MARKETING_VERSION` in `captAI.xcodeproj` (currently `0.1.0`).
- Build number: `CURRENT_PROJECT_VERSION` (integer; bump for every distributed build).
- `AppVersion.displayString` reads these from the bundle at runtime.

## Local developer signing

1. Copy `Config/Local.xcconfig.example` → `Config/Local.xcconfig` (gitignored).
2. Set `DEVELOPMENT_TEAM` and prefer Apple Development so Screen Recording TCC stays stable (KI-004).
3. Release builds enable the hardened runtime (`Shared.xcconfig` / project Release settings).

## Release checklist (direct / notarized)

1. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` as needed.
2. `CAPTAI_DISABLE_SWIFT_SANDBOX=1 ./scripts/test.sh all` on a real Mac (unit, integration, UI).
3. Archive in Xcode (Release, Developer ID Application).
4. Notarize and staple (`xcrun notarytool` / `stapler`) for Gatekeeper.
5. Smoke-test the notarized app on a clean Mac: launch, Screen Recording prompt, Quick Copy without a provider, Library search offline.
6. Record known limitations from `docs/KNOWN_ISSUES.md` in the release notes.

## Privacy gates before shipping

- No provider keys or OCR/prompt bodies in ordinary diagnostics (`DiagnosticsTests`).
- Cloud consent cancel leaves zero network upload for that request.
- Quick Copy does not write history unless the user opts in.
- Library Clear All / retention only delete when the user configured or confirmed them.
