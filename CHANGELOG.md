# Changelog

## 1.12.0 candidate — unreleased, build 21

### Preferences visual polish
- Replace neutral gray navigation, checkboxes and actions in the four new panes with consistent ink-green controls, clear selection/press/focus states and opaque appearance-aware surfaces. Keep the existing macOS font family and unchanged main panel.
- Give the trend comparison a distinct summary and model-contribution card; retain UTC, incomplete-day and model-attribution qualifications at a quieter visual level.
- Group server and local CLI diagnostics separately, align timestamps, collect related actions and disable refresh while loading. Do not imply a retry uploads activity.
- Add a menu-bar composition preview with unknown cost/rank explicitly shown as placeholders, green toggles and reorder controls. Preserve immediate saving and the final-enabled-item safeguard.
- Separate cost thresholds from notification cadence; emphasize saving, retain validation and distinguish OS notification authorization from delivered banners.
- Refresh native 2× screenshots in both README languages after visual review of all four panes in light and dark appearances.

### Existing candidate changes

- Replace manual-entry-as-automation framing with opt-in supported local paths: Codex app-server account rate-limit/activity reads, Claude Code statusLine sanitized quota observations, and clearly separate Muse Code cached usage/read (not Meta Muse personal agent). Keep tokens.ci submitted scope and OpenRouter per-key scope separate. No cookie scraping, account-key minting or model turn.
- Add strict today/prior-seven UTC-day comparison; missing days are unknown, not zero. Attribute a model only from complete per-day detail; preserve existing main-panel order.
- Add compact native data-health, menu-bar and alert settings: attempts/success/submission times, specific CLI errors, real retry/setup/submission actions, editable persistent display order, daily/month-end estimated-cost thresholds and bounded notification frequency. Permission/OS acceptance does not claim displayed delivery.
- Preserve typography and deep-green native light/dark direction; regenerate actual 2× AppKit screenshots. A 67-entry reference catalog and optional snapshots remain, but are not live integrations. Personal Meta Muse/Grok Bot/Cue/Wabi quota automation remains unavailable in this candidate.
- Universal arm64/x86_64 candidate; 76 existing, 57 Agent and 35 automation/trend/preferences regressions, plus native controls/transport/accent checks. Authenticated provider data, real Keychain, notification banners and full manual UI acceptance remain unverified. No main merge, tag or release. See `docs/AGENT-USAGE.md`.

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
