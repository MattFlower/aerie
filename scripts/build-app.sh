#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch="${AERIE_BUILD_SCRATCH:-.build}"
revision="$(git rev-parse HEAD 2>/dev/null || printf 'unversioned')"
source_modified=false
if [[ "$revision" == unversioned ]] || [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  source_modified=true
fi
swift build --scratch-path "$scratch" --build-system native -c release --product Aerie
app="${AERIE_APP_OUTPUT:-dist/Aerie.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp THIRD_PARTY_NOTICES.md "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$scratch/release/Aerie" "$app/Contents/MacOS/Aerie"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Aerie</string>
<key>CFBundleDisplayName</key><string>Aerie</string>
<key>CFBundleIdentifier</key><string>app.aerie.monitor</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleExecutable</key><string>Aerie</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSCalendarsFullAccessUsageDescription</key><string>Show your upcoming calendar events locally in the Aerie time menu.</string>
<key>NSLocationWhenInUseUsageDescription</key><string>Choose one Mac location for Weather and Daylight, or allow macOS to reveal Wi-Fi network names. Location is requested only when you choose Use My Mac Location.</string>
<key>NSLocationUsageDescription</key><string>Choose one Mac location for Weather and Daylight, or allow macOS to reveal Wi-Fi network names. Location is requested only when you choose Use My Mac Location.</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :AerieSourceRevision string $revision" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :AerieSourceModified bool $source_modified" "$app/Contents/Info.plist"
# Finder can annotate a generated bundle directory; that metadata invalidates strict signing.
# Only this build output's FinderInfo is removed; other attributes are preserved.
if [[ "$(/usr/bin/xattr "$app")" == *com.apple.FinderInfo* ]]; then
  /usr/bin/xattr -d com.apple.FinderInfo "$app"
fi
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
current_revision="$(git rev-parse HEAD 2>/dev/null || printf 'unversioned')"
if [[ "$current_revision" != "$revision" ]]; then
  printf 'Source revision changed during build; rebuild before launching.\n' >&2
  exit 1
fi
if [[ "$source_modified" == false ]] && [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  printf 'Source files changed during build; rebuild before launching.\n' >&2
  exit 1
fi
python3 scripts/check-app-build.py "$app" --write-receipt --revision "$revision" --modified "$source_modified"
printf 'Built %s from %s\n' "$app" "$revision"
printf 'Before launch: python3 scripts/check-app-build.py "%s"\n' "$app"
