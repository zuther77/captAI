#!/usr/bin/env bash
# Runs automated tests. Usage: scripts/test.sh [unit|integration|ui|all]   (default: unit + integration)
#
# UI tests drive the real app through Accessibility, so they need a logged-in graphical session and
# Xcode's UI-test runner must be allowed under System Settings > Privacy & Security > Accessibility.
source "$(dirname "$0")/common.sh"

SUITE="${1:-fast}"
ONLY=()
case "$SUITE" in
  unit)        ONLY=(-only-testing:captAIUnitTests) ;;
  integration) ONLY=(-only-testing:captAIIntegrationTests) ;;
  ui)          ONLY=(-only-testing:captAIUITests) ;;
  fast)        ONLY=(-only-testing:captAIUnitTests -only-testing:captAIIntegrationTests) ;;
  all)         ;;
  *) echo "Unknown suite: $SUITE (use unit|integration|ui|fast|all)" >&2; exit 2 ;;
esac

RESULT="$ROOT/build/TestResults-$SUITE.xcresult"
rm -rf "$RESULT"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'platform=macOS' \
  -resultBundlePath "$RESULT" \
  ${XCODEBUILD_EXTRA[@]+"${XCODEBUILD_EXTRA[@]}"} \
  ${ONLY[@]+"${ONLY[@]}"} \
  test | pretty
