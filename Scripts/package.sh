#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/build.sh
app="build/Lyrix.app"
rm -rf "$app" "build/Lyrix-0.1.0.zip"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Lyrix "$app/Contents/MacOS/Lyrix"
cp Resources/Demo/demo.lrc "$app/Contents/Resources/demo.lrc"
iconset="build/Lyrix.iconset"
mkdir -p "$iconset"
swift Scripts/make-icon.swift "$iconset/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  if (( size < 512 )); then sips -z "$((size*2))" "$((size*2))" "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null; fi
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Lyrix.icns"
rm -rf "$iconset"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.lyrix.app</string>
<key>CFBundleName</key><string>Lyrix</string>
<key>CFBundleDisplayName</key><string>Lyrix</string>
<key>CFBundleExecutable</key><string>Lyrix</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>Lyrix</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><false/>
<key>NSAppleEventsUsageDescription</key><string>Lyrix displays Spotify track metadata in its menu bar. Spotify timing does not control lyrics.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" build/Lyrix-0.1.0.zip
