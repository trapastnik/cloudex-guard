#!/bin/zsh
# Копирует мод в ~/.claude/mods/context-meter. Подключить его один раз — блоком env
# в ~/.claude/settings.json (см. README), после этого он работает в каждом чате.
set -e
cd "$(dirname "$0")"
DEST="$HOME/.claude/mods/context-meter"
mkdir -p "$DEST"
rsync -a --delete --exclude '.claude-plugin/types' mod/ "$DEST/"
echo "Мод скопирован в $DEST"
if ! grep -q "mods/context-meter" "$HOME/.claude/settings.json" 2>/dev/null; then
  echo
  echo "Осталось подключить его: добавьте в ~/.claude/settings.json на верхний уровень"
  echo
  echo "  \"env\": {"
  echo "    \"CLAUDE_CODE_PLUGIN_DIRS\": \"$DEST\","
  echo "    \"CLAUDE_CODE_PLUGIN_DIR_WATCH\": \"1\""
  echo "  }"
  echo
  echo "и перезапустите Claude."
fi
