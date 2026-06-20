#!/usr/bin/env bash
# Build La Berceuse (Release) and install it to a connected iPhone.
#
# Why this script exists (two traps the Atelier native apps hit):
#   1. iCloud xattrs: code that lives under iCloud Drive gets extended
#      attributes stamped on every file, and `codesign` refuses to sign a bundle
#      containing them ("resource fork, Finder information, or similar detritus
#      not allowed"). FIX: keep the build output OUT of iCloud -> DerivedData in
#      /tmp. (This repo already lives outside iCloud at ~/Claude/apps, but the
#      /tmp DerivedData rule is kept for belt-and-suspenders.)
#   2. Debug "debug dylib": modern Debug builds produce a stub executable that
#      loads a *.debug.dylib and expects to be launched by Xcode, which can fail
#      to install standalone. FIX: build the RELEASE configuration.
#
# Requirements: iPhone connected & unlocked, Developer Mode ON, signed in to
# Jac's Apple Developer account (team 9WZ66DZ69J).
set -euo pipefail
cd "$(dirname "$0")"

DD="${LABERCEUSE_DD:-/tmp/la-berceuse-rel}"   # DerivedData OUTSIDE iCloud

echo "==> Generating project…"
./gen.sh >/dev/null

echo "==> Building Release for device…"
xcodebuild -project LaBerceuse.xcodeproj -scheme "LaBerceuse" \
  -configuration Release -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates -derivedDataPath "$DD" build

APP="$DD/Build/Products/Release-iphoneos/La Berceuse.app"
[[ -d "$APP" ]] || { echo "Build product not found at $APP" >&2; exit 1; }

# Find the first *connected* iPhone (devicectl identifier).
PHONE="$(xcrun devicectl list devices 2>/dev/null \
  | awk -F'  +' '/iPhone/ && /connected/ {print $3; exit}')"
[[ -n "${PHONE:-}" ]] || { echo "No connected iPhone found (connect & unlock it)." >&2; exit 1; }
echo "==> Installing to iPhone $PHONE …"

xcrun devicectl device uninstall app --device "$PHONE" app.atelier.laberceuse >/dev/null 2>&1 || true
xcrun devicectl device install app --device "$PHONE" "$APP"

echo
echo "==> La Berceuse (Release) installed. Open it, dim the lights, and breathe."
