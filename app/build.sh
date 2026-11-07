#!/bin/zsh
# Собирает Cloudex Guard.app в ~/Applications и перезапускает его.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/Cloudex Guard.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/mod"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Cloudex Guard</string>
  <key>CFBundleIdentifier</key><string>io.github.trapastnik.cloudex-guard</string>
  <key>CFBundleExecutable</key><string>CloudexGuard</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1.0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
# Собираем рядом и подменяем файл целиком: перезапись на месте ломает подпись,
# и macOS убивает приложение при запуске (Code Signature Invalid).
swiftc -O -target "$(uname -m)-apple-macos13" *.swift -o "$APP/Contents/MacOS/CloudexGuard.new"
mv -f "$APP/Contents/MacOS/CloudexGuard.new" "$APP/Contents/MacOS/CloudexGuard"
# Мод — внутри приложения: подключение к Claude Code из меню или при первом запуске.
rm -rf "$APP/Contents/Resources/mod" && mkdir -p "$APP/Contents/Resources/mod"
cp -R ../mod/.claude-plugin ../mod/hooks "$APP/Contents/Resources/mod/"
rm -rf "$APP/Contents/Resources/mod/.claude-plugin/types"
[ -f ../assets/AppIcon.icns ] && cp ../assets/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
pkill -x CloudexGuard || true
sleep 1
open -g "$APP"
echo "built $APP"
