# Phase 0: inventory

Verified from code on `main` at `45f1b30` unless marked [I] (inferred) or "could not verify".

## 1. Things tied to Graham

| What | Where | Ships to users? | Action |
|---|---|---|---|
| "Gunner, 8th grade: cross country, band" placeholder | `App/Shoebox/Settings/SettingsView.swift:256`; also prescribed in `docs/SPEC.md:150` | **Yes, every user** | Replace with a neutral example (P-5) |
| Gunner and grade 8 as the example in code comments | `Shared/Store.swift:89`, `Core/Sources/ShoeboxCore/Rules/EmailCalendar.swift:4,32-33` | No (comments) | Neutral examples |
| "Roosevelt newsletter" in comments | `App/Shoebox/Services/Inbox.swift:123`, `EmailCalendar.swift:247-248` | No | Fine, already fictional |
| Children's names in tests: "Hi Graham", "Dentist reminder for Heidi", Gunner profile | `App/ShoeboxTests/EmailPostTests.swift:6,20-21`, `Core/Tests/ShoeboxCoreTests/EmailCalendarTests.swift:25,27` | No, but the repo is **public** | Scrub (P-8) |
| Real Wilmington details in the newsletter fixture (Hugh MacRae Park, Battleship North Carolina, 910 area code) | `Core/Tests/ShoeboxCoreTests/Fixtures/newsletter-27-dates.txt:27-31,44` | No, public repo | Scrub (P-8) |
| Demo data with work jargon ("Retro format for PI planning") used for App Store screenshots | `App/Shoebox/Model/SampleData.swift:29` (DEBUG only, `:5`) | Only in screenshots | Neutral demo copy |
| SampleData | `#if DEBUG` (`SampleData.swift:5`), seeded only with `-demo YES` (`ShoeboxApp.swift:9-13,20-21`) | No | None. New users start empty |
| US school-calendar logic: grades as numbers, "8TH GRADE" headings, US month-first dates | `EmailCalendar.swift:107-116,135-139,167-174` | Yes | Decide US-only or broaden (C-7, C-10) |
| en_US hardcoding | `EmailCalendar.swift:144` (POSIX parse, fine), `:234` (display, an issue), `Shared/LaterPlanner.swift:105,112` (fallback) | Yes | C-10 |
| Reason words English only | `Shared/LaterPlanner.swift:42-62` | Yes | US English for v1 |
| Tests pinned to America/New_York and en_US_POSIX | `Core/Tests/ShoeboxCoreTests/EmailRulesTests.swift:6`, `EmailCalendarTests.swift:6`, `App/ShoeboxTests/DateReaderTests.swift:8` | No | Fine; add one non-US test |
| Your email address | Not in the app. The relay's shared `EMAIL_ADDRESS` is exposed by `/version` (`relay/perplexity-relay.js:112`) | Via relay | Trim `/version` (RELAY-13) |
| Your relay account and domains | `Shared/Relay.swift:7-8` (shoebox-api.tangomike.app, Origin inmyshoebox.com); `relay/wrangler.jsonc:17` | Yes, by design | Fine; it is the product's server |
| Shoebox Me (staff phones) logic in the relay: `firstname-keep` addresses, `com.grahamdeno.shoebox.me` attest id | `relay:679`, `relay:1531` | Relay only | Remove from the new app's Worker (R-1) |
| Identifiers: team 7MHDTK68M2, bundle and group ids | `project.yml:5,17,33-39`, `Shared/Store.swift:6`, `App/Shoebox/Services/Backups.swift:9` | Yes, expected | None |

## 2. Every AI call

All three run on the phone. The app makes **no cloud AI calls**: no `/ai/*` route and no Anthropic use anywhere in `App/`, `Shared/` or `Share/`. Vision is used only for faces and saliency (`App/Shoebox/Today/PostPhoto.swift:85-86`); there is no text recognition on `main` (PR #28 adds it).

| # | Purpose | File | Model | Input | Trigger, frequency | Fallback | Guard |
|---|---|---|---|---|---|---|---|
| 1 | Email to post: short title and 2 to 5 sentences | `App/Shoebox/Services/EmailPost.swift:18-25`; schema `:76-82` | FoundationModels, greedy | Subject plus lines, first 3,500 chars (`:17`), about 1k tokens; output capped 900 chars (`:36`) | Each ordinary email on app open (`Inbox.swift:138`); about 1 to 5 a day | `try?` to `plain()`, the first useful lines; never rewritten later | `EmailRules.invents` (`EmailRules.swift:61-68`): rejects digits not in the email and seven day words. Misses invented weekday and month names and wrong pairings; rejects "4:00 PM" from "4 pm" (C-1) |
| 2 | Stock-photo search words | `App/Shoebox/Services/StockPhoto.swift:221-227`; schema `:249` | FoundationModels, default sampling | Title, snippet, body prefix 400 then 600 chars | First 3 queued posts with no picture (`TodayView.swift:625`), retried at most daily; about 3 to 10 a day | Keyword rules (`StockPhoto.swift:85,160-182`) | Fixed vocabulary whitelist (`:91-97,143-157`), capitalized words removed (`:83,103-118`), health, money and legal skipped (`:81,133-140`). Strong |
| 3 | Pick the best of 6 Pixabay captions | `StockPhoto.swift:238-240`; schema `:255` | FoundationModels | 6 captions | After each search; about 3 to 10 a day | Word overlap or first result (`:198-204`) | Bounds check only; no range guide (`:237,256`) |

Not wired in: the Core planner and its `ModelHints` (`Core/Sources/ShoeboxCore/Planner/PlannerTypes.swift:57-75`), `NameMask`, `quoteFound`, `looksLikePromotion`. SPEC section 3.1 says the planner "takes over"; the plain `LaterPlanner` is what ships.

Availability: only `.available` is checked (`StockPhoto.swift:212`). Model not downloaded, Apple Intelligence off, or an unsupported language all fall to the rule-based path silently.

## 3. Every network call

### What the app calls

| Route | Called from | Purpose |
|---|---|---|
| `GET /preview?url=` | `Shared/Relay.swift:33`; `Share/ShareViewController.swift:119`; `Inbox.swift:107` | Page title, description, picture, text |
| `GET /stock?q=&n=` | `StockPhoto.swift:187` | Pixabay candidates for generic words |
| `GET /inbox` | `Inbox.swift:65` | Collect waiting mail |
| `POST /inbox/address` | `Inbox.swift:42` | Mint a forwarding address from a first name |
| `GET /inbox/file` | `Inbox.swift:206` | Attachments |
| `POST /inbox/ack` | `Inbox.swift:168` | Delete collected mail on the relay |
| `POST /me/delete` | `SettingsView.swift:364` | Delete address and waiting mail |
| Direct image fetch | `Shared/Relay.swift:40-46` | Page pictures and the chosen Pixabay picture, straight from the phone |

Auth: the app sends a fixed `Origin: https://inmyshoebox.com` header (`Relay.swift:17`) and, for inbox routes, an `x-inbox-key`. The Origin check is not authentication; any script can send it.

### Legacy routes on the shared Worker (not called by the new app)

`/image`, `/file`, `/photo` (Shoebox 1), `/version`, `/stats`, `/stats/report`, `/ai/register`, `/ai/challenge`, `/ai/attest`, `/ai/messages`, `/ai/usage`, `/ai/quotes`, `/ai/stories`, `/beta`, `/push/*`, `/remind` with a 15-minute cron, `/ical`, `/apple/*`, `/song`, `/v1/agent` (an open Perplexity proxy). Recommendation in `03-decisions.md` D and backlog R-1: split.

### Secrets and bindings

`SHOEBOX` (KV), `EMAIL_ADDRESS`, `EMAIL_ALIASES`, `EMAIL_DOMAIN`, `APPLE_P8`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `ANTHROPIC_API_KEY`, `AI_OWNER_DEVICES`, `AI_ATTEST`, Pixabay key. The new app needs only `SHOEBOX`, the email domain and the Pixabay key. The KV namespace id is kept out of the repo on purpose (`relay/wrangler.jsonc:14`). No secrets are committed.

### What breaks at scale

| Users | Breaks first |
|---|---|
| About 70 to 280 | On the Workers free plan: KV deletes (about 70 users), lists (about 200), writes (about 280) per day. Move to Workers Paid ($5 a month) before a public beta |
| 1,000 | Nothing on Workers Paid. Owner's shared-mail listing breaks past 1,000 waiting mails across all users (`relay:744-745`) |
| 10,000 | KV deletes about 4.2M a month (about $16 over, fixed by R-6), lists about 1.5M (about $2.50). Pixabay peaks over 100 per minute at the morning notification time; per-IP `/stock` limits trip behind carrier NAT (`relay:353-362`) |
| Any | Abuse of open write routes (`/inbox/address`, `/remind`, `/ai/register`) is the real cost risk, not normal use |

## 4. Likely App Store review failures

| Area | Status | Evidence |
|---|---|---|
| Privacy policy URL and in-app link (5.1.1(i)) | Policy exists at `https://inmyshoebox.com/privacy` and is set in App Store Connect; needs updates; **no in-app link**, no terms | Settings Privacy is three lines (`SettingsView.swift:317-326`) |
| Privacy manifest, collected data | **Wrong** | `App/Shoebox/PrivacyInfo.xcprivacy:17-43` |
| Required-reason APIs | **Missing** UserDefaults; share extension has no manifest | `PrivacyInfo.xcprivacy:44-45`; `Shared/Store.swift:15` |
| Accurate in-app privacy claim | **False** ("Nothing is kept") | `SettingsView.swift:324` |
| Camera and photo strings | Present, plain | `project.yml:55-56` |
| Share extension | Works; memory risk on large photos; silent failure | `ShareViewController.swift:81,112,131,147` |
| Account deletion (5.1.1(v)) | No accounts. The email address is a server-side identity created in the app, and Delete everything removes it, but fire-and-forget | `SettingsView.swift:360-368` |
| Email forwarding disclosure | Partial: onboarding asks for a first name without saying it leaves the phone | `Onboarding.swift:73-107` |
| AI-generated content | On device, from the user's own content. No disclosure required; a short "written on your iPhone" line helps | `EmailPost.swift:18-25` |
| Background tasks | None declared or used | grep: no BGTask |
| Push | Local notifications only; relay push routes unused | `App/Shoebox/Services/Notifier.swift` |
| Minimum functionality (4.2) and design (4.0) | Fine: native, real features | |
| Completeness (2.1) | Reviewer needs a demo path for email; stock pictures fail until the relay is deployed | `relay/README.md:5` |
| Accurate metadata (2.3) | README promises Lock Screen, Watch, Siri; none built | `README.md:3-6` |
| Apple Intelligence unavailable | Silent fallback exists for all three calls | `StockPhoto.swift:212`, `EmailPost.swift:15` |
| iPad | iPhone only (`project.yml:19`); runs in compatibility mode on iPad if a reviewer uses one [I] | |
| Export compliance | `ITSAppUsesNonExemptEncryption: NO` set | `project.yml:45` |

## 5. Known open items

| Item | Finding |
|---|---|
| Writing surface (Keep, Share, Edit) untested on a device | Still open. PR #28 rewrites it; test after it merges (`07-test-on-your-phone.md`) |
| Close button flakiness on the opened post | Likely causes [I]: a fast second tap creates a new `OpenedPost` id and re-presents the cover (`TodayView.swift:13,500-503`); Close during Edit or Quick Look dismissal (`OpenedView.swift:16-18,142-144`); two presentation hosts (`BoxView.swift:181`, `TodayView.swift:109`). Backlog A-9 |
| Inbox key lost on reinstall | **Confirmed.** Kept in App Group UserDefaults (`Shared/Store.swift:79-82`); comes back only via an iCloud device restore or a Shoebox backup (`Backups.swift:234,261`). Backlog D-5 |
| Events moved to a different day not detected | **Confirmed.** Repeat newsletters match only the same day (`Inbox.swift:118-119`); the old post stays on the old date. Backlog C-8 |
| Do past-dated posts stay until acted on? | **No.** The day after the event they move to Kept on their own, silently (`TodayView.swift:610`, `Shared/Rules.swift:29-38`). Matches SPEC rule 5; needs a notice (A-7) |
| TestFlight group handling manual | **Confirmed.** `testflight.yml:54-79` uploads only. Backlog Q-3 |
