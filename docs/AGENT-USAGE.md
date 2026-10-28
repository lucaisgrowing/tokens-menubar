# Agent usage: local, unreleased implementation

Based on TokensBar main `d4a1ff0966c49765a402e90400ab1236034715e5`; provider research checked 2026-10-28. This feature is not in the published v1.11.1 App. No source was pushed and no release was created. The existing main panel, typography and green accent are retained; the new entrance opens a separate native AppKit window.

## What this version implements

Open the panel's Actions → Agent usage, or the context menu's Agent usage item (keyboard shortcut A). The window offers My usage and Service catalog, search and Personal / Coding / API categories.

- Submitted coding activity: automatically reuses the already-configured tokens.ci daily client records for today, 7 or 30 UTC days. Shows the account, fetch time, submission time and failures. Actual returned client names, tokens and estimated USD only; does not invent empty clients. It never adds the local CLI total to submitted all-device activity.
- Remaining allowance and consumption: add/edit/delete a local snapshot for any catalog or custom service. Record the actual unit, used amount, total allowance, reported remaining, model-token count, cost/currency, period, next reset, observation date and optional shared-pool label. Blank means unknown. Remaining is derived only from the same row's allowance minus used (clamped at zero), or from the reported remaining. Contradictory values are rejected; overage is retained. No cross-service grand total or credit-to-token conversion.
- Import/export: versioned JSON, an explicit confirmation before import, stable-ID upsert, unrelated records preserved. Imports always have imported provenance, never automatic. Up to 5 MB and 5,000 snapshots; invalid files do not partially import. The local store is `~/Library/Application Support/TokensBar/agent-usage.json` (0700 directory, 0600 file). Corrupt existing files are preserved rather than silently overwritten. Export is local and explicitly chosen; it may include account labels, so share it deliberately. Keys are never exported.
- OpenRouter: opt-in implementation of the official `GET https://openrouter.ai/api/v1/key` endpoint for one key's spend, cap, remaining and reset rule. The screen labels it per-key, not account balance or subscription. Credentials are collected in an AppKit secure field and stored in macOS Keychain. No model calls, no cookie scraping, no key upload to tokens.ci, no redirect forwarding; five-minute refresh backoff. An API key is not intrinsically read-only: the connection prompt explicitly recommends a dedicated low-limit key. This adapter has fixture/parser tests, not a live-account/Keychain test.
- Catalog: 66 entries including one custom-service entry, not 66 integrations. Includes personal agents, coding clients and API accounts. Each entry has its official/upstream source, unit and integration caveat. Unknown quotas are not zero. The upstream coding-client list is evidence of possible local/session support, not proof that the current user's CLI is installed/configured or that their service quota is connected.

No usage records or credentials are seeded. No service is connected just because it appears in the directory. Values become stale after one day, at their period end or their stated reset; old values are retained and marked, not replaced with fake zeroes.

## Research that shapes the implementation

| Source | Useful data / boundary | Current implementation |
| --- | --- | --- |
| [Meta Muse](https://www.meta.com/help/subscriptions/1021145227643680/) | Weekly Muse tokens, not generic model tokens; no public personal quota API verified | Manual/import |
| [Grok Bot](https://docs.x.ai/grok-bot/faq) | Plan-dependent shared weekly pool with Grok/Cursor; legacy plans differ. Grok Build local sessions are not Bot quota | Manual/import; Grok Build activity only if returned by tokens.ci |
| [Manus Cue](https://help.manus.im/en/articles/11711111-what-is-the-current-membership-pricing-for-manus) | Cue phone allowance is separate from Manus credits | Manual/import; no false Manus-to-Cue balance substitution |
| [Wabi](https://wabi.ai/terms) | No verified public personal usage endpoint; terms restrict automated scraping | Manual/import, no scraping |
| [Manus API](https://open.manus.im/docs/v2/authentication) | Credit APIs exist, but personal keys have broad account powers and ordinary OAuth cannot read all usage endpoints | No key requested; manual/import |
| [Claude](https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work) | App/Code plan usage shared; different windows; API billing separate | Local session activity if submitted, separate subscription snapshots |
| [OpenAI Codex / ChatGPT](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan) | Plan-specific shared credit/usage rules; API account billing separate | Submitted coding activity plus separately labelled snapshots |
| [Gemini](https://support.google.com/gemini/answer/16275805?hl=en) | Plan/feature-specific limits; Gemini API project quotas separate | Manual/import plus submitted CLI activity where present |
| [Perplexity Computer / Comet](https://www.perplexity.ai/help-center/en/articles/13838041-how-credits-work-on-perplexity) | Weekly included Computer usage is separate from credits; Comet Work runs Computer, Search does not. Enterprise caps/pools differ | Manual/import with separate pools/periods |
| [Notion Agent](https://www.notion.com/help/manage-your-ai-credits) | Standard, Select and workspace credits have different funding; admin policy controls fallback | Manual/import, explicit workspace/pool |
| [Microsoft 365 Copilot](https://support.microsoft.com/en-us/microsoft-365-copilot/ai-credits-and-limits-for-microsoft-365-subscriptions) | Feature-specific limits and credits depend on plan/entry point. Consumer AI benefits belong to the subscription owner | Manual/import, no hardcoded plan allowance |
| [Lindy](https://docs.lindy.ai/account-billing/usage) | Teammates and agents share workspace pool; monthly credits expire but purchased top-ups remain; personal caps are not extra credits | Manual/import |
| [Genspark](https://www.genspark.ai/helpcenter/credits-guide) / [GenCode](https://www.genspark.ai/helpcenter/gencode) | Weekly Free Quota, credits and some model limits are separate. GenCode uses credits, not Standard-agent Free Quota | Manual/import |
| [OpenRouter key API](https://openrouter.ai/docs/api/api-reference/api-keys/get-current-key) | Official per-key spending/cap fields, not full-account or personal subscription quota | Optional automatic implementation; no live account verification |
| [tokens CLI](https://github.com/missuo/tokens/blob/c2f3857c328478e2599a3ba871151ec255e00831/README.md) | Supported session/sync clients can contribute submitted model/client token data. Support depends on installed CLI version and configuration | Reuses actual tokens.ci daily client data, no new uploader |

The machine-readable catalog and all per-provider source links are in `agent-provider-catalog.json`; compiled bilingual catalog entries are in `Sources/AgentCatalog.swift`. Research covers a representative set, not every AI agent. Documentation is not proof of a particular account's availability, permissions or current allowance. No fixed plan quotas/prices are baked into account rows.

## Build and verification

On macOS 13+ with Xcode Command Line Tools, the existing build command `./build.sh` includes all new Swift sources; `./build.sh --universal` creates both architectures. Run `./Tests/run.sh` for the deterministic checks.

Verified in this delivery environment: 76 existing pure-Swift checks and 57 new checks pass under Swift 6.0.3 with Swift 5 language mode; frontend parsing of every `Sources/*.swift` succeeds. The new checks cover unit-safe remaining/overage/unknowns, period/reset staleness, invalid numbers, provenance spoof prevention, all-or-nothing JSON import, stable-ID upserts, local file permissions, preservation of corrupt data, OpenRouter response parsing, client-day filtering and overflow handling, and catalog invariants.

Not verified: native macOS compilation/linking, live AppKit layout or interaction, real Keychain behavior, live OpenRouter authentication/values, user device/CLI configuration. Only Linux is available to this task. No native screenshot or packaged `.app` is supplied, and syntax parsing is not advertised as a macOS build. The implementation is ready for native compilation and acceptance testing, not a verified installable release.

Native acceptance checklist: open the new window in light/dark modes and Chinese/English; resize/search/category-filter; add/edit/delete a snapshot; confirm a reset marks stale without fabricating data; import/export and cancel import; change tokens.ci account/failure state; optionally connect a dedicated low-limit OpenRouter key, refresh, cancel/reconnect and disconnect; confirm existing menu charts, contribution labels and actions remain intact.
