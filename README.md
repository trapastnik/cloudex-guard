# Claudex

**Keep your Claude Code chats clean.** A small macOS menu bar companion for Claude Code in the Claude desktop app: see how full every chat's context is, which chats are waiting for you, and ask a chat to write a handoff before you clear it. Plus a network guard that pauses chosen apps when your connection suddenly changes.

Free and open source (MIT). [Русская версия](README.ru.md) · [dvn-dev.tech](https://dvn-dev.tech)

> Claudex is an independent project. It is not made, endorsed or supported by Anthropic. Claude and Claude Code are trademarks of Anthropic.

## Why

If you run many Claude Code chats in parallel, they quietly fill up. A chat at 80% context gets slower, forgets earlier details, and eventually compacts at the worst moment. Claudex shows every chat's fill at a glance, so you clear the right chat at the right time — after it has saved its state.

## Features

### Chat hygiene

- **Context at a glance** — a colored dot and the fullest chat's percentage right in the menu bar.
- **Every chat by fill** — percent, tokens, sidebar group and time of the last reply. Click a row to open the chat.
- **Waiting for you** — a section that appears only when needed: ✋ a chat is blocked on your permission or answer, 💬 a chat finished its turn in the last hour and you haven't replied yet. The ✋ count shows in the menu bar too.
- **Handoff before clearing (🧹)** — one click asks a chat to save everything to the project docs, write a detailed handoff and a short text to start a new chat. Asks you to confirm first. A sleeping chat opens with the text on your clipboard.
- **Recent 10 chats** and **plan limits** (5-hour and weekly, with reset times; shown in the menu bar only above 80%).

### Network guard

Many people reach AI services through a VPN — a corporate one, or just for privacy. When the VPN reconnects, Wi-Fi changes or the exit server switches to another country, your apps keep talking from the new address before you notice. Claudex can pause the apps you choose until your connection is back to the countries you allow.

- **Your country in the menu bar**, as claude.ai sees it, with a warning when your VPN routes some traffic another way or IPv6 bypasses it.
- **Pause, don't kill.** Pick apps (Claude, ChatGPT, Cursor, Telegram or any other) and allowed countries. On a network change the apps are paused instantly (`SIGSTOP`, together with everything they started — for Claude that includes Claude Code and MCP servers) and resumed in about a second if all is well (`SIGCONT`). Nothing is lost: an app continues exactly where it stopped.
- **Checks what the service itself sees.** Claude, ChatGPT and Perplexity are checked through their own sites, so split-tunnel VPNs don't cause false pauses.
- **How others see us** — a one-off check: what claude.ai, the Claude API, chatgpt.com and Cloudflare see; four IP services one by one; apps that ignore the system proxy; IPv6; your DNS server; your Mac's time zone vs. the IP's.
- **Speed test** in one menu line: download, upload, and latency to Claude, its API and ChatGPT. About 12 seconds, on demand only.
- **Safe by design**: system apps, Claudex itself and VPN clients can't be paused (a paused VPN could never reconnect). Processes you stopped yourself (Ctrl-Z) are left alone. Quitting or restarting Claudex resumes everything; if it crashes, the login agent restarts it within a minute and it resumes whatever it had paused.

Nothing is paused until you choose at least one country and one app. Claudex doesn't change or route your traffic — it only pauses apps on your own Mac.

The interface follows your system language: English or Russian.

## Install

You need macOS 13 or later and the Claude desktop app. Claudex has two parts: a **mod** that runs inside each Claude Code chat and reports its numbers, and the **menu bar app** that shows them.

**1. Get the code and install the mod**

```bash
git clone https://github.com/trapastnik/claudex.git
cd claudex
./install-mod.sh
```

The script copies the mod to `~/.claude/mods/claudex` and prints a block to add once to `~/.claude/settings.json`:

```json
"env": {
  "CLAUDE_CODE_PLUGIN_DIRS": "/Users/<you>/.claude/mods/claudex",
  "CLAUDE_CODE_PLUGIN_DIR_WATCH": "1"
}
```

If the file already has an `env` block, add the two lines inside it. If `CLAUDE_CODE_PLUGIN_DIRS` is already set, append the path with a colon. Check the file is still valid: `python3 -m json.tool ~/.claude/settings.json > /dev/null && echo OK`. The setting applies to every Claude Code session on this Mac, but the mod does nothing outside the desktop app. Restart Claude.

**2. Install the app** — either build it (needs `xcode-select --install`):

```bash
./app/build.sh
./app/autostart.sh
```

or download `Claudex-macos.zip` from [Releases](https://github.com/trapastnik/claudex/releases), unzip it into `~/Applications`, and since the app isn't notarized by Apple, remove the download quarantine once: `xattr -dr com.apple.quarantine ~/Applications/Claudex.app`. Then run `./app/autostart.sh` from the cloned repo to start it at login.

## What goes over the network

Only what's needed to find out your address — no analytics, nothing about you or your chats. The mod sends nothing at all.

- Every 20 seconds: `claude.ai/cdn-cgi/trace` (plus the site of each guarded app), `api.ipify.org`, `ipv4.icanhazip.com`, `api6.ipify.org`. Every 3 seconds only while apps are paused or about to be, so they resume quickly.
- If a system proxy is on: one more request to `api.ipify.org` that bypasses the proxy, on every check — it shows ipify your address without the VPN.
- Country of an address: `ipinfo.io`, fallback `api.country.is`; the address is part of the request, the answer is cached until restart.
- Speed test (on demand): `speed.cloudflare.com` (up to 25 MB down, at most 6 seconds; 1.5 MB up) and four requests each to `claude.ai`, `api.anthropic.com`, `chatgpt.com`.
- "How others see us" (on demand) adds `api.anthropic.com`, `chatgpt.com`, `1.1.1.1`, `checkip.amazonaws.com`, `v4.ident.me`, `ipv6.icanhazip.com`, `ipinfo.io/json`, your DNS server's address to `ipinfo.io`, and a DNS lookup of `whoami.akamai.net`. With a system proxy on, it deliberately reaches `claude.ai` and `api.ipify.org` around the proxy to show what proxy-unaware apps see — those two sites then see your address without the VPN.

Local data lives in `~/.claude/claudex`; old files are cleaned up automatically.

## Troubleshooting

- **The icon is gone.** macOS hides menu bar icons that don't fit (behind the camera notch). Check it runs: `pgrep -lx Claudex`. If it does, ⌘-drag it to the right or free some space.
- **An app looks frozen.** That's a pause. Claudex resumes it when your address is allowed again, when you quit Claudex, or right after a restart. If Claudex isn't running, start it: `open -g ~/Applications/Claudex.app`.
- **A chat doesn't appear.** It shows up after its next reply; chats that haven't run since the Claude restart are asleep.

## Uninstall

```bash
./app/autostart.sh off
pkill -x Claudex
rm -rf ~/Applications/Claudex.app ~/.claude/mods/claudex ~/.claude/claudex
```

Then remove the two lines from `env` in `~/.claude/settings.json`. Guard settings are in `~/Library/Preferences/io.github.trapastnik.claudex.plist`.

## Support

Claudex is free. If it saves you time, you can support its development:

- **Bitcoin (BTC):** `1JZ3neiNzLC5kiGAer5UQGQvK9xSJqnc87`
- **Ethereum (ETH) or USDT (ERC-20, Ethereum network only):** `0x2f507c67655ddf3638c83238c71d51defe7b1fec`

Please double-check the network: tokens sent through other networks (BNB Chain, Tron and so on) can be lost. Stars, bug reports and ideas in [Issues](https://github.com/trapastnik/claudex/issues) help too.

## Credits

The pausing and leak-check approach was inspired by [Kordon](https://github.com/ef1m03/kordon) by Efimov Dev: confirming the address with several services, asking the AI service itself, `SIGSTOP` on the whole process tree, DNS check via `whoami.akamai.net`. Claudex's code is written from scratch; nothing was copied from Kordon. If you need a full kill switch for Mac, Windows and Linux with a browser extension and Telegram alerts, have a look at Kordon.

## License

MIT — see [LICENSE](LICENSE).
