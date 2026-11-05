#!/bin/zsh
# Включает (или с аргументом off — выключает) запуск ContextMeter при входе в систему.
# Агент вызывает /usr/bin/open, как двойной клик: прямой запуск самоподписанного файла
# агентом macOS блокирует после каждой пересборки (Launch Constraint Violation).
set -e
LABEL=ru.dvn.context-meter
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
if [ "${1:-on}" = "off" ]; then
  rm -f "$PLIST"
  echo "Автозапуск выключен."
  exit 0
fi
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/open</string>
    <string>-g</string>
    <string>$HOME/Applications/ContextMeter.app</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Автозапуск включён: $PLIST"
