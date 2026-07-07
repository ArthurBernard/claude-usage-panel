#!/usr/bin/env bash
# Build a distributable ClaudeUsagePanel.app bundle (menu-bar agent, no Dock icon).
# Run on macOS with the Swift toolchain / Xcode installed.
set -euo pipefail

APP="ClaudeUsagePanel"
BUNDLE="$APP.app"
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

echo "Building release binary…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP"

echo "Assembling $BUNDLE…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Claude Usage Panel</string>
  <key>CFBundleDisplayName</key><string>Claude Usage Panel</string>
  <key>CFBundleIdentifier</key><string>io.github.fschmutz.claude-usage-panel</string>
  <key>CFBundleVersion</key><string>1.3.1</string>
  <key>CFBundleShortVersionString</key><string>1.3.1</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

echo "Done: $HERE/$BUNDLE"
echo "Run it:   open '$BUNDLE'"
echo "Sign it:  codesign --deep --force --sign - '$BUNDLE'   # ad-hoc; see PUBLISHING.md for notarization"
