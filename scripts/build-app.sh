#!/bin/sh
# Build ClauthBar.app from the Swift package. The Xcode Command Line Tools are
# enough for a native build; a universal build (UNIVERSAL=1) needs full Xcode.
#
#   scripts/build-app.sh            # -> build/ClauthBar.app
#   scripts/build-app.sh --install  # also copies to ~/Applications and launches it
#   scripts/build-app.sh --zip      # also writes build/ClauthBar-<version>.zip
#
# Env: VERSION (default: latest git tag without the "v", else 0.0.0-dev),
#      UNIVERSAL=1 for an arm64 + x86_64 binary.
set -eu

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/ClauthBar.app"
BUNDLE_ID="com.raccoonv.clauthbar"
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

if [ "${UNIVERSAL:-0}" = "1" ]; then
  ARCH_FLAGS="--arch arm64 --arch x86_64"
else
  ARCH_FLAGS=""
fi

# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS
# shellcheck disable=SC2086
BIN="$(swift build -c release $ARCH_FLAGS --show-bin-path)/ClauthBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClauthBar"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>ClauthBar</string>
  <key>CFBundleDisplayName</key><string>ClauthBar</string>
  <key>CFBundleExecutable</key><string>ClauthBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for local use and launch-at-login. Not notarized.
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP ($VERSION)"

for arg in "$@"; do
  case "$arg" in
    --zip)
      ZIP="$ROOT/build/ClauthBar-$VERSION.zip"
      rm -f "$ZIP"
      ditto -c -k --keepParent "$APP" "$ZIP"
      echo "Zipped $ZIP"
      ;;
    --install)
      DEST="$HOME/Applications/ClauthBar.app"
      mkdir -p "$HOME/Applications"
      pkill -x ClauthBar 2>/dev/null || true
      rm -rf "$DEST"
      cp -R "$APP" "$DEST"
      open "$DEST"
      echo "Installed and launched $DEST"
      ;;
  esac
done
