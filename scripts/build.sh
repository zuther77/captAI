#!/usr/bin/env bash
# Builds captAI. Usage: scripts/build.sh [Debug|Release]
source "$(dirname "$0")/common.sh"

CONFIGURATION="${1:-Debug}"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  ${XCODEBUILD_EXTRA[@]+"${XCODEBUILD_EXTRA[@]}"} \
  build | pretty

echo "Built: $DERIVED_DATA/Build/Products/$CONFIGURATION/captAI.app"
