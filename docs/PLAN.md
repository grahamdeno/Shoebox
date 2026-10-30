# Shoebox: the plan

Written October 30, 2026. This is the brief for every build step. Read it before doing anything in this repo. When a decision here changes, change it here first.

## 1. What Shoebox is

**Keep it. It comes back to you.**

People save things everywhere (a link, a screenshot, a school flyer, a note) and mean to come back to them. They rarely do, because coming back is the hard part. Every read-later app asks you to open it and work a list. Shoebox doesn't.

You save something once, with your reason ("Drive it next fall", "Show the kids at dinner"). Shoebox reads the reason, decides when the save will be useful, and brings it back at that moment, wherever you already are: the Lock Screen, a notification, the car, the Watch, Siri. You answer with one touch. Most days you never open the app.

The old app (repo `grahamdeno/edition`, a web app in an iPhone wrapper) proved the core idea: saves with reasons, coming back a few at a time, three verdicts. This repo is a native rebuild around the better version of that idea.

## 2. The rules

These decide every design and engineering question. If a feature breaks one, the feature changes.

1. **Your reason decides when it comes back.** "Before we plan next quarter" means the gap before that meeting. "This weekend" means Saturday morning. "At dinner" means the evening at home. Dated saves (school emails, events) come back on their own: 5 days before, 1 day before, and on the day.
2. **One post at a time.** The app is one full-screen feed called Today, one post per screen, like Scales. No second "sort" screen.
3. **Moving on is a decision.** Swiping up past a post is the soft pass: it comes back tomorrow. Nothing to tap.
4. **Two words, nothing more.** Each post offers only Done and Later. Later accepts a suggested date in one tap; Pick a date and Let go live inside Later. Every action is instant with Undo; nothing asks to confirm.
5. **Answer without unlocking.** Notifications carry the same two words: Done and Later.
6. **Shoebox prepares; you decide.** It can look things up, fill in dates and draft a reminder. It never books, pays, sends or deletes on its own.

## 3. Version 1: the ten moments

From the storyboard (`docs/design/storyboard.html`, Midnight Gold). Each is a v1 requirement unless marked later.

| # | Moment | When | iOS feature | Phase |
|---|---|---|---|---|
| 1 | Today: one notification at your chosen time ("5 came out of the box") opens straight into the feed | Your time | Notification | 3 |
| 2 | The issue read aloud in the car | Commute | Audio, Siri | Later |
| 3 | The reason finds a time: the gap before a matching calendar event | 9:48 AM | Live Activity, EventKit (read) | 4 |
| 4 | Capture: hold the Action Button on any page, say why | Any time | App Intent, speech | 4 (share sheet with voice in 2) |
| 5 | A screenshot is a save: the flyer is read, the reminder set | 3:10 PM | Photos (new screenshots), on-device text reading | 5 |
| 6 | "At dinner" means dinner: comes back at home in the evening | 6:10 PM | Notification, Focus filter | 3 |
| 7 | Search by asking Siri, answered in your own words | Any time | App Intents, Spotlight | 4 |
| 8 | A task comes back with the work done ("Book the campsite": open dates, a prefilled link) | Friday | Relay web lookup | 5 |
| 9 | A weekend save on the weekend, on the wrist | Saturday | Notifications mirrored to Watch (a Watch app is later) | 3 |
| 10 | The app: Today (the feed) and Box (put away by date, plus Kept and search) | Any time | The app itself | 3 |

## 4. Decisions made

| Decision | Choice | Why |
|---|---|---|
| Platform | Native iPhone (SwiftUI) only | Lock Screen, Live Activities, Siri, Action Button and on-device AI are native-only. |
| PWA, web, Android | Not now | Can come later. See section 8 for what keeps that cheap. |
| Repo | New repo, `Shoebox` | Clean structure around "a save is a moment". The old repo becomes the archive. |
| App Store | Same record and bundle ID (`com.grahamdeno.shoebox`); this ships as version 2.0 | Keeps the name and listing. Never create a new app record. |
| Old 1.0 | Don't submit it | Recommended; Graham to confirm. TestFlight build 36 stays for his own use until 2.0. |
| Relay | Carry over the Cloudflare Worker | Link previews, email in, AI with App Attest and cost limits all work and are tested. |
| Data | On the phone, ready to sync later | Privacy promise stays. Sync becomes a feature, not a rewrite. |
| Palette | Peach and slate, light by default, dark follows the system | Chosen October 30, replacing Midnight Gold and Plum and Peach. Section 5. |
| Type | SF Pro (system) throughout | Chosen October 30. Native, nothing to bundle. |
| Names | Today (the feed) and Box (put away, kept, search) | Chosen October 30. |
| Actions | Words, not pills or icon-only buttons: Done, Later | Same rule as Scales. Every control on screen is a labeled word. |
| Accent | One accent element per screen: Done | The accent means "act". No decorative accent. |

## 5. Design: Today, Box, Peach and slate

Decided October 30 after an interview with Graham. The Daily Issue, Midnight Gold and Plum and Peach directions are retired; their files in `docs/design/` are history only.

### 5.1 Today (the whole app, almost)

- Full screen, one post per screen. Swipe up for the next post.
- A post shows: a photo when it has a good one, the headline, a short snippet, and your note as a peach highlight. Lots of white space. No avatar, no badges.
- Text posts (emails, notes, dates) are type only: a large headline, a snippet, and "Comes back Nov 7 on its own" when dated.
- Tap the post to open it in an in-app reader. Closing the reader returns to the same post.
- Bottom of the screen: **Later** on the left, **Done** on the right (accent). Nothing else.
- Top of the screen, all words: **Box** (left), "3 left today" (plain information, not a button), **+** (right).
- When Today is empty: a short finish moment, then the screen rests.

### 5.2 The four outcomes

| You | What happens |
|---|---|
| Swipe up | Soft pass. Back tomorrow. |
| Done | Kept in the archive, searchable. Leaves Today. |
| Later | Sheet: one suggested date (tap to accept), Pick a date, Let go. |
| Let go (inside Later) | Removed, with Undo. |

### 5.3 Box

Put-away posts grouped by when they come back (Tomorrow, This weekend, Nov 12), then Kept, then search.

### 5.4 Peach and slate

| Job | Light | Dark |
|---|---|---|
| Surface | `#FFF8F3` | slate `#36445E` |
| Sheet | `#FFFFFF` | `#43526E` |
| Text | `#1E2A3D` | `#F6EEE8` |
| Quiet (dates, sources) | `#7A8292` | `#B7C0CF` |
| Lines | `#EEDFD5` | `#4A5975` |
| The one action (Done) | slate `#33415C` | peach `#FFB38A` |
| Your note highlight | peach `#FFC4A3`, text `#1E2A3D` | peach at 30%, text `#FFE0CC` |

Dark mode is a clear slate blue, never black. Type is SF Pro. Photos have 14 px corners; sheets 20 px top corners.

## 6. Architecture

**App targets**
- `Shoebox` (SwiftUI app): Coming back, everything kept, settings, onboarding.
- `Share` extension: save from any app; type or speak the reason.
- `Widgets`: Home Screen and Lock Screen widgets, plus the Live Activity.
- App Intents (in the app target): Action Button capture, Siri questions, Shortcuts, Spotlight.
- Later: a Watch app; CarPlay audio (needs Apple's audio entitlement).

**Minimum iOS:** 26. That gives Foundation Models (on-device AI), current Live Activities and App Intents. Devices without Apple Intelligence fall back to the relay's AI. Open decision 1 in section 9.

**Storage:** SwiftData in the shared App Group (`group.com.grahamdeno.shoebox`), so the app, share extension and widgets read one store. Files and photos live as files in the group container.
- Every record has a UUID, `createdAt`, `updatedAt`, and a soft-delete marker. This makes sync possible later without a migration.
- Export and import as JSON with files alongside. The importer also reads the old app's backup (version 2: items, meta, settings, files as base64).

**The return planner** (the heart of the app):
- Input: the save, its reason, its kind, and context (calendar events, Focus, time of day, how long it takes).
- Output: one `nextMoment` (a time window, a place or Focus condition, and the surface to use), or "quiet".
- First pass is on device: Foundation Models with structured output turns the reason into a when (date words, weekday words, "before X", "at dinner", "this weekend", "next fall"). Plain rules cover common phrases without AI. The relay's AI is the fallback.
- Delivery is local. Local notifications and Live Activities are scheduled on the phone. The relay is not needed for reminders, so the old web-push routes go away.
- Each save is offered once at its moment. Ignoring it (no answer within the window) counts as a pass. After two passes it goes quiet.

**Outcomes:** swipe up (back tomorrow), Done, Later (suggested date, Pick a date, or Let go). See section 5.2.

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
| `/beta` | Decide at launch (open decision 6) |

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

## 9. Open decisions

| # | Decision | Recommendation |
|---|---|---|
| 1 | Minimum iOS 26 (on-device AI) or 17 (wider reach)? | iOS 26. By launch most active iPhones will run it; the relay covers devices without Apple Intelligence. |
| 2 | AI for the return planner: on device first, or relay first? | On device first, relay fallback. More private and free per call. |
| 3 | "At home": Focus only, or location too? | Focus only in v1. No location permission. |
| 4 | Reading new screenshots: Photos access, or a Shortcut automation? | Ask for Photos access limited to screenshots; offer the Shortcut as the no-permission path. |
| 5 | Shoebox Me (Graham's private variant): keep? | Drop it. One app; Graham uses the real one. |
| 6 | Beta sign-up page and `/beta`: keep for 2.0 TestFlight? | Keep until launch, then remove. |
| 7 | Submit old 1.0, or wait for 2.0? | Wait for 2.0. |
| 8 | ~~Primary palette~~ | Decided October 30: Peach and slate. |
| 9 | Quiet rule: a post swiped past every day comes back every day. Should it go quiet after some number of passes? | Ask Graham. A cap (for example 5 passes, then it waits in Box) keeps Today from filling with things he keeps skipping. |

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

## 11. Loose ends in the old repo (`grahamdeno/edition`)

- **PR #166** (removes Quote of the day) is open and unmerged. Recommendation: close it without merging; the old app is frozen.
- **TestFlight build 36** (web 4.70.0, relay 26) is the current build. It stays installed until 2.0.
- **Do not submit 1.0** (decision 7). The App Store listing text in `edition/docs/app-store.md` gets rewritten for 2.0.
- **The relay** keeps running from the old repo until phase 2 moves it here. Don't deploy it from two places at once.
- **inmyshoebox.com** (the welcome, privacy and support pages) gets rewritten for 2.0 in phase 6.

## 12. How we work

The same rules are in `CLAUDE.md` for every session.

- **Graham picks the model for each step.** Opus for feel, data safety and judgment; Sonnet for building and shipping. At each handoff, say which model the next step needs.
- **Don't merge or ship until Graham says "ship".** He prefers one big release over several small ones.
- **Claude opens and merges pull requests itself.** Branch first and never commit to `main` directly after the first commit.
- **Graham presses Submit for Review himself.** Agents stop before it.
- **Crucial and irreversible steps** (submit, publish, delete, deploy) go first in any handoff and stand out.
- **Writing:** plain, direct, compressed. No em-dashes. No military metaphors in anything published.
- **Checks:** do the checks you can do yourself (run tests, open the build, read the page) instead of handing them to Graham.
