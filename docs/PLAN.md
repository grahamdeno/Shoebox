# Shoebox: the plan

Written October 30, 2026. This is the brief for every build step. Read it before doing anything in this repo. When a decision here changes, change it here first.

## 1. What Shoebox is

**Keep it. It comes back to you.**

People save things everywhere (a link, a screenshot, a school flyer, a note) and mean to come back to them. They rarely do, because coming back is the hard part. Every read-later app asks you to open it and work a list. Shoebox doesn't.

You save something once, with your reason ("Drive it next fall", "Show the kids at dinner"). Shoebox reads the reason, decides when the save will be useful, and brings it back at that moment, wherever you already are: the Lock Screen, a notification, the car, the Watch, Siri. You answer with one touch. Most days you never open the app.

The old app (repo `grahamdeno/edition`, a web app in an iPhone wrapper) proved the core idea: saves with reasons, coming back a few at a time, three verdicts. This repo is a native rebuild around the better version of that idea.

## 2. The rules

These decide every design and engineering question. If a feature breaks one, the feature changes.

1. **Your reason decides when it comes back.** "Before we plan next quarter" means the gap before that meeting. "This weekend" means Saturday morning. "At dinner" means the evening at home.
2. **One moment per save.** A save comes back once, at one well-chosen time. Not a list to work through.
3. **Ignored twice, it goes quiet.** If you pass on a save twice, it stops coming back. It's kept, and it returns only if you ask.
4. **Answer without unlocking.** Every moment has its actions on it: the main one, Later, Drop.
5. **Shoebox prepares; you decide.** It can look things up, fill in dates and draft a reminder. It never books, pays, sends or deletes on its own.

## 3. Version 1: the ten moments

From the storyboard (`docs/design/storyboard.html`, Midnight Gold). Each is a v1 requirement unless marked later.

| # | Moment | When | iOS feature | Phase |
|---|---|---|---|---|
| 1 | The Daily Issue: a small cover with today's few, as your reasons | 7:00 AM | Rich notification | 3 |
| 2 | The issue read aloud in the car | Commute | Audio, Siri | Later |
| 3 | The reason finds a time: the gap before a matching calendar event | 9:48 AM | Live Activity, EventKit (read) | 4 |
| 4 | Capture: hold the Action Button on any page, say why | Any time | App Intent, speech | 4 (share sheet with voice in 2) |
| 5 | A screenshot is a save: the flyer is read, the reminder set | 3:10 PM | Photos (new screenshots), on-device text reading | 5 |
| 6 | "At dinner" means dinner: comes back at home in the evening | 6:10 PM | Notification, Focus filter | 3 |
| 7 | Search by asking Siri, answered in your own words | Any time | App Intents, Spotlight | 4 |
| 8 | A task comes back with the work done ("Book the campsite": open dates, a prefilled link) | Friday | Relay web lookup | 5 |
| 9 | A weekend save on the weekend, on the wrist | Saturday | Notifications mirrored to Watch (a Watch app is later) | 3 |
| 10 | The app: Coming back by date, everything kept one question away | Sunday | The app itself | 3 |

## 4. Decisions made

| Decision | Choice | Why |
|---|---|---|
| Platform | Native iPhone (SwiftUI) only | Lock Screen, Live Activities, Siri, Action Button and on-device AI are native-only. |
| PWA, web, Android | Not now | Can come later. See section 8 for what keeps that cheap. |
| Repo | New repo, `Shoebox` | Clean structure around "a save is a moment". The old repo becomes the archive. |
| App Store | Same record and bundle ID (`com.grahamdeno.shoebox`); this ships as version 2.0 | Keeps the name and listing. Never create a new app record. |
| Old 1.0 | Submit it (Graham decided October 30). Graham presses Submit for Review himself. | Gets Shoebox in front of people now. 2.0 then ships as an update to the same app, so it must carry 1.0 users' saves over by itself (section 11). |
| Minimum iOS | 26 | On-device AI, current Live Activities and App Intents. The relay covers phones without Apple Intelligence. |
| Planner AI | Plain rules first, then on-device model, then the relay | Most reasons never need AI. Private, free per call, works offline. |
| "At home" | No location in v1. A home-evening window set once in onboarding (default 6:00 to 8:30 PM), sharpened by a Home Focus if you use one, and moved over time by when you actually answer. | Location "Always" is a heavy ask and the wrong first impression for a privacy-first app. Most people don't run a Home Focus, so Focus alone would leave "at dinner" broken for them. Learning from answers costs no permission. Location can come later as an opt-in. |
| New screenshots | Photos access limited to screenshots; a Shortcut automation is offered as the no-permission path | |
| Shoebox Me | Dropped. One app. | |
| Beta page and `/beta` | Kept until 2.0 launches, then removed | |
| Relay | Carry over the Cloudflare Worker | Link previews, email in, AI with App Attest and cost limits all work and are tested. |
| Data | On the phone, ready to sync later | Privacy promise stays. Sync becomes a feature, not a rewrite. |
| Palette | **Plum and Peach is primary** (Sharpened), Day and Night. Midnight Gold stays in the design system as the alternate, Night and Day. | Changed October 30 (decision 8). Sections 5 and 5a. Colors are role tokens (`act`, `text`, `quiet`...), so either palette fits every component. |
| Type | DM Serif Display for your reasons; Archivo for labels and UI | Both open-licensed (OFL), bundled in the app. |
| Shape | 4 to 6 px corners; thin outlines; no pill buttons | Reads as paper and print, not bubbles. |
| The act color | One act-colored element per screen: the thing to tap. Plum by day, peach at night (gold in Midnight Gold). | The act color means "act". Decoration in it is not allowed. |

## 5. Design

**The design system** (phase 1) is published as the Design System artifact "Shoebox" and kept in this repo as `design/tokens.json`, the single source of every color, type style, spacing, corner and shadow. Four themes, in order: Plum and Peach Day, Plum and Peach Night, Midnight Gold Night, Midnight Gold Day. Six components: Button, Notification, Live Activity, Issue cover, Coming back row, Capture sheet.

Phase 1 changed four values so every text color passes 4.5:1 (the tables below show the new values, with the old ones struck through).

### 5.1 Midnight Gold (the alternate)

Reference: `docs/design/storyboard.html` (Night/Day switch at the top).

| Job | Night | Day |
|---|---|---|
| Surface | `#0F1630` | `#F7F1E3` |
| Deep (Lock Screen, wallpaper) | `#0B1129` | `#0B1129` |
| Text (your words) | `#F3EAD7` | `#0F1630` |
| Gold (the one action) | `#D8B45A`, text on it `#0F1630` | `#D8B45A`, text on it `#0F1630` |
| Gold as text | `#E2C47A` | `#86671B` (~~`#8A6A1C`~~) |
| Quiet (dates, sources) | `#8F97B3` | `#5D6584` |
| Done | `#8FB3A0` | `#4A725E` (~~`#5F8A74`~~) |
| Lines | cream at 13% | navy at 12% |

Your reason is always the largest text on a moment, in the serif. Sources and times are small, in Archivo. Pictures sit in plain frames with 3 px corners.

### 5a. Plum and Peach (the primary)

Graham's favorite from the first round, made the primary on October 30 (decision 8). Reference: `docs/design/plum-and-peach.html`.

**Base colors**

| Job | Day (Sharpened) | Night (Plum night) |
|---|---|---|
| Surface | Blush `#F7EFE9` | `#22142A`, cards `#2E1B36` |
| Text (your words) | Plum ink `#2A1830` | `#F7E3D8` |
| The one action | Plum `#7A2E6E`, white text | Peach `#F4B49A`, text `#22142A` |
| Quiet (dates, sources) | Mauve `#776174` (~~`#806A7C`~~) | `#B597AE` |
| Done | Faded cyan `#3F6E6C` (~~`#7FA8A6`~~) | `#8FB9B7` |
| Mark (app mark only) | Peach `#F4B49A` | Peach `#F4B49A` |
| Deep (Lock Screen) | `#1D1222` | `#1D1222` |

The same rules apply: one action color per screen, 4 px corners, thin outlines, no pills.

**Four ideas that came with it.** Decided October 30: **only Sharpened.** The other three are not in v1.

1. **Sharpened.** The base above: small corners, outlined secondary buttons, plum only on the main action.
2. **Dusk to dawn.** The notification's color follows the time of day: morning `#FDE3D2` with `#B2456F`, midday `#F6F1EF` with plum, evening `#4A2148` with peach type and a peach action. More to keep consistent; strong sense of time.
3. **Ripening.** The date on a Coming back row shows how long you've kept the save: today `#F4B49A`, a week `#E5939A`, a month `#C06B91`, three months `#8E3A7D`, a year `#4A1D45`. The age is always written too, since color can't be the only signal.
4. **Two-ink print.** For the Daily Issue cover only: peach `#FF9E7A` and plum `#9D3C8F` as overlapping inks on `#F3EDE4`, type in `#5A1E52`, a fine grain and square corners.

## 6. Architecture

**App targets**
- `IssueContent` (Notification Content extension): the Daily Issue's opened view, with answers per line, and the expanded single-moment view. Added in phase 1 (`docs/SPEC.md` section 6).
- `Shoebox` (SwiftUI app): Coming back, everything kept, settings, onboarding.
- `Share` extension: save from any app; type or speak the reason.
- `Widgets`: Home Screen and Lock Screen widgets, plus the Live Activity.
- App Intents (in the app target): Action Button capture, Siri questions, Shortcuts, Spotlight.
- Later: a Watch app; CarPlay audio (needs Apple's audio entitlement).

**Minimum iOS:** 26 (decided). That gives Foundation Models (on-device AI), current Live Activities and App Intents. Devices without Apple Intelligence fall back to the relay's AI.

**Storage:** SwiftData in the shared App Group (`group.com.grahamdeno.shoebox`), so the app, share extension and widgets read one store. Files and photos live as files in the group container.
- Every record has a UUID, `createdAt`, `updatedAt`, and a soft-delete marker. This makes sync possible later without a migration.
- Export and import as JSON with files alongside. The importer also reads the old app's backup (version 2: items, meta, settings, files as base64).

**The return planner** (the heart of the app):
- Input: the save, its reason, its kind, and context (calendar events, Focus, time of day, how long it takes).
- Output: one `nextMoment` (a time window, a place or Focus condition, and the surface to use), or "quiet".
- First pass is on device: Foundation Models with structured output turns the reason into a when (date words, weekday words, "before X", "at dinner", "this weekend", "next fall"). Plain rules cover common phrases without AI. The relay's AI is the fallback.
- Delivery is local. Local notifications and Live Activities are scheduled on the phone. The relay is not needed for reminders, so the old web-push routes go away.
- Each save is offered once at its moment. Ignoring it (no answer within the window) counts as a pass. After two passes it goes quiet.

**Verdicts:** Done (or the kind's own word: Read, Watched, Booked), Later (pick a time or let Shoebox choose), Drop.

**Relay routes** (from `edition/relay/perplexity-relay.js`):

| Keep | Why |
|---|---|
| `/preview`, `/image`, `/file` | Link pages, pictures and files for saves |
| `/inbox`, `/inbox/ack`, `/inbox/address`, `/inbox/file` | Your Shoebox email address |
| `/ai/register`, `/ai/challenge`, `/ai/attest`, `/ai/usage` and the AI proxy | AI with App Attest and cost limits |
| `/me/delete`, `/version`, `/stats`, `/stats/report` | Delete my data; health; anonymous counts |

| Drop | Why |
|---|---|
| `/push/*`, `/remind` | Reminders become local notifications |
| `/ical` | Calendar is read on the phone with EventKit |
| `/song`, `/apple/*` | Song of the day isn't in v1 |
| `/ai/quotes`, `/ai/stories` | Quote of the day and top stories aren't in v1 |
| `/beta` | Kept until 2.0 launches, then removed (decision 6) |

New relay work: a lookup route for task saves (moment 8), returning facts with their sources, never acting.

## 7. What carries over from the old app

Extract these into `docs/SPEC.md` in phase 0, reading the old code, not from memory.

- **Saves and kinds:** link, note, quote, photo, PDF, file, video. `detectText` in the old `src/capture.js` decides which. Several links pasted together become several saves.
- **The reason line:** `why`, up to 140 characters, always shown at the top.
- **Old fading rules,** which the new quiet rule replaces: an item faded after 21 days untouched (`FADE_DAYS`) or 8 deferrals (`MAX_SKIPS`), and nothing was ever deleted automatically. The new rule (two passes, then quiet) keeps that promise.
- **School newsletters by email:** the AI turns a newsletter into short posts with dates. The child's name is masked as `{child}` before anything is sent to AI and put back on the phone. Flyers and PDFs are read too. Keep the prompt from `edition/src/ai.js` (`schoolPosts`).
- **AI cost limits:** per device per month (default $1), whole relay per day ($20), per network per day. App Attest is required, with an owner allow-list.
- **Privacy promises:** no account, no ads, no tracking, data on the phone, one-button delete. `edition/privacy.html` is the starting text.
- **Identifiers:** Team `7MHDTK68M2`; bundle `com.grahamdeno.shoebox`, `.share` and `.widget`; App Group `group.com.grahamdeno.shoebox`; Apple key ID `79QU7DSTN9`; site `inmyshoebox.com`; support `support@inmyshoebox.com`.
- **CI:** the old `.github/workflows/ios.yml` builds with XcodeGen on a cloud Mac and uploads to TestFlight with the App Store Connect key in secrets. Reuse that pattern.

Not carried over: the web app, the PWA, the feed of six, Shoebox Me's extra modules (morning cards, calendar day bar, song, top stories), weather, sports, quotes.

## 8. Keeping web and Android possible later

1. **Rules live in the spec, not only in Swift.** The return planner's rules are written in `docs/SPEC.md` with examples, so another client can follow them.
2. **Data is sync-ready from day one:** UUIDs, timestamps on every change, soft deletes, a documented export format.
3. **Design tokens live in one file** (`design/tokens.json`), generated into Swift. A web or Android build reads the same file.

## 9. Decisions made October 30 (were open)

All eight are settled. The results are also in section 4.

| # | Decision | Answer |
|---|---|---|
| 1 | Minimum iOS 26 or 17? | **iOS 26.** |
| 2 | Return planner AI: on device first, or relay first? | **On device first, relay fallback**, with plain rules ahead of both. |
| 3 | "At home": Focus only, or location too? | **Claude's call, as experience design:** no location in v1. A home-evening window set once (default 6:00 to 8:30 PM), sharpened by a Home Focus when there is one, and moved over time by when Graham actually answers. Reasoning in section 4. |
| 4 | New screenshots: Photos access or a Shortcut? | **Photos access limited to screenshots,** Shortcut as the no-permission path. |
| 5 | Shoebox Me: keep? | **Drop it.** |
| 6 | Beta page and `/beta`: keep for 2.0 TestFlight? | **Keep until launch, then remove.** |
| 7 | Submit old 1.0, or wait for 2.0? | **Submit 1.0.** Graham presses Submit. This adds two requirements, in section 11. |
| 8 | Primary palette: Midnight Gold, Plum and Peach, or both as a theme choice? | **Plum and Peach is primary,** with only the Sharpened idea. Midnight Gold stays in the design system as the alternate. |

New questions raised by the spec are listed at the end of `docs/SPEC.md` ("For Graham to check").

## 10. Build phases

Each phase ends with something Graham can try on his phone. The model named is the one to use for that phase.

| Phase | What | Model | Done when |
|---|---|---|---|
| 0 | **Spec.** Read the old repo; write `docs/SPEC.md`: data model, kinds, verdicts, the return planner's rules with 30 or more example reasons and the time each resolves to, the quiet rule, school parsing, privacy. | Opus | Graham has read it and said yes. |
| 1 | **Design system.** Tokens for both modes, type scale, spacing, corners, and components: notification, Live Activity, issue cover, Coming back row, capture sheet, buttons. Published as a Design System artifact and as `design/tokens.json`. | Opus | Graham approves the components. |
| 2 | **Foundation.** XcodeGen project, CI to TestFlight, relay moved into `relay/`, SwiftData store, import of the old backup, share extension with typed or spoken reason, the Everything kept list. | Sonnet | Graham's old saves are in the new app on his phone. |
| 3 | **It comes back.** The return planner (rules plus on-device model), local notifications with actions, the 7 AM issue, the Coming back screen, the quiet rule, Watch mirroring. | Sonnet builds; Opus reviews the planner | A week of Graham's real saves come back at sensible times. |
| 4 | **Everywhere.** Live Activity for calendar gaps, Action Button and Siri capture, Siri and Spotlight search, widgets. | Sonnet | Moments 3, 4 and 7 work on his phone. |
| 5 | **Smart saves.** Screenshot capture and flyer reading, school email posts, task lookups on the relay. | Opus designs the prompts; Sonnet builds | Moments 5 and 8 work. |
| 6 | **Ship 2.0.** Accessibility pass, App Store text and screenshots, privacy labels, review notes, TestFlight. | Opus reviews; Sonnet ships | Ready for Graham to press Submit for Review. |
| Later | Watch app, the issue read aloud (CarPlay audio), web or Android. | | |

### 10a. Where v1 stands (October 30, built on branch `phase-2-foundation`)

Built, compiled and tested on a GitHub macOS runner (Xcode 26) on every push. CI also takes screenshots of each screen and publishes them to the `ci-screens` branch.

| Phase | State |
|---|---|
| 2 Foundation | Done in code: XcodeGen project (same bundle ids as 1.0), CI, relay copied to `relay/` (not deployed from here), SwiftData store in the App Group, old-backup import (files, iCloud copy, then 1.0's web storage), share sheet with typed or spoken reason, Everything kept. TestFlight workflow is ready but needs the App Store Connect key in this repo's secrets. |
| 3 It comes back | Done in code: planner rules R1 to R22 (all 45 spec examples pass), on-device model hints, daily budget, quiet rule, Daily Issue with per-line answers, notifications with Done, Later, Drop, home evening that learns. Watch mirrors notifications on its own. |
| 4 Everywhere | Done in code: Live Activity before calendar events, Action Button and Siri (Keep, Find, Bring back), Spotlight, Home and Lock Screen widgets. |
| 5 Smart saves | Screenshots read on the phone; email in; school newsletters into posts (masked on the phone, relay AI with the carried-over sign-up). **Not done:** task lookups (moment 8) need a new relay route and a deploy; link filing (titles, summaries) by AI. |
| 6 Ship | Not started: accessibility pass, App Store text and screenshots, privacy labels, review notes. |

**TestFlight:** build 1004 (2.0) is Ready to Test in group "Me". A commit whose message contains `[testflight]` on this branch uploads a new build. The Issue view extension (`com.grahamdeno.shoebox.issue`) is left out until it has an App Store profile: Apple won't let an API key make one while the team's distribution certificate is cloud-managed. It joins builds on its own once the profile exists.

**Needs Graham, in this order:**
1. **Add `ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID` to this repo's Actions secrets** (the same values as `grahamdeno/edition`), then run Actions › TestFlight. It never submits for review.
2. Install the TestFlight build over 1.0 on his phone and check that his saves came over (phase 2 is done when they have).
3. Decide when the relay moves: one deploy from `relay/` and the old repo's relay workflow turned off. Moment 8 waits on this.
4. Submit for Review, when he says ship.

## 11. Loose ends in the old repo (`grahamdeno/edition`)

- **PR #166** (removes Quote of the day) is open and unmerged. Recommendation: close it without merging; the old app is frozen.
- **TestFlight build 36** (web 4.70.0, relay 26) is the current build. It stays installed until 2.0.
- **1.0 goes to App Review** (decision 7, changed October 30). **Graham presses Submit for Review; no agent does.** The listing text in `edition/docs/app-store.md` is used for 1.0 and rewritten for 2.0.
- **Because 1.0 ships, two things become requirements:**
  1. **2.0 must carry 1.0 saves over with no action from the person.** 1.0 already writes a daily backup to its own Documents › Backups folder (and iCloud Drive › Shoebox › Backups). 2.0 is an update to the same app, so on first launch it reads the newest backup there and imports it (`docs/SPEC.md`, section 11). A last-resort path reads the old web storage directly. Nothing is deleted.
  2. **inmyshoebox.com must keep serving the old web app while 1.0 is installed anywhere.** 1.0 loads `https://inmyshoebox.com/?native=1` live; if phase 6 replaces that page, every 1.0 install breaks. The 2.0 site goes beside it (new paths), and the old app is retired only after 2.0 has been out long enough.
- **The relay** keeps running from the old repo until phase 2 moves it here. Don't deploy it from two places at once. 1.0 still uses the routes this plan drops (`/push/*`, `/remind`, `/ical`, `/song`, `/ai/quotes`, `/ai/stories`), so they stay live until 1.0 is retired, even after 2.0 stops calling them.
- **inmyshoebox.com** (the welcome, privacy and support pages) gets rewritten for 2.0 in phase 6, without breaking the 1.0 app page (above).

## 12. How we work

The same rules are in `CLAUDE.md` for every session.

- **Graham picks the model for each step.** Opus for feel, data safety and judgment; Sonnet for building and shipping. At each handoff, say which model the next step needs.
- **Don't merge or ship until Graham says "ship".** He prefers one big release over several small ones.
- **Claude opens and merges pull requests itself.** Branch first and never commit to `main` directly after the first commit.
- **Graham presses Submit for Review himself.** Agents stop before it.
- **Crucial and irreversible steps** (submit, publish, delete, deploy) go first in any handoff and stand out.
- **Writing:** plain, direct, compressed. No em-dashes. No military metaphors in anything published.
- **Checks:** do the checks you can do yourself (run tests, open the build, read the page) instead of handing them to Graham.
