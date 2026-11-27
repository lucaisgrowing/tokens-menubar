## TokensBar 1.12.1

### Highlights / 主要更新

- **Smarter Leaderboard Fetching**: Reads `user.isPrivate` from `/api/users/<name>` and skips pointless `/api/leaderboard` pagination for private accounts, unranked all-time profiles, and days with no submitted usage yet.
- **HTTP 429 Rate-Limit Backoff**: Honors `Retry-After` headers (seconds or HTTP-date) with exponential fallback (`60s` up to `10m`), pauses automatic polling during cooldown, displays the next retry time, and stops leaderboard paging immediately on 429 without discarding valid profile data.
- **Structured `tokens status --json` Support**: Switches CLI service detection from text matching to `tokens status --json` (with text fallback), displays `tokens serve` sync intervals, and picks up CLI-authenticated usernames when `credentials.json` is absent.
- **Private-Account Read Token UX**: Displays configured status in Actions & Settings, makes 404/401 error hints clickable straight from the main panel, adds a quick `Open tokens.ci Settings…` button to the Keychain dialog, and adds a gentle confirmation for non-`tkr_` tokens.

- **消除无效榜单翻页请求**：解析 `/api/users/<name>` 的 `user.isPrivate`，对私密账号、总榜未上榜及当日尚未提交的情况自动跳过 `/api/leaderboard` 翻页（避免单次白打最多 12 次无效请求），私密账号在榜单区明确展示说明。
- **HTTP 429 限流退避**：解析 `Retry-After` 响应头（支持秒数与 HTTP-date）并辅以指数退避（`60s` 至 `10m`），退避期间暂停自动轮询并在提示中显示下次重试时间；榜单翻页遇 429 立即中止且保留有效个人数据。
- **改用 `tokens status --json`**：优先解析官方结构化状态输出（保留旧版文本回退），在操作页底部展示 `tokens serve` 自动提交周期，并支持 `credentials.json` 缺失时自动兜底读取 CLI 登录用户名。
- **私密账号读取令牌体验打磨**：设置页与右键菜单展示「已配置」状态，404/401 错误提示条在主面板支持一键点击直达输入框，弹窗内新增「打开 tokens.ci 设置…」快捷按钮与非 `tkr_` 前缀温和二次确认。

[Full changelog / 完整更新日志](https://github.com/lucaisgrowing/tokens-menubar/blob/v1.12.1/CHANGELOG.md)

## Build and verification / 构建与验证

Universal binary (arm64 + x86_64), macOS 13+. This workflow runs the 126 pure-Swift assertions and 10 native light/dark palette/contrast checks under a blue system-accent preference, compiles the full AppKit/Security app on macOS, and verifies both CPU slices, bundle metadata and the ad-hoc signature before publishing.

由 macOS GitHub Actions 构建；发布前运行 126 项纯 Swift 断言和 10 项原生浅深色调色／对比度检查（系统强调色设为蓝色）、完整编译并校验双架构、包信息和 ad-hoc 签名。

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
