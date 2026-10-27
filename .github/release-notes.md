## TokensBar 1.11.1

Restores the original deep-green buttons and highlights instead of inheriting the system accent color. Ranking/average and activity bars, selected settings, header icon, informational feedback and share-card emphasis use the app palette in light and dark mode. Small dark-mode accent text is lifted for legibility. Original fonts, layout, functions, semantic status colors and model-category colors are preserved.

恢复原来的墨绿／深绿色按钮和高亮，不再随 macOS 的系统蓝色等强调色变化；排名／均值与活动条、设置选中项、标题图标、信息提示和战绩卡强调色保持一致。深色模式的小号绿色文字适当提亮以保证可读性，原字体、布局、功能、状态色与模型分类色不变。

[Full changelog / 完整更新日志](https://github.com/lucaisgrowing/tokens-menubar/blob/v1.11.1/CHANGELOG.md)。

## Build and verification / 构建与验证

Universal binary (arm64 + x86_64), macOS 13+. This workflow runs the 45 pure-Swift assertions and 10 native light/dark palette/contrast checks under a blue system-accent preference, compiles the full AppKit/Security app on macOS, and verifies both CPU slices, bundle metadata and the ad-hoc signature before publishing. These checks do not verify interactive UI, Keychain prompts, private accounts or live CLI behavior.

由 macOS GitHub Actions 构建；发布前运行 45 项纯 Swift 断言和 10 项原生浅深色调色／对比度检查（故意使用蓝色系统强调色）、完整编译并校验双架构、包信息和 ad-hoc 签名。尚未完成真人交互、钥匙串提示、私密账号和实际 CLI 的实机验收。

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
