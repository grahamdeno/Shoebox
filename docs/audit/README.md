# Shoebox release-readiness audit

Read-only audit of `main` at `45f1b30` (November 2, 2026), from TestFlight to a commercial App Store release. Fourteen lenses, reconciled into one plan. Nothing in the app or relay was changed, built, deployed or uploaded.

**Update, November 2:** Graham answered the open questions; the decisions are in `docs/SPEC.md` section 8 and `06-open-questions.md`. A Shoebox 2 privacy policy already exists at `https://inmyshoebox.com/privacy` (the website lives outside this repo), so P-1 is an update, not a new policy. Version is 1.0, not 2.0.

**Overall rating: not ready for a public TestFlight beta.** The app itself is close: the core loop, the on-device AI and the design are sound. What is missing is everything a stranger relies on: a privacy policy and honest disclosures, a relay that can't be abused, and data that survives a bad day.

## What blocks a public release

1. **The privacy and compliance package is missing or wrong.** The privacy policy at inmyshoebox.com/privacy needs updates (7-day retention, children's details, the preview cache, rights for EU and California users), there are no terms, and the app doesn't link to it (P-1). The privacy manifest declares analytics the app never sends and leaves out the email content, name and address the relay keeps for up to 30 days (P-2). UserDefaults is used but not declared as a required-reason API, and the share extension has no manifest (P-3). Settings tells users "Nothing is kept", which is false (P-4, `App/Shoebox/Settings/SettingsView.swift:324`). The Settings placeholder ships your son's name and grade to every user (P-5, `SettingsView.swift:256`).
2. **The relay is built for one person and isn't deployed.** The live relay has no `/stock`, so stock pictures fail today (R-2). Anyone can mint unlimited inbox addresses (R-3, `relay/perplexity-relay.js:755-763`), take over the shared owner mailbox after a Delete everything (R-4, `relay:737`, `relay:959-960`), guess valid addresses from bounces (R-5), or use legacy open routes such as the Perplexity proxy and the Apple Music token (R-1, `relay:125-143`, `relay:940`). Split the new app onto its own Worker with only the seven routes it calls.
3. **Data safety has three single points of loss.** No SwiftData schema version, and a store that fails to open crashes every launch with no way to reach Backups (D-1, `Shared/Store.swift:29`, `App/Shoebox/ShoeboxApp.swift:17`). Mail is acknowledged (deleted on the relay) even when saving it failed (D-2, `App/Shoebox/Services/Inbox.swift:165-168`). The share extension decodes up to 10 full-size photos on the main thread and will exceed its memory limit on modern camera photos (D-3, `Share/ShareViewController.swift:81,112,147`).

All three are mostly S-effort work. The full beta list is 24 items, tagged `phase:beta` in `backlog.csv`.

## What blocks v1.0 after the beta

- **Accessibility.** 92 fixed font sizes and no Dynamic Type anywhere (X-1). VoiceOver can reach the hidden Shoebox sheet (X-2). Settings choices don't announce which is selected; four date pickers have no label (X-4).
- **First run.** A first save goes to "away" until tomorrow morning (A-1, `Shared/Capture.swift:67-68`), so the onboarding ends on "Try it" with nothing to try. SPEC section 3 rules 1 and 6 disagree on this; you need to pick one.
- **Money.** No StoreKit code exists. Decision C recommends a one-time unlock that also gates the email address.
- **Content correctness.** Outlook "Sent: Monday" headers become false events (C-2, `Inbox.swift:95`); the invented-content guard misses invented weekday and month names (C-1).

## Score per lens

| # | Lens | Score /10 | One line |
|---|---|---|---|
| 1 | Product strategy | 7 | Clear, differentiated loop; the return lever (widget, notification actions) isn't built yet |
| 2 | UX research | 6 | SUS estimate about 70 first week, 76 settled; target 80 |
| 3 | Onboarding and activation | 5 | First save is invisible until tomorrow; permissions asked before value |
| 4 | Visual and design system | 7 | Palette matches SPEC exactly, no black; Undo pill and leftover neumorphic code |
| 5 | Accessibility | 3 | No Dynamic Type, no Reduce Motion or Transparency, VoiceOver order leaks |
| 6 | iOS platform | 5 | No schema versioning, heavy main-thread backups, share extension memory |
| 7 | App Store compliance | 3 | No privacy policy, wrong manifest, false privacy claim |
| 8 | AI architecture | 7 | All on device, good vocabulary whitelist and fallbacks; guard has gaps |
| 9 | Monetization | 2 | Nothing built; costs are tiny, so this is a pricing choice, not a cost problem |
| 10 | Privacy, security, legal | 4 | Good minimization design; plain-text mail, no policy, wrong claims |
| 11 | QA and release | 4 | Tests don't gate TestFlight; no production crash reporting |
| 12 | Retention measurement | 4 | Nothing measured; App Store Connect analytics is enough for v1 |
| 13 | Email ingest and relay | 4 | Right pieces, open to abuse, no monitoring, not deployed |
| 14 | Generated content quality | 6 | Newsletters strong for US schools; false dates from headers and loose weekdays |

## Files

| File | What it holds |
|---|---|
| `01-inventory.md` | Phase 0: personal hardcoding, every AI call, every network route, review risks, the known open items |
| `02-expert-audits.md` | Phase 1: findings per lens with severity, effort and file:line evidence |
| `03-decisions.md` | Phase 2: decisions A to F with options, recommendation and what would change it, including the cost model |
| `04-roadmap.md` | Public TestFlight beta, App Store v1.0, post-launch |
| `05-release-checklist.md` | App Store metadata, privacy labels, screenshots, review notes, demo path, URLs |
| `06-open-questions.md` | What you need to answer, most blocking first |
| `07-test-on-your-phone.md` | What this audit couldn't verify |
| `backlog.csv` | 73 items, RICE scored, grouped by epic, for GitHub Project import |

## How the backlog is scored

- **Reach:** users touched per quarter, assuming a 1,000-user beta.
- **Impact:** 3 massive, 2 high, 1 medium, 0.5 low, 0.25 minimal.
- **Confidence:** 1.0 verified in code, 0.8 strong inference, 0.5 judgment.
- **Effort:** person-weeks for a human developer (S 0.5, M 2, L 5). This is for comparing items, not a schedule; agent-built work moves faster.
- **RICE** = reach × impact × confidence ÷ effort. Labels carry `phase:beta|v1|post`, severity, effort and an id (for example `id:D-1`) that the docs refer to.
- GitHub Project import: create the Project, then import the CSV as items (title, epic and labels map to fields; labels need to exist on the repo first).

## Verified versus inferred

- **Verified in code:** every finding with a file:line reference unless marked [I]. I re-checked the highest-severity ones myself after the lens reviews: the placeholder (`SettingsView.swift:256`), first-save status (`Capture.swift:67-68`), the key in UserDefaults (`Store.swift:79-82`), address minting (`relay:730-763`), fire-and-forget delete (`SettingsView.swift:360-368`), the guard (`EmailRules.swift:61-68`), the header filter (`Inbox.swift:95`) and the 92 fixed font sizes.
- **Inferred [I]:** runtime behavior that needs a device: VoiceOver order, share extension memory peaks, Close flakiness causes, contrast over real photos, AI output quality.
- **Could not verify:** no Swift compiler (nothing built or tested), FoundationModels can't run in a cloud sandbox, no live relay calls were made, no device. These are listed in `07-test-on-your-phone.md`.

## Assumptions

1. Target user: busy parents and working adults, about 28 to 50 (confirmed).
2. Price: free download plus Shoebox Plus, a one-time $9.99 unlock (decided).
3. Shoebox 1.0 was never released publicly (`docs/PLAN.md:53`, `:163`). Confirmed November 2: the record's only version is 1.0 (Prepare for Submission), 45 TestFlight builds, highest 1043, and Graham is the only user. Ships as 1.0.
4. US English only for v1.0; Spanish in v1.1 (decided).
5. Cloudflare prices are from Cloudflare's pricing page today: Workers Paid $5 a month with 10M requests; KV includes 10M reads and 1M writes, deletes and lists, then $5 per million. Pixabay: 100 requests per 60 seconds per key, results cached 24 hours, images downloaded not hotlinked.
6. Domains cost about $15 a year each (two: inmyshoebox.com, tangomike.app). Not checked against your registrar.
7. Open PR #28 ("Write on the post") was being updated while this audit ran. It adds photo text reading (`PhotoRead.swift`), a return choice in the share sheet and an invented-label filter. Findings are against `main`; where PR #28 overlaps (C-1, A-1, photo-to-post), check after it merges. Note that `PhotoRead.recognizedText` also decodes the full image with `UIImage(data:)`, the same memory pattern as D-3.

## Next step

Decisions A to F and the pricing call (`03-decisions.md`) and the six blocking questions (`06-open-questions.md`) are judgment about feel, data safety and pricing: **Opus**. Once you've answered them, the 24 `phase:beta` items are building work: **Sonnet**. The relay deploy (R-2) is the one irreversible step in that batch and goes first in that handoff.
