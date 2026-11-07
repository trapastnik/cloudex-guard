#!/bin/zsh
# Копирует мод в ~/.claude/mods/cloudex-guard. Подключить его один раз — блоком env
# в ~/.claude/settings.json (см. README), после этого он работает в каждом чате.
set -e
cd "$(dirname "$0")"
DEST="$HOME/.claude/mods/cloudex-guard"
# Клон, лежащий прямо в папке мода, rsync --delete стёр бы целиком — отказываемся.
HERE="$(pwd -P)"
if [ "$HERE" = "$DEST" ] || [ "${HERE#$DEST/}" != "$HERE" ] || [ "${DEST#$HERE/}" = "mod" ]; then
  echo "Склонируйте репозиторий в другую папку (не в $DEST) и запустите скрипт оттуда." >&2
  exit 1
fi
mkdir -p "$DEST"
rsync -a --delete --exclude '.claude-plugin/types' mod/ "$DEST/"
echo "Мод скопирован в $DEST"
if ! grep -q "mods/cloudex-guard" "$HOME/.claude/settings.json" 2>/dev/null; then
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
