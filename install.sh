#!/bin/sh
# Cloudex Guard installer for macOS: one command, nothing to build.
#
#   curl -fsSL https://raw.githubusercontent.com/trapastnik/cloudex-guard/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/trapastnik/cloudex-guard/main/install.sh | sh -s uninstall
#
# Downloads the latest release, checks its SHA-256, puts Cloudex Guard.app into ~/Applications
# and the Claude Code mod into ~/.claude/mods/cloudex-guard, asks before adding the mod to
# ~/.claude/settings.json (a backup is kept), starts Cloudex Guard and turns on start at login.
# Downloaded with curl, the app carries no quarantine flag, so Gatekeeper lets the
# unnotarized build start. Uninstall removes all of that and the settings lines.
set -eu

REPO="trapastnik/cloudex-guard"
BASE="${CLOUDEX_BASE:-https://github.com/$REPO/releases/latest/download}"
ACTION="${1:-install}"
APPS="$HOME/Applications"
MOD="$HOME/.claude/mods/cloudex-guard"
SETTINGS="$HOME/.claude/settings.json"
LABEL="io.github.trapastnik.cloudex-guard"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# Asks on the terminal even when the script itself arrives through a pipe.
# CLOUDEX_YES=1 answers yes without asking (unattended installs). Without a terminal to ask,
# the answer is no: settings.json is never changed without an explicit yes.
confirm() {
  [ "${CLOUDEX_YES:-}" = "1" ] && return 0
  if ( : > /dev/tty ) 2>/dev/null; then
    printf '%s [Y/n] ' "$1" > /dev/tty
    if read -r answer < /dev/tty; then
      case "$answer" in [nN]*) return 1 ;; esac
      return 0
    fi
  fi
  return 1
}

# Adds (add) or removes (remove) the mod path in the env block of settings.json, keeping
# everything else. JavaScript for Automation ships with macOS, so no Python is needed.
settings() {
  /usr/bin/osascript -l JavaScript - "$1" "$SETTINGS" "$MOD" <<'JXA'
function run(argv) {
  const [mode, path, mod] = argv
  ObjC.import('Foundation')
  const fm = $.NSFileManager.defaultManager
  let data = {}
  if (fm.fileExistsAtPath(path)) {
    const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null).js
    try { data = text.trim() === '' ? {} : JSON.parse(text) } catch (e) { return 'invalid' }
  } else if (mode === 'remove') {
    return 'absent'
  }
  data.env = data.env || {}
  // Пути ранних версий проекта убираются, чтобы мод не загрузился дважды.
  const legacy = /\/\.claude\/mods\/(context-meter|claudex|cloudex)$/
  const dirs = (data.env.CLAUDE_CODE_PLUGIN_DIRS || '').split(':').filter(d => d !== '')
  const rest = dirs.filter(d => d !== mod && !legacy.test(d))
  if (mode === 'add') {
    if (rest.length === dirs.length - 1 && dirs.includes(mod)) return 'present'
    rest.push(mod)
    data.env.CLAUDE_CODE_PLUGIN_DIRS = rest.join(':')
    data.env.CLAUDE_CODE_PLUGIN_DIR_WATCH = '1'
  } else {
    if (rest.length === dirs.length) return 'absent'
    if (rest.length > 0) data.env.CLAUDE_CODE_PLUGIN_DIRS = rest.join(':')
    else { delete data.env.CLAUDE_CODE_PLUGIN_DIRS; delete data.env.CLAUDE_CODE_PLUGIN_DIR_WATCH }
    if (Object.keys(data.env).length === 0) delete data.env
  }
  $(JSON.stringify(data, null, 2) + '\n').writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null)
  return 'changed'
}
JXA
}

# CLOUDEX_NO_LAUNCH=1 (for testing): don't touch the running Cloudex Guard or its login agent.
stop_running() {
  [ "${CLOUDEX_NO_LAUNCH:-}" = "1" ] && return 0
  # A clean quit resumes any app Cloudex Guard had paused.
  pkill -x CloudexGuard 2>/dev/null || true
  sleep 1
}

autostart_off() {
  [ "${CLOUDEX_NO_LAUNCH:-}" = "1" ] && return 0
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$AGENT"
}

autostart_on() {
  autostart_off
  mkdir -p "$(dirname "$AGENT")"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/open</string><string>-g</string><string>$APPS/Cloudex Guard.app</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>60</integer>
</dict>
</plist>
PLIST
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
}

uninstall() {
  stop_running
  autostart_off
  rm -rf "$APPS/Cloudex Guard.app" "$MOD"
  # Установленное из DMG лежит в /Applications.
  [ -w "/Applications/Cloudex Guard.app" ] && rm -rf "/Applications/Cloudex Guard.app"
  case "$(settings remove)" in
    changed) say "Removed Cloudex Guard from ~/.claude/settings.json." ;;
    invalid) say "~/.claude/settings.json isn't valid JSON — remove the cloudex-guard path from its env block by hand." ;;
  esac
  say "Cloudex Guard removed. Its data is in ~/.claude/cloudex-guard and its guard settings in ~/Library/Preferences/$LABEL.plist — delete them if you like."
}

install() {
  [ "$(uname -s)" = "Darwin" ] || fail "Cloudex Guard runs on macOS only."
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge 13 ] || fail "Cloudex Guard needs macOS 13 or later."

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  say "Downloading Cloudex Guard…"
  for file in CloudexGuard-macos.zip cloudex-guard-mod.zip SHA256SUMS.txt; do
    curl -fsSL "$BASE/$file" -o "$tmp/$file"
  done
  # Сверяются ровно скачанные файлы: обе строки обязаны быть в SHA256SUMS.txt и совпасть.
  (cd "$tmp" && grep -E "  (CloudexGuard-macos\.zip|cloudex-guard-mod\.zip)\$" SHA256SUMS.txt > wanted.txt \
    && [ "$(wc -l < wanted.txt)" -eq 2 ] && shasum -a 256 -c wanted.txt >/dev/null) \
    || fail "Checksum mismatch — the download is damaged or altered. Nothing was installed."

  stop_running
  mkdir -p "$APPS" "$MOD"
  rm -rf "$APPS/Cloudex Guard.app"
  ditto -x -k "$tmp/CloudexGuard-macos.zip" "$APPS"
  rm -rf "$MOD" && mkdir -p "$MOD"
  ditto -x -k "$tmp/cloudex-guard-mod.zip" "$MOD"
  say "Installed $APPS/Cloudex Guard.app and the mod in $MOD."

  if confirm "Add the Cloudex Guard mod to ~/.claude/settings.json (a backup is kept)?"; then
    # Копия исходного файла — только при первой установке, повтор её не перезаписывает.
    [ -f "$SETTINGS" ] && [ ! -f "$SETTINGS.before-cloudex-guard" ] && cp "$SETTINGS" "$SETTINGS.before-cloudex-guard"
    case "$(settings add)" in
      changed) say "Added. Backup: ~/.claude/settings.json.before-cloudex-guard" ;;
      present) say "Already there." ;;
      invalid) say "~/.claude/settings.json isn't valid JSON, so it was left alone. Add this to its env block by hand:"
               echo "  \"CLAUDE_CODE_PLUGIN_DIRS\": \"$MOD\","
               echo "  \"CLAUDE_CODE_PLUGIN_DIR_WATCH\": \"1\"" ;;
    esac
  else
    say "Skipped. To enable the mod later, add this to the env block of ~/.claude/settings.json:"
    echo "  \"CLAUDE_CODE_PLUGIN_DIRS\": \"$MOD\","
    echo "  \"CLAUDE_CODE_PLUGIN_DIR_WATCH\": \"1\""
  fi

  if [ "${CLOUDEX_NO_LAUNCH:-}" != "1" ]; then
    autostart_on
    open -g "$APPS/Cloudex Guard.app"
  fi
  say "Done. Restart the Claude app — each chat appears in the Cloudex Guard menu after its next reply."
}

case "$ACTION" in
  install) install ;;
  uninstall) uninstall ;;
  *) fail "Usage: install.sh [install|uninstall]" ;;
esac
