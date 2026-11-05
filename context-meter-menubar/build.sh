#!/bin/zsh
# Собирает ContextMeter.app в ~/Applications и перезапускает его.
set -e
cd "$(dirname "$0")"
APP=~/Applications/ContextMeter.app
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ContextMeter</string>
  <key>CFBundleIdentifier</key><string>ru.dvn.context-meter</string>
  <key>CFBundleExecutable</key><string>ContextMeter</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
# Собираем рядом и подменяем файл целиком: перезапись на месте ломает подпись,
# и macOS убивает приложение при запуске (Code Signature Invalid).
swiftc -O *.swift -o "$APP/Contents/MacOS/ContextMeter.new"
mv -f "$APP/Contents/MacOS/ContextMeter.new" "$APP/Contents/MacOS/ContextMeter"
codesign --force --sign - "$APP"
pkill -x ContextMeter || true
sleep 1
open -g "$APP"
echo "built $APP"
