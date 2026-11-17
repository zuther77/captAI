#!/usr/bin/env bash
# Shared settings for the captAI helper scripts. Source this file; do not execute it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/captAI.xcodeproj"
SCHEME="captAI"
DERIVED_DATA="$ROOT/build/DerivedData"

# Extra xcodebuild arguments. Normal developer machines need none.
#
# CAPTAI_DISABLE_SWIFT_SANDBOX=1 passes -disable-sandbox to swiftc. It is only needed when xcodebuild itself
# runs inside another macOS sandbox (for example some CI runners or agent harnesses), where the nested
# sandbox-exec used by Swift macro plugins (@Observable, @State) is refused and the build fails with
# "external macro implementation type ... could not be found ... produced malformed response".
XCODEBUILD_EXTRA=()
if [[ "${CAPTAI_DISABLE_SWIFT_SANDBOX:-0}" == "1" ]]; then
  XCODEBUILD_EXTRA+=(OTHER_SWIFT_FLAGS=-disable-sandbox)
fi

# Pipes through xcbeautify when installed, otherwise raw output.
pretty() {
  if command -v xcbeautify >/dev/null 2>&1; then xcbeautify; else cat; fi
}
