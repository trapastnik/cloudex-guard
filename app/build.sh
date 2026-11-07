#!/bin/zsh
# Собирает Claudex.app в ~/Applications и перезапускает его.
set -e
cd "$(dirname "$0")"
APP=~/Applications/Claudex.app
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Claudex</string>
  <key>CFBundleIdentifier</key><string>io.github.trapastnik.claudex</string>
  <key>CFBundleExecutable</key><string>Claudex</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
# Собираем рядом и подменяем файл целиком: перезапись на месте ломает подпись,
# и macOS убивает приложение при запуске (Code Signature Invalid).
swiftc -O -target "$(uname -m)-apple-macos13" *.swift -o "$APP/Contents/MacOS/Claudex.new"
mv -f "$APP/Contents/MacOS/Claudex.new" "$APP/Contents/MacOS/Claudex"
codesign --force --sign - "$APP"
pkill -x Claudex || true
sleep 1
open -g "$APP"
echo "built $APP"
