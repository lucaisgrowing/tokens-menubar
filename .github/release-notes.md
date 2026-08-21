## Install / 安装

Download `TokensBar.app.zip`, unzip, move it to `/Applications`, then clear the quarantine flag:

解压后拖进 `/Applications`，然后去掉隔离标记：

```bash
xattr -dr com.apple.quarantine /Applications/TokensBar.app
open /Applications/TokensBar.app
```

The build is ad-hoc signed and **not notarised**, so macOS refuses to open it until the quarantine attribute is gone. Right-click → Open, or System Settings → Privacy & Security, works too.

这个包是 ad-hoc 签名、**没有公证**的，隔离标记不去掉 macOS 会直接拒绝打开。也可以右键 → 打开，或者去「系统设置 → 隐私与安全性」里点「仍要打开」。

Requires the [`tokens`](https://github.com/missuo/tokens) CLI installed and logged in (`brew install owo-network/brew/tokens && tokens login`). Universal binary (arm64 + x86_64), macOS 13+, built by GitHub Actions.

需要先装好并登录 [`tokens`](https://github.com/missuo/tokens) CLI。universal 二进制（arm64 + x86_64），要求 macOS 13 以上，由 GitHub Actions 构建。

MIT licensed. Credits to [missuo/tokens](https://github.com/missuo/tokens) and [junhoyeo/tokscale](https://github.com/junhoyeo/tokscale) — TokensBar is only a menu bar front end for their work, and is not affiliated with tokens.ci.

