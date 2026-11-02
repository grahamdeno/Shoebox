# Phase 1: expert audits

Each finding: id, severity, finding, evidence, recommendation, effort (S, M, L). [I] marks a runtime inference. Backlog ids in brackets map to `backlog.csv`.

---

## 1. Product strategist (7/10)

**Position.** Shoebox is the only app in its set that decides *when* to bring something back from your own reason, and that turns forwarded school and trip email into dated posts. Notes and Reminders store; Pocket-style apps (Pocket itself closed in 2025) and Readwise ask you to work a list; Things needs you to plan; Apple Mail flags never come back. "Keep it. It comes back to you." is the right line.

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| PS-1 | high | The daily return loop depends on opening the app. The levers that bring people back without opening it (widget, actions on the notification, Lock Screen) are not built, though the README sells them | `README.md:3-6`; SPEC 7 items 1, 2 | Ship v1 honest; widget first after launch [F-2] | L |
| PS-2 | high | Email forwarding is the moat (newsletters to dated posts) and the main abuse and cost surface | `EmailCalendar.swift`; `relay:755-763` | Make it the paid unlock (decision C) [M-1] | M |
| PS-3 | med | The App Store name "Shoebox: Your Own Feed" undersells the return idea; "feed" reads as social | `docs/SPEC.md:7` | Test "Shoebox: It Comes Back" or similar in the subtitle | S |
| PS-4 | med | PLAN.md is stale against SPEC: Done and Later, the bar, the quiet rule, Peach and slate, relay AI fallback | `docs/PLAN.md:21-25,56-61,76,89` | Rewrite PLAN sections 2, 4 and 6 to match SPEC so future agents don't build the old design | S |
| PS-5 | med | The default daily limit "All" lets Today grow without end; a pile is what read-later users are escaping | `Shared/Rules.swift:74-76` | Default to 10 [UX-12] | S |
| PS-6 | low | Photo-to-post (flyers) is promised in PLAN moment 5 and missing on `main` | `Shared/Capture.swift:18-24` | Lands with PR #28; don't market until tested | M |

## 2. UX researcher (6/10)

Nielsen heuristics, 1 to 5:

| Heuristic | Score | Why |
|---|---|---|
| Visibility of status | 4 | Threshold ticks, lid, count, Undo. Keep something gives no confirmation; past posts retire silently |
| Match with the real world | 4 | The box metaphor and words work. "Put away" in the UI, "Kept" in the model and SPEC |
| User control and freedom | 3 | Undo only 5 s; no swipe back in Settings |
| Consistency and standards | 3 | Close moves between corners; custom navigation; Undo pill |
| Error prevention | 4 | 160 pt pull, duplicate check, backup before delete; Box allows full-swipe delete |
| Recognition over recall | 2 | Nothing on Today shows the moves after onboarding |
| Flexibility and efficiency | 3 | Fast gestures, share sheet, email; no widget or shortcuts |
| Minimalist design | 5 | |
| Error recovery | 3 | Plain words; share sheet store failure is silent |
| Help | 4 | The three moves can be replayed |

**SUS estimate [I]: about 70 in week one, about 76 settled.** Below the 80 target mainly because of UX-1 and the invisible gestures.

Walkthrough: first launch is 4 screens ending on "Try it" (`Onboarding.swift:21-26`) and an empty Today (`TodayView.swift:401-402`). First save closes with no message and goes away until tomorrow 8 AM (`AddSheet.swift:213-217`, `Capture.swift:67-68`, `LaterPlanner.swift:79`). Next morning the notification names the first headline (`Notifier.swift:34-35`) and the loop works. In week one, passed posts return daily with no limit, dated posts reappear at 5, 1 and 0 days before (`Rules.swift:128`), and past ones vanish.

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| UX-1 | high | First save never shows on Today the same day; SPEC 3 rule 1 says saves made during the day join Today, rule 6 says tomorrow | `Capture.swift:67-68`; `Rules.swift:61,72` | Decide (decision E); first saves or first-day saves go to Today [A-1] | S |
| UX-2 | med | No confirmation after Keep something (share sheet has one) | `AddSheet.swift:217` vs `ShareViewController.swift:157-158` | Same line as an Undo toast [A-3] | S |
| UX-3 | med | Past-dated posts move to Kept silently and look like ones you put away | `TodayView.swift:610`; `Rules.swift:29-38` | One-line notice and a "Day passed" tag [A-7] | S |
| UX-4 | med | No resting hint of the moves | `TodayView.swift:267-283` | Hint on the first 3 posts [A-4] | S |
| UX-5 | med | Box rows allow a full swipe to delete; SPEC 2.4 keeps actions on the opened post | `BoxView.swift:221-227` | Remove [V-2] | S |
| UX-6 | med | Settings uses custom paging: no edge swipe back | `SettingsView.swift:33-39,124-131` | NavigationStack with hidden bar | M |
| UX-7 | low | Settings only through the Box; SPEC says Today too | `TodayView.swift:179` | [A-8] | S |
| UX-8 | med | "Delete all N posts" counts soft-deleted posts | `SettingsView.swift:9,331,333` | Filter `deletedAt == nil` [D-6] | S |
| UX-9 | low | "Get my address" can be double-tapped | `Onboarding.swift:90-99`; `SettingsView.swift:239-246` | `.disabled(working)` | S |
| UX-11 | low | The notification shows a headline on the Lock Screen | `Notifier.swift:35` | Count only, or respect system preview setting | S |

## 3. Onboarding and activation (5/10)

Time to first kept post: about 60 to 90 s [I]. Time to first post *seen*: next morning. SampleData never reaches release builds (`SampleData.swift:5`, `ShoeboxApp.swift:9-13`).

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| ON-1 | critical | Onboarding ends on "Try it" with nothing to try, then the first save vanishes until tomorrow | `Onboarding.swift:25`; `TodayView.swift:401-402`; `Capture.swift:67-68` | A starter post ("Pull me down to put me away") plus UX-1 [A-2] | S |
| ON-2 | critical | Your son's name and grade ship as a placeholder | `SettingsView.swift:256`; SPEC 2.8 | Neutral example; fix SPEC [P-5] | S |
| ON-4 | high [I] | Share sheet is described in 3 text steps before any reason to save | `Onboarding.swift:70-72` | Teach it after the first save, or "Try it: open Safari" | M |
| ON-5 | med | Forwarding address asks for a first name on screen 2, before value is clear, without saying it leaves the phone | `Onboarding.swift:73-107`; `Inbox.swift:39-42` | Defer, disclose [A-6] | S |
| ON-6 | med | Notification permission asked before value; never asked again after "Not now" | `Onboarding.swift:112-124`; `Notifier.swift:18` | Ask after first save, or provisional [A-5] | S |
| ON-7 | low | Welcome is three sentences; SPEC says one line | `Onboarding.swift:56` | One line | S |
| ON-8 | low | No step indicator or Back | `Onboarding.swift:21-28,42` | "2 of 4", Back as a quiet word | S |
| ON-9 | med | Empty state has no single primary action; SPEC forbids a Keep row | `TodayView.swift:401-402,420-426` | Your call (question 6) | S |

## 4. Visual and design system (7/10)

Palette hex values in `Shared/Theme.swift:27-84` match SPEC 5.1 exactly. No `Color.black` in shipped code; all 15 shadows use the plum shade. Liquid Glass is used on the post panel, opened-post words, Close, Edit and the bottom strip. No icon-only buttons.

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| VD-1 | med | Undo is a word inside a filled Capsule: a pill | `Shared/Surface.swift:142-163` | Words on a 20 pt glass panel [V-1] | S |
| VD-2 | med | Neumorphic helpers and white `lightSide` token still in code, unused | `Surface.swift:3-36`; `Theme.swift:48-53` | Delete [V-1] | S |
| VD-3 | med | Close is top right in Settings, top left elsewhere | `SettingsView.swift:66`; `OpenedView.swift:198`; `EditSheet.swift:67` | Top left everywhere [V-1] | S |
| VD-4 | low | 34 pt titles mix semibold and bold | `BoxView.swift:92`, `Onboarding.swift:146,195`, `SettingsView.swift:376` vs `AddSheet.swift:36`, `EditSheet.swift:71` | One title style | S |
| VD-5 | low | Glass radii 14 or 16 where SPEC says 20 | `OpenedView.swift:73,84,99,220`; `CameraSheet.swift:40` | `Metrics.cardRadius` | S |
| VD-6 | low | Boxed fields (search, name) next to hairline fields | `Surface.swift:78-85`; `Onboarding.swift:87-89` | Hairline for the name field | S |
| VD-7 | low | Share sheet titled "Keep it", + New "Keep something"; why field multiline in one, single in the other | `ShareViewController.swift:183,191-192`; `AddSheet.swift:35,83` | One title, one field (PR #28 touches this) | S |
| VD-8 | low | Reason is Nectarine text on Today, a filled chip on the opened post | `PostCard.swift:32-35`; `OpenedView.swift:68-73` | Pick one | S |
| VD-9 | low | "1 of N" on Today is not in SPEC | `TodayView.swift:249-254` | Add to SPEC or drop | S |
| VD-10 | low | Paired glass controls not in a `GlassEffectContainer` | `OpenedView.swift:195-251` | Group them | S |
| VD-12 | low | Demo photos use black ridges (screenshots only) | `SampleData.swift:67,72` | Plum shade | S |

Broad-audience check (decision F): the box, lid and rattle carry meaning for anyone who has kept a shoebox of keepsakes; Plum Night and Nectarine read warm, not gendered. "Put away" is clear; "Back tomorrow" is clear only after the first flick (UX-4 covers it).

## 5. Accessibility, WCAG 2.2 AA (3/10)

**92 fixed `.system(size:)` uses** across 11 files; zero text styles, `@ScaledMetric` or `dynamicTypeSize`. Zero matches for Reduce Motion or Reduce Transparency. Good: VoiceOver custom actions "Next one" and "Put away" on the Today card (`TodayView.swift:98-99`), button alternatives on the opened post (`OpenedView.swift:235-241`), so WCAG 2.5.1 is met; the rattle always pairs haptics with a visible shake.

Contrast (computed): all text pairs in SPEC 5.1 pass, lowest quiet on card at 4.70. Fails: placeholder at 80% quiet on Wheat 3.57; field hairline `#DCCAB8` on Wheat 1.49 and hairline `#EADCCB` 1.26 (non-text needs 3:1); text over a bright photo patch the 16 by 16 average misses about 2.3 to 3.5 [I].

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| AX-1 | critical | No Dynamic Type; headlines also shrink to 0.8 and clip | 92 sites, e.g. `PostCard.swift:33-59`, `TodayView.swift:242-439`; `PostCard.swift:41-42` | Text styles with weights, `@ScaledMetric`, a large-text Today layout [X-1] | L |
| AX-2 | high [I] | Shoebox sheet parked off-screen stays in VoiceOver order; Today stays reachable behind it when open | `TodayView.swift:109-112,127`; `BoxPull.swift:27,47` | `accessibilityHidden` when closed; modal when open [X-2] | S |
| AX-3 | high | Undo appears silently and leaves after 5 s | `TodayView.swift:455-470,565-571`; `BoxView.swift:203-207` | Announce; longer with VoiceOver or Switch Control [X-3] | S |
| AX-4 | high | Settings choices don't expose `.isSelected` | `SettingsView.swift:401-411` | Add trait [X-4] | S |
| AX-5 | high | 4 DatePickers with empty labels | `Onboarding.swift:119`; `AddSheet.swift:100`; `EditSheet.swift:155`; `SettingsView.swift:181` | Labels plus `.labelsHidden()` [X-4] | S |
| AX-6 | med | Line field labels not tied to their fields | `Surface.swift:118-133`; `AddSheet.swift:62,83` | `accessibilityLabel` inside LineField [X-4] | S |
| AX-7 | med [I] | Today card has the button trait but no default action | `TodayView.swift:94-97,481,500-503` | `.accessibilityAction` [X-7] | S |
| AX-8 | med | No Reduce Motion | `TodayView.swift:318-330,362-383,512-522` | Cross-fades, no shake [X-5] | S |
| AX-9 | med [I] | No Reduce Transparency or Increase Contrast for hand-tuned scrims | `PostCard.swift:65`; `OpenedView.swift:114` | Opaque plum panels [X-5] | S |
| AX-10 | med [I] | Text on photos can drop below 4.5:1 | `TodayView.swift:251-257`; `PostCard.swift:34,56,60`; `PostPhoto.swift:27,198-201` | Stronger top scrim, full-opacity byline, sample under the panel [X-6] | M |
| AX-11 | med | Field lines and placeholders fail contrast | `Theme.swift:83`; `Surface.swift:127,138` | Field line about `#A8957F`; full quiet placeholder [X-6] | S |
| AX-12 | low | No header traits | `BoxView.swift:91,237-245`; `OpenedView.swift:54` | `.isHeader` [X-4] | S |
| AX-13 | low | "›" and "‹" glyphs are read aloud | `TodayView.swift:439`; `SettingsView.swift:125,419` | Hide glyphs [X-4] | S |
| AX-14 | low | Photo credit link under 44 pt | `OpenedView.swift:180-190` | Min height [X-7] | S |

## 6. iOS platform engineer (5/10)

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| IOS-1 | high | No `VersionedSchema` or migration plan; store failure crashes every launch | `Shared/Store.swift:29`; `ShoeboxApp.swift:17` | Version v1 now; recovery screen with "Bring one back" [D-1] | S |
| IOS-2 | high | UserDefaults not declared; share extension has no manifest | `PrivacyInfo.xcprivacy:44-45`; `Store.swift:15`; `ShareViewController.swift:30` | CA92.1 and 1C8F.1 in both [P-3] | S |
| IOS-3 | high | Share extension decodes up to 10 full photos on main thread; 48 MP is about 190 MB vs about 120 MB limit | `ShareViewController.swift:81,112,147`; `Relay.swift:48-49` | `CGImageSourceCreateThumbnailAtIndex` (already in `BoxPull.swift:61-67`), file representations, one at a time [D-3] | S |
| IOS-4 | med | Share extension closes silently if the store won't open | `ShareViewController.swift:131,156` | Message [D-4] | S |
| IOS-5 | high | Daily backup on main thread at background entry, no background task, photos as base64 inside JSON; 8 files kept in two places | `ShoeboxApp.swift:74-80`; `Backups.swift:227,269-293,285-286` | Photos beside the JSON; background task [D-7] | M |
| IOS-6 | high | No restore path for 2.0 backups on a new phone; iCloud folder likely invisible in Files | `Backups.swift:44-57,70-86`; `App/Info.plist:1-11` | `NSUbiquitousContainers`; auto-offer native backup when store is empty [D-8] | S |
| IOS-7 | med | iCloud writes uncoordinated, errors ignored | `Backups.swift:279,289-291` | `NSFileCoordinator` [D-9] | S |
| IOS-8 | med | No background work; notifications planned 7 days ahead; mail only on open | `Notifier.swift:26`; `ShoeboxApp.swift:68-71` | Background refresh [F-1] | M |
| IOS-9 | med | Inbox key in plain UserDefaults and in every backup file | `Store.swift:79-82`; `Backups.swift:203,234`; `project.yml:53` | Keychain, shared access group [D-5] | S |
| IOS-10 | med | Delete everything leaves gaps (see D-6) | `SettingsView.swift:350-370` | [D-6] | S |
| IOS-11 | med | Mail acked after an unchecked save | `Inbox.swift:165-168` | Ack after success [D-2] | S |
| IOS-12 | med | Swift 5 mode; static mutable state; `DispatchQueue.main` timing | `project.yml:14`; `TodayView.swift:127,388` | Strict concurrency, then Swift 6 [F-4] | M |
| IOS-13 | low | Shoebox 1 import decodes photos on main thread at first launch | `Backups.swift:116` | Detached decode | M |
| IOS-14 | low | Manifest declares analytics with no analytics code | `PrivacyInfo.xcprivacy:5,21,33` | [P-2] | S |

Test coverage: Core about 105 tests (planner, rules, email calendar, importer, name mask, detection); App about 64 (DateReader, rules, library, backup filename, relay headers, in-memory store). Untested: `Inbox.collect`, backup round trip, retention, Delete everything, Notifier, StockPhoto, the share extension, the on-disk store, migration. No UI tests.

## 7. App Store review and compliance (3/10)

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| AS-1 | critical | No privacy policy URL or in-app link (5.1.1(i)); external TestFlight also needs it | none in repo | [P-1] | M |
| AS-2 | high | Privacy manifest and nutrition label would misstate collection | `PrivacyInfo.xcprivacy:17-43` | Labels in `05-release-checklist.md` [P-2] | S |
| AS-3 | high | False in-app privacy claim | `SettingsView.swift:324` | [P-4] | S |
| AS-4 | high | Missing required-reason declarations may block upload (ITMS-91053). TestFlight uploads have succeeded, so check App Store Connect email for warnings | `PrivacyInfo.xcprivacy:44-45` | [P-3] | S |
| AS-5 | med | Account deletion (5.1.1(v)): no account, but the email address is a server identity made in the app. Delete everything covers it, unreliably | `SettingsView.swift:362-368` | Retry until confirmed; say so in review notes [D-6] | S |
| AS-6 | med | Metadata must not promise Siri, Watch, Lock Screen, widgets or flyer reading (2.3.1) | `README.md:3-6` | [P-6] | S |
| AS-7 | med | Reviewer can't easily exercise email; stock pictures fail until relay deploy (2.1) | `relay/README.md:5` | Demo path in review notes [P-7, R-2] | S |
| AS-8 | low | Name "Shoebox: Your Own Feed" availability and conflicts not checked | SPEC line 7 | Check in App Store Connect before beta | S |
| AS-9 | low | Pixabay credit is shown (API rule), good | `OpenedView.swift:178-190`; `StockPhoto.swift:57` | Keep | |

## 8. AI architect (7/10)

Strengths: everything on device, greedy sampling for the email post, a vocabulary whitelist that keeps names and private words off the network, a fallback for every call.

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| AI-1 | high | Guard misses invented weekday and month names, places, wrong pairings ("Nov 7" passes if 7 appears in "7 pm"); rejects good output ("4:00 PM" from "4 pm", "4150" from "$4,150"); years added to the source let invented 2026 or 2027 pass | `EmailRules.swift:61-68`; `EmailPost.swift:31` | Check weekday and month words; pair digits with units; normalize ":00" [C-1] | M |
| AI-2 | med | A post written while the model is unavailable keeps fallback text forever | `EmailPost.swift:15` | Mark and rewrite later [C-5] | S |
| AI-3 | med | 3,500-char prefix of email plus PDF and page text drops late deadlines | `EmailPost.swift:17`; `Inbox.swift:103,108` | Body first, trim attachments separately [C-6] | S |
| AI-4 | low | Email passed without delimiters; prompt injection can produce a calm post for phishing | `EmailPost.swift:18-25` | Delimit as data; run `looksLikePromotion` [C-6] | S |
| AI-5 | low | `PhotoChoice.number` has no range guide (0-based list); `photoWords` not greedy | `StockPhoto.swift:237,256` | `@Guide(.range)`; greedy [C-11] | S |
| AI-6 | low | Sensitive-word list English only (whitelist still protects the network) | `StockPhoto.swift:121-130` | With C-10 | M |
| AI-7 | info | Core planner (R1 to R20 plus model hints) not wired in | no planner calls in `App/` or `Shared/` | Keep out of v1; wire post-launch with tests | |

## 9. Monetization and pricing analyst (2/10)

Nothing is built: no StoreKit, no paywall, no restore. Costs are small and mostly fixed, so pricing is a positioning choice. Full cost model and options in `03-decisions.md` decision C.

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| MO-1 | high | No way to earn revenue | grep: no StoreKit | One-time unlock [M-1] | M |
| MO-2 | med | The costly, abusable feature (email address) is free and unauthenticated | `relay:755-763` | Gate minting on a verified StoreKit transaction | M |
| MO-3 | low | Small Business Program not confirmed | | Enroll [M-2] | S |

## 10. Privacy, security and legal advisor (4/10)

**Data map**

| Data | Leaves the phone to | Kept | Who can read |
|---|---|---|---|
| Link URL | Relay `/preview`, then the site | Cloudflare edge cache 24 h | Operator, Cloudflare, the site sees the relay |
| Page picture | Fetched by the phone directly | No | The site sees the phone's IP |
| Stock words (2 to 4 generic words) | Relay to Pixabay | Cache 24 h | Pixabay; never names or private words (`StockPhoto.swift:78-97,120-141`) |
| Forwarded email: From, subject, up to 60,000 chars, 30 links, PDFs and pictures up to 4 MB | Cloudflare Email Routing to KV | Until collected, up to 30 days | Operator, Cloudflare, key holder |
| First name in the address | Relay | No expiry | Anyone who receives mail from the user |
| Inbox key | Phone, backups | Plain text | Anyone with a backup file |
| Saves, notes, photos, "Who it's about" | Stay on the phone and its backups | | User |

Processors: Cloudflare, Pixabay. Anthropic is not used by the new app (the shared relay's `/beta` sends applicant answers to Anthropic, `relay:1487-1513`).

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| PRIV-1 | critical | No privacy policy or terms | none | [P-1]; cover the data map, 30-day retention, processors, GDPR access and erasure, CCPA no sale, children's details, contact | M |
| PRIV-2 | high | Manifest declares the wrong data | `PrivacyInfo.xcprivacy:17-43`; `relay:92,693,197` | [P-2] | S |
| PRIV-3 | high | "Nothing is kept" is false | `SettingsView.swift:324`; `relay:90-92,692-693` | "Email waits on our server until your phone collects it, up to 30 days, then it's deleted." [P-4] | S |
| PRIV-4 | med | Mail in plain text in KV; key in plain backups | `Store.swift:79-81`; `Backups.swift:234,261` | Keychain now [D-5]; seal mail to a device key later [R-13] | M |
| PRIV-5 | med | Auto-fetched links and pictures reveal IP to senders; GET can burn magic links | `Inbox.swift:107,152-153`; `Relay.swift:40-46` | Pictures via relay; skip token URLs [R-12] | S |
| PRIV-6 | med | Newsletters carry children's names, grades, activities; 30-day retention | SPEC 2.8; `Inbox.swift:115` | 7-day retention [R-11]; disclose; not directed at children, so COPPA doesn't apply | S |
| PRIV-7 | low | Beta applicants' data on the shared relay goes to Anthropic | `relay:1487-1513` | Leave on the old Worker or retire | S |
| PRIV-8 | med | The repo is public and carries family details in tests | see `01-inventory.md` section 1 | [P-8] | S |

## 11. QA and release engineer (4/10)

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| QA-1 | high (testers only) | 2.0 reads only Shoebox 1 backup files, not 1.0's live store; a tester without a recent backup loses saves on update | `project.yml:2`; `Backups.swift:44-57,70-86` | Test on your phone from build 36; ask testers to save a backup first [D-10]. Not a public risk: 1.0 was never released (`PLAN.md:53`) | M |
| QA-2 | high | Tests don't gate TestFlight | `testflight.yml:4-6,29-45`; `ios.yml:3-6` | Test steps before archive [Q-1] | S |
| QA-3 | med | CI picks any iPhone simulator, maybe below iOS 26 | `ios.yml:35` | Pin as `screens.yml:22` does [Q-1] | S |
| QA-4 | med | Newest Xcode 26 on the runner may be a beta, which App Review rejects | `testflight.yml:16`; `ios.yml:16` | Pin a release [Q-1] | S |
| QA-5 | med | Unsigned archive plus ad-hoc entitlement stamp is fragile | `testflight.yml:44,51-52,60-68` | Post-export entitlement check [Q-6] | M |
| QA-6 | low | Re-run reuses a build number; no concurrency group | `testflight.yml:43,79` | [Q-4] | S |
| QA-7 | med | Tester groups manual | `testflight.yml:54-79` | [Q-3] | S |
| QA-8 | high | No production crash reporting | `Scripts/crash_report.py:2-4` | MetricKit [Q-2] | S |
| QA-9 | med | Smoke launch runs only with `[screens]` off main | `screens.yml:4-10` | Smoke launch in ios.yml [Q-5] | S |
| QA-10 | med | Riskiest paths untested | `App/ShoeboxTests` | [Q-5] | M |
| QA-11 | med | App depends on relay routes not yet deployed | `relay/README.md:5`; `StockPhoto.swift:187` | [R-2] | S |
| QA-12 | low | No kill switch | `Relay.swift:7-8` | Relay returns a minimum version or notice | M |

Regression risk from big batched releases: high while tests don't gate uploads and nothing reports crashes. Q-1 and Q-2 make one-big-release safe. Rollback: none on the App Store; the relay can be redeployed to a previous version, and a minimum-version check (QA-12) is the only lever.

## 12. Retention analyst, privacy-preserving (4/10)

Today nothing is measured. That is consistent with the privacy promise and should stay that way for v1.

- **Use App Store Connect Analytics:** installs, sessions, active devices, D1, D7 and D28 retention and crashes from users who share analytics with developers. No SDK, no manifest entry.
- **TestFlight:** sessions and crashes per tester, plus feedback. Ask three questions weekly: did something come back at the right time; what did you put away; what did you stop saving.
- **Relay aggregate counts (optional, later):** mails received per day and addresses active in 7 days, counted without content. That is server data about the service, not users; disclose it in the policy if added.
- **On-device only:** a private "your week" line (kept, came back, put away) can help the user and needs no network.
- **Targets for the beta:** D7 at least 40%, D28 at least 25%, at least 3 saves in week one for 60% of testers. These are judgment, not benchmarks.

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| RT-1 | low | `/stats` exists on the relay but the new app sends nothing, while the manifest says it does | `relay:1348,1361`; `PrivacyInfo.xcprivacy:17-43` | Don't add stats for v1; fix the manifest [P-2, T-1] | S |

## 13. Email ingest and relay reliability (4/10)

Routes used and legacy routes are mapped in `01-inventory.md` section 3.

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| RELAY-1 | high | Unlimited address minting, no attest, no rate limit, no TTL | `relay:735,755-763,692-693` | [R-3] | M |
| RELAY-2 | high | Owner mailbox goes to the first caller when `inbox-key` is missing, which `/me/delete` causes | `relay:721,737,959-960` | Pin by secret; remove `/apple/*` [R-4] | S |
| RELAY-3 | high | Anyone who knows an address can post into a feed; about 20 bits of suffix; bounces reveal valid addresses | `relay:646,657-660,85,90-92` | 8+ chars, silent drop, per-box cap [R-5] | M |
| RELAY-4 | med | 7 KV deletes per ack; list per poll; owner list stops at 1,000 keys | `relay:777,744-745,718-719` | [R-6] | S |
| RELAY-5 | med | Regex MIME parser over 12 MB with no CPU guard; no logging | `relay:81-86,818-842`; `wrangler.jsonc` | Paid plan, caps, try/catch stub, content-free logs [R-7] | M |
| RELAY-6 | med | `/image`, `/file`, `/preview`, `/ical` can act as open fetchers; redirects not re-checked; IPv6 private ranges missed | `relay:195,412,431,434,447,453` | Remove `/image` and `/file`; harden `/preview` [R-1, R-8] | S |
| RELAY-7 | med | AI caps can be beaten by parallel calls; attest only at sign-up (not reachable by the new app) | `relay:1066-1072,1078,1086-1087,1533` | Fix before ever enabling relay AI | M |
| RELAY-8 | med | Per-IP limits will block users behind carrier NAT | `relay:353-362,1063-1064` | [R-10] | M |
| RELAY-9 | med | Delete can leave the address alive forever | `SettingsView.swift:362-368`; `relay:692` | [D-6, R-3 TTL] | S |
| RELAY-10 | low | No Message-ID dedup; ack even when the attachment fetch failed | `relay:87`; `Inbox.swift:79-82,100,163-168` | [R-9] | S |
| RELAY-11 | low | Mail collected only on open | `ShoeboxApp.swift:70` | [F-1] | M |
| RELAY-12 | med | Repo relay not deployed; README stale; legacy routes open | `relay/README.md:5,12,40`; `relay:125-143,940,506-515,1050` | [R-1, R-2] | M |
| RELAY-13 | low | `/version` exposes `EMAIL_ADDRESS`; 500s echo exceptions; localhost and github.io origins allowed; `workers_dev` bypasses cache | `relay:112,100,54,59`; `wrangler.jsonc:9` | Trim in the split | S |

Delivery latency: the phone collects on foreground only; KV reads can lag about 60 s after arrival. Acceptable for v1 if the help line says "Mail shows up next time you open Shoebox."

## 14. Generated-content quality evaluator (6/10)

Scores from reading rules and fixtures; no model output could be run here.

| Output | Accuracy | Tone | Dates | No invented details |
|---|---|---|---|---|
| Email, AI path | 3 | 4 | 3 | 4 |
| Email, fallback | 3 | 2 | 3 | 5 |
| Newsletter calendar (27-date fixture) | 4 | 4 | 4 (US only) | 5 |
| Photo to post | not on `main` (PR #28) | | | |

The fixture's 27 dated lines yield 16 posts for a grade 8 profile and 7 with no profile, matching tests (`EmailCalendarTests.swift:18,30,44`).

| ID | Sev | Finding | Evidence | Recommendation | Eff |
|---|---|---|---|---|---|
| GEN-1 | high | Outlook and Apple Mail "Sent:" and "Cc:" headers not filtered; "Sent: Monday, October 26" becomes next Monday's event | `Inbox.swift:95`; `EmailRules.swift:128-133` | [C-2] | S |
| GEN-2 | high | Email weekday matching looser than DateReader ("last", "every", "Black Friday", substring "mondays") and reads 400 lines of page text and PDFs, against SPEC 4.2 | `EmailRules.swift:128-133`; `DateReader.swift:79`; `Inbox.swift:155` | Use DateReader on limited text [C-3] | M |
| GEN-3 | med | Dated email keeps only the day; time and deadline lost; "RSVP by Nov 3, party Nov 7" dates Nov 3 | `Inbox.swift:181-185`; `DateReader.swift:114` | [C-3] | S |
| GEN-4 | med | No card or account number redaction despite SPEC 4 | `EmailPost.swift:56-60` | Luhn plus "acct" redaction [C-4] | S |
| GEN-5 | med | Month-first numeric dates everywhere; NSDataDetector follows device locale, so readers can disagree | `DateReader.swift:58-72,272`; `EmailCalendar.swift:167-174`; `EmailRules.swift:122` | [C-10] | M |
| GEN-6 | med | Locale mixed: device symbols in one reader, English hardcoded in another, en_US display | `EmailRules.swift:128,135`; `DateReader.swift:262,265`; `EmailCalendar.swift:234` | [C-10] | M |
| GEN-7 | med | Three different year-rollover windows (120, 60, 60 days) and SPEC says 7 | `DateReader.swift:250-251`; `EmailRules.swift:145`; `EmailCalendar.swift:181` | [C-9] | S |
| GEN-8 | med | Any short line can be a heading and hide items; no post cap; "Grades 6-8", K, Pre-K, Year 9 not parsed | `EmailCalendar.swift:97,107-116,135-139` | [C-7] | M |
| GEN-9 | low | "Nov 25 to 27: No school" dated Nov 25 only, retired on Nov 26 | `EmailCalendar.swift:196-201` | [C-7] | S |
| GEN-10 | low | Fallback keeps greetings ("Hi Graham,") | `EmailPostTests.swift:6` input | [C-11] | S |
| GEN-11 | low | "6:30" always PM; 7:00 to 11:59 bare times dropped | `DateReader.swift:210-211` | [C-11] | S |
| GEN-12 | high | No OCR on `main`: a photographed flyer becomes "A photo" | `Shared/Capture.swift:18-24` | PR #28 adds `PhotoRead`; test it | M |

## Reconciled conflicts

- **QA-1 severity.** Platform review rated the Shoebox 1 update path critical. 1.0 was never public (`PLAN.md:53,163`), so it is high for your own phone and testers and absent for the public. Kept as a beta item for testers.
- **First save timing.** UX wants saves on Today the same day; SPEC rule 6 says tomorrow. Not a code bug; a product decision (decision E, question 3).
- **Relay AI fallback.** PLAN says devices without Apple Intelligence fall back to relay AI; the app has none, and the relay's AI path is the least safe code (RELAY-7). Recommendation (decision B): stay on device.
- **Email gating.** Monetization wants email as the paid feature; activation wants email early. Resolved by letting the free tier keep everything except minting an address, and showing the address as the reason to buy after the first week.
- **Backups vs privacy.** Backups carry the inbox key (useful for restore, risky in plain files). Resolved by the Keychain (D-5), which survives reinstall on the same device, plus an explicit "include my email address" choice in backups.
