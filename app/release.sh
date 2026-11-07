#!/bin/zsh
# Собирает релиз: универсальное «Cloudex Guard.app» (Apple Silicon и Intel, macOS 13+) с модом внутри,
# dist/CloudexGuard.dmg (перетащить в «Программы»), dist/CloudexGuard-macos.zip и
# dist/cloudex-guard-mod.zip для install.sh, dist/SHA256SUMS.txt. Ничего не устанавливает и не запускает.
set -e
cd "$(dirname "$0")"
VERSION="${1:?укажите версию, например 1.1.0}"
DIST=../dist
APP="$DIST/Cloudex Guard.app"
rm -rf "$DIST" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Cloudex Guard</string>
  <key>CFBundleDisplayName</key><string>Cloudex Guard</string>
  <key>CFBundleIdentifier</key><string>io.github.trapastnik.cloudex-guard</string>
  <key>CFBundleExecutable</key><string>CloudexGuard</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13" *.swift -o "$DIST/CloudexGuard-$arch"
done
lipo -create "$DIST/CloudexGuard-arm64" "$DIST/CloudexGuard-x86_64" -output "$APP/Contents/MacOS/CloudexGuard"
rm "$DIST/CloudexGuard-arm64" "$DIST/CloudexGuard-x86_64"

# Мод — внутри приложения: при первом запуске оно само подключается к Claude Code.
mkdir -p "$APP/Contents/Resources/mod"
(cd ../mod && cp -R .claude-plugin hooks "$OLDPWD/$APP/Contents/Resources/mod/")
rm -rf "$APP/Contents/Resources/mod/.claude-plugin/types"
[ -f ../assets/AppIcon.icns ] && cp ../assets/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

# Мод отдельным архивом — для install.sh.
(cd ../mod && zip -qr -X "$OLDPWD/$DIST/cloudex-guard-mod.zip" .claude-plugin/plugin.json hooks)
(cd "$DIST" && ditto -c -k --keepParent "Cloudex Guard.app" CloudexGuard-macos.zip)

# DMG: приложение и ярлык «Программы» — перетащить одно на другое.
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Cloudex Guard" -srcfolder "$STAGE" -ov -format UDZO "$DIST/CloudexGuard.dmg"
rm -rf "$STAGE"

(cd "$DIST" && shasum -a 256 CloudexGuard.dmg CloudexGuard-macos.zip cloudex-guard-mod.zip > SHA256SUMS.txt)
lipo -info "$APP/Contents/MacOS/CloudexGuard"
cat "$DIST/SHA256SUMS.txt"
