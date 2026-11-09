#!/bin/zsh
# Builds build/StemSeparator.app with swiftc (no Xcode project needed).
# Pass --install to also copy it to /Applications (replaces any existing copy).
set -euo pipefail
cd "$(dirname "$0")"
APP=build/StemSeparator.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -framework AppKit -framework SwiftUI \
  Sources/*.swift -o "$APP/Contents/MacOS/StemSeparator"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'tell application "StemSeparator" to quit' 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/StemSeparator.app
  ditto "$APP" /Applications/StemSeparator.app
  echo "Installed to /Applications/StemSeparator.app"
fi
