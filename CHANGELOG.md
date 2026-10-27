# Changelog

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
