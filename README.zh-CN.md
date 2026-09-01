<div align="right">
  <a href="README.md"><img src="https://img.shields.io/badge/English-6e7681?style=for-the-badge&logoColor=white" alt="English"></a>
  <a href="README.zh-CN.md"><img src="https://img.shields.io/badge/简体中文-1f6feb?style=for-the-badge&logoColor=white" alt="简体中文"></a>
</div>

<p align="center">
  <img src="docs/icon.png" width="112" alt="TokensBar icon">
</p>

<h1 align="center">TokensBar</h1>

<p align="center">
  在 macOS 菜单栏上看 <a href="https://tokens.ci">tokens.ci</a> 的 token 用量和排名，不用再开网页。
</p>

<p align="center">
  <a href="https://github.com/lucaisgrowing/tokens-menubar/actions/workflows/build.yml"><img src="https://github.com/lucaisgrowing/tokens-menubar/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <a href="https://github.com/lucaisgrowing/tokens-menubar/releases/latest"><img src="https://img.shields.io/github/v/release/lucaisgrowing/tokens-menubar?style=flat-square" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-lightgrey?style=flat-square" alt="macOS 13+">
  <img src="https://img.shields.io/badge/binary-arm64%20%2B%20x86__64-lightgrey?style=flat-square" alt="Universal">
</p>

Swift 编写，`swiftc` 直接编译，不需要 Xcode 工程，除了系统框架没有任何依赖。

<p align="center">
  <img src="docs/menu.png" width="380" alt="TokensBar 下拉面板（浅色）">
  <img src="docs/menu-dark.png" width="380" alt="TokensBar 下拉面板（深色）">
</p>

```
菜单栏:  ⚡ 12.4M  #87       ← 累计榜名次
  或:    ⚡ 12.4M  今#31     ← 当日榜名次
```

前面那个 token 数是整个账号今天的总量，跟网站上是同一个数，所以和旁边的名次口径一致。把鼠标放在图标上还能看到本机的实时值。

界面内置中英双语，默认英文，在面板的操作页或右键菜单「语言 / Language」下面那两行里随时切换，也可以在 config.json 里写 `language` 设默认。

## 下拉面板

左键点图标弹出的就是上面那块面板。最上面是今天的总量，接着是菜单栏当前显示的那个榜
—— 跟前一名的差距画成一条进度条，然后是今天和之前 7 天均值的对比，另一个榜和本周做
成两张小卡片，再往下是近 7 天的柱状图，最后是今天的模型占比，颜色和环形图一致。悬停
某根柱子，标题右边会读出那一天的数。

点面板上的区块会打开对应的视图：最上面的总量、或任意一行模型，打开环形图；柱状图打开
贡献热力图；小卡片打开另一个榜的明细。可点的区块右边都带一个小箭头，底部那行字会说明
鼠标当前指着的区块点下去会打开什么 —— 没指任何东西时，它说明面板怎么用。**提交**按钮
跑 `tokens submit`，结果显示在底部，旁边是最近一次本地扫描和服务端刷新的时间。

右键点图标 —— 或者点面板右上角的 ⋯ —— 都能拿到同一组动作。⋯ 不再往面板上盖一层菜单，
而是把面板翻到第二页：提交、刷新、排名和语言做成一排胶囊按钮、开机启动是个开关，再往下是
打开主页、检查更新、赞助和退出，顶上是 **‹ 操作与设置**，底下是当前版本号。两套界面现在
彻底分开了：左键点图标出面板，右键点图标出那个纯 NSMenu，面板里没有任何一处再把菜单盖回来。
菜单的动作和快捷键都没变，只有一层：数字排在最上面，点它们打开的模型分布从菜单栏算起只要
一次点击；排名和语言的选项改成标题下面的缩进行，不再做成子菜单。

<p align="center">
  <img src="docs/panel-actions.png" width="380" alt="面板里的操作页（浅色）">
  <img src="docs/panel-actions-dark.png" width="380" alt="面板里的操作页（深色）">
</p>

## 模型分布饼图

点最上面的总量、任意一行模型 —— 或者菜单里的**累计** / **今日**那一行 —— 会在菜单栏图标下方弹出一个面板，里面是环形图，右上角带 Token / 费用 切换：

- **累计**用 API 的 `modelUsage`
- **今日**用 API `contributions` 里当天那条，所以覆盖账号下的全部设备，跟「今日」那一行是同一个数；当天第一次提交之前没有服务端数据，会退回本地扫描

前 5 个模型各占一块，其余折进「其他」—— 环形图超过 6 块就不好读了。只有一两个模型时会改画成一条 100% 的横条。浅色和深色模式各用一套配色，分别按各自背景做过对比度和色盲可分辨性校验。

面板打开、以及切换 Token / 费用 时，图表会有一段画入动效。鼠标悬停某一块（或图例里对应那一行），两边会同时高亮、其余变淡，中间的读数换成那个模型自己的数字。

<p align="center">
  <img src="docs/chart-today-tokens.png" width="360" alt="今日模型分布（按 token）">
  <img src="docs/chart-lifetime-cost.png" width="360" alt="累计模型分布（按费用）">
</p>

## 贡献图

面板上的近 7 天柱状图 —— 或者菜单里的**活跃天数**那一行 —— 点开是一年的每日 token 活动热力图，跟网站上那块是同一个视图。悬停某一天会读出当天的 token、花费、消息条数和各客户端占比；没悬停时显示活跃天数和统计区间。

<p align="center">
  <img src="docs/contributions.png" width="640" alt="一年的每日 token 活动热力图">
</p>

右上角的切换决定下方读数按什么拆分：**模型**、**客户端**、**金额**。切到金额时格子的深浅也会跟着变 —— token 的深浅用 API 给的强度，金额的深浅是按每日花费的四分位自己算的，所以「量大但便宜」和「量小但贵」两种日子看起来不一样。

色阶是单一色相由浅到深，浅色和深色模式各一套；只要当天有用量，就不会退回成空格子的颜色。

## 两个排名

- **累计榜** —— 历史总量的排名，也就是 tokens.ci 首页那个榜
- **今日榜** —— 只按当天提交量排，榜上只有当天提交过的人，所以人数少、名次跳动大

`#87 / 265` 是「第 87 名 / 榜上共 265 人」。当日名次在菜单栏里前面带个「今」字（`今#31`），用来跟累计名次区分。

菜单栏显示哪一个，在面板操作页的「菜单栏显示排名」那一行、或右键菜单里同名标题下面的两行随时切换（选择会记住）；想改默认值就在 config.json 里写 `menuBarRank`。两个排名在面板和菜单里始终都列出来，切换只影响菜单栏那一行、以及差距进度条看的是哪个榜。

## 前提

需要先装好并登录 [`tokens`](https://github.com/missuo/tokens) CLI：

```bash
brew install owo-network/brew/tokens
tokens login
```

## 安装

去 [Releases](https://github.com/lucaisgrowing/tokens-menubar/releases) 下 `TokensBar.app.zip`，解压后拖进 `/Applications`，然后去掉隔离标记：

```bash
xattr -dr com.apple.quarantine /Applications/TokensBar.app
open /Applications/TokensBar.app
```

发布的包是 ad-hoc 签名、**没有公证**的，所以隔离标记不去掉 macOS 会直接拒绝打开。也可以右键 → 打开，或者去「系统设置 → 隐私与安全性」里点「仍要打开」。release 里的二进制是 universal（arm64 + x86_64），要求 macOS 13 以上。

也可以自己编，除了 Xcode 自带的 Swift 工具链什么都不需要：

```bash
git clone https://github.com/lucaisgrowing/tokens-menubar.git
cd tokens-menubar
./build.sh              # 只编本机架构
./build.sh --universal  # arm64 + x86_64
open TokensBar.app
```

app 是 `LSUIElement`，只在菜单栏出现，没有 Dock 图标和窗口。

图标是 `Resources/AppIcon.icns`，已经提交进仓库。它是用代码画的 —— 改 `Tools/make-icon.swift` 然后跑 `swift Tools/make-icon.swift` 重新生成。

## 配置

可选，`~/.config/tokens-menubar/config.json`：

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

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `username` | 读 `~/.config/tokens/credentials.json` | tokens.ci 用户名 |
| `apiBase` | `https://tokens.ci` | API 地址 |
| `language` | `en` | 界面语言：`en` 或 `zh` |
| `menuBarRank` | `all` | 菜单栏默认显示哪个排名：`all` 累计榜 / `today` 当日榜 |
| `apiRefreshSeconds` | 300 | 拉服务端数据的间隔（最小 30） |
| `localRefreshSeconds` | 120 | 跑本地扫描的间隔（最小 30） |
| `topModels` | 5 | 下拉里列几个模型，0 = 不列 |

在菜单里切过排名或语言之后，记住的选择（`UserDefaults`）优先于 config.json。想让 config 重新生效：`defaults delete ci.tokens.menubar menuBarRank`（语言是 `language`）。

## 检查更新

「检查更新」把当前 bundle 版本和 GitHub 最新 release 比一下。后台每天也会静默查一次，有新版时这个菜单项会变成安装链接。

点一下就地更新：下载那个 release 的 `TokensBar.app.zip`，确认里面的 bundle 确实是它宣称的版本，替换掉正在运行的 app 并重启——不用开浏览器、不用解压、不用往 `/Applications` 拖，也不用再去掉隔离标记。会先弹窗确认，没点确认不会装任何东西。如果 app 所在目录当前账号写不进去，或者那个 release 没附 zip，就还是打开 release 页面，跟以前一样。

这里的信任基础是到 GitHub 的 HTTPS。下载包没有做代码签名校验——构建是 ad-hoc 签名而非公证的，在同一个地址旁边再发一个 `SHA-256` 并不能多证明什么。

## 命令行

```bash
# 把菜单栏那行、整个下拉、以及两个图表的明细打到终端，便于排查数据链路
./TokensBar.app/Contents/MacOS/TokensBar --dump [--lang en|zh]

# 把整个图表面板离屏渲染成 PNG，用来预览布局
# dark = 深色模式，hover N = 第 N 块的悬停态，reveal F = 把画入动效冻结在进度 F
./TokensBar.app/Contents/MacOS/TokensBar --chart-png out.png \
    [today|lifetime] [tokens|cost] [dark] [hover N] [reveal F]

# 把贡献图离屏渲染成 PNG
./TokensBar.app/Contents/MacOS/TokensBar --contrib-png out.png \
    [models|clients|cost] [dark] [hover YYYY-MM-DD]

# 把下拉面板离屏渲染成 PNG，同时打印各个可点区域 —— 静态图看不出点哪里会有反应
# dark = 深色模式，menu = 操作页，hover N = 近 7 天里第 N 天的悬停态（0 是最早那天），
# hit N = 第 N 个可点区域的悬停态，也就是底部提示行会跟着变的那个
./TokensBar.app/Contents/MacOS/TokensBar --panel-png out.png [dark] [menu] [hover N] [hit N] [notice success|failure|info 文字]

# 用一个临时锚点真的把面板弹出来，打印它的实际几何，还能顺便截下弹出窗口
# 面板偏心就是靠这个查出来的：popover 会给内容视图留边，它给的尺寸和我们要的尺寸不是一回事
# 加 menu 会在弹出后翻到操作页 —— 给已经显示的 popover 改尺寸只有这条路能验
./TokensBar.app/Contents/MacOS/TokensBar --panel-probe [out.png] [menu]

# 把菜单按树打印出来，缩进行会按它的缩进级别显示
./TokensBar.app/Contents/MacOS/TokensBar --menu-dump

# 拿当前版本和 GitHub 最新 release 比一下
./TokensBar.app/Contents/MacOS/TokensBar --check-updates

# 下载、校验并把最新 release 装到当前 bundle 上，然后重启
# 跟菜单里那个更新走同一条路径，只是省掉点击和确认弹窗，所以拿副本试，别拿在用的那个
./TokensBar.app/Contents/MacOS/TokensBar --self-update

# 跑菜单里「立即提交」走的同一条路径，便于在终端复现失败；加 --dry-run 则不真的上报
./TokensBar.app/Contents/MacOS/TokensBar --submit [--dry-run]

# 开机启动（装/卸 ~/Library/LaunchAgents/ci.tokens.menubar.plist）
./TokensBar.app/Contents/MacOS/TokensBar --set-login on
./TokensBar.app/Contents/MacOS/TokensBar --set-login off
```

菜单里的「开机启动」勾选项做的是同一件事。

## 工作原理

两个数据源：

- **API** —— tokens.ci 的公开只读接口 `GET /api/users/<name>` 和 `GET /api/leaderboard?period=all|today`，不带任何凭据。两个排名、累计总量、模型占比、贡献图，以及**今日的总量**都来自这里
- **本地 CLI** —— `tokens --today --json` / `tokens --week --json`，提供本周、以及本机的今日用量

两点值得知道：

- 下拉里的百分比是按 **token** 重算的占比。API 自带的百分比是按**花费**算的，两者会不一样
- 「今日」那一行是服务端的数，所以跟当日榜名次、跟网站都对得上：账号下所有设备的累计，截止到最近一次提交。它下面那行灰字是本机的实时扫描。两个数会双向偏差 —— 别的机器的用量只在前者里，最近一次提交之后新产生的量只在后者里。token 的差距可能远大于金额的差距，因为大量走缓存的免费模型能贡献几百万 token 却几乎不花钱

接口拉不通时，下拉会显示服务端读取失败，并保留上一次拿到的数据。

## 赞助

TokensBar 一直免费。如果它帮你省下了开网页的功夫，欢迎用 USDT 请杯咖啡，两条链都可以：

| 链 | 地址 |
| --- | --- |
| TRON（TRC20） | `TNKSjygE7JaMSJBPZcYPpWxVPUKrFr8DDU` |
| Ethereum · BNB Chain · Base（ERC20 / BEP20） | `0x027E4828B67f4c8cAc006A637Cab4f0164F501B8` |

<table align="center">
  <tr>
    <td align="center"><img src="docs/qr-tron.png" width="170" alt="TRON TRC20 收款地址二维码"><br><sub>TRON（TRC20）</sub></td>
    <td align="center"><img src="docs/qr-evm.png" width="170" alt="EVM 收款地址二维码"><br><sub>ERC20 / BEP20 / Base</sub></td>
  </tr>
</table>

转账前先确认链，两个地址不能混用。

## 引用与致谢

本项目只是给下面这些项目做了个菜单栏前端，核心的用量统计工作都是它们做的：

- [missuo/tokens](https://github.com/missuo/tokens) —— 本项目调用的 `tokens` CLI，以及 [tokens.ci](https://tokens.ci) 排行榜本身（MIT）
- [junhoyeo/tokscale](https://github.com/junhoyeo/tokscale) —— `missuo/tokens` 的上游（MIT）

TokensBar 没有复制上述项目的任何代码，只通过它们的 CLI 输出和公开只读 API 取数。与 tokens.ci 官方无隶属关系。

## 协议

[MIT](LICENSE)，与上游两个项目保持一致。


