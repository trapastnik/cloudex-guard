#!/bin/zsh
# Демо для записи GIF и скриншотов: настоящее приложение с выдуманными чатами (см. demo.swift).
#
#   zsh app/demo.sh        — чаты: «Ждут вас», 🧹 (английский интерфейс)
#   zsh app/demo.sh ru     — то же на русском
#   zsh app/demo.sh net    — страж сети: VPN прыгает в другую страну → ❄︎ заморозка → адрес вернулся
#                            (фазы переключаются Enter в этом окне; настоящие программы не трогаются)
#
# На время записи настоящий Cloudex Guard выключается (заморозка отпускается, автозапуск
# приостанавливается), чтобы в строке меню был один значок без ваших чатов и адреса.
# Enter в этом окне — демо закрывается, настоящее приложение и автозапуск возвращаются.
set -e
cd "$(dirname "$0")"
LANG_UI=en; NET=0
for a in "$@"; do case "$a" in ru|en) LANG_UI=$a;; net) NET=1;; esac; done
PHASE="$(getconf DARWIN_USER_TEMP_DIR)cloudex-guard-demo/net-phase"
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
open -g --env CLOUDEX_DEMO=1 --env "CLOUDEX_DEMO_LANG=$LANG_UI" "$APP"
sleep 2

if [ "$NET" = 1 ]; then
  echo ok > "$PHASE"
  cat <<'TXT'

Демо стража сети запущено: в строке меню 🇺🇸 ● 84% ✋1 — VPN в США, всё разрешено.
Запись: ⌘⇧5 → «Записать выбранную область» (строка меню справа и место под меню) → «Записать».
  1. Открыть меню, навести на «Network guard» — видны программы (Claude, ChatGPT) и разрешённая страна 🇺🇸 US.
     Закрыть меню (Esc).
  2. Вернуться в это окно и нажать Enter — «VPN переподключился в Бразилию»: в строке меню красное ❄︎BR.
  3. Открыть меню — красная строка «❄︎ Paused: ChatGPT, Claude…». Закрыть меню.
  4. Снова Enter здесь — адрес вернулся: в строке меню снова 🇺🇸. Открыть меню на секунду, закрыть.
  5. Остановить запись (■ в строке меню). Пришлите .mov — сделаю GIF.

TXT
  read "?Enter — сеть прыгнула в Бразилию (❄︎)… "
  echo jump > "$PHASE"
  read "?Enter — адрес вернулся (🇺🇸)… "
  echo ok > "$PHASE"
else
cat <<'TXT'

Демо запущено: в строке меню значок с 84% и ✋1.
Запись: ⌘⇧5 → «Записать выбранную область» (строка меню справа и место под меню) → «Записать».
  1. Щёлкнуть значок — открыть меню, подержать 2 секунды.
  2. Провести мышью по «Waiting for you» (✋ и 💬).
  3. Нажать 🧹 у «payments migration» → в окне «Send» — у строки появится ⏳.
  4. Остановить запись (кнопка ■ в строке меню).
Сохранённый .mov пришлите — переведу в GIF.

TXT
fi
read "?Enter — закрыть демо и вернуть настоящий Cloudex Guard… "

pkill -x CloudexGuardDemo 2>/dev/null || true
if [ -f "$AGENT" ]; then
  launchctl bootstrap "gui/$(id -u)" "$AGENT" 2>/dev/null || open -g "$HOME/Applications/Cloudex Guard.app"
else
  open -g "$HOME/Applications/Cloudex Guard.app"
fi
sleep 2
pgrep -x CloudexGuard >/dev/null && echo "Настоящий Cloudex Guard снова работает." || echo "Проверьте: Cloudex Guard не запустился — откройте его из ~/Applications."
