#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
make -B -C Vendor/m1ddc CFLAGS="-Wall -Werror -Wextra -fmodules -mmacosx-version-min=14.0" LDLIBS="-framework CoreDisplay -mmacosx-version-min=14.0"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/Display Wizard.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DisplayWizard" "$APP/Contents/MacOS/DisplayWizard"
cp Vendor/m1ddc/m1ddc "$APP/Contents/Resources/"
if [ -f Assets/AppIcon.png ]; then cp Assets/AppIcon.png "$APP/Contents/Resources/"; fi
if [ -f Assets/AppIcon.icns ]; then cp Assets/AppIcon.icns "$APP/Contents/Resources/"; fi
if [ -f Vendor/m1ddc/LICENSE ]; then cp Vendor/m1ddc/LICENSE "$APP/Contents/Resources/m1ddc-LICENSE"; fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DisplayWizard</string>
<key>CFBundleIdentifier</key><string>com.local.displaywizard</string>
<key>CFBundleName</key><string>Display Wizard</string>
<key>CFBundleDisplayName</key><string>Display Wizard</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.8.0</string>
<key>CFBundleVersion</key><string>9</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
printf 'Built %s\n' "$PWD/$APP"
