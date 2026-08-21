# TokensBar

在 macOS 菜单栏上看 [tokens.ci](https://tokens.ci) 的 token 用量和排名，不用再开网页。

单文件 Swift，`swiftc` 直接编译，不需要 Xcode 工程，除了系统框架没有任何依赖。

```
菜单栏:  ⚡ 20.2M  #174

下拉:
  #174 / 265  ·  @lucaisgrowing
  ──────────────────────────────
  累计   4.03B     $7,161.81
  今日   20.2M     $92.48
  本周   424.8M    $1,013.79
  ──────────────────────────────
  距 #173 @fl0w1nd 还差 30.1M
  ──────────────────────────────
  claude-opus-4-8          33.7%  1.36B
  gpt-5.6-sol              28.0%  1.13B
  glm-4.5-flash            14.1%  568.0M
  claude-opus-4-6           5.3%  215.3M
  claude-opus-4-7           4.3%  174.8M
  ──────────────────────────────
  本地 11:44  ·  服务端 11:35
  立即提交 / 刷新 / 打开主页 / 开机启动 / 退出
```

## 前提

需要先装好并登录 [`tokens`](https://github.com/missuo/tokens) CLI：

```bash
brew install owo-network/brew/tokens
tokens login
```

## 安装

```bash
git clone https://github.com/lucaisgrowing/tokens-menubar.git
cd tokens-menubar
./build.sh
open TokensBar.app
```

编出来的是 ad-hoc 签名的未公证 app。第一次打开若被 Gatekeeper 拦，在「系统设置 → 隐私与安全性」里点「仍要打开」，或者 `xattr -dr com.apple.quarantine TokensBar.app`。

app 是 `LSUIElement`，只在菜单栏出现，没有 Dock 图标和窗口。

## 配置

可选，`~/.config/tokens-menubar/config.json`：

```json
{
  "username": "lucaisgrowing",
  "apiRefreshSeconds": 300,
  "localRefreshSeconds": 120,
  "topModels": 5
}
```

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `username` | 读 `~/.config/tokens/credentials.json` | tokens.ci 用户名 |
| `apiBase` | `https://tokens.ci` | API 地址 |
| `apiRefreshSeconds` | 300 | 拉服务端数据的间隔（最小 30） |
| `localRefreshSeconds` | 120 | 跑本地扫描的间隔（最小 30） |
| `topModels` | 5 | 下拉里列几个模型，0 = 不列 |

## 命令行

```bash
# 把菜单栏那行和整个下拉内容打到终端，用来排查数据链路
./TokensBar.app/Contents/MacOS/TokensBar --dump

# 开机启动（装/卸 ~/Library/LaunchAgents/ci.tokens.menubar.plist）
./TokensBar.app/Contents/MacOS/TokensBar --set-login on
./TokensBar.app/Contents/MacOS/TokensBar --set-login off
```

菜单里的「开机启动」勾选项做的是同一件事。

## 工作原理

两个数据源混着用：

- **排名、累计、模型占比** —— tokens.ci 的公开只读接口 `GET /api/users/<name>` 和 `GET /api/leaderboard?limit=20&page=N`（后者用来拿上一名的量算差距，`page = ceil(rank / limit)`）。不带任何凭据，只读。
- **今日、本周** —— 本地跑 `tokens --today --json` / `tokens --week --json`。服务端只有已提交的数据（`tokens serve` 默认 30 分钟一轮），本地扫描才是实时的，而且这两条各只要约 1 秒。

几个容易算错的地方，实现里已经处理：

- `totalTokens = input + output + cacheRead + cacheWrite + reasoning`
- `tokens --json` 顶层没有 `totalReasoning`，reasoning 得从 `entries[].reasoning` 自己加
- API `modelUsage[].percentage` 是**花费**占比不是 token 占比（便宜模型会显示 0.0% 却吃掉两位数百分比的 token），所以下拉里的百分比是本地按 token 重算的
- GUI app 不继承 shell 的 `PATH`，`tokens` 二进制按 `/usr/local/bin` → `/opt/homebrew/bin` → `~/.cargo/bin` → `/usr/bin` 逐个探

如果 tokens.ci 走代理才通，注意它在 Cloudflare 后面：共享出口 IP 可能触发 managed challenge，此时接口会返回 403 的挑战页而不是 JSON，菜单里会显示成「服务端读取失败」。

## 引用与致谢

本项目只是给下面这些项目做了个菜单栏前端，核心的用量统计工作都是它们做的：

- [missuo/tokens](https://github.com/missuo/tokens) —— 本项目调用的 `tokens` CLI，以及 [tokens.ci](https://tokens.ci) 排行榜本身（MIT）
- [junhoyeo/tokscale](https://github.com/junhoyeo/tokscale) —— `missuo/tokens` 的上游（MIT）

TokensBar 没有复制上述项目的任何代码，只通过它们的 CLI 输出和公开只读 API 取数。与 tokens.ci 官方无隶属关系。

## 协议

[MIT](LICENSE)，与上游两个项目保持一致。

---

**English:** TokensBar is a tiny macOS menu bar app that shows your [tokens.ci](https://tokens.ci) AI coding token usage — today's tokens plus your leaderboard rank in the menu bar, with lifetime totals, weekly usage, the gap to the next rank, and a per-model token split in the dropdown. Single-file Swift, built with `swiftc` via `./build.sh`, no dependencies beyond system frameworks. Requires the [`tokens`](https://github.com/missuo/tokens) CLI to be installed and logged in. MIT licensed; credits to [missuo/tokens](https://github.com/missuo/tokens) and [junhoyeo/tokscale](https://github.com/junhoyeo/tokscale).


