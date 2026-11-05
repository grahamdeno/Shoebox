# Shoebox: design spec

Written October 30, 2026, from the design sessions with Graham. This is the detailed behavior of Shoebox 2.0. `docs/PLAN.md` has the why, the architecture and the phases; where the two disagree, this file wins and PLAN.md gets fixed.

**Keep it. It comes back to you.**

App Store name: **Shoebox: Your Own Feed**, subtitle "Keep it. Come back to it." It ships as **version 1.0** on the existing App Store record (`com.grahamdeno.shoebox`); no new record. One app. There is no Shoebox Me (decided October 30 and confirmed again the same day).

## 1. What it is, in one breath

Shoebox is your own feed, made of the things you meant to come back to. They live scattered across email, notes, texts and open tabs. You keep something once, with your reason. Each morning what's due comes out of the box. You flick it up (it comes back when your reason says, or tomorrow), pull it down to put it away (done, kept and searchable), or tap it to open it. You use it once a day as an idle scroll, and the goal is a clear feed, not a finished list.

What Graham said matters most: things coming to him and getting handled or put away. Seamless, easy choices, clear actions and results. Each step makes sense without explanation.

## 2. The screens

Updated October 31, 2026 for the stack (PR #11 and #12). The moves are copied from Scales. Current pictures come from the CI screenshot run (`[screens]`, then the `ci-screens` branch); the files in `docs/design/screens/` show the earlier bar design and are history.

### 2.1 Today

Full screen, one post per screen. No list, no second sort screen, no tab bar.

- **A post:** the photo fills the whole screen, graded (section 5.3). The words sit low on one Liquid Glass panel: your reason in Sunflower, the headline (30 pt bold, 34 pt with no photo), a short snippet, a "Comes back ..." line for dated posts, and the byline ("You, 2 weeks ago, from Safari").
- **No photo:** a stock picture is found for it (section 4.1). Until then, or when none is found, Plum lit warm from the top corner with a Sunflower glow.
- **Dated posts:** one line under the words, "Oct 30 at 4:00 PM. Back Oct 25, Oct 29 and Oct 30."
- **Top left:** "+ New" opens Keep something. On the day's end screen it sits low on the right instead, just above the box, under the right thumb.
- **Your Shoebox** across the bottom (section 2.2).

**The moves (Scales'):**

| Move | What happens |
|---|---|
| Flick up past 100 pt | Next. The post comes back when your reason says, or tomorrow. The box rattles lightly. |
| Pull down past 160 pt | Put away: done, kept and searchable. The lid tips open as you cross; let go and it drops in with a heavy knock and a strong rattle. |
| Quick tap (under 0.35 s) | Opens the post full screen. |

The post follows the finger 1:1 for 40 pt, then at half speed, and springs back if you let go short. A tick at each threshold. Every move has Undo for 5 seconds.

### 2.2 Your Shoebox (the bottom box)

Agreed November 4, 2026 (mock: the "Shoebox box: six glass directions" canvas, board "2 · Working: flick up, pull down"; copies in `docs/design/glass/`). Not a band across the bottom: the post runs to the bottom edge, Plum glass rises into it from below, and the lid is the one solid object on the screen.

- **The glass.** The lower 150 pt of the screen, ending just above the lid and clear of the post's panel, blurs the post and tints it Plum (lighter Plum `#6A4F73` in dark): clear at the top, nearly solid at the bottom edge, so the post's panel sits partly in its glow. No edge, no outline.
- **The lid.** Sunflower, 44 pt tall, 12 pt in from each screen edge, 8 pt corners, resting canted 2° up to the right on a hinge at its left end, like the logo. A lighter top face (the upper 56%) over a deeper lip (`#D4A21E`) and a 1 pt highlight along the top. One smooth shape: no side flaps or end pieces. It casts a soft plum-shade shadow down onto the glass. No glow at rest. The faces and highlight are separate smooth shapes, so a tilted lid never shows stair-step lines.
- Bare: the count of posts not put away at the right, just under the lid, and "Let go to put it away" in Sunflower at the left while a post is pulled down past the threshold.
- Pulling a post down leans the lid 1.5° further open once it has moved 40 pt. Past the threshold it tips 5° further and glows Sunflower, and the words appear. Let go and the post drops in, shrinking toward the lid.
- After a flick up, the next post rises out of the lid.
- Flicking a post up or dropping one in makes the lid and glass shake, with a rustling haptic: quick knocks that spread out and fade over a low rumble (light for a flick, strong for a drop).
- Pull the lid up, or tap it, and the Shoebox (2.4) rises from under it at the pace of your thumb (not on release); the lid lifts with it. Let go and it settles open or closed by where it is and how fast you were going.
- Retired: the full-width Sunflower band, the Plum slab, the hinge post, the side flaps.

### 2.3 The opened post

- The photo fills the screen, darker than on Today (a little over all of it, more behind the words), and stays still while the words scroll over it.
- **Close** sits top left and **Edit** top right, both words on Liquid Glass.
- Your reason, the link, then the full text, each on glass.
- A glass strip along the bottom: **Next** (same as flick up) and **Put away** (same as pull down). A put away post has one word instead: **Bring back**.

#### Edit

- Opens on the same surface as Keep something (section 2.5): the post itself, with **Close** and **Keep** at the top and one glass panel holding the title (large), your notes, the why, and the return line.
- It saves on its own a moment after you stop typing and again when you leave. **Keep** saves, taps a haptic and the line under the title says "Saved".
- A Date line holds the date it is about: Add a date, or the date with Add a time and Clear date. With a date, it says it comes back 5 days before and stays until put away. New words that name a date are read, unless you cleared one yourself.
- **Delete** is the last word, bottom left of the panel, in thumb reach. One tap closes the post and shows Undo for 5 seconds. A delete is soft: the post is hidden from every list and stays in backups.

### 2.4 Shoebox (the library)

- **Opens under the lid.** The sheet is Plum glass over the blurred Today post. The open lid sits along its top edge, lying level (no cant) along its top edge, where a grab handle would be; pull it down to close the Shoebox, or tap Today.
- "Today" on the left and "Settings" on the right, then a large "Shoebox" title.
- **Search is at the bottom**, under the thumb: a glass field, no outline, "Search everything", filtering as you type.
- The list is everything you are not done with, in two calm sections with one row shape (a date, or a small picture when the post has one; the words, up to two lines and never cut off with "…"; one quiet line of where it came from). When you wrote a reason, the reason leads and the title moves to the quiet line.
  - **Coming up:** posts dated in the next two months, soonest first, with the date block at the left. A day within the next 7 days has its number in Sunflower. Posts dated later sit in Everything else until they are within two months.
  - **Everything else:** newest first, with the post's picture as a small tile. A post without a picture has no tile: never an empty or colored square.
- The last row, **Go through them one at a time**, closes the Shoebox and brings the posts out on Today with the same moves.
- One word at the top right, **Put away (41)**, shows only what you are done with, newest first. The title becomes "Put away" and the word becomes **Shoebox**. It does not show when nothing is put away.
- **Put away is by topic**, like Scales' Insights (rules on the phone, `Tidy.topics` in ShoeboxCore; nothing kept is changed). Each topic is one row, closed until tapped: its count large on the left, its name, and its newest post in one quiet line. The topics are School, Sports, Food, Travel, Home & money, Shopping, Work, Apps, Watch, Reading, and Something else last; the largest first, newest first inside. An email is read for its topic by its words too, so a newsletter goes where its news is. Anything the rules can't place is Something else. The same title shows once. No folds. Searching shows a plain list. Rows look as in the Shoebox.
- **Repeats are not made.** Mail that would make a post with the same title and the same opening words as an email post from the last two weeks makes nothing.
- **Titles that say nothing are shown as something** in every list and on posts: a bare link, "Id1120837655", the site's name or "A photo" become the post's first sentence, then (in lists) your reason, then a plain name ("Instagram reel", "An app on the App Store", "Link from example.org"). A link whose kept title is one of these takes the page's title when its preview arrives.
- Search covers the headline, reason, snippet, full text and link, and always looks everywhere. Put away posts that match appear under their own "Put away" heading.
- Tap a post to open it. Everything else (Next, Put away, Bring back, Edit, Delete) is on the opened post, so each is learned once.
- The count on the box at the bottom of Today is the posts in this list.

### 2.5 Writing on the post: Keep something, the share sheet, and Edit

Every screen where you write is the post you are making. What you see while you write is what comes back. Agreed November 2, 2026 (mock: the "Shoebox Keep screen" canvas); it replaces the Scales-style form.

- **The ground is the post.** Its photo, full-bleed and graded as on Today, or Plum lit warm with Sunflower. The same in light and dark, as posts are.
- **Top:** **Cancel** (**Close** in Edit) at the left and **Keep** at the right, words on Liquid Glass as on the opened post. Keep is quiet until there is something to keep, then Sunflower.
- **One Liquid Glass panel** holds everything, in this order:
  1. The words, large. One field: "Paste a link or write a note". No screen title; the placeholder says it.
  2. **Why**, one line, shown once there are words. Your why is Sunflower.
  3. A bottom row: **Photo or file** at the left, the return line at the right.
- **The return line** says when it comes back and changes as you type: "Back tomorrow", "Back Saturday", "Back Nov 9 · 5 days before". Tap it for one small screen of choices as words: Tomorrow, This weekend, Next week, Pick a day; for a dated save also its date, Add a time and Clear. It replaces "Start showing it on" and the paragraph about the why.
- **Photo or file** opens the standard menu: Photo Library, Take Photo (the system camera), Choose File. A photo becomes the ground and Photo or file becomes **Remove photo**. A file shows as one line in the panel with **Remove**.
- **The panel rides the keyboard.** With the keyboard down it sits at the bottom in thumb reach. One swipe down closes the screen.
- **Read on the phone.** After a photo, the phone suggests the words and the why: Vision reads the text in it, Apple Intelligence writes a short title, the details and the why (refused if it holds a number or day word the photo does not), and the date reader finds the date in those words. Suggestions show lighter under one line, "Read from the photo. Tap to change." Typing makes them yours and solid. Keep keeps what is shown; nothing is kept on its own. Nothing leaves the phone for this. Without Apple Intelligence the first line is the title and the next lines the details; a photo with no readable text stays "A photo". A suggested why is used only when most of its words are in the photo, and "not stated" claims, half-read first words and anything that reads like an instruction are dropped. Files and links are read after they are kept, as before (the page's title and picture, a file's text, dates in the words).
- **The share sheet** is the same surface: the page's picture is the ground, the page's title is the words once read, and your own words go under it ("Add a note").
- Several links pasted together become several saves. A link that's already kept isn't kept twice.

### 2.6 Today's clear

At the top: the app logo, **Shoebox** and "Keep it. It comes back to you." Then "That's N for today." or "That's all for today." When posts remain in the Shoebox, one row: **Go through your Shoebox**. It brings the rest out one at a time, soonest first, each once, with Today's moves; when they are done the screen returns. When nothing remains it says when the next one comes back. With nothing kept yet, Today shows one welcome post on the same full-screen card as any post: "Pull me down to put me away. Flick up to see the next one." It teaches the moves by doing them once and is gone after either move. No "Keep something" row (+ New is low on the right).

### 2.7 First run

One idea per screen, one clear choice. The words sit along the bottom on the ground, a quiet word on the left and the action on the right, with no bar behind them.

1. **Welcome.** The app logo, "Keep it. It comes back to you.", one line on how it works. If Shoebox 1's saves were found, it says so in a Pistachio tint. Start.
2. **Save from anywhere.** Three numbered steps for the share sheet. Skip, Next. (The email address is not offered here; it comes with Shoebox Plus, offered after the first week.)
3. **When should they come out?** A time wheel and one line about the daily notification. Not now, Turn on.
4. **Three moves. That's the whole app.** Swipe up: Next, it comes back when your why says, or tomorrow. Pull down: Put it away, done, kept, and search finds it. Tap it: Open it, Edit is there too.

Settings › How Shoebox works shows the moves again.

### 2.8 Settings

Reached from Today and the Box. Laid out like Scales' Settings: a few short groups, each under a small quiet title. The sheet is the same glass as the Shoebox (2.4) over the blurred Today post; the groups are glass cards (a faint Bone fill in dark, a faint Plum Ink fill in light, a 1 pt highlight along the top), no outline. No lid here: the lid appears only where the box is. Each row shows its answer on the right. At most one quiet line under a group. A row opens one small screen: a title, its question, the choices as words.

- **Your day:** Each day (How many: 5, 10 or All, default 10; Remind me: the time or Off), Look (Automatic, Light or Dark; then Colors: Pistachio, the default, or Stone; the share sheet follows both), Pictures (On or Off).
- **Email** (when Plus is offered, section 9): Your Shoebox address. Under it: "Forward an email to keep it. Only your phone can read it." The screen has the address and Copy, or a first name and Get address, and "Who it's about".
- **Back up:** Backups, answered **Automatic**, with one line saying when and where the last copy went. The screen says there is nothing to do (a copy once a day, the last 7 kept), then Back up now (Save a file) and Restore from a backup (Choose a file; only adds, takes any Shoebox 1 or 2 file).
- **Help and about:** How Shoebox works (each move as a small looping picture, then how your reason sets when a post comes back), Send feedback (mail to support), Support (inmyshoebox.com/support), Privacy (three short lines and the policy), Restore purchases (when Plus is offered), Version.
- A quiet word below: **Delete everything** (one question, a copy saved first; it also asks the relay to delete your email address and waiting mail, `POST /me/delete`).
- At the end, the logo and "Your posts stay on your phone."

### 2.9 The notification

One a day, at the time you chose, naming the first post and how many more. Tapping it opens Today.

## 3. The rules

1. **Today is a daily pick.**
   - Everything coming back always comes out: posts put away until now, and dated steps.
   - Anything new since the morning (kept, shared or emailed today) always joins Today, and so does anything dated within 5 days. The daily limit never holds these back.
   - A newsletter's dates more than a week out go straight to Coming up in the Shoebox, with one line on Today ("6 dates from the school newsletter are in Coming up"), so one email never floods Today.
   - The rest of the pile follows, up to the daily limit (default 10; All is a setting).
   - Posts you passed before go first, then the oldest never seen.
   - Bringing something back from the Box puts it first.
2. **Flick up = Next.** If your reason names a time, it comes back then; otherwise it's gone until tomorrow. A post you keep passing keeps coming back.
3. **Pull down = Put away.** Done, kept, and found by search in the Shoebox.
4. **Every action is instant, with Undo for 5 seconds.** No confirm dialogs, except Delete everything.
5. **Dated posts** show once when they arrive, then come back on their own 5 days before at 8 AM and stay on Today every day (Next skips a day) until put away. Every save is read for the date it is about (section 4.2). The nearest event comes first. Once the day has gone by, the post moves to Kept on its own (never deleted) and stays searchable.
6. **A new save** shows on Today the day it is kept (rule 1). After you flick it up, it comes back when your reason says, or tomorrow.
7. **Never delete on its own.** Shoebox never removes a save without you saying so.

### 3.1 Reasons to times (plain rules, on the phone)

| Words in your reason | Comes back |
|---|---|
| weekend | Saturday 9 AM |
| tonight, dinner, evening | today 6 PM, or tomorrow 6 PM if that's past |
| tomorrow | tomorrow 8 AM |
| a weekday ("Monday") | that day 8 AM |
| before a weekday ("before Monday") | the evening before, 6 PM |
| nothing that names a time | tomorrow |

Next: the Core package's richer planner (`Core/Sources/ShoeboxCore/Planner`, rules R1 to R20, plus Foundation Models on device) takes over from these plain rules.

## 4. Getting things in

| Way | How |
|---|---|
| Share sheet | Safari or any app: Share, then Shoebox (section 2.5). Reads the page while you type. Pages, links, text and up to 10 photos. |
| + New | Link, note or photo, with a reason (section 2.5). |
| Email | Forward to your Shoebox address. Your words above the forward are the reason. An ordinary email is one post: a short title and two to five sentences written on the phone from what matters (Apple Intelligence, greedy, and refused if it holds a number or day word the email does not; then the first few useful lines, quoted replies included). Codes, amounts, deadlines and each leg of a trip are kept; card numbers are not. A PDF attachment is read and kept on the post; an email that is only a link reads the page. An email with four or more dated lines (a newsletter, a season schedule) becomes one post per date that matters (each shown once when it arrives, then back 5 days before and every day after until put away): lines naming your grade or your words, and school-wide days; other grades and other activities are left out; with no "Who it's about" only school-wide days. Each date post reads as a short title (up to six words) and one line that starts with the day: "Saturday, Nov 14 · 5:00 PM · Cafeteria · Potluck." Where it came from is in the byline ("from Roosevelt newsletter"). Its picture names its own subject (trumpet, lacrosse) or there is none, and no stock picture is used twice. A date already made into a post (same day, a matching name) is not made again when the newsletter comes back next week: new details replace the words quietly, and a new time shows it once more with "Changed: 6:30 PM to 7:00 PM", even if it was put away. A post about a date leads with that day ("Thursday, Nov 12 · ...") when its words do not. Titles are in sentence case and never carry a time. A label the email never used ("Location:", "Trip leg:") is taken out. Posts say "you" for the person the mail is for, read from the first name in their Shoebox address; a mail with no known name just keeps the email's own words. Lines of a newsletter that the mail program wrapped mid-sentence are joined back. A date range reads "Wednesday, Nov 25 to Friday, Nov 27". The email itself is not kept. Ads, sign-in codes and account notices are skipped unless you wrote a note. Subjects lose `[tags]` and `Fwd:`/`Re:`. The same email twice is kept once. Mail waits on the relay up to 7 days. Forwarding needs Shoebox Plus. |
| Shoebox 1 | On first run, the newest Shoebox 1 backup (`shoebox-backup-*.json` in Files or iCloud Drive, Shoebox › Backups) is brought in. Importing twice adds nothing. The email address and its key come over too. |
| Backups | Settings › Bring in a backup takes any Shoebox 1 or 2 file. |

### 4.1 Pictures for posts without one

- The phone does the thinking. Apple Intelligence turns the post into two to four generic words ("school gym string lights"), asks the relay for about six candidates, and picks the best by their captions. Without Apple Intelligence, a short list of plain keyword rules writes the words and the server's first candidate is used.
- Only those generic words leave the phone: never names, your text or your reason. A guard drops any word that looks like a name from the post. Posts about health, money or legal matters are never looked up.
- The relay's `/stock?q=&n=` endpoint (not `/photo`, which Shoebox 1 still uses) asks Pixabay (key kept as a Worker secret) and returns candidates, cached 24 hours. Nothing about the post is logged.
- The picture is copied to the phone when it is chosen (Pixabay does not allow keeping links). The credit ("Photo by … on Pixabay", linked) shows under the words on the opened post.
- A real picture from the page replaces a stock one. A miss is retried tomorrow. Settings > Pictures turns it off.

### 4.2 Dates in the words

- Read on the phone with plain rules (`Shared/DateReader.swift`): written dates ("October 30", "Nov 7, 2026"), "10/30", and weekdays within two weeks. A time of day is taken from the same sentence ("4:00 to 6:00" is 4 PM) or the one after.
- Only dates still ahead of the day the post was kept count. A year-less date more than a week back means next year. Link digits are ignored. For web pages only the title, description and your note are read.
- The event is the earliest date that isn't a deadline ("forms due Nov 3"); deadlines are kept as other dates. Your reason still wins when it names a time.
- Done at capture, when a page's text arrives, and once for saves kept before this was added.

**Link previews.** The relay reads the page and returns its title, description, best picture and readable text. The picture is shrunk to 1200 px and kept on the phone. Your own words are never replaced.

## 5. Look

### 5.1 Colors

| Job | Light | Dark |
|---|---|---|
| Ground | Pistachio `#F6F3E8` | Plum `#3B2240` |
| Sheet | `#FBF9F1` | `#442B4B` |
| Card (Settings groups) | `#E8ECDA` | `#4A3352` |
| Text | Plum Ink `#2A1E2E` | Bone `#F1E9D8` |
| Quiet (dates, sources, labels) | `#6A6070` | `#BBA7BE` |
| Hairlines | `#DEDAC9`; fields `#CFCBB6` | `#54405A`; fields `#5E4965` |
| Your reason (chip) | Pistachio tint `#E3EBD7` | Pistachio `#B9C9A3` at 28%, text `#E3EBD7` |
| Your reason (on a photo) | Sunflower | Sunflower |
| Action word (Keep, Next) | Plum Ink | Sunflower `#F9C93A` |
| System controls (date pickers, links) | Plum `#3B2240` | Sunflower |
| Bottom box | Plum `#3B2240` glass, text Bone | lighter Plum `#6A4F73` glass, text Bone (no bright band on a dark screen; the lid is the bright mark) |
| Lid | Sunflower `#F9C93A` with a `#D4A21E` lip | same |
| Logo | tile Bone, box Plum, cards `#A798AD` | tile Plum, box lighter Plum `#6A4F73`, cards `#B7A6BA` |
| Delete (swipe) | Brick `#A8402F` with Bone word | same |
| Words on photos | Bone | Bone |
| Shadows, scrims, glass over photos | plum shade `#1A1020` | same |
| Launch screen | Pistachio | Plum |

No black anywhere. Brick is the only red and is used for Delete alone. Each color has one job:
- Pistachio is the light ground. Plum is the dark ground, and posts without a picture are Plum in both modes.
- Bone is the text on dark and on photos, and the box in dark mode.
- Plum Ink is the text on light. Plum is the box in light mode and the light-mode accent.
- Sunflower is the lid, your reason on a photo, and the action word and accent in dark mode.
- Shadows and scrims are the plum shade, so dark parts stay warm.

#### Stone (a second set of colors, chosen in Settings › Look › Colors)

The same colors as Scales' Stone: warm stone to read on, graphite for anything your hand is on. Dark puts the post on graphite with the sheets a step darker. Sunflower stays the lid, your reason on a photo and the dark accent; the logo and app icon stay Plum. Pistachio stays the default.

| Job | Light | Dark |
|---|---|---|
| Ground | Stone `#C9C6BD` | Graphite `#23262B` |
| Text | `#1F2124` | `#EEEAE2` |
| Quiet | `#55524B` | `#A5A39D` |
| Card | `#BDBAB0` | `#2E3238` |
| Hairlines; fields | `#B3B0A7`; `#ACA9A0` | `#3A3D43`; `#42464C` |
| Bottom box, Shoebox and Settings glass; posts without a picture | Graphite `#23262B` | `#16181B` |
| Words on photos and dark | `#EEEAE2` | `#EEEAE2` |
| Shadows and scrims | `#121316` | same |

Every photo is measured once (average brightness and spread from a 16 by 16 copy) and graded: bright ones get more plum shade and a little less color, dark ones are lifted, flat ones get more contrast. Then a light Oceanic soft-light tint, an edge vignette, and shading top and bottom so the status bar and the glass always read.

### 5.4 App icon

Shoebox 1's layered Liquid Glass icon (`App/Shoebox/AppIcon.icon`: lid, box and cards), recolored: tile Bone or Plum, box Plum (`#3B2240`) on Bone and Bone (`#F1E9D8`) on Plum, cards `#A798AD` or `#8E7A92`, lid Sunflower. Each layer is glass, so iOS renders it in Liquid Glass, dark and tinted on its own. The same artwork is drawn in the app (`AppLogo`, from `Assets.xcassets` Logo*).

### 5.5 Retired

The Nectarine bar with Later and Open, the Later list and date picker, neumorphic cards, the Daily Issue, Midnight Gold, Plum and Peach, the Timeline layout, and a separate sort screen.

## 6. Data and safety

- **One store.** SwiftData in the App Group `group.com.grahamdeno.shoebox`, shared by the app and the share sheet. CloudKit sync is off.
- **Sync-ready.** Every save has a UUID, created and updated times, and a soft-delete marker.
- **Daily automatic backup.** Once a day, the whole store is written as JSON (photos included) to Files and to iCloud Drive (Shoebox › Backups). The last 7 are kept, plus the biggest. Shoebox 1's backups are never touched.
- **Privacy.** No account, no ads, no tracking. Saves stay on the phone. Link previews and email pass through the relay (`https://shoebox-api.tangomike.app`). Email waits there until the phone collects it, up to 7 days, then it is deleted; link previews are cached by Cloudflare for 24 hours. The policy is at `https://inmyshoebox.com/privacy`.

## 7. Not built yet, in order

1. Home Screen and Lock Screen widgets.
2. Next and Put away on the notification itself (in v1.0).
3. The relay's source moved into this repo (`relay/`), so a deploy from the frozen edition repo can't remove `/stock`.
4. School newsletters turned into short dated posts by AI, with the child's name masked as `{child}` (Core `NameMask` is ready).
5. The richer return planner: Core rules R1 to R20 plus Foundation Models, and "before the meeting" from the calendar.
6. Siri and Shortcuts: Keep, Find, Bring back.
7. Screenshots as saves.
8. Deep links (`shoebox://`).
9. Moving the relay into this repo.

## 8. Release decisions (November 2, 2026)

From the release-readiness audit (`docs/audit/`) and Graham's answers.

| Decision | Choice |
|---|---|
| Who it's for | Busy parents and working adults, about 28 to 50 |
| Version | 1.0 on the existing record (`MARKETING_VERSION` 1.0.0). Never create a new record or remove the old one |
| Price | Free download. **Shoebox Plus**, a one-time $9.99 lifetime unlock with Restore Purchases, adds the email address (forwarding, newsletter dates, pictures for email posts). The relay mints an address only for a verified purchase |
| Language | English for v1.0. v1.1 adds Spanish for Mexico and French for Canada, each as screens plus reading that language's dates, reasons and newsletters |
| First save | Shows on Today the day it is kept (section 3, rules 1 and 6) |
| Empty Today | One welcome post that teaches the moves (section 2.6) |
| Daily limit | Default 10; new and soon-dated posts always join (section 3, rule 1) |
| Mail retention on the relay | 7 days, plus a background refresh that collects mail without opening the app |
| Notification actions | Next and Put away on the notification, in v1.0 |
| AI | On the phone only. No cloud AI and no relay AI fallback in v1.0 |
| Relay | The new app gets its own Worker (`relay/app`, `https://api.inmyshoebox.com`) with only the seven routes it uses; Shoebox 1's routes stay on the old Worker (`shoebox-api.tangomike.app`) until build 36 is gone. Workers Paid on the day a public beta link goes out |
| Seller and policy | Graham DeNoyer as an individual. Support mail reaches Graham's Gmail under Support/Shoebox |
| Storefronts | v1.0: United States, Canada, Mexico, United Kingdom, Australia, New Zealand. No EU (the trader rule would publish a home address). Future countries are not added automatically |
| Repo | Stays public while CI needs free Mac minutes; family names come out of tests and fixtures now; private later |
| Small Business Program | Submitted November 2 |

## 9. Shoebox Plus

- One non-consumable in-app purchase, $9.99, bought once and restored on any phone with the same Apple Account.
- Without it: everything except getting a Shoebox email address. With it: the address, newsletter dates and pictures for email posts.
- Settings › Email shows "Get address with Shoebox Plus" until bought; Settings gets **Restore purchases** as a quiet word.
- The phone sends the signed purchase to the relay when it asks for an address; the relay checks it before minting.
- Offered after the first week of use, never in the first run.
- **TestFlight and App Review get it free** (decided November 5). When StoreKit verifies the install came from the App Store sandbox, Settings › Email offers the first name and Get address at once, with no purchase. The phone sends the signed app transaction (`AppTransaction`) as `beta`; the relay accepts it only for this app and only in Sandbox, up to five phones per Apple Account. "Buy Shoebox Plus" stays as a quiet second row so App Review can find the purchase. The same build on the App Store reads Production, so the free path ends at launch with no code change. Testers' addresses keep working after launch; collecting is never gated.

## 10. How we work

- **The model for each step.** Graham picks it: Opus for feel, data safety and judgment; Sonnet for building and shipping. Name the next step's model at every handoff.
- **Shipping.** Don't merge or ship until Graham says "ship". Claude opens and merges pull requests itself, on branches, never on `main`.
- **Submit for Review.** Graham presses it. TestFlight uploads are fine once he has said ship. Push `main` to the `testflight` branch; tests run first, and build numbers are 1000 + run number x 10 + attempt.
- **Irreversible steps.** Submit, publish, delete and deploy go first in any handoff and stand out.
- **Writing.** Plain and compact. No em-dashes. No military metaphors in published text.
- **Checks.** Iterate fast: batch changes, build once when Graham asks. CI screenshots only when they're worth it: put `[screens]` in a commit message, then read the `ci-screens` branch.
