# Changelog

## Unreleased — local source preview

- Add a native unified Agent usage entrance, separate from the existing panel, with actual tokens.ci client activity, validated local allowance/consumption snapshots, JSON import/export and an opt-in official OpenRouter per-key connector.
- Add a 66-entry researched catalog with explicit source, account/plan boundaries and unavailable-connector labels; do not aggregate incompatible units or shared pools.
- Preserve the existing green design, fonts, contribution-label repair and release version. Not pushed or released; Linux core tests and syntax parse passed, native macOS build/Keychain/UI/live account verification remains outstanding. See `docs/AGENT-USAGE.md`.

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
