# README screenshot provenance

The English and Chinese READMEs use native AppKit offscreen renders of the published **TokensBar v1.11.0 (build 17)** app. They are not design mockups. The unmodified release executable draws the same panel, actions page, model chart and contributions views through its existing diagnostic PNG commands.

The renders use synthetic `demo-user` profile, leaderboard and CLI data. No real account, login, read token, Keychain credential or production API request is used. The diagnostic renderer supplies a fixed backing surface instead of the live popover's translucent material; these images are not desktop screen captures or interactive acceptance tests.

## Current images

[Successful rendering run](https://github.com/lucaisgrowing/tokens-menubar/actions/runs/40480548974) — 2026-10-27, macOS 26.6.2 (25G83).

- Source: the `TokensBar.app.zip` asset from the [v1.11.0 release](https://github.com/lucaisgrowing/tokens-menubar/releases/tag/v1.11.0), downloaded and checked against the release's `SHA256SUMS.txt` before extraction.
- Bundle version checked: `1.11.0`; strict ad-hoc signature verification passed before rendering.
- Rendered executable SHA-256: `ac583b50cb41309485eee657c90738ad14c8294022ae333a99b7bedb26ba4743` (the executable, not the ZIP asset).
- English images: `docs/*.png` in the table below. Chinese images: the matching names under `docs/zh/`.

| File | View | Native PNG dimensions |
| --- | --- | --- |
| `menu.png` | Main panel, light | 360 × 746 |
| `menu-dark.png` | Main panel, dark | 360 × 746 |
| `panel-actions.png` | Actions & Settings, light | 360 × 480 |
| `panel-actions-dark.png` | Actions & Settings, dark | 360 × 480 |
| `chart-today-tokens.png` | Today's models by tokens, light | 380 × 374 |
| `chart-lifetime-cost.png` | Lifetime models by cost, dark | 380 × 374 |
| `contributions.png` | Annual contributions, light | 748 × 216 |

All 14 PNGs were opened for visual review after download. The main panel and actions page cover both appearances; the chart examples deliberately illustrate different periods/metrics and appearances. The Chinese README links to Chinese UI renders rather than reusing the English UI images. The icon and donation QR images were unchanged because their source assets did not change in this release.

## Reproduce for a release

Run the [README snapshots workflow](../.github/workflows/readme-snapshots.yml) with a published release tag:

```sh
gh workflow run readme-snapshots.yml --ref main -f release=v1.11.0
```

The workflow downloads the existing release; it does not rebuild, retag or publish it. On a disposable macOS runner, [`Tools/render-readme-snapshots.sh`](../Tools/render-readme-snapshots.sh) starts the loopback-only [`readme-fixture-server.py`](../Tools/readme-fixture-server.py), installs a temporary synthetic `tokens submit --dry-run` responder, and invokes the released app's `--panel-png`, `--chart-png` and `--contrib-png` commands in each language. It checks all PNGs exist and records their dimensions, macOS version, app version and executable digest in the artifact. Temporary config and CLI files are removed on exit; the script refuses to replace pre-existing ones. Run it only on a disposable runner, not a personal Mac.

Download `TokensBar-readme-snapshots` from the completed workflow, inspect every image, then replace the English files in `docs/` and Chinese files in `docs/zh/`. Update the README release summary and this record together. The generated data covers the year ending on the rendering date, so later runs can differ without a UI change.

## 中文说明

这 14 张图片由已发布的 1.11.0 原生 App 在 macOS 上离屏渲染，使用虚构的 `demo-user` API／CLI 数据；不是 Linux 近似图，也没有使用真实账号、钥匙串令牌或线上 API。诊断模式以固定底色代替实际弹层材质。中英文图片分别生成，浅色／深色主面板与操作页、两种模型图表和贡献图均已逐张检查。它们验证的是实际二进制的静态渲染，不代替真实账号、钥匙串、CLI 和界面交互的人工验收。以后更新版本时，可运行上述工作流、检查并替换图片，同时更新 README 的版本说明和本记录。
