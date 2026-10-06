#!/bin/bash
# Builds TrackIt.app into ./build. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/TrackIt.app"

echo "▸ Compiling (release)…"
swift build -c release

if [ ! -f Resources/AppIcon.icns ]; then
  echo "▸ Rendering app icon…"
  mkdir -p build/AppIcon.iconset
  swift scripts/make_icon.swift build/icon_1024.png >/dev/null
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/TrackIt" "$APP/Contents/MacOS/TrackIt"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null 2>&1
echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x TrackIt 2>/dev/null || true
  sleep 0.3
  rm -rf /Applications/TrackIt.app
  cp -R "$APP" /Applications/
  echo "✓ Installed to /Applications/TrackIt.app"
  open /Applications/TrackIt.app
fi
