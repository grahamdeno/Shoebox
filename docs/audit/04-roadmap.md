# Phased roadmap

Ids refer to `backlog.csv`. Effort points are human person-weeks for comparison; agent-built work moves faster.

## Phase 1: public TestFlight beta

**Irreversible steps in this phase, first:**
- **Deploy the relay** (R-2) to production after the split (R-1). Do it from this repo only, never from `grahamdeno/edition` too.
- **Publish the updated privacy policy and the terms** (P-1) on inmyshoebox.com.
- **Enable external testing** in App Store Connect (Beta App Review sees the policy URL and the build).

**Exit criteria:** a stranger installs from a public link, keeps something, forwards an email, and nothing they do can lose data, leak another user's mail, or contradict the privacy text.

| Group | Items |
|---|---|
| Privacy and compliance | P-1 policy and terms, P-2 manifest types, P-3 required-reason APIs, P-4 honest retention line, P-5 remove the child's name, P-8 scrub family details from the public repo |
| Relay | R-1 split, R-2 deploy, R-3 attested and rate-limited minting with TTL, R-4 pin the owner, R-5 longer suffix, silent drop, per-box cap. Move to Workers Paid |
| Version | Q-7 MARKETING_VERSION 1.0.0 |
| Data safety | D-1 schema version and recovery screen, D-2 ack after save, D-3 share extension memory, D-4 share failure message, D-10 your update path from build 36 |
| Content | C-2 forward headers |
| Usability | A-9 Close flakiness |
| Release | Q-1 tests gate uploads, pinned Xcode and simulator, Q-2 MetricKit, Q-3 tester groups, Q-4 build numbers, Q-6 entitlement check, T-1 retention measures |

About 25 items. PR #28 is merged; one beta build at the end (your one-big-release rule).

## Phase 2: App Store v1.0

**Irreversible steps in this phase, first:**
- **Create the StoreKit product** (M-1) in App Store Connect. Product ids can't be reused once created.
- **Submit for Review** is yours to press. Agents stop at a ready, uploaded build with metadata filled.

**Exit criteria:** SUS 80 or better from 10 or more testers, D7 retention 40% or better, crash-free sessions 99.5% or better, every item in `05-release-checklist.md` ticked.

| Group | Items |
|---|---|
| Activation | A-1 first save on Today, A-10 daily limit 10 with new posts joining, A-2 welcome post, A-3 confirmation, A-4 resting hint, A-5 notification timing, A-6 email later, A-7 past-date notice, A-8 Settings from Today |
| Accessibility | X-1 Dynamic Type (the largest item), X-2 to X-7 |
| Data safety | D-5 Keychain, D-6 Delete everything, D-7 backups off main, D-8 restore on a new phone, D-9 iCloud coordination |
| Content | C-14 day-first dates and Year levels (CA, UK, AU, NZ are on sale), C-1 guard, C-3 dates, C-4 card numbers, C-5 rewrite fallbacks, C-6 ordering and delimiters, C-7 newsletters, C-8 moved events, C-9 one rollover rule, C-10 locale decision, C-11 small fixes |
| Relay | R-6 KV efficiency, R-7 parser guard and logs, R-8 `/preview`, R-9 dedup, R-10 device limits, R-11 7-day retention, R-12 pictures via relay |
| Platform | F-1 background refresh, F-5 notification actions |
| Money | M-1 Shoebox Plus unlock, M-2 Paid Apps Agreement (Graham) |
| Design | V-1 cleanup, V-2 no full-swipe delete |
| Text | P-6 metadata and README, P-7 review notes |
| Release | Q-5 tests for Inbox, backups, Delete everything |

About 47 items.

## Phase 3: post-launch

1. **v1.1 languages:** C-12 Spanish for Mexico (and Spanish speakers in the US), C-13 French for Canada. Both are screens plus reading dates, reasons and newsletters in that language.
2. F-2 Home and Lock Screen widget.
3. F-3 App Intents: Keep, Find, Bring back; Action Button.
4. R-13 mail sealed to a device key.
5. F-4 Swift 6.
6. Core planner (R1 to R20) wired in with tests; "before the meeting" from the calendar.
7. Revisit sync (decision A) and a cloud AI tier (decision B) only on user demand.
8. Retire Shoebox 1's routes and the old Worker once no build 36 phones remain.
