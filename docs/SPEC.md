# Shoebox: design spec

Written October 30, 2026, from the design sessions with Graham. This is the detailed behavior of Shoebox 2.0. `docs/PLAN.md` has the why, the architecture and the phases; where the two disagree, this file wins and PLAN.md gets fixed.

**Keep it. It comes back to you.**

App Store name: **Shoebox: Your Own Feed**. One app. There is no Shoebox Me (decided October 30 and confirmed again the same day).

## 1. What it is, in one breath

Shoebox is your own feed, made of the things you meant to come back to. They live scattered across email, notes, texts and open tabs. You keep something once, with your reason. Each morning a few come out of the box. You swipe past (it comes back tomorrow), put it away until a better time, or open it and call it done. You use it once a day as an idle scroll, and the goal is a clear feed, not a finished list.

What Graham said matters most: things coming to him and getting handled or put away. Seamless, easy choices, clear actions and results. Each step makes sense without explanation.

## 2. The screens

The pictures are in `docs/design/screens/` and on the "Shoebox 2.0 screens" design canvas.

| # | Screen | Picture |
|---|---|---|
| 1 | Today, a photo post, the lid at rest | `01-main.png` |
| 2 | Today, a dated text post | `02-todaytext.png` |
| 3 | Tap the lid: the Later list | `03-lidopen.png` |
| 4 | Flick out of the lid: the opened post | `04-opened.png` |
| 5 | Box | `05-box.png` |
| 6 | + Keep something | `06-add.png` |
| 7 | Today's clear | `07-clear.png` |
| 8 | Today in dark mode | `08-dark.png` |
| 9 | First run: the three moves | `09-learn.png` |
| 10 | It comes to you (the notification) | `10-lock.png` |
| 11 | Design system | `11-system.png` |

### 2.1 Today

The whole app, almost. Full screen, one post per screen, like Scales. No stack of cards, no list, no second sort screen.

- **Top bar, all words:** Box (left), "5 left today" (plain information, not a button), + (right).
- **A post:** a byline ("You, 2 weeks ago, from Safari"), your reason as a Nectarine-tint highlight, the headline, and a short snippet. A photo sits above when the post has a good one, 300 pt tall with 18 pt corners. Text posts (emails, notes) are type only, with a larger headline set lower on the screen.
- **Dated posts** add one line: "Comes back Nov 7, Nov 11 and Nov 12 on its own".
- **Bottom left:** "Swipe up for the next one", in quiet text.
- **Bottom right:** the box top (section 2.2).
- **Lots of white space.** No avatars, no badges, no icons.

### 2.2 The box top

The brand made into a control: a Nectarine lid (`#FFBD76`) with an Oceanic lip (a 9 pt band along its top edge), the same lid as the app icon. It is the one colored control on screen.

- **At rest:** about 128 by 92 pt, in the bottom-right thumb corner, 20 pt from the edge, with one word: **Later**. It is only slightly smaller than its open size.
- **Tap it:** it grows up from the corner into the Later list:
  - "Bring it back" heading
  - the suggestion, highlighted `#FFDBB4`, with its reason ("Suggested, it's a weekend trip")
  - This weekend
  - Next week
  - Pick a date
  - Let go and Close, set apart at the bottom
- **Flick out of it** (drag more than 40 pt): the post opens full screen.

### 2.3 The opened post

- The photo runs edge to edge at the top, with Close top left.
- Then the byline, headline, your reason, "Open the page on example.com", and the full text with links tappable.
- **The strip:** the lid comes with the post and becomes a full-width Nectarine strip along the bottom, with **Later** on the left and **Done** on the right. Later raises the same list from the strip.
- Done appears only here. Opening a post is dealing with it.

### 2.4 Box

- The top has "Today" on the left and "Settings" on the right, then a large "Box" title, then search ("Search everything you kept").
- Below that, "Tap anything to bring it back to Today now."
- Put-away posts are grouped by when they come back: Tomorrow, This weekend, a weekday, or a date such as Nov 7. Kept (done) posts follow, dimmed.
- Search covers the headline, reason, snippet, full text and link.
- Tap a post and it comes back to Today, first in line.

### 2.5 + Keep something

- A sheet with two fields: "Link or note" ("Paste a link or write a note") and "Why are you keeping it? (optional)" ("Before the trip").
- "Keep a photo instead" opens Photos.
- Cancel on the left, the lid as a Keep button on the right.
- The note under the fields: "Your why decides when it comes back. Say nothing and it comes back tomorrow."
- Several links pasted together become several saves. A link that's already kept isn't kept twice.

### 2.6 Today's clear

The box mark (an Oceanic box, the Nectarine lid ajar), then "Today's clear." and "6 things are waiting in the Box. The next ones come out tomorrow."

With nothing kept yet, it says "Nothing kept yet." and how to start: share a page from Safari or any app, or tap +.

### 2.7 First run

One idea per screen, one clear choice, the lid as the button in the thumb corner. Graham loved the old onboarding because it was seamless: easy choices, clear actions and clear results. Keep it that way.

1. **Welcome.** The box mark, "Keep it. It comes back to you.", one line on how it works. If Shoebox 1's saves were found, it says so in a Nectarine tint ("214 saves and your email address came over from Shoebox 1."). Lid: Start.
2. **Save from anywhere.** Three numbered steps (Tap Share, Tap Shoebox, Say why and tap Keep), then "Or forward email". It shows your Shoebox address, or a first-name field and "Get my address". Skip on the left, lid: Next.
3. **When should they come out?** A time wheel and one line about the single daily notification. Not now on the left, lid: Turn on (asks for notification permission).
4. **Three moves. That's the whole app.** Swipe up; Tap the lid; Flick out of the lid. The lid pulses where it will be, labeled "Try it", and it lands on Today.

Settings has "Show the three moves again".

### 2.8 Settings

Reached from Box. Everything is words, nothing is a pill.

- **Each day:** how many come out (3, 5 or 8; default 5); the notification time (default 7:30 AM); notifications on or off.
- **Your Shoebox email:** the address and Copy, or "Get my address" from your first name.
- **Backups:** Bring in a backup (a Shoebox 1 file or one of this app's own); Save a backup now; when the last automatic copy was made.
- **Help:** Show the three moves again; how to put Shoebox in the share row.
- **Privacy:** what stays on the phone and what passes through the relay.
- **Everything:** Delete everything. Two steps, because it's the one thing that can't be undone. A final backup is written to Files first.
- The version and build number.

### 2.9 The notification

One a day, at the time you chose: "5 came out of the box", with the body "Picture day forms are due this week, plus 4 more." Tapping it opens Today on the first post.

Later: Later and Open as long-press actions, and a Lock Screen widget.

## 3. The rules

1. **Today is a daily pick.**
   - Everything coming back always comes out: posts put away until now, and dated steps.
   - The rest of the pile fills up to the daily number (default 5).
   - Posts you passed before go first, so "back tomorrow" means back tomorrow. After them come the oldest never seen.
   - The pick holds for the day, so the count only goes down. Bringing something back from the Box puts it first.
2. **Swipe up = seen.** It's gone until tomorrow. There is no quiet rule: a post you keep passing keeps coming back.
3. **Later** puts it away until the chosen time. The suggestion comes from your reason (section 3.1). A Later choice never asks to confirm; Undo is always there.
4. **Done** (opened posts only) keeps it in the Box under Kept, searchable.
5. **Let go** removes it (soft delete), with Undo.
6. **Every action is instant, with Undo for 4 seconds.** No confirm dialogs, except Delete everything.
7. **Dated posts** come back on their own 5 days before, 1 day before and on the day, at 8 AM. Passing one moves it to its next step. After the day itself, it goes to Kept.
8. **A new save** goes into the box and comes back when its reason says, or tomorrow at 8 AM when no reason is given.
9. **Never delete on its own.** Shoebox never removes a save without you saying so.

### 3.1 Reasons to times (plain rules, on the phone)

| Words in your reason | Comes back |
|---|---|
| weekend | Saturday 9 AM |
| tonight, dinner, evening | today 6 PM, or tomorrow 6 PM if that's past |
| tomorrow | tomorrow 8 AM |
| a weekday ("Monday") | that day 8 AM |
| before a weekday ("before Monday") | the evening before, 6 PM |
| nothing that names a time | Later list suggests Next week (Monday 8 AM); a new save comes back tomorrow 8 AM |

Next: the Core package's richer planner (`Core/Sources/ShoeboxCore/Planner`, rules R1 to R20, plus Foundation Models on device) takes over from these plain rules.

## 4. Getting things in

| Way | How |
|---|---|
| Share sheet | Safari or any app: Share, then Shoebox. Shows what was found (title, site, picture), "Why are you keeping it?", Cancel and Keep. Reads the page while you type. Pages, links, text and up to 10 photos. |
| + | Link, note or photo, with a reason (section 2.5). |
| Email | Forward to your Shoebox address. Each email is one post; your words above the forward are the reason. Ads are skipped (USPS Informed Delivery included) unless you wrote a note. A date in the email makes it a dated post. The same email twice is kept once. Mail waits on the relay up to 30 days. |
| Shoebox 1 | On first run, the newest Shoebox 1 backup (`shoebox-backup-*.json` in Files or iCloud Drive, Shoebox › Backups) is brought in. Importing twice adds nothing. Done stays done, let go stays gone, and a future return date is kept. The email address and its key come over too. |
| Backups | Settings › Bring in a backup takes any Shoebox 1 or 2 file. |

**Link previews.** The relay reads the page and returns its title, description, best picture and readable text. The picture is shrunk to 1200 px and kept on the phone. Your own words are never replaced. Previews are fetched when you keep something, and for the posts coming up on Today.

## 5. Look

### 5.1 Onyx, Wheat, Oceanic, Nectarine

| Job | Light | Dark |
|---|---|---|
| Surface | Wheat `#FFF6E9` | Oceanic `#003F47` (never black) |
| Sheet | `#FFFCF7` | `#144E54` |
| Text | Onyx `#0A171D` | Wheat `#FFF6E9` |
| Quiet (dates, sources) | `#5A6B6E` | `#B8C4BF` |
| Lines | `#EADFCC` | `#295C61` |
| Your reason | pale Nectarine `#FFD7AA`, text Onyx | Nectarine at 30%, text `#FFE2BD` |
| Box top | Nectarine `#FFBD76`, text Onyx, suggestion `#FFDBB4` | same |
| Box top lip | Oceanic `#003F47` | Onyx `#0A171D` |
| Logo box | Oceanic `#003F47` | lighter Oceanic `#2F7E88` |

Each color has one job:
- Wheat is the ground, Onyx is the text.
- The pale Nectarine tint is your own words, and nothing else.
- Oceanic is the box in the logo, the lid lip, and the dark ground.
- Nectarine is the box top: put away, open, done.

### 5.2 Type and shape

- SF Pro throughout.
- Headline 30 pt semibold on photo posts, 38 pt on text posts, tracking about -0.7.
- Snippet 17 pt, quiet. Byline 14 pt, quiet.
- Photo corners 18 pt; sheets 24 pt top corners; the lid 18 pt.
- Touch targets at least 44 pt.
- Actions are words: never pills, never icon-only buttons.

### 5.3 App icon

Shoebox 1's layered Liquid Glass icon (`App/Shoebox/AppIcon.icon`: lid, box and cards), recolored:

| Layer | Light | Dark |
|---|---|---|
| Ground | Wheat `#FFF6E9` | Oceanic `#003F47` |
| Box | Oceanic `#003F47` | lighter Oceanic `#2F7E88` |
| Cards | `#5A6B6E` | `#B8C4BF` |
| Lid | Nectarine `#FFBD76` | Nectarine `#FFBD76` |

Fine-tune it in Icon Composer on a Mac.

### 5.4 Retired

The Daily Issue, Midnight Gold, Plum and Peach, the Timeline layout, the stack of cards, and a separate sort screen. The files in `docs/design/` other than `screens/` are history only.

## 6. Data and safety

- **One store.** SwiftData in the App Group `group.com.grahamdeno.shoebox`, shared by the app and the share sheet. CloudKit sync is off.
- **Sync-ready.** Every save has a UUID, created and updated times, and a soft-delete marker.
- **Daily automatic backup.** Once a day, the whole store is written as JSON (photos included) to Files and to iCloud Drive (Shoebox › Backups). The last 7 are kept. Shoebox 1's backups are never touched.
- **Privacy.** No account, no ads, no tracking. Saves stay on the phone. Link previews and email pass through the relay (`https://shoebox-api.tangomike.app`) and aren't kept there once collected.

## 7. Not built yet, in order

1. Home Screen and Lock Screen widgets.
2. Later and Open on the notification itself.
3. School newsletters turned into short dated posts by AI, with the child's name masked as `{child}` (Core `NameMask` is ready).
4. The richer return planner: Core rules R1 to R20 plus Foundation Models, and "before the meeting" from the calendar.
5. Siri and Shortcuts: Keep, Find, Bring back.
6. Screenshots as saves.
7. Deep links (`shoebox://`).
8. Moving the relay into this repo.

## 8. How we work

- **The model for each step.** Graham picks it: Opus for feel, data safety and judgment; Sonnet for building and shipping. Name the next step's model at every handoff.
- **Shipping.** Don't merge or ship until Graham says "ship". Claude opens and merges pull requests itself, on branches, never on `main`.
- **Submit for Review.** Graham presses it. TestFlight uploads are fine once he has said ship. Push `main` to the `testflight` branch; build numbers are 1000 plus the run number.
- **Irreversible steps.** Submit, publish, delete and deploy go first in any handoff and stand out.
- **Writing.** Plain and compact. No em-dashes. No military metaphors in published text.
- **Checks.** Do the ones you can yourself. CI screenshots: put `[screens]` in a commit message on a branch, then read the `ci-screens` branch.
