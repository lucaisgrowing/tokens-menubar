<div align="right">
  <a href="README.md"><img src="https://img.shields.io/badge/English-1f6feb?style=for-the-badge&logoColor=white" alt="English"></a>
  <a href="README.zh-CN.md"><img src="https://img.shields.io/badge/简体中文-6e7681?style=for-the-badge&logoColor=white" alt="简体中文"></a>
</div>

# TokensBar

Your [tokens.ci](https://tokens.ci) token usage and leaderboard rank, in the macOS menu bar — no browser tab needed.

Single-file Swift, compiled straight with `swiftc`. No Xcode project, no dependencies beyond system frameworks.

```
menu bar:  ⚡ 12.4M  #87       ← all-time rank
     or:   ⚡ 12.4M  今#31     ← today's rank

dropdown:
  @your-handle
  ──────────────────────────────
  累计榜   #87 / 265  · 菜单栏     (all-time board)
  今日榜   #31 / 121               (today's board)
  #rank / people on the board
  ──────────────────────────────
  累计   1.82B      $3,410.55     (lifetime)
  今日   12.4M      $54.30        (today)
  本周   210.6M     $612.40       (this week)
  ──────────────────────────────
  累计榜 距 #86 @someone-ahead 还差 24.3M   (gap to the rank above)
  ──────────────────────────────
  claude-opus-4-8          33.6%  1.36B
  gpt-5.6-sol              28.1%  1.13B
  glm-4.5-flash            14.1%  568.2M
  ──────────────────────────────
  本地 12:21  ·  服务端 12:06    (local scan / server data timestamps)
  submit now / refresh / rank shown in menu bar / open profile / launch at login / quit
```

The interface is currently Chinese-only. Localisation is welcome — every string lives in the `Presenter` type in [`Sources/main.swift`](Sources/main.swift).

## The two ranks

- **累计榜 (all-time)** — ranked by lifetime tokens. This is the board on the tokens.ci front page.
- **今日榜 (today)** — ranked by tokens submitted today only. Just the people who submitted today are on it, so it is a smaller board and the rank moves a lot.

`#87 / 265` reads "rank 87 out of 265 people on the board" — it is **one** rank, not two different ones. In the menu bar a daily rank is prefixed with 今 (`今#31`) so it cannot be mistaken for a lifetime one.

Pick which one the menu bar shows from the "菜单栏显示排名" submenu (the choice is remembered), or set `menuBarRank` in the config file for the default. Both ranks are always listed in the dropdown; the setting only changes the menu bar line and which board the gap line refers to.

## Requirements

The [`tokens`](https://github.com/missuo/tokens) CLI, installed and logged in:

```bash
brew install owo-network/brew/tokens
tokens login
```

## Install

Download `TokensBar.app.zip` from [Releases](https://github.com/lucaisgrowing/tokens-menubar/releases), unzip, move it to `/Applications`, then clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/TokensBar.app
open /Applications/TokensBar.app
```

The build is ad-hoc signed and **not** notarised, so macOS will refuse to open it until the quarantine attribute is gone. Alternatively, right-click → Open, or allow it in System Settings → Privacy & Security. The release binary is universal (arm64 + x86_64) and needs macOS 13 or newer.

Or build it yourself — nothing but the Swift toolchain that ships with Xcode is required:

```bash
git clone https://github.com/lucaisgrowing/tokens-menubar.git
cd tokens-menubar
./build.sh              # this Mac's architecture
./build.sh --universal  # arm64 + x86_64
open TokensBar.app
```

The app is an `LSUIElement`: menu bar only, no Dock icon and no windows.

## Configuration

Optional, `~/.config/tokens-menubar/config.json`:

```json
{
  "username": "your-github-username",
  "menuBarRank": "all",
  "apiRefreshSeconds": 300,
  "localRefreshSeconds": 120,
  "topModels": 5
}
```

| Key | Default | Meaning |
| --- | --- | --- |
| `username` | read from `~/.config/tokens/credentials.json` | tokens.ci username |
| `apiBase` | `https://tokens.ci` | API base URL |
| `menuBarRank` | `all` | Which rank the menu bar shows: `all` (lifetime) or `today` |
| `apiRefreshSeconds` | 300 | How often to hit the API (minimum 30) |
| `localRefreshSeconds` | 120 | How often to run the local scan (minimum 30) |
| `topModels` | 5 | Models listed in the dropdown, 0 to list none |

Once you switch the rank from the menu, that remembered choice (`UserDefaults`) wins over `menuBarRank`. To hand control back to the config file: `defaults delete ci.tokens.menubar menuBarRank`.

## Command line

```bash
# Print the menu bar line and the whole dropdown to stdout — useful for
# checking the data path (CLI discovery, network, parsing) without the GUI.
./TokensBar.app/Contents/MacOS/TokensBar --dump

# Launch at login (installs/removes ~/Library/LaunchAgents/ci.tokens.menubar.plist)
./TokensBar.app/Contents/MacOS/TokensBar --set-login on
./TokensBar.app/Contents/MacOS/TokensBar --set-login off
```

The "开机启动" checkbox in the menu does the same thing as `--set-login`.

## How it works

Two data sources, mixed:

- **Ranks, lifetime totals, model split** — the public read-only endpoints `GET /api/users/<name>` and `GET /api/leaderboard?period=all|today&limit=100&page=N`. Both boards are paged through until your own entry turns up, so the rank, the board size and the entry above all come from one ordered list and the gap is self-consistent. No credentials are sent.
- **Today and this week** — the local CLI, `tokens --today --json` and `tokens --week --json`. The server only knows what has been submitted (`tokens serve` submits every 30 minutes by default); the local scan is live, and each of these takes about a second.

Details that are easy to get wrong, handled here:

- `totalTokens = input + output + cacheRead + cacheWrite + reasoning`
- `tokens --json` has no top-level `totalReasoning` — reasoning has to be summed from `entries[].reasoning`
- `modelUsage[].percentage` from the API is a share of **cost**, not tokens (a cheap model can show 0.0% while eating a double-digit share of tokens), so the dropdown recomputes token share locally
- `GET /api/users/<name>?period=today` **does not work** — it echoes `"period": "all"` regardless, so a daily rank has to come from the daily board listing
- The dropdown's 今日 (local scan, this machine only) and the daily board rank (server-side, all your devices summed) are not the same number; with several machines on one account the local figure reads low
- GUI apps do not inherit the shell `PATH`, so the `tokens` binary is probed at `/usr/local/bin` → `/opt/homebrew/bin` → `~/.cargo/bin` → `/usr/bin`

If tokens.ci only works for you through a proxy, note that it sits behind Cloudflare: a shared exit IP can trigger a managed challenge, in which case the endpoints return a 403 challenge page instead of JSON and the dropdown shows 服务端读取失败 (server read failed).

## Credits

TokensBar is only a menu bar front end. All the actual usage accounting is done by:

- [missuo/tokens](https://github.com/missuo/tokens) — the `tokens` CLI this app calls, and the [tokens.ci](https://tokens.ci) leaderboard itself (MIT)
- [junhoyeo/tokscale](https://github.com/junhoyeo/tokscale) — upstream of `missuo/tokens` (MIT)

No code from either project is copied here; TokensBar only reads their CLI output and public read-only API. Not affiliated with tokens.ci.

## License

[MIT](LICENSE), matching both upstream projects.



