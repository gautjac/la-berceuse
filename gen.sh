#!/usr/bin/env bash
# Regenerate LaBerceuse.xcodeproj from project.yml (and refresh the app icon set).
#
# La Berceuse is iOS-only — a single iOS scheme resolves a simulator destination
# directly. No watch/mac variant.
set -euo pipefail
cd "$(dirname "$0")"

# Keep the opaque app-icon set fresh (a missing/alpha icon = install failure).
if command -v python3 >/dev/null 2>&1; then
  python3 scripts/gen-appicon.py >/dev/null || echo "warn: icon gen skipped"
fi

/opt/homebrew/bin/xcodegen generate --spec project.yml
echo "Generated LaBerceuse.xcodeproj"
