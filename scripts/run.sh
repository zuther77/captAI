#!/usr/bin/env bash
# Builds (Debug) and launches captAI. It is a menu-bar app: look for the camera icon in the menu bar.
source "$(dirname "$0")/common.sh"

"$ROOT/scripts/build.sh" Debug
open "$DERIVED_DATA/Build/Products/Debug/captAI.app"
