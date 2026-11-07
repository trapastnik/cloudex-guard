<p align="center"><img src="assets/logo.svg" alt="Cloudex Guard" width="440"></p>

<p align="center"><b>Keep your Claude Code chats clean — and your connection where you expect it.</b><br>
A small, free macOS menu bar app for Claude Code in the Claude desktop app.</p>

<p align="center"><a href="https://github.com/trapastnik/cloudex-guard/releases/latest">Download</a> · <a href="#install">Install</a> · <a href="#your-keys-and-data-stay-yours">Privacy</a> · <a href="README.ru.md">Русский</a> · <a href="https://medfab-dev.tech/cloudex-guard/">Website</a></p>

> Cloudex Guard is an independent open-source project. It is not made, endorsed or supported by Anthropic. Claude and Claude Code are trademarks of Anthropic.

## What it does

### Chat hygiene

If you run many Claude Code chats in parallel, they quietly fill up. A chat at 80% context gets slower, forgets earlier details and eventually compacts at the worst moment. Cloudex Guard shows every chat's fill at a glance, so you clear the right chat at the right time — after it has saved its state.

- **Context at a glance** — a colored dot and the fullest chat's percentage in the menu bar; every chat sorted by fill in the menu, with tokens, group and time of the last reply. Click a row to open the chat.
- **Waiting for you** — ✋ chats blocked on your permission or answer, 💬 chats that just finished their turn. Shown only when someone is waiting.
- **Handoff before clearing (🧹)** — one click asks a chat to save everything to the project docs and write a detailed handoff and a short starter for a new chat. Always asks you to confirm first.
- **Recent chats** and **plan limits** — 5-hour and weekly limits with reset times; in the menu bar only above 80%.

### Network guard

Many people reach AI services through a VPN — a corporate one, or just for privacy. When it reconnects, Wi-Fi changes or the exit server moves to another country, apps keep working from the new address before you notice. Cloudex Guard can pause the apps you choose until your connection is back where you expect it.

- **Your country in the menu bar**, as claude.ai itself sees it, with a warning when your VPN routes some traffic another way or IPv6 bypasses it.
- **Pause, don't kill.** Pick apps and allowed countries. On an unexpected network the apps — and everything they started; for Claude that includes Claude Code and its MCP servers — are paused, and continue exactly where they stopped once the network is back. Nothing is lost.
- **How others see us** — what claude.ai, the Claude API, chatgpt.com and others see; IPv6, DNS and time zone checks.
- **Speed test** — download, upload and latency to Claude and ChatGPT in one menu line.
- **Safe by design** — system apps and VPN clients can never be paused; quitting Cloudex Guard always resumes everything; after a crash it is restarted within a minute and resumes what it had paused.

Nothing is paused until you pick at least one country and one app. Cloudex Guard doesn't change or route your traffic. The interface is English, or Russian on a Russian system.

## Install

You need macOS 13 or later and the Claude desktop app.

### The usual way: download and drag

1. **Download** [`CloudexGuard.dmg`](https://github.com/trapastnik/cloudex-guard/releases/latest/download/CloudexGuard.dmg).
2. **Open it and drag** Cloudex Guard onto the Applications folder.
3. **Open Cloudex Guard.** The first time, macOS says it can't check the developer. That's expected for free apps distributed outside the App Store without a paid Apple developer certificate — it doesn't mean anything is wrong. To allow it once:
   - open **System Settings → Privacy & Security**,
   - scroll down to the message about Cloudex Guard and click **Open Anyway**,
   - confirm. macOS remembers the choice; you won't be asked again.
4. **Click Connect** when Cloudex Guard offers to connect to Claude Code. It installs its small mod, adds one line to `~/.claude/settings.json` (keeping a copy of the original) and starts at login.
5. **Restart the Claude app.** Each chat appears in the menu after its next reply.

Changed your mind? Quit it from the menu and run the uninstall command below — it removes everything, including the line in `settings.json`.

### One command in Terminal

No dialogs, nothing to approve in System Settings:

```bash
curl -fsSL https://raw.githubusercontent.com/trapastnik/cloudex-guard/main/install.sh | sh
```

It downloads the latest release, checks its SHA-256, installs the app and the mod, **asks** before touching `~/.claude/settings.json` (keeping a backup) and starts Cloudex Guard at login. [Read the script](install.sh) first if you like. To remove everything:

```bash
curl -fsSL https://raw.githubusercontent.com/trapastnik/cloudex-guard/main/install.sh | sh -s uninstall
```

### From source

```bash
git clone https://github.com/trapastnik/cloudex-guard.git && cd cloudex-guard
./app/build.sh        # needs Xcode Command Line Tools: xcode-select --install
```

Then choose **Connect to Claude Code…** in the menu.

## Your keys and data stay yours

**What Cloudex Guard never touches:** your API keys and tokens, your Claude account and login, your passwords and Keychain, the contents of your chats and transcripts, your files and projects.

**What it asks macOS for:** nothing. No Accessibility, Full Disk Access, Screen Recording, Keychain or Location permission — you will never see such a prompt from it.

**What it does see:** the mod receives from Claude Code only numbers and labels about each chat — how full its context is, plan limits, whether it's busy or waiting for you, its title, sidebar group, folder and link — and writes them to `~/.claude/cloudex-guard` on your Mac. **The mod makes no network requests at all** — the only thing it asks for is the chat's title and link, from the Claude app itself on your Mac. The menu bar app makes only the requests needed to find your public IP, all listed [below](#what-goes-over-the-network). No analytics, no telemetry, no server of ours.

### Don't take our word for it

There is no paid audit of this project, but everything above can be checked independently:

1. **Read the code.** It is all here — about 1,700 lines of Swift for the app and a single file for the mod.
2. **Check the file — or skip it entirely.** Compare the SHA-256 of your download with `SHA256SUMS.txt` in the release (`shasum -a 256 CloudexGuard.dmg`). If you'd rather not trust a binary at all, build the app from this source yourself — it takes a minute (see *From source*).
3. **Watch the network.** Run a firewall that shows every connection, such as the free open-source [LuLu](https://objective-see.org/products/lulu.html) by Objective-See or [Little Snitch](https://www.obdev.at/products/littlesnitch/). You'll see only the hosts listed below.
4. **Check what the mod can do.** Claude Code itself lists every engine call and event a mod uses: `claude plugin validate ~/.claude/mods/cloudex-guard` — you'll see file writes, timers, the usage numbers and one call to the Claude app's own session service (`ccd_session_mgmt`, for the chat title and link), and no network access.
5. **Scan the file.** Upload the DMG to [VirusTotal](https://www.virustotal.com) to check it with about 70 antivirus engines, or compare its SHA-256 with `SHA256SUMS.txt` in the release.

## What goes over the network

- Every 20 seconds: `claude.ai/cdn-cgi/trace` (plus the site of each guarded app), `api.ipify.org`, `ipv4.icanhazip.com`, `api6.ipify.org`. Every 3 seconds only while apps are paused or about to be, so they resume quickly.
- If a system proxy is on: one more request to `api.ipify.org` that bypasses the proxy on every check — it shows ipify your address without the VPN.
- Country of an address: `ipinfo.io`, fallback `api.country.is`; the address is part of the request, the answer is cached until restart.
- Speed test (on demand): `speed.cloudflare.com` (up to 25 MB down for at most 6 seconds, 1.5 MB up) and four requests each to `claude.ai`, `api.anthropic.com`, `chatgpt.com`.
- "How others see us" (on demand) adds `api.anthropic.com`, `chatgpt.com`, `1.1.1.1`, `checkip.amazonaws.com`, `v4.ident.me`, `ipv6.icanhazip.com`, `ipinfo.io/json`, your DNS server's address to `ipinfo.io`, and a DNS lookup of `whoami.akamai.net`. With a system proxy on, it deliberately reaches `claude.ai` and `api.ipify.org` around the proxy to show what proxy-unaware apps see — those two sites then see your address without the VPN.

## Troubleshooting

- **The icon is gone.** macOS hides menu bar icons that don't fit (behind the camera notch). Check it runs: `pgrep -lx CloudexGuard`. If it does, ⌘-drag it to the right or free some space.
- **An app looks frozen.** That's a pause. Cloudex Guard resumes it when your address is allowed again, when you quit Cloudex Guard, or right after it restarts. If it isn't running, open it again.
- **A chat doesn't appear.** It shows up after its next reply; chats that haven't run since you restarted Claude are asleep.

## Support

Cloudex Guard is free. If it saves you time, you can support its development:

- **Bitcoin (BTC):** `1JZ3neiNzLC5kiGAer5UQGQvK9xSJqnc87`
- **Ethereum (ETH):** `0x2f507c67655ddf3638c83238c71d51defe7b1fec`
- **USDT (Tether), ERC-20 on the Ethereum network only:** `0x2f507c67655ddf3638c83238c71d51defe7b1fec`

Please double-check the network: tokens sent through other networks (BNB Chain, Tron and so on) can be lost. Stars, bug reports and ideas in [Issues](https://github.com/trapastnik/cloudex-guard/issues) help too.

## Credits

The pausing and leak-check approach was inspired by [Kordon](https://github.com/ef1m03/kordon) by Efimov Dev: confirming the address with several services, asking the AI service itself, `SIGSTOP` on the whole process tree, DNS check via `whoami.akamai.net`. Cloudex Guard's code is written from scratch; nothing was copied from Kordon. If you need a full kill switch for Mac, Windows and Linux with a browser extension and Telegram alerts, have a look at Kordon.

## License

MIT — see [LICENSE](LICENSE).
