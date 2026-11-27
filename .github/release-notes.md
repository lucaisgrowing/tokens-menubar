## TokensBar 1.12.0

### Highlights / 主要更新

- **Redesigned UI & macOS AppIcon**: Elevated light/dark card hierarchy, proportional model bars, macOS Settings-style grouped Actions & Settings page, and a new text-free deep obsidian-teal AppIcon with emerald-mint telemetry bars.
- **Live Mini-Leaderboard Ladder**: Replaces the static near-100% progress bar with a 3-row race around your rank (rival above, you highlighted, rival below), percentile badge (`Top XX%`), and 1-click Today / All-time switching.
- **Animated 7-Day Pace Bar**: Smooth ease-out glide with a one-shot specular highlight sweep on the Today / 7-day average bar (respects Reduce Motion).
- **In-App Settings & Hot-Reload**: Toggle menu-bar items (`Tokens` / `Cost` / `Rank`) and set your daily USD budget directly from Actions & Settings, with automatic hot-reload for `config.json` and `tokens login`.
- **Streak, Cache Hit Rate & CLI Update Check**: Shows UTC active-day streaks, prompt cache-hit ratio, local `tokens` CLI version / `tokens serve` status, and alerts when a newer `missuo/tokens` CLI is available.
- **Reliability & Updater Verification**: Fixes `#101`/`#201` leaderboard boundary lookups and the 600-user cap via direct page jumping, adds wake & network-recovery refresh, throttles local CLI scans, verifies `SHA256SUMS.txt` + bundle ID during in-place updates, and expands pure-Swift tests to 101 checks.

- **全新界面与 macOS 图标**：重构浅深色立体卡片层级、模型比例底条与系统设置风格分组操作页，并重绘与青绿主题一致的无文字深青玻璃质感 AppIcon。
- **3 人实时梯队排行榜**：用「上一名 / 你（青绿高亮）/ 下一名」实时梯队取代常年满格的追赶条，附带 `前 XX%` 百分位徽章与一键切换今日榜 / 累计榜。
- **均值进度条动效**：「今日 / 7 日均值」进度条新增顺滑展开与高光扫掠动效（完整适配系统「减弱动态效果」）。
- **可视化设置与热重载**：操作页直接勾选菜单栏显示项（Token / 费用 / 排名）与配置每日预算，监听 `config.json` 与 `credentials.json` 变动自动热重载。
- **连胜、缓存命中率与 CLI 检测**：新增 UTC 连续活跃天数（Streak）、提示词缓存命中率，以及 `tokens` CLI 新版检测与 `tokens serve` 状态提示。
- **可靠性与更新校验**：修复 `#101`/`#201` 跨页丢失上一名与 600 名上限、补齐休眠唤醒与断网重连刷新、本地扫描节流、就地更新增加 `SHA256SUMS.txt` 与 Bundle ID 校验，纯 Swift 离线回归测试扩展至 101 项。

[Full changelog / 完整更新日志](https://github.com/lucaisgrowing/tokens-menubar/blob/v1.12.0/CHANGELOG.md)

## Build and verification / 构建与验证

Universal binary (arm64 + x86_64), macOS 13+. This workflow runs the 101 pure-Swift assertions and 10 native light/dark palette/contrast checks under a blue system-accent preference, compiles the full AppKit/Security app on macOS, and verifies both CPU slices, bundle metadata and the ad-hoc signature before publishing.

由 macOS GitHub Actions 构建；发布前运行 101 项纯 Swift 断言和 10 项原生浅深色调色／对比度检查（系统强调色设为蓝色）、完整编译并校验双架构、包信息和 ad-hoc 签名。

## Install / 安装

Download `TokensBar.app.zip`, unzip and move `TokensBar.app` to `/Applications`. Requires the [`tokens`](https://github.com/missuo/tokens) CLI installed and logged in. Download the matching native CLI for your Mac architecture.

下载 `TokensBar.app.zip`，解压后将 App 移到 `/Applications`；需要安装并登录 [`tokens`](https://github.com/missuo/tokens) CLI，CLI 架构应与 Mac 匹配。

This app is ad-hoc signed, not Developer ID signed or notarized. macOS may block opening an internet download. If you trust this release, use the opening exception in System Settings → Privacy & Security when available. Alternatively remove this app's quarantine flag only:

这个包使用 ad-hoc 签名，没有 Developer ID 签名或 Apple 公证。macOS 可能拦截下载的 App；确认信任此发布后，可在「系统设置 → 隐私与安全性」允许打开，或只移除此 App 的隔离标记：

```bash
xattr -dr com.apple.quarantine /Applications/TokensBar.app
open /Applications/TokensBar.app
```

MIT licensed. Credits to [missuo/tokens](https://github.com/missuo/tokens) and [junhoyeo/tokscale](https://github.com/junhoyeo/tokscale). TokensBar is an unofficial menu bar front end, not affiliated with tokens.ci.
