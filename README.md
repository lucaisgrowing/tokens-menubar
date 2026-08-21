<div align="right">
  <a href="README.md"><img src="https://img.shields.io/badge/English-1f6feb?style=for-the-badge&logoColor=white" alt="English"></a>
  <a href="README.zh-CN.md"><img src="https://img.shields.io/badge/简体中文-6e7681?style=for-the-badge&logoColor=white" alt="简体中文"></a>
</div>

<p align="center">
  <img src="docs/icon.png" width="128" alt="TokensBar icon">
</p>

# TokensBar

Your [tokens.ci](https://tokens.ci) token usage and leaderboard rank, in the macOS menu bar — no browser tab needed.

[![Build](https://github.com/lucaisgrowing/tokens-menubar/actions/workflows/build.yml/badge.svg)](https://github.com/lucaisgrowing/tokens-menubar/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/lucaisgrowing/tokens-menubar?style=flat-square)](https://github.com/lucaisgrowing/tokens-menubar/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-lightgrey?style=flat-square)
![Universal](https://img.shields.io/badge/binary-arm64%20%2B%20x86__64-lightgrey?style=flat-square)

Single-file Swift, compiled straight with `swiftc`. No Xcode project, no dependencies beyond system frameworks.

<p align="center">
  <img src="docs/menu.png" width="460" alt="The TokensBar dropdown">
</p>

```
menu bar:  ⚡ 12.4M  #87       ← all-time rank
     or:   ⚡ 12.4M  D#31      ← today's rank
```

English and 简体中文 are both built in — switch from the Language submenu (English is the default), or set `language` in the config file.

## Model distribution

Clicking the **Lifetime** or **Today** row opens a popover under the menu bar icon with a donut chart of the per-model split, and a Tokens / Cost toggle:

- **Lifetime** comes from the API's `modelUsage`
- **Today** comes from the local CLI scan, so it is live rather than waiting on the next submission

The top seven models get their own slice and the rest are folded into "Others". The popover refreshes in place as new data arrives.

<p align="center">
  <img src="docs/chart-today-tokens.png" width="360" alt="Today's model distribution by tokens">
  <img src="docs/chart-lifetime-cost.png" width="360" alt="Lifetime model distribution by cost">
</p>

## The two ranks

- **All-time** — ranked by lifetime tokens. This is the board on the tokens.ci front page.
- **今日榜 (today)** — ranked by tokens submitted today only. Just the people who submitted today are on it, so it is a smaller board and the rank moves a lot.

`#87 / 265` reads "rank 87 out of 265 people on the board" — it is **one** rank, not two different ones. In the menu bar a daily rank is prefixed (`D#31`, 今#31 in Chinese) so it cannot be mistaken for a lifetime one.

Pick which one the menu bar shows from the "Rank Shown in Menu Bar" submenu (the choice is remembered), or set `menuBarRank` in the config file for the default. Both ranks are always listed in the dropdown; the setting only changes the menu bar line and which board the gap line refers to.

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

The icon lives at `Resources/AppIcon.icns` and is committed. It is drawn in code — edit `Tools/make-icon.swift` and run `swift Tools/make-icon.swift` to regenerate it.

## Configuration

Optional, `~/.config/tokens-menubar/config.json`:

```json
{
  "username": "your-github-username",
  "language": "en",
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
| `language` | `en` | UI language: `en` or `zh` |
| `menuBarRank` | `all` | Which rank the menu bar shows: `all` (lifetime) or `today` |
| `apiRefreshSeconds` | 300 | How often to hit the API (minimum 30) |
| `localRefreshSeconds` | 120 | How often to run the local scan (minimum 30) |
| `topModels` | 5 | Models listed in the dropdown, 0 to list none |

Switching the rank or the language from the menu stores the choice in `UserDefaults`, which then wins over the config file. To hand control back: `defaults delete ci.tokens.menubar menuBarRank` (or `language`).

## Updates

"Check for Updates…" compares the bundle version against the latest GitHub release. A daily background check runs too; when a newer release exists the menu item turns into a download link. Nothing is ever installed automatically.

## Command line

```bash
# Print the menu bar line, the whole dropdown and both chart breakdowns to
# stdout — useful for checking the data path without the GUI.
./TokensBar.app/Contents/MacOS/TokensBar --dump [--lang en|zh]

# Render the chart popover offscreen to a PNG, to review the layout itself.
./TokensBar.app/Contents/MacOS/TokensBar --chart-png out.png [today|lifetime] [tokens|cost]

# Compare this build against the latest GitHub release.
./TokensBar.app/Contents/MacOS/TokensBar --check-updates

# Launch at login (installs/removes ~/Library/LaunchAgents/ci.tokens.menubar.plist)
./TokensBar.app/Contents/MacOS/TokensBar --set-login on
./TokensBar.app/Contents/MacOS/TokensBar --set-login off
```

The "Launch at Login" checkbox in the menu does the same thing as `--set-login`.

## How it works

Two data sources, mixed:

- **Ranks, lifetime totals, model split** — the public read-only endpoints `GET /api/users/<name>` and `GET /api/leaderboard?period=all|today&limit=100&page=N`. Both boards are paged through until your own entry turns up, so the rank, the board size and the entry above all come from one ordered list and the gap is self-consistent. No credentials are sent.
- **Today and this week** — the local CLI, `tokens --today --json` and `tokens --week --json`. The server only knows what has been submitted (`tokens serve` submits every 30 minutes by default); the local scan is live, and each of these takes about a second.

Details that are easy to get wrong, handled here:

- `totalTokens = input + output + cacheRead + cacheWrite + reasoning`
- `tokens --json` has no top-level `totalReasoning` — reasoning has to be summed from `entries[].reasoning`
- `modelUsage[].percentage` from the API is a share of **cost**, not tokens (a cheap model can show 0.0% while eating a double-digit share of tokens), so the dropdown recomputes token share locally
- `GET /api/users/<name>?period=today` **does not work** — it echoes `"period": "all"` regardless, so a daily rank has to come from the daily board listing
- The dropdown's Today (local scan, this machine only) and the daily board rank (server-side, all your devices summed) are not the same number; with several machines on one account the local figure reads low
- GUI apps do not inherit the shell `PATH`, so the `tokens` binary is probed at `/usr/local/bin` → `/opt/homebrew/bin` → `~/.cargo/bin` → `/usr/bin`

If tokens.ci only works for you through a proxy, note that it sits behind Cloudflare: a shared exit IP can trigger a managed challenge, in which case the endpoints return a 403 challenge page instead of JSON and the dropdown reports that the server read failed.

## Credits

TokensBar is only a menu bar front end. All the actual usage accounting is done by:

- [missuo/tokens](https://github.com/missuo/tokens) — the `tokens` CLI this app calls, and the [tokens.ci](https://tokens.ci) leaderboard itself (MIT)
- [junhoyeo/tokscale](https://github.com/junhoyeo/tokscale) — upstream of `missuo/tokens` (MIT)

No code from either project is copied here; TokensBar only reads their CLI output and public read-only API. Not affiliated with tokens.ci.

## License

[MIT](LICENSE), matching both upstream projects.



