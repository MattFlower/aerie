#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="${AERIE_BUILD_SCRATCH:-.build}"
swift build --scratch-path "$scratch" --build-system native -c release --product Aerie
app="${AERIE_APP_OUTPUT:-dist/Aerie.app}"
mkdir -p "$app/Contents/MacOS"
cp "$scratch/release/Aerie" "$app/Contents/MacOS/Aerie"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Aerie</string>
<key>CFBundleDisplayName</key><string>Aerie</string>
<key>CFBundleIdentifier</key><string>app.aerie.monitor</string>
<key>CFBundleExecutable</key><string>Aerie</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSCalendarsFullAccessUsageDescription</key><string>Show your upcoming calendar events locally in the Aerie time menu.</string>
<key>NSLocationWhenInUseUsageDescription</key><string>Allow macOS to reveal Wi-Fi network identity in Aerie's Network menu. Aerie does not request your device coordinates.</string>
<key>NSLocationUsageDescription</key><string>Allow macOS to reveal Wi-Fi network identity in Aerie's Network menu. Aerie does not request your device coordinates.</string>
</dict></plist>
PLIST
# Finder can annotate a generated bundle directory; that metadata invalidates strict signing.
# Only this build output's FinderInfo is removed; other attributes are preserved.
if [[ "$(/usr/bin/xattr "$app")" == *com.apple.FinderInfo* ]]; then
  /usr/bin/xattr -d com.apple.FinderInfo "$app"
fi
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
