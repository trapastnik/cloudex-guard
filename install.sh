#!/bin/sh
# Claudex installer for macOS: one command, nothing to build.
#
#   curl -fsSL https://raw.githubusercontent.com/trapastnik/claudex/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/trapastnik/claudex/main/install.sh | sh -s uninstall
#
# Downloads the latest release, checks its SHA-256, puts Claudex.app into ~/Applications
# and the Claude Code mod into ~/.claude/mods/claudex, asks before adding the mod to
# ~/.claude/settings.json (a backup is kept), starts Claudex and turns on start at login.
# Downloaded with curl, the app carries no quarantine flag, so Gatekeeper lets the
# unnotarized build start. Uninstall removes all of that and the settings lines.
set -eu

REPO="trapastnik/claudex"
BASE="${CLAUDEX_BASE:-https://github.com/$REPO/releases/latest/download}"
ACTION="${1:-install}"
APPS="$HOME/Applications"
MOD="$HOME/.claude/mods/claudex"
SETTINGS="$HOME/.claude/settings.json"
LABEL="io.github.trapastnik.claudex"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# Asks on the terminal even when the script itself arrives through a pipe.
# CLAUDEX_YES=1 answers yes without asking (unattended installs).
confirm() {
  [ "${CLAUDEX_YES:-}" = "1" ] && return 0
  if [ -r /dev/tty ]; then
    printf '%s [Y/n] ' "$1" > /dev/tty
    read -r answer < /dev/tty || answer=""
    case "$answer" in [nN]*) return 1 ;; esac
    return 0
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
  const dirs = (data.env.CLAUDE_CODE_PLUGIN_DIRS || '').split(':').filter(d => d !== '')
  const rest = dirs.filter(d => d !== mod)
  if (mode === 'add') {
    if (rest.length === dirs.length) rest.push(mod); else return 'present'
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

# CLAUDEX_NO_LAUNCH=1 (for testing): don't touch the running Claudex or its login agent.
stop_running() {
  [ "${CLAUDEX_NO_LAUNCH:-}" = "1" ] && return 0
  # A clean quit resumes any app Claudex had paused.
  pkill -x Claudex 2>/dev/null || true
  sleep 1
}

autostart_off() {
  [ "${CLAUDEX_NO_LAUNCH:-}" = "1" ] && return 0
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
  <array><string>/usr/bin/open</string><string>-g</string><string>$APPS/Claudex.app</string></array>
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
  rm -rf "$APPS/Claudex.app" "$MOD"
  case "$(settings remove)" in
    changed) say "Removed Claudex from ~/.claude/settings.json." ;;
    invalid) say "~/.claude/settings.json isn't valid JSON — remove the claudex path from its env block by hand." ;;
  esac
  say "Claudex removed. Its data is in ~/.claude/claudex and its guard settings in ~/Library/Preferences/$LABEL.plist — delete them if you like."
}

install() {
  [ "$(uname -s)" = "Darwin" ] || fail "Claudex runs on macOS only."
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge 13 ] || fail "Claudex needs macOS 13 or later."

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  say "Downloading Claudex…"
  for file in Claudex-macos.zip claudex-mod.zip SHA256SUMS.txt; do
    curl -fsSL "$BASE/$file" -o "$tmp/$file"
  done
  (cd "$tmp" && shasum -a 256 -c SHA256SUMS.txt >/dev/null) || fail "Checksum mismatch — the download is damaged or altered. Nothing was installed."

  stop_running
  mkdir -p "$APPS" "$MOD"
  rm -rf "$APPS/Claudex.app"
  ditto -x -k "$tmp/Claudex-macos.zip" "$APPS"
  rm -rf "$MOD" && mkdir -p "$MOD"
  ditto -x -k "$tmp/claudex-mod.zip" "$MOD"
  say "Installed $APPS/Claudex.app and the mod in $MOD."

  if confirm "Add the Claudex mod to ~/.claude/settings.json (a backup is kept)?"; then
    # Копия исходного файла — только при первой установке, повтор её не перезаписывает.
    [ -f "$SETTINGS" ] && [ ! -f "$SETTINGS.before-claudex" ] && cp "$SETTINGS" "$SETTINGS.before-claudex"
    case "$(settings add)" in
      changed) say "Added. Backup: ~/.claude/settings.json.before-claudex" ;;
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

  if [ "${CLAUDEX_NO_LAUNCH:-}" != "1" ]; then
    autostart_on
    open -g "$APPS/Claudex.app"
  fi
  say "Done. Restart the Claude app — each chat appears in the Claudex menu after its next reply."
}

case "$ACTION" in
  install) install ;;
  uninstall) uninstall ;;
  *) fail "Usage: install.sh [install|uninstall]" ;;
esac
