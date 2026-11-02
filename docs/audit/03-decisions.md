# Phase 2: decision log

Each decision: options, recommendation, and what would change it. Recommendations are mine; nothing here is decided until you say so.

---

## A. Platform

**Floor.** Keep iOS 26. The app is built on Liquid Glass and FoundationModels; lowering the floor means a second design and no on-device AI. iOS 26 adoption by early 2027 will cover most active iPhones [assumption, not checked].

**Without Apple Intelligence** (iPhone 15 and older non-Pro models, Apple Intelligence off, unsupported language): all three AI calls fall back to rules silently (`StockPhoto.swift:212`, `EmailPost.swift:15`). Email posts become the first useful lines, greetings included; stock pictures come from keyword rules. That is usable, not good.
- Recommendation: keep the fallback; strip greetings (C-11); rewrite fallback posts once the model arrives (C-5); say in the App Store text "Best on iPhones with Apple Intelligence"; no in-app nagging.

**Native features, in order of value for daily return:**
1. Notification actions (Next, Put away on the notification itself): small, and the loop's front door. v1.0 if time allows.
2. Home and Lock Screen widget showing today's post (F-2): biggest return lever. First post-launch release.
3. App Intents: Keep from Shortcuts and the Action Button, Find through Siri and Spotlight (F-3).
4. Background refresh (F-1) for mail and notifications: v1.0.
5. Live Activities: no; nothing in Shoebox is a live, time-bound event.

**CloudKit sync.** Not for v1.0. Cost: a CloudKit schema that can never remove fields, conflict handling for soft deletes and returns, a privacy story that changes from "on this phone" to "on this phone and your iCloud" (which most users accept), and the inbox key needing sync too. The data model is already sync-ready (UUIDs, timestamps, soft delete). Revisit when users ask for iPad or a second phone.

**Would change it:** testers mostly on devices without Apple Intelligence (then fallback quality becomes a v1 item), or many requests for iPad.

## B. AI path

**Options:** (1) fully on device; (2) on device plus a paid cloud tier through the relay; (3) relay AI as a fallback for devices without Apple Intelligence (what PLAN.md:76 says).

**Recommendation: stay fully on device for v1.0.**
- Zero inference cost and the privacy line "your words stay on your phone" stays true.
- The relay's AI path is the least safe code in the system (RELAY-7: caps beaten by parallel calls, attest only at sign-up, bearer tokens).
- Sending email content to a cloud model changes the privacy label, the policy and the children's-data story.

**What the prompts and guards need** (judged against the fixtures, not run): the email prompt is sound; the guard (`EmailRules.swift:61-68`) is the weak part (C-1). The stock-photo design is strong. Priorities: C-2 (headers), C-1 (guard), C-3 (dates), C-4 (card numbers).

**Could not test here:** any real model output, refusal rates, latency, behavior when the model is downloading. You must test on your phone: 20 to 30 real forwards (receipts, trips, school notices, quotes), Apple Intelligence off, a long PDF (see `07-test-on-your-phone.md`).

**Would change it:** on-device output failing on more than about 1 in 5 real emails after C-1 to C-3, or paying users asking for summaries of long PDFs. Then a cloud tier (Claude Haiku class) behind App Attest assertions per call, a pre-charge reservation and a monthly cap, included in a subscription.

## C. Monetization

### Cost model

| Cost | Per year | Notes |
|---|---|---|
| Apple Developer Program | $99 | |
| Cloudflare Workers Paid | $60 | Needed past about 70 active users (free plan's 1,000 KV deletes a day) |
| Domains (inmyshoebox.com, tangomike.app) | about $30 | Assumed $15 each |
| Email Routing, Pixabay API | $0 | Pixabay is free; its limit is 100 requests per 60 s per key |
| On-device AI | $0 | |
| **Fixed total** | **about $189** | |

Usage per active user per day (relay review assumptions: 5 opens, 2 forwarded mails, 2 link saves, 2 stock lookups): about 15 requests, 5 KV lists, 8 reads, 3.6 writes, 14 deletes (2.6 after R-6).

| Active users | Variable cost per year, today | After R-6 (fewer KV deletes) |
|---|---|---|
| 100 | $0 (inside included) | $0 |
| 1,000 | $0 | $0 |
| 10,000 | about $228 (deletes about $192, lists $30, writes $6) | about $36 (lists and writes) |

**What drives cost:** email volume (KV writes and deletes per mail) is the only real driver. Stock lookups cost nothing but are rate-limited, so they drive *reliability*, not cost. The real cost risk is abuse of open write routes (R-1, R-3, R-5).

### Options

| Model | For | Against |
|---|---|---|
| Free | Most installs | No revenue; email abuse has no gate |
| Paid upfront | Simple, private | Kills discovery; reviewers and testers can't try it |
| Freemium, one-time unlock | Matches "no ads, no tracking" and near-zero running cost; the unlock can gate the email address, which closes the abuse path | One-time revenue per user; must keep finding new users |
| Subscription | Recurring | Hard to justify with no ongoing service cost; subscription fatigue in this category |
| Tip jar | Goodwill | Little revenue |

### Margin, Small Business Program (15%), 15% of active users paying [assumption]

| Active users | One-time $9.99 (net $8.49) | Annual $4.99 (net $4.24) |
|---|---|---|
| 100 | $127 revenue, about -$62 | $64, about -$125 |
| 1,000 | $1,274, about +$1,085 (85%) | $636, about +$447 (70%) |
| 10,000 | $12,735, about +$12,510 (98%) after R-6 | $6,360, about +$6,135 (96%) |

One-time revenue repeats only with new users each year; the table assumes the active base turns over yearly. Break-even on fixed costs: **23 unlocks a year** at $9.99, or **45 subscribers** at $4.99.

**Recommendation:** free download with everything except the email address; **Shoebox Plus, a one-time $9.99 unlock**, adds the forwarding address, newsletter dates and pictures for email posts. Restore Purchases in Settings. Mint addresses only for a verified StoreKit transaction (the relay checks a signed JWS), which also closes RELAY-1. Enroll in the Small Business Program. No tip jar at launch.

**Would change it:** adding a cloud AI tier or sync (real running cost, then a subscription fits), or conversion under 5% in the first month (then try $4.99).

## D. Data and identity

**Recommendation: local-first, no accounts, for v1.0.**

- **New phone.** Today the only reliable path is an iCloud device restore. Fix: declare the iCloud Drive container so the Backups folder shows in Files, and on an empty store offer the newest 2.0 backup the way Shoebox 1 backups are offered (D-8). The inbox key moves to the Keychain (D-5), which iCloud Keychain carries to a new phone; backups include it only if the user chooses.
- **Backups.** Daily, 7 kept plus the biggest, local and iCloud Drive. Move photos out of the JSON and run off the main thread (D-7).
- **Export.** A backup file is the export. Add "Save a copy" to the share sheet so a normal user can send it to Files or email.
- **Delete everything.** Keeps the key until `/me/delete` returns 200 and retries on launch; clears "Who it's about"; says "Your backups stay in Files until you delete them" (D-6). That satisfies 5.1.1(v), GDPR erasure (the user holds the only copy of everything else) and CCPA.
- **What `/me/delete` removes on the relay:** the address, the box record and waiting mail (first 1,000 keys only, `relay:718-719`). Not removed: per-network counters, which expire. Fix paging (R-6).
- **Relay split.** New app on its own Worker with seven routes; Shoebox 1 routes stay on the old Worker until it is retired (R-1).

**Would change it:** sync (decision A) or a cloud AI tier, either of which needs an account-like identity.

## E. Personalization

| Your choice today | Becomes |
|---|---|
| "Gunner, 8th grade..." placeholder | Removed. Neutral example ("Sam, 4th grade: soccer, band") |
| Daily limit All | Default 10, setting keeps All |
| Notification at 7:30 | Default, setting |
| Dated posts back 5 days before at 8 AM | Default; no setting in v1 |
| US school grades and month-first dates | Declared US English for v1 (question 4) |
| Pictures on | Default, setting |
| Look Auto | Default, setting |
| Shoebox 1 import on first run | Keep; silent when none found |
| "Who it's about" | Setting, only after the email address exists |

**First launch so it isn't empty:** one starter post that teaches the moves ("Pull me down to put me away"), and the first real save showing on Today the same day (A-1, A-2). This needs you to settle SPEC rule 1 ("anything kept during the day joins Today") against rule 6 ("comes back tomorrow"). Recommendation: saves made during the day join Today; after the first flick up, rule 6 applies.

**Settings "short list, no paragraphs":** the root list holds (`SettingsView.swift:73-100`). The Email screen shows up to three quiet lines where SPEC allows one (`SettingsView.swift:218,233,252,262`). Trim it.

**Would change it:** testers finding the starter post childish (then a one-line empty-state instruction instead).

## F. Design and return

**Raises daily return without manipulation:**
- The daily notification with Next and Put away on it.
- A widget (post-launch).
- A default daily limit of 10, so Today stays finishable: "That's all for today" is the reward.
- "Coming up" in the Shoebox already gives a reason to look ahead.

**Avoid:** streaks, badges, red counts on the icon, "you missed" notifications, more than one notification a day.

**Broad audience:** the box, lid, rattle, Plum Night and Nectarine work: warm, not gendered, and the shoebox of keepsakes is a common image. Keep the rattle, honor Reduce Motion (X-5).

**Words:** "Put away" is clear. "Back tomorrow" is clear after one use; the resting hint on the first posts (A-4) covers the first time. Use "Put away" everywhere; retire "Kept" from user-facing text (it remains the model's name).

**Would change it:** testers not returning on day 2 even with the notification on; then the notification copy and time are the first thing to test.
