**Cloudex Guard** keeps your Claude Code chats clean: context of every chat, 🧹 handoff before clearing, chats waiting for you, plan limits.

**New in 1.2.0**
- **One app, one job.** Cloudex Guard now does only the context tracker. The network guard — pausing apps when your VPN drops or switches servers, "How others see us", the speed test — moved to a separate free app, [Cloudex Shield](https://github.com/trapastnik/cloudex-shield).
- **No network requests at all.** Neither the app nor the mod goes online anymore. A web address opens only when you click a link in the menu, and then in your browser. Check it with a firewall such as [LuLu](https://objective-see.org/products/lulu.html).
- **Tidier data folder.** Files of chats that have been silent for more than 60 days are deleted from `~/.claude/cloudex-guard` at launch.

**Upgrading**: install the new app over the old one (or run `install.sh` again). The app updates its mod in Claude Code by itself on the next launch; restart Claude to load it. If you used the network guard in 1.1, install [Cloudex Shield](https://github.com/trapastnik/cloudex-shield#install): it takes your apps and allowed countries from Cloudex Guard on first launch and resumes anything 1.1 left paused. Cloudex Guard shows a one-time notice about this.

**Files**: `CloudexGuard.dmg` (recommended), `CloudexGuard-macos.zip`, `cloudex-guard-mod.zip` (used by `install.sh`), `SHA256SUMS.txt`. Universal (Apple Silicon and Intel), macOS 13+. Built by GitHub Actions with a build provenance attestation: `gh attestation verify CloudexGuard.dmg --repo trapastnik/cloudex-guard`. Not notarized by Apple: the first time, allow it in System Settings → Privacy & Security → Open Anyway — see the [README](https://github.com/trapastnik/cloudex-guard#install).

Cloudex Guard is an independent project, not affiliated with Anthropic.
