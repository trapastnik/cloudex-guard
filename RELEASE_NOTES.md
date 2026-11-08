**Cloudex Guard** keeps your Claude Code chats clean and your connection where you expect it.

**New in 1.1.1**
- **Clear and keep going in the same chat.** The 🧹 request now asks the chat for a short text to paste back into *this* chat after `/clear` — save everything to the docs, write a handoff, clear, continue. No new chat needed.
- **Built by GitHub, verifiable by you.** This release is built by GitHub Actions from the public source, with a signed build provenance attestation for every file. Check your download:
  `gh attestation verify CloudexGuard.dmg --repo trapastnik/cloudex-guard`
- **Demo mode** for screenshots and recordings: `zsh app/demo.sh` runs the real app with made-up chats and a documentation IP address, without touching your data.

**Upgrading**: install the new app over the old one (or run `install.sh` again). The app updates its mod in Claude Code by itself on the next launch; restart Claude to load it.

**Files**: `CloudexGuard.dmg` (recommended), `CloudexGuard-macos.zip`, `cloudex-guard-mod.zip` (used by `install.sh`), `SHA256SUMS.txt`. Universal (Apple Silicon and Intel), macOS 13+. Not notarized by Apple: the first time, allow it in System Settings → Privacy & Security → Open Anyway — see the [README](https://github.com/trapastnik/cloudex-guard#install).

Cloudex Guard is an independent project, not affiliated with Anthropic.
