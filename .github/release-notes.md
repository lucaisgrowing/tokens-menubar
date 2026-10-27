## TokensBar 1.11.0

Keeps the original UI modules, teal light/dark style and original macOS typography, with refined spacing, cards, chart details and clearer data labels. Adds private-account read-token support through Keychain, differentiated API errors, truthful successful-update times, a 60-second API polling floor and CLI documentation/parser fixes.

保留原有模块、青绿浅深色与原版系统字体，精修留白、卡片和图表；补上钥匙串 read token、错误分类、成功更新时间、60 秒 API 刷新下限，以及 CLI 文档/解析修正。完整记录见 [CHANGELOG.md](https://github.com/lucaisgrowing/tokens-menubar/blob/v1.11.0/CHANGELOG.md)。

## Build and verification / 构建与验证

Universal binary (arm64 + x86_64), macOS 13+. This workflow runs the 45 pure-Swift assertions, compiles the full AppKit/Security app on macOS, and verifies both CPU slices, bundle metadata and the ad-hoc signature before publishing. These checks do not verify interactive UI, Keychain prompts, private accounts or live CLI behavior.

由 macOS GitHub Actions 构建；发布前运行 45 项纯 Swift 断言、完整编译并校验双架构、包信息和 ad-hoc 签名。尚未完成真人交互、钥匙串提示、私密账号和实际 CLI 的实机验收。

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
