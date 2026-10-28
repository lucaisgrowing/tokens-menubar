# README screenshot provenance

The English and Chinese READMEs use 2× native AppKit offscreen renders of a **TokensBar v1.11.1 (build 18)** source build on macOS. They are not design mockups. The rendering-specific code creates a 2× bitmap at the original view size; it does not upscale an existing image or alter the live interface.

The renders use synthetic `demo-user` profile, leaderboard and CLI data. No real account, login, read token, Keychain credential or production API request is used. The diagnostic renderer supplies a fixed backing surface instead of the live popover's translucent material; these images are not desktop screen captures or interactive acceptance tests.

## Current images

[Successful macOS build and rendering run](https://github.com/lucaisgrowing/tokens-menubar/actions/runs/40654008694) — 2026-10-28, macOS 26.6.2 (25G83).

- Rendered source: commit `1a784f41450fa905663fe760c29bd9ba5675c320`, based on the v1.11.1 main branch, with the snapshot-only 2× bitmap change. This is a rebuilt candidate, not the previously published release executable.
- Bundle version checked: `1.11.1`. The build, bundle verification, regression tests and native accent/contrast checks passed.
- Rendered executable SHA-256: `39df168f3844ac0f6517408279cd1bcaa6b0a32b3d23a8175264d2e124fd81f1` (the executable, not the ZIP asset).
- English images: `docs/*.png` in the table below. Chinese images: the matching names under `docs/zh/`.

| File | View | Native PNG dimensions |
| --- | --- | --- |
| `menu.png` | Main panel, light | 720 × 1492 |
| `menu-dark.png` | Main panel, dark | 720 × 1492 |
| `panel-actions.png` | Actions & Settings, light | 720 × 960 |
| `panel-actions-dark.png` | Actions & Settings, dark | 720 × 960 |
| `chart-today-tokens.png` | Today's models by tokens, light | 760 × 748 |
| `chart-lifetime-cost.png` | Lifetime models by cost, dark | 760 × 748 |
| `contributions.png` | Annual contributions, light | 1496 × 432 |

The main panel and actions page cover both appearances; the chart examples illustrate different periods/metrics and appearances. The Chinese README links to Chinese UI renders rather than reusing the English UI images. Icon and donation QR assets were unchanged. In the contributions view the first two month labels overlap when the rolling year starts close to a month boundary; this is an existing view-layout limitation, not an image-resizing artifact.

## Reproduce

Run the [build workflow](../.github/workflows/build.yml) for the desired source ref. Its macOS job builds a candidate app and calls [`Tools/render-readme-snapshots.sh`](../Tools/render-readme-snapshots.sh), which starts the loopback-only [`readme-fixture-server.py`](../Tools/readme-fixture-server.py), installs a temporary synthetic `tokens submit --dry-run` responder, and invokes the app's diagnostic PNG commands in each language. Temporary config and CLI files are removed on exit; the script refuses to replace pre-existing ones. Run only on a disposable runner, not a personal Mac. Download `TokensBar-candidate-snapshots` from the completed workflow and inspect the images before replacing the English files in `docs/` and Chinese files in `docs/zh/`. The generated data covers the year ending on the rendering date, so later runs can differ without a UI change.

The earlier [2026-10-27 run](https://github.com/lucaisgrowing/tokens-menubar/actions/runs/40484684242) rendered the unmodified published v1.11.1 release binary (SHA-256 `806e23c07e60b8a9ad4cd22e47f65d9e3fdb8213b65c3e647a5c10eaf04e4399`) at 1×. The [release-snapshot workflow](../.github/workflows/readme-snapshots.yml) continues to render whichever published binary is selected; a release without the 2× change will still produce 1× images.

## 中文说明

这 14 张图片由 1.11.1 源码构建的 App 在 macOS 上以 2× 分辨率原生离屏渲染，使用虚构的 `demo-user` API／CLI 数据。截图模式使用固定底色代替实际弹层材质；它不是桌面截图，也不代替真实账号、钥匙串、CLI 和界面交互的人工验收。贡献图在滚动年份靠近月初时，前两个标签可能重叠，这是原界面的布局问题，不是图片放大造成的。


## Unreleased 1.12.0 build 20 candidate

The candidate README images were refreshed from the exact universal App produced by [macOS run 40668113754](https://github.com/lucaisgrowing/tokens-menubar/actions/runs/40668113754), source `e685551dceedc970c8b1c892c61da57f9214789e`. They supersede the released-version image provenance above only on the isolated candidate branch.

- `docs/menu*.png` and their Chinese counterparts are 720×1492; Agent windows are 1400×1440; Usage & display panes are 920×1100. All are 2× native AppKit offscreen renders, not an image upscaling.
- `Tools/render-readme-snapshots.sh` uses a loopback fixture server and temporary demo CLI. `--agent-diagnostics` and `--preferences-diagnostics` use synthetic fixtures and labelled disabled/error/demo states. They never connect personal accounts or send notifications.
- All four preferences panes, both main panel appearances and both automatic-connection appearances in English/Chinese were visually reviewed. Text fits without overlapping; long Agent content intentionally scrolls. The new screenshots are copied without pixel edits. Normal macOS controls may appear neutral in offscreen rendering; the existing panel's deep-green accent remains checked by the native contrast tests.
- The trends illustration is a deterministic example, not a current account statement. No authenticated Codex/Claude/Muse Code usage, real Keychain/OpenRouter behavior or notification banner delivery is verified.
- App ZIP SHA256: `8cb9dc70836ad9e874ca6ad39f45f927abbdf36ef720ee4f6680640b092a354a`. Binary SHA256: `20ff3c2468f2db3ca47ba065f77a87c35160f9f93bbe16bc10895c98facdac18`.
