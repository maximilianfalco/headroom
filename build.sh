#!/bin/bash
# Builds, installs to /Applications, and relaunches.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "No .env found. Copy .env.example to .env and edit it." >&2
  exit 1
fi
set -a; . ./.env; set +a

: "${BUNDLE_ID_PREFIX:?BUNDLE_ID_PREFIX missing from .env}"
: "${SIGNING_IDENTITY:?SIGNING_IDENTITY missing from .env}"

APP_NAME=Headroom
INSTALLED="/Applications/$APP_NAME.app"
BUILT="build/Build/Products/Release/$APP_NAME.app"

# xcode-select may point at CommandLineTools, which cannot build app extensions.
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

# Ad-hoc signing changes identity every build, which breaks keychain ACL entries and
# orphans placed widgets. See README > Signing identity.
if ! security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY"; then
  echo "Signing identity '$SIGNING_IDENTITY' not found. See README > Signing identity." >&2
  exit 1
fi

xcodegen generate

xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
  OTHER_CODE_SIGN_FLAGS="--keychain $HOME/Library/Keychains/login.keychain-db" \
  ENABLE_DEBUG_DYLIB=NO \
  build

pkill -f "$APP_NAME.app" 2>/dev/null || true
rm -rf "$INSTALLED"
cp -R "$BUILT" /Applications/

# LaunchServices registers every bundle it finds, so an unregistered build copy leaves
# chronod free to load a stale widget. Keep /Applications as the only known copy.
LSR=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
"$LSR" -u "$PWD/$BUILT" 2>/dev/null || true
"$LSR" -f "$INSTALLED"

killall chronod 2>/dev/null || true
open "$INSTALLED"

echo "Installed and launched. Check the menu bar."
