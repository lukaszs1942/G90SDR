#!/bin/sh
# Builds G90SDR and wraps it in a .app so macOS will show the microphone permission prompt.
set -e
cd "$(dirname "$0")/.."
swift build -c release
APP=build/G90SDR.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/G90SDR "$APP/Contents/MacOS/G90SDR"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>G90SDR</string>
  <key>CFBundleIdentifier</key><string>com.lukaszs.g90sdr</string>
  <key>CFBundleExecutable</key><string>G90SDR</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>G90SDR reads the radio's audio output to draw the waterfall.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
