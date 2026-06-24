#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Dex"
LEGACY_APP_NAME="Nile"
BUNDLE_ID="com.neilsanghrajka.Dex"
MIN_SYSTEM_VERSION="14.0"
DEFAULT_LOCAL_SIGNING_IDENTITY="Dex Local Development"
REQUESTED_SIGNING_IDENTITY="${DEX_CODESIGN_IDENTITY:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PUBLISHED_APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
BUILD_ROOT="${TMPDIR:-/private/tmp}/dex-build-$$"
APP_BUNDLE="$BUILD_ROOT/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "$LEGACY_APP_NAME" >/dev/null 2>&1 || true

swift build
BIN_PATH="$(swift build --show-bin-path)"
BUILD_BINARY="$BIN_PATH/$APP_NAME"

rm -rf "$BUILD_ROOT"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

RESOURCE_BUNDLE="$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi

if [ -f "$ROOT_DIR/Assets/AppIcon/AppIcon.icns" ]; then
  cp "$ROOT_DIR/Assets/AppIcon/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Dex uses Automation to list and focus Dia browser tabs in the Arrange Board.</string>
PLIST

if [ -f "$APP_RESOURCES/AppIcon.icns" ]; then
cat >>"$INFO_PLIST" <<PLIST
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
PLIST
fi

cat >>"$INFO_PLIST" <<PLIST
</dict>
</plist>
PLIST

if [ -x /usr/bin/xattr ]; then
  /usr/bin/xattr -rc "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

find_codesign_identity() {
  local requested="$1"
  if [ -n "$requested" ]; then
    printf '%s\n' "$requested"
    return 0
  fi

  /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/awk -F '"' -v name="$DEFAULT_LOCAL_SIGNING_IDENTITY" '$2 == name { print $2; found=1; exit } END { exit(found ? 0 : 1) }'
}

sign_app() {
  local identity
  if identity="$(find_codesign_identity "$REQUESTED_SIGNING_IDENTITY")"; then
    /usr/bin/codesign --force --deep --sign "$identity" "$APP_BUNDLE"
    echo "Signed $APP_NAME with stable identity: $identity"
  else
    /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
    echo "warning: Signed $APP_NAME ad-hoc. macOS Privacy permissions may not survive rebuilds." >&2
    echo "warning: Create a local Code Signing certificate named '$DEFAULT_LOCAL_SIGNING_IDENTITY' or set DEX_CODESIGN_IDENTITY." >&2
  fi
}

sign_app

clean_bundle_metadata() {
  if [ -x /usr/bin/xattr ]; then
    /usr/bin/xattr -rc "$APP_BUNDLE" >/dev/null 2>&1 || true
    /usr/bin/xattr -rc "$PUBLISHED_APP_BUNDLE" >/dev/null 2>&1 || true
  fi
}

publish_app() {
  rm -rf "$DIST_DIR/$LEGACY_APP_NAME.app"
  rm -rf "$PUBLISHED_APP_BUNDLE"
  if [ -x /usr/bin/ditto ]; then
    /usr/bin/ditto --norsrc "$APP_BUNDLE" "$PUBLISHED_APP_BUNDLE"
  else
    cp -R "$APP_BUNDLE" "$PUBLISHED_APP_BUNDLE"
  fi
}

publish_app

open_app() {
  /usr/bin/open -n "$PUBLISHED_APP_BUNDLE"
  sleep 0.2
  clean_bundle_metadata
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    clean_bundle_metadata
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
