#!/bin/zsh
# Собирает релиз: универсальный Claudex.app (Apple Silicon и Intel, macOS 13+),
# dist/Claudex-macos.zip и dist/SHA256SUMS.txt. Ничего не устанавливает и не запускает.
set -e
cd "$(dirname "$0")"
VERSION="${1:?укажите версию, например 1.0.0}"
DIST=../dist
APP="$DIST/Claudex.app"
rm -rf "$DIST" && mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Claudex</string>
  <key>CFBundleIdentifier</key><string>io.github.trapastnik.claudex</string>
  <key>CFBundleExecutable</key><string>Claudex</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13" *.swift -o "$DIST/Claudex-$arch"
done
lipo -create "$DIST/Claudex-arm64" "$DIST/Claudex-x86_64" -output "$APP/Contents/MacOS/Claudex"
rm "$DIST/Claudex-arm64" "$DIST/Claudex-x86_64"
codesign --force --sign - "$APP"
(cd "$DIST" && ditto -c -k --keepParent Claudex.app Claudex-macos.zip && shasum -a 256 Claudex-macos.zip > SHA256SUMS.txt)
lipo -info "$APP/Contents/MacOS/Claudex"
cat "$DIST/SHA256SUMS.txt"
