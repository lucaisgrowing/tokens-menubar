# README screenshot provenance

The English and Chinese READMEs use 2× native AppKit offscreen renders of **TokensBar v1.12.0 (build 19)** on macOS. They are not design mockups. The rendering-specific code creates a 2× bitmap at the original view size; it does not upscale an existing image or alter the live interface.

The renders use synthetic `demo-user` profile, leaderboard and CLI data. No real account, login, read token, Keychain credential or production API request is used. The diagnostic renderer supplies a fixed backing surface instead of the live popover's translucent material; these images are not desktop screen captures or interactive acceptance tests.

## Current images

[Successful macOS build and rendering run](https://github.com/lucaisgrowing/tokens-menubar/actions/runs/45957843399) — 2026-11-27, macOS 26.7.2 (25G332).

- Rendered source: commit `bf6a1de` (`v1.12.0`).
- Bundle version checked: `1.12.0` (build `19`). The build, bundle verification, 101 pure-Swift regression checks and 10 native accent/contrast checks passed.
- Rendered executable SHA-256: `8e4725d08e63c29525f965c550c67cc2d6a65d6b160201af32a06b732ec43f5c` (the executable, not the ZIP asset).
- English images: `docs/*.png` in the table below. Chinese images: the matching names under `docs/zh/`.

| File | View | Native PNG dimensions |
| --- | --- | --- |
| `menu.png` | Main panel, light | 720 × 1636 |
| `menu-dark.png` | Main panel, dark | 720 × 1636 |
| `panel-actions.png` | Actions & Settings, light | 720 × 1154 |
| `panel-actions-dark.png` | Actions & Settings, dark | 720 × 1154 |
| `chart-today-tokens.png` | Today's models by tokens, light | 760 × 748 |
| `chart-lifetime-cost.png` | Lifetime models by cost, dark | 760 × 748 |
| `contributions.png` | Annual contributions, light | 1496 × 432 |

The main panel and actions page cover both appearances; the chart examples illustrate different periods/metrics and appearances. The Chinese README links to Chinese UI renders rather than reusing the English UI images.

## Reproduce

Run the [build workflow](../.github/workflows/build.yml) for the desired source ref. Its macOS job builds a candidate app and calls [`Tools/render-readme-snapshots.sh`](../Tools/render-readme-snapshots.sh), which starts the loopback-only [`readme-fixture-server.py`](../Tools/readme-fixture-server.py), installs a temporary synthetic `tokens submit --dry-run` responder, and invokes the app's diagnostic PNG commands in each language. Temporary config and CLI files are removed on exit; the script refuses to replace pre-existing ones. Run only on a disposable runner, not a personal Mac. Download `TokensBar-candidate-snapshots` from the completed workflow and inspect the images before replacing the English files in `docs/` and Chinese files in `docs/zh/`. The generated data covers the year ending on the rendering date, so later runs can differ without a UI change.

## 中文说明

这 14 张图片由 **1.12.0** 源码构建的 App 在 macOS 上通过 GitHub Actions 以 2× 分辨率原生离屏渲染，使用虚构的 `demo-user` API／CLI 数据。截图模式使用固定底色代替实际弹层材质；它不是桌面截图，也不代替真实账号、钥匙串、CLI 和界面交互的人工验收。
