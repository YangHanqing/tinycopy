#!/bin/bash
# Builds Release signed with the local Apple Development identity and installs to /Applications.
# A stable signature matters: macOS remembers the Accessibility permission (needed to paste) by it.
set -euo pipefail
cd "$(dirname "$0")/.."
IDENTITY="${IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)}"
[ -n "$IDENTITY" ] || { echo "no Apple Development identity in keychain" >&2; exit 1; }
# The build number is the minute of the build (yyyyMMddHHmm); the version comes from project.yml.
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
xcodegen generate >/dev/null
xcodebuild -project TinyCopy.xcodeproj -scheme TinyCopy -configuration Release \
  -derivedDataPath build/rel CODE_SIGN_IDENTITY="$IDENTITY" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" build | tail -3
APP=build/rel/Build/Products/Release/TinyCopy.app
[ "$(lipo -archs "$APP/Contents/MacOS/TinyCopy" | tr " " "\n" | sort | xargs)" = "arm64 x86_64" ] || { echo "not universal" >&2; exit 1; }
# TinyCopy quits normally on SIGTERM (it writes its index first). Apple Events from scripts can time out, so no osascript.
if pgrep -x TinyCopy >/dev/null; then
  pkill -TERM -x TinyCopy || true
  for _ in $(seq 50); do pgrep -x TinyCopy >/dev/null || break; sleep 0.1; done
fi
rm -rf /Applications/TinyCopy.app
cp -R "$APP" /Applications/TinyCopy.app
codesign --verify --strict --verbose=2 /Applications/TinyCopy.app
codesign -dv /Applications/TinyCopy.app 2>&1 | grep -E "Authority|TeamIdentifier|Identifier"
PLIST=/Applications/TinyCopy.app/Contents/Info.plist
echo "Installed TinyCopy $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST") ($(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST"))"
# Drop the build-tree copies so Spotlight and the login item see only /Applications/TinyCopy.app.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
while IFS= read -r -d '' app; do
  "$LSREGISTER" -u "$app" 2>/dev/null || true
  rm -rf "$app"
done < <(find build -type d -name TinyCopy.app -prune -print0)
"$LSREGISTER" -f /Applications/TinyCopy.app
[ "${NO_LAUNCH:-}" = 1 ] || open /Applications/TinyCopy.app
