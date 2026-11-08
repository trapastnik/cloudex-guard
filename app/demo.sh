#!/bin/zsh
# Демо для записи GIF и скриншотов: настоящее приложение с выдуманными чатами (см. demo.swift).
#
#   zsh app/demo.sh        — английский интерфейс
#   zsh app/demo.sh ru     — русский
#
# На время записи настоящий Cloudex Guard выключается (заморозка отпускается, автозапуск
# приостанавливается), чтобы в строке меню был один значок без ваших чатов и адреса.
# Enter в этом окне — демо закрывается, настоящее приложение и автозапуск возвращаются.
set -e
cd "$(dirname "$0")"
APP="${TMPDIR:-/tmp}/Cloudex Guard Demo.app"
ID=io.github.trapastnik.cloudex-guard.demo
AGENT="$HOME/Library/LaunchAgents/io.github.trapastnik.cloudex-guard.plist"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Cloudex Guard Demo</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>CloudexGuardDemo</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
echo "Собираю демо…"
swiftc -O -target "$(uname -m)-apple-macos13" *.swift -o "$APP/Contents/MacOS/CloudexGuardDemo.new"
mv -f "$APP/Contents/MacOS/CloudexGuardDemo.new" "$APP/Contents/MacOS/CloudexGuardDemo"
[ -f ../assets/AppIcon.icns ] && cp ../assets/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
# Значок демо — правее, ближе к часам, чтобы не спрятался под вырезом экрана.
defaults write $ID "NSStatusItem Preferred Position Cloudex Guard Demo" -float 260

# Убрать настоящий значок на время записи.
[ -f "$AGENT" ] && launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
osascript -e 'tell application id "io.github.trapastnik.cloudex-guard" to quit' 2>/dev/null || true
sleep 1

pkill -x CloudexGuardDemo 2>/dev/null || true
open -g --env CLOUDEX_DEMO=1 --env "CLOUDEX_DEMO_LANG=${1:-en}" "$APP"

cat <<'TXT'

Демо запущено: в строке меню значок с 84% и ✋1.
Запись: ⌘⇧5 → «Записать выбранную область» (строка меню справа и место под меню) → «Записать».
  1. Щёлкнуть значок — открыть меню, подержать 2 секунды.
  2. Провести мышью по «Waiting for you» (✋ и 💬).
  3. Нажать 🧹 у «payments migration» → в окне «Send» — у строки появится ⏳.
  4. Остановить запись (кнопка ■ в строке меню).
Сохранённый .mov пришлите — переведу в GIF.

TXT
read "?Enter — закрыть демо и вернуть настоящий Cloudex Guard… "

pkill -x CloudexGuardDemo 2>/dev/null || true
if [ -f "$AGENT" ]; then
  launchctl bootstrap "gui/$(id -u)" "$AGENT" 2>/dev/null || open -g "$HOME/Applications/Cloudex Guard.app"
else
  open -g "$HOME/Applications/Cloudex Guard.app"
fi
sleep 2
pgrep -x CloudexGuard >/dev/null && echo "Настоящий Cloudex Guard снова работает." || echo "Проверьте: Cloudex Guard не запустился — откройте его из ~/Applications."
