# Developing Cloudex Guard

## Layout

- `mod/` — the Claude Code mod (plugin with function hooks), `mod/hooks/register.tsx`. Active only in the Claude desktop app (`CLAUDE_CODE_ENTRYPOINT=claude-desktop`); the chat id comes from `CLAUDE_CODE_HOST_SESSION_ID`, title and link from the app's `ccd_session_mgmt` service. It writes, under `~/.claude/cloudex-guard`: `<chat id>.json` (context fill), `_limits.json`, `status/<id>.json` (working / asking / done), `alive/<id>` (heartbeat once a minute), and reads `requests/<id>.json` (🧹 requests, honoured for 10 minutes, the prompt text travels in the request). No network access.
- `app/` — the menu bar app (Swift, AppKit, no dependencies): `main.swift` (menu, chats, limits, 🧹), `guard.swift` (public IP, pausing apps), `leaks.swift` ("How others see us"), `netmenu.swift`, `speed.swift`, `setup.swift` (connecting to Claude Code from the app), `lang.swift` (`t("English", "Русский")`, by system language; force with `defaults write io.github.trapastnik.cloudex-guard language ru`).
- `assets/` — logo, mark, app icon; `make-icon.swift` redraws the icon: `cd assets && swift make-icon.swift && iconutil -c icns AppIcon.iconset`.
- `install.sh` — one-command install from the latest release; `install-mod.sh` — mod only, from a clone.

## Build and release

```bash
./app/build.sh               # native build into ~/Applications, restarts the app
./app/release.sh 1.2.0       # universal app, DMG, zip, mod zip and SHA256SUMS into dist/
```

Both compile to a temporary file, then move it in place and re-sign (`codesign --force --sign -`): overwriting a signed binary in place makes macOS kill it at launch ("Code Signature Invalid"). The login agent runs `/usr/bin/open -g <app>` rather than the binary itself, for the same reason ("Launch Constraint Violation").

Check the mod with the Claude Code build the desktop app ships (the `claude` on your PATH may be older):

```bash
C=$(ls -d ~/Library/Application\ Support/Claude/claude-code/*/*/claude.app/Contents/MacOS/claude | tail -1)
"$C" plugin validate mod
```

## Testing the installer safely

Use a throwaway `HOME` and these switches, otherwise the script will stop your running Cloudex Guard and re-point its login agent:

```bash
cat install.sh | HOME=/tmp/cg-test CLOUDEX_NO_LAUNCH=1 CLOUDEX_YES=1 sh
cat install.sh | HOME=/tmp/cg-test CLOUDEX_NO_LAUNCH=1 CLOUDEX_BASE=file:///path/to/dist sh
```

`CLOUDEX_NO_LAUNCH=1` leaves the running app and its agent alone, `CLOUDEX_YES=1` answers the `settings.json` question, `CLOUDEX_BASE` points at local release files. Check `pgrep -x CloudexGuard` before and after.

## Things learned the hard way

- The `isInteractive` flag of `session.start` is false in the desktop app too (it is an SDK host) — gate on `CLAUDE_CODE_ENTRYPOINT` instead.
- A permission prompt and the tool run are one `tool.call`; "waiting for you" uses `classic.PermissionRequest` and clears on `PostToolUse` / `PostToolUseFailure` / `PermissionDenied`.
- Geolocation databases disagree for VPN exits; the country of the general address comes from ipinfo, Claude/ChatGPT/Perplexity are judged by their own `/cdn-cgi/trace`.
- A crowded menu bar hides icons under the camera notch: the app is running, the icon just isn't shown.
- A static site's container keeps its bind-mounted `site/` by inode: after swapping the folder, restart the container.
