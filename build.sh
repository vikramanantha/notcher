#!/bin/bash
# Builds build/Notcher.app: the Swift app plus the bundled mediaremote-adapter.
# Usage: ./build.sh [--run]
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Notcher.app
ADAPTER=Vendor/mediaremote-adapter
FRAMEWORK="$APP/Contents/Frameworks/MediaRemoteAdapter.framework"

echo "==> Building Swift app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Notcher"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$FRAMEWORK/Versions/A/Resources"
cp "$BIN" "$APP/Contents/MacOS/Notcher"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$ADAPTER/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"

echo "==> Building MediaRemoteAdapter.framework"
# The framework is loaded by /usr/bin/perl at runtime, never linked into the app.
clang -dynamiclib -fobjc-arc -fvisibility=default -O2 -w \
  -mmacosx-version-min=14.0 \
  -I"$ADAPTER/include" -I"$ADAPTER/src" \
  "$ADAPTER"/src/adapter/*.m "$ADAPTER"/src/private/*.m "$ADAPTER"/src/utility/*.m \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/MediaRemoteAdapter \
  -o "$FRAMEWORK/Versions/A/MediaRemoteAdapter"
cat > "$FRAMEWORK/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
	<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
	<key>CFBundleName</key><string>MediaRemoteAdapter</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>CFBundleVersion</key><string>0.1.0</string>
</dict>
</plist>
PLIST
ln -s A "$FRAMEWORK/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$FRAMEWORK/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$FRAMEWORK/Resources"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$FRAMEWORK"
codesign --force --sign - "$APP"

echo "==> Done: $APP"

if [[ "${1:-}" == "--run" ]]; then
  pkill -x Notcher 2>/dev/null || true
  open "$APP"
fi
