# Changelog

## 1.12.0

### Redesigned UI & App Icon
- Redesign the macOS AppIcon (`Tools/make-icon.swift`, `Resources/AppIcon.icns`, `docs/icon.png`) into a text-free deep obsidian-teal squircle with ascending emerald-mint telemetry bars and a sculpted luminous lightning bolt.
- Upgrade the dropdown panel to an elevated card hierarchy (hero telemetry card with cost & prompt cache-hit badges, unified mini-leaderboard + 7-day pace card, elevated dual KPI cards, unified 7-day bar card, month + flame-streak card, and inline proportional bars for today's models).
- Replace the 99%–100% single-bar leaderboard progress with a live **3-row Mini-Leaderboard Ladder** showing the rival directly above (`+gap`), your highlighted row, and the trailing rival below (`−lead`), plus a percentile badge (`Top XX%`) and a 1-click Today / All-time board switcher.
- Add an ease-out reveal animation with a one-shot leading-edge sheen & specular sweep on the Today / 7-day average bar (interruptible on live updates, automatically disabled when Reduce Motion is enabled).
- Redesign Actions & Settings into macOS Sequoia inset grouped cards with soft-tinted icon badges, inline **Menu Bar Display** multi-toggle pills (`Tokens` / `Cost` / `Rank`), and a **Daily Cost Budget** dialog persisted directly to `config.json`.
- Add back navigation (`‹`) on the chart & contributions popovers and an in-popover Today / Lifetime switcher on the model distribution chart.
- Add a pill backing behind the footer status stamp for legibility over dark wallpapers.

### Added & Fixed
- Compute and display UTC active-day streaks (panel, heatmap summary, and share card) and prompt cache-hit rate (hero card, tooltip, and heatmap day readout) from existing contribution fields with zero extra API calls.
- Watch `~/.config/tokens-menubar` and `~/.config/tokens` for hot-reloading `config.json` and `credentials.json` without restarting TokensBar.
- Detect local `tokens` CLI version, background `tokens serve` status, and upstream `missuo/tokens` releases; surface a 1-click copyable upgrade command when the CLI is outdated.
- Fix leaderboard page-boundary `#101`/`#201` missing `above` neighbour, jump directly to the target page using `user.rank` (removing the 600-user cap), and fall back to `user.rank` on the Share Card (also auto-fitting large 10B+ token counts without truncation).
- Add `NSWorkspace.didWakeNotification` and `NWPathMonitor` network-recovery refreshes, timer coalescing tolerances, `refreshLocal` re-entrancy/throttling (decoupling `--week`/`--month` scans), cached `DateFormatter`s and `CLI.binary()`, shared `URLSession`s, dynamic `User-Agent`, and `config.apiBase` support in `Embed` / `ShareCardView`.
- Verify `SHA256SUMS.txt` and `CFBundleIdentifier` in the in-place updater (`Installer.swift`) and self-clean the temporary swap script.
- Expand offline pure-Swift regression suite from 76 to 101 assertions. Bundle version 1.12.0 (build 19).

## 1.11.1

### Fixed
- Restore the original deep-green accent from the pre-1.11 screenshots for buttons, selected settings, ranking/average bars, activity bars, header icon, informational feedback and share-card emphasis. App accents no longer follow the system's blue (or other) accent preference.
- Preserve the original light/dark hues; lift small green text in dark mode for legibility. Keep semantic error/success colors and categorical model colors distinct.
- Keep the existing typography, layout and functionality unchanged. Bundle version 1.11.1 (build 18).
- Refresh both READMEs and native macOS screenshots to match this release. Still ad-hoc signed and not notarized; native rendering is not manual interaction/Keychain/live-CLI acceptance testing.

## 1.11.0

### Improved
- Refine the existing teal light/dark interface without removing or reordering its modules: 360pt panel, spacing, card proportions, clearer progress bars and chart details.
- Retain the original macOS system font declarations, sizes and weights; distinguish local Mac data from all-device submitted data, UTC days and estimated costs.
- Add immediate press feedback with drag-out cancellation, interruptible chart transitions, reduced-motion support and stronger opaque/high-contrast presentation when requested by the system.
- Display nonzero model shares below one percent as `<1%`.

### Fixed
- Support optional private-account read tokens using a secure field, macOS Keychain and HTTPS Bearer authorization. Scope stored tokens to username/API origin; do not include them in public leaderboard requests or follow authenticated redirects.
- Separate last successful fetch, attempted refresh, server submission and local scan times. Preserve valid cached data on errors; do not label failed refreshes as newly fetched data.
- Differentiate network, invalid-response, authentication, not-found, rate-limit and other HTTP failures. A 404 is not treated as zero usage.
- Enforce a 60-second minimum API polling interval; retain the 300-second default.
- Avoid false first-place/not-ranked claims when leaderboard coverage is incomplete.
- Correct obsolete CLI commands in both READMEs. Keep the existing `tokens submit --dry-run` text-based data path and add 45 pure-Swift parser/formatting assertions. The daily/model API endpoint was already in use, not newly introduced here.

### Packaging and verification
- Bump bundle version to 1.11.0 (build 17).
- Run regression tests and universal macOS compilation before packaging; verify bundle metadata, both CPU slices and ad-hoc signature before a release can be published.
- Refuse to overwrite an existing release. Attach `TokensBar.app.zip` and SHA-256 checksums only after verification.
- This remains an ad-hoc-signed, non-notarized distribution for macOS 13+. Automated compilation and bundle checks do not constitute interactive UI, Keychain or live-account testing.

Project naming and attribution already followed the maintainer's feedback. Inclusion of a TokensBar link in the upstream project remains the upstream maintainer's decision.
